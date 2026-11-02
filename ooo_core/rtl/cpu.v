// WISC-S25 out-of-order core (single-issue front end, out-of-order back end).
//
//   Fetch -> IFQ -> Decode/Rename/Dispatch -> Issue queue -> ALU / BRU / LDU / STU
//                                         \-> ROB  (in-order commit)    \-> SQ -> D-cache
//
// Same top-level interface as the phase-3 in-order core:
//   cpu(clk, rst_n, hlt, pc)  -- pc is the PC of the last committed instruction.
//
// Parameters:
//   BP_TYPE         direction predictor (see ooo_defs.vh)
//   EARLY_RECOVERY  1: recover from a mispredict as soon as the branch
//                      executes (selective squash of younger instructions)
//                   0: wait until the branch reaches the ROB head
//   ROB_W           ROB has 2**ROB_W entries
//   IQ_N            issue-queue entries
//   SQ_W            store queue has 2**SQ_W entries
//   EARLY_RESTART   critical-word-first refills, words usable as they arrive
//   I_PREFETCH      next-line instruction prefetch
//   D_PREFETCH      next-line data prefetch after a D-cache miss
module cpu #(
    parameter BP_TYPE        = 6,
    parameter EARLY_RECOVERY = 1,
    parameter ROB_W          = 4,
    parameter IQ_N           = 8,
    parameter SQ_W           = 3,
    parameter EARLY_RESTART  = 1,
    parameter I_PREFETCH     = 1,
    parameter D_PREFETCH     = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        hlt,
    output wire [15:0] pc
);
`include "ooo_defs.vh"
    localparam GHR_W = 16;

    // ==================================================================
    // Wires between blocks
    // ==================================================================
    // I-cache / D-cache / memory
    wire [15:0] ic_addr, ic_data;
    wire        ic_en, ic_hit, i_miss_req;
    wire [15:0] dc_rd_addr, dc_rd_data, dc_wr_addr, dc_wr_data;
    wire        dc_rd_en, dc_rd_hit, dc_wr_hit, dc_wr_en;
    wire        d_miss_req;
    wire [15:0] d_miss_addr;
    wire        mem_wr_ok, mem_wr_en;
    wire [15:0] mem_wr_addr, mem_wr_data;
    wire        i_fill_start, d_fill_start, i_fill_we, d_fill_we, i_fill_done, d_fill_done;
    wire [15:0] fill_addr, fill_data;
    wire [2:0]  fill_word;
    wire        mem_busy, pf_start;
    wire [15:0] ipf_addr = {ic_addr[15:4] + 12'd1, 4'h0};
    wire [15:0] dpf_addr;
    wire        ipf_present, dpf_present;

    // Front end
    wire             ifq_valid;
    wire [15:0]      ifq_pc, ifq_instr, ifq_pred_npc;
    wire [GHR_W-1:0] ifq_ghr;
    wire             fetch_fire;

    // Recovery event
    reg              rec_valid;
    reg [ROB_W-1:0]  rec_tag;
    reg [15:0]       rec_pc;
    reg [GHR_W-1:0]  rec_ghr;
    reg [SQ_W:0]     rec_sqp;

    // Result buses (registered: a unit's result is broadcast the cycle after it executes)
    reg              cdba_valid;
    reg [ROB_W-1:0]  cdba_tag;
    reg [15:0]       cdba_val;
    reg              cdba_z, cdba_n, cdba_v;
    reg              cdbb_valid;
    reg [ROB_W-1:0]  cdbb_tag;
    reg [15:0]       cdbb_val;

    // ==================================================================
    // Memory system and caches
    // ==================================================================
    mem_system #(.EARLY_RESTART(EARLY_RESTART), .I_PREFETCH(I_PREFETCH), .D_PREFETCH(D_PREFETCH)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .i_req(i_miss_req), .i_addr(ic_addr),
        .d_req(d_miss_req), .d_addr(d_miss_addr),
        .wr_ok(mem_wr_ok), .wr_en(mem_wr_en), .wr_addr(mem_wr_addr), .wr_data(mem_wr_data),
        .ipf_addr(ipf_addr), .ipf_present(ipf_present),
        .dpf_addr(dpf_addr), .dpf_present(dpf_present),
        .i_fill_start(i_fill_start), .d_fill_start(d_fill_start), .fill_addr(fill_addr),
        .i_fill_we(i_fill_we), .d_fill_we(d_fill_we), .fill_word(fill_word), .fill_data(fill_data),
        .i_fill_done(i_fill_done), .d_fill_done(d_fill_done), .pf_start(pf_start), .busy(mem_busy));

    cache #(.EARLY_RESTART(EARLY_RESTART)) u_icache (
        .clk(clk), .rst_n(rst_n),
        .rd_addr(ic_addr), .rd_en(ic_en), .rd_hit(ic_hit), .rd_data(ic_data),
        .wr_addr(16'h0000), .wr_hit(), .wr_en(1'b0), .wr_data(16'h0000),
        .probe_addr(ipf_addr), .probe_hit(ipf_present),
        .fill_start(i_fill_start), .fill_addr(fill_addr), .fill_we(i_fill_we),
        .fill_word(fill_word), .fill_data(fill_data), .fill_done(i_fill_done));

    cache #(.EARLY_RESTART(EARLY_RESTART)) u_dcache (
        .clk(clk), .rst_n(rst_n),
        .rd_addr(dc_rd_addr), .rd_en(dc_rd_en), .rd_hit(dc_rd_hit), .rd_data(dc_rd_data),
        .wr_addr(dc_wr_addr), .wr_hit(dc_wr_hit), .wr_en(dc_wr_en), .wr_data(dc_wr_data),
        .probe_addr(dpf_addr), .probe_hit(dpf_present),
        .fill_start(d_fill_start), .fill_addr(fill_addr), .fill_we(d_fill_we),
        .fill_word(fill_word), .fill_data(fill_data), .fill_done(d_fill_done));

    // ==================================================================
    // Front end
    // ==================================================================
    wire             commit_en, commit_wr_rd, commit_is_store, commit_is_cond_br;
    wire             commit_is_br_reg, commit_is_halt, commit_taken, commit_mispred;
    wire [15:0]      commit_pc, commit_instr, commit_val, commit_npc;
    wire [3:0]       commit_rd;
    wire [GHR_W-1:0] commit_ghr;
    wire [SQ_W:0]    commit_sqp;
    wire             disp_fire;

    frontend #(.BP_TYPE(BP_TYPE), .GHR_W(GHR_W)) u_fe (
        .clk(clk), .rst_n(rst_n),
        .ic_addr(ic_addr), .ic_en(ic_en), .ic_hit(ic_hit), .ic_data(ic_data), .i_miss_req(i_miss_req),
        .ifq_valid(ifq_valid), .ifq_pc(ifq_pc), .ifq_instr(ifq_instr),
        .ifq_pred_npc(ifq_pred_npc), .ifq_ghr(ifq_ghr), .ifq_deq(disp_fire),
        .redirect(rec_valid), .redirect_pc(rec_pc), .redirect_ghr(rec_ghr),
        .upd_dir(commit_en & commit_is_cond_br), .upd_pc(commit_pc), .upd_ghr(commit_ghr),
        .upd_taken(commit_taken),
        .upd_btb(commit_en & commit_is_br_reg & commit_taken), .upd_btb_target(commit_npc),
        .fetch_fire(fetch_fire));

    // ==================================================================
    // Decode / rename / dispatch
    // ==================================================================
    wire [1:0] d_fu;
    wire       d_needs_iq, d_use_s1, d_use_s2, d_use_z, d_use_nv;
    wire       d_wr_rd, d_wr_z, d_wr_nv;
    wire [3:0] d_s1_reg, d_s2_reg;
    wire       d_is_load, d_is_store, d_is_cond_br, d_is_br_reg, d_is_pcs, d_is_halt;

    decoder u_dec (
        .instr(ifq_instr), .fu(d_fu), .needs_iq(d_needs_iq),
        .use_s1(d_use_s1), .s1_reg(d_s1_reg), .use_s2(d_use_s2), .s2_reg(d_s2_reg),
        .use_z(d_use_z), .use_nv(d_use_nv),
        .wr_rd(d_wr_rd), .wr_z(d_wr_z), .wr_nv(d_wr_nv),
        .is_load(d_is_load), .is_store(d_is_store), .is_cond_br(d_is_cond_br),
        .is_br_reg(d_is_br_reg), .is_pcs(d_is_pcs), .is_halt(d_is_halt));

    wire [3:0] d_rd      = ifq_instr[11:8];
    wire       d_wr_rd_q = d_wr_rd & (d_rd != 4'd0);         // R0 is never renamed
    // An ALU op with no architectural effect (e.g. PADDSB R0,..: the NOP idiom)
    // is completed at dispatch instead of occupying the issue queue.
    wire       d_no_effect = (d_fu == FU_ALU) & d_needs_iq & !d_wr_rd_q & !d_wr_z & !d_wr_nv;
    wire       d_to_iq     = d_needs_iq & !d_no_effect;

    wire             rob_full, rob_empty;
    wire [ROB_W-1:0] rob_tail, rob_head;
    wire [ROB_W:0]   rob_occ;
    wire             iq_full;
    wire [$clog2(IQ_N):0] iq_occ;
    wire             sq_full, sq_empty;
    wire [SQ_W:0]    sq_tail;
    reg              halted;

    wire stall_rob = rob_full;
    wire stall_iq  = d_to_iq & iq_full;
    wire stall_sq  = d_is_store & sq_full;
    assign disp_fire = ifq_valid & !stall_rob & !stall_iq & !stall_sq & !rec_valid & !halted;

    wire             s1_rdy, s2_rdy, z_rdy, nv_rdy, z_val;
    wire [ROB_W-1:0] s1_tag, s2_tag, z_tag, nv_tag;
    wire [15:0]      s1_val, s2_val;
    wire [1:0]       nv_val;

    // BRU / STU / ROB query wires (declared here, driven below)
    wire             iq_alu_issue, iq_bru_issue, iq_ldu_issue, iq_stu_issue;
    wire [ROB_W-1:0] iq_alu_tag, iq_bru_tag, iq_ldu_tag, iq_stu_tag;
    wire [15:0]      iq_alu_instr, iq_alu_a, iq_alu_b;
    wire [15:0]      iq_bru_instr, iq_bru_pc, iq_bru_pred_npc, iq_bru_a;
    wire             iq_bru_z, iq_bru_n, iq_bru_v;
    wire [15:0]      iq_ldu_instr, iq_ldu_a;
    wire [SQ_W:0]    iq_ldu_sqp;
    wire [15:0]      iq_stu_instr, iq_stu_a, iq_stu_b;
    wire [SQ_W:0]    iq_stu_sqp;
    wire             bru_taken, bru_mispred;
    wire [15:0]      bru_npc;
    wire [GHR_W-1:0] q_ghr;
    wire [SQ_W:0]    q_sqp;
    wire             q_is_cond_br;

    rob #(.ROB_W(ROB_W), .SQ_PW(SQ_W+1), .GHR_W(GHR_W)) u_rob (
        .clk(clk), .rst_n(rst_n),
        .disp_en(disp_fire), .disp_pc(ifq_pc), .disp_instr(ifq_instr),
        .disp_wr_rd(d_wr_rd_q), .disp_rd(d_rd), .disp_wr_z(d_wr_z), .disp_wr_nv(d_wr_nv),
        .disp_done(!d_to_iq), .disp_value(ifq_pc + 16'd2),
        .disp_is_store(d_is_store), .disp_is_cond_br(d_is_cond_br),
        .disp_is_br_reg(d_is_br_reg), .disp_is_halt(d_is_halt),
        .disp_ghr(ifq_ghr), .disp_sqp(sq_tail),
        .tail(rob_tail), .head(rob_head), .full(rob_full), .empty(rob_empty), .occupancy(rob_occ),
        .s1_reg(d_s1_reg), .s2_reg(d_s2_reg),
        .s1_rdy(s1_rdy), .s1_tag(s1_tag), .s1_val(s1_val),
        .s2_rdy(s2_rdy), .s2_tag(s2_tag), .s2_val(s2_val),
        .z_rdy(z_rdy), .z_tag(z_tag), .z_val(z_val),
        .nv_rdy(nv_rdy), .nv_tag(nv_tag), .nv_val(nv_val),
        .cdba_valid(cdba_valid), .cdba_tag(cdba_tag), .cdba_val(cdba_val),
        .cdba_z(cdba_z), .cdba_n(cdba_n), .cdba_v(cdba_v),
        .cdbb_valid(cdbb_valid), .cdbb_tag(cdbb_tag), .cdbb_val(cdbb_val),
        .bru_valid(iq_bru_issue), .bru_tag(iq_bru_tag), .bru_taken(bru_taken),
        .bru_npc(bru_npc), .bru_mispred(bru_mispred),
        .stu_valid(iq_stu_issue), .stu_tag(iq_stu_tag),
        .q_tag(iq_bru_tag), .q_ghr(q_ghr), .q_sqp(q_sqp), .q_is_cond_br(q_is_cond_br),
        .rec_valid(rec_valid), .rec_tag(rec_tag),
        .commit_stall(halted), .commit_en(commit_en),
        .commit_pc(commit_pc), .commit_instr(commit_instr),
        .commit_wr_rd(commit_wr_rd), .commit_rd(commit_rd), .commit_val(commit_val),
        .commit_is_store(commit_is_store), .commit_is_cond_br(commit_is_cond_br),
        .commit_is_br_reg(commit_is_br_reg), .commit_is_halt(commit_is_halt),
        .commit_taken(commit_taken), .commit_npc(commit_npc), .commit_mispred(commit_mispred),
        .commit_ghr(commit_ghr), .commit_sqp(commit_sqp));

    // ==================================================================
    // Issue queue
    // ==================================================================
    wire              ldu_busy;
    wire [SQ_W:0]     sq_head;
    wire [(1<<SQ_W)-1:0] sq_unresolved;

    issue_queue #(.IQ_N(IQ_N), .ROB_W(ROB_W), .SQ_W(SQ_W)) u_iq (
        .clk(clk), .rst_n(rst_n), .rob_head(rob_head),
        .disp_en(disp_fire & d_to_iq), .disp_fu(d_fu), .disp_tag(rob_tail),
        .disp_instr(ifq_instr), .disp_pc(ifq_pc), .disp_pred_npc(ifq_pred_npc), .disp_sqp(sq_tail),
        .disp_s1_rdy(!d_use_s1 | s1_rdy), .disp_s1_tag(s1_tag), .disp_s1_val(s1_val),
        .disp_s2_rdy(!d_use_s2 | s2_rdy), .disp_s2_tag(s2_tag), .disp_s2_val(s2_val),
        .disp_z_rdy(!d_use_z | z_rdy),    .disp_z_tag(z_tag),   .disp_z_val(z_val),
        .disp_nv_rdy(!d_use_nv | nv_rdy), .disp_nv_tag(nv_tag), .disp_nv_val(nv_val),
        .full(iq_full), .occupancy(iq_occ),
        .cdba_valid(cdba_valid), .cdba_tag(cdba_tag), .cdba_val(cdba_val),
        .cdba_z(cdba_z), .cdba_n(cdba_n), .cdba_v(cdba_v),
        .cdbb_valid(cdbb_valid), .cdbb_tag(cdbb_tag), .cdbb_val(cdbb_val),
        .ldu_busy(ldu_busy), .sq_head(sq_head), .sq_unresolved(sq_unresolved),
        .rec_valid(rec_valid), .rec_tag(rec_tag),
        .alu_issue(iq_alu_issue), .alu_tag(iq_alu_tag), .alu_instr(iq_alu_instr),
        .alu_a(iq_alu_a), .alu_b(iq_alu_b),
        .bru_issue(iq_bru_issue), .bru_tag(iq_bru_tag), .bru_instr(iq_bru_instr),
        .bru_pc(iq_bru_pc), .bru_pred_npc(iq_bru_pred_npc), .bru_a(iq_bru_a),
        .bru_z(iq_bru_z), .bru_n(iq_bru_n), .bru_v(iq_bru_v),
        .ldu_issue(iq_ldu_issue), .ldu_tag(iq_ldu_tag), .ldu_instr(iq_ldu_instr),
        .ldu_a(iq_ldu_a), .ldu_sqp(iq_ldu_sqp),
        .stu_issue(iq_stu_issue), .stu_tag(iq_stu_tag), .stu_instr(iq_stu_instr),
        .stu_a(iq_stu_a), .stu_b(iq_stu_b), .stu_sqp(iq_stu_sqp));

    // ==================================================================
    // Execute
    // ==================================================================
    wire [15:0] alu_result;
    wire        alu_z, alu_n, alu_v;
    alu_unit u_alu (
        .instr(iq_alu_instr), .a(iq_alu_a), .b(iq_alu_b),
        .result(alu_result), .z(alu_z), .n(alu_n), .v(alu_v));

    branch_unit u_bru (
        .instr(iq_bru_instr), .pc(iq_bru_pc), .pred_npc(iq_bru_pred_npc), .a(iq_bru_a),
        .z(iq_bru_z), .n(iq_bru_n), .v(iq_bru_v),
        .taken(bru_taken), .npc(bru_npc), .mispred(bru_mispred));

    // Address generation: (base & 0xFFFE) + (sext(offset) << 1)
    wire [15:0] ld_addr = (iq_ldu_a & 16'hFFFE) + {{11{iq_ldu_instr[3]}}, iq_ldu_instr[3:0], 1'b0};
    wire [15:0] st_addr = (iq_stu_a & 16'hFFFE) + {{11{iq_stu_instr[3]}}, iq_stu_instr[3:0], 1'b0};

    wire             ld_done, ld_forwarded, ld_miss_cycle;
    wire [ROB_W-1:0] ld_done_tag;
    wire [15:0]      ld_done_val;
    wire [15:0]      cm_addr, cm_data;

    lsu #(.SQ_W(SQ_W), .ROB_W(ROB_W)) u_lsu (
        .clk(clk), .rst_n(rst_n), .rob_head(rob_head),
        .sq_alloc(disp_fire & d_is_store), .sq_tail_o(sq_tail), .sq_full(sq_full),
        .stu_valid(iq_stu_issue), .stu_sqp(iq_stu_sqp), .stu_addr(st_addr), .stu_data(iq_stu_b),
        .sq_commit(commit_en & commit_is_store), .cm_addr(cm_addr), .cm_data(cm_data),
        .rec_valid(rec_valid), .rec_tag(rec_tag), .rec_sqp(rec_sqp),
        .ld_valid(iq_ldu_issue), .ld_tag(iq_ldu_tag), .ld_addr(ld_addr), .ld_sqp(iq_ldu_sqp),
        .ld_busy(ldu_busy), .ld_done(ld_done), .ld_done_tag(ld_done_tag), .ld_done_val(ld_done_val),
        .ld_forwarded(ld_forwarded), .ld_miss_cycle(ld_miss_cycle),
        .sq_head_o(sq_head), .sq_unresolved(sq_unresolved), .sq_empty(sq_empty),
        .dc_rd_addr(dc_rd_addr), .dc_rd_en(dc_rd_en), .dc_rd_hit(dc_rd_hit), .dc_rd_data(dc_rd_data),
        .dc_wr_addr(dc_wr_addr), .dc_wr_hit(dc_wr_hit), .dc_wr_en(dc_wr_en), .dc_wr_data(dc_wr_data),
        .d_miss_req(d_miss_req), .d_miss_addr(d_miss_addr),
        .mem_wr_ok(mem_wr_ok), .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data));

    // ==================================================================
    // Branch recovery
    // ==================================================================
    always @(*) begin
        if (EARLY_RECOVERY != 0) begin
            rec_valid = iq_bru_issue & bru_mispred;
            rec_tag   = iq_bru_tag;
            rec_pc    = bru_npc;
            rec_ghr   = q_is_cond_br ? {q_ghr[GHR_W-2:0], bru_taken} : q_ghr;
            rec_sqp   = q_sqp;
        end else begin
            rec_valid = commit_en & commit_mispred;
            rec_tag   = rob_head;
            rec_pc    = commit_npc;
            rec_ghr   = commit_is_cond_br ? {commit_ghr[GHR_W-2:0], commit_taken} : commit_ghr;
            rec_sqp   = commit_sqp;
        end
    end

    // An instruction is squashed by the recovery if it is younger than rec_tag.
    function younger;
        input [ROB_W-1:0] t;
        begin
            younger = rec_valid && ((t - rob_head) > (rec_tag - rob_head));
        end
    endfunction

    // ==================================================================
    // Result buses
    // ==================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            cdba_valid <= 1'b0;
            cdbb_valid <= 1'b0;
        end else begin
            cdba_valid <= iq_alu_issue & !younger(iq_alu_tag);
            cdba_tag   <= iq_alu_tag;
            cdba_val   <= alu_result;
            cdba_z     <= alu_z;
            cdba_n     <= alu_n;
            cdba_v     <= alu_v;
            cdbb_valid <= ld_done;                       // already squash-gated in the LSU
            cdbb_tag   <= ld_done_tag;
            cdbb_val   <= ld_done_val;
        end
    end

    // ==================================================================
    // Commit / halt
    // ==================================================================
    reg [15:0] last_commit_pc;
    always @(posedge clk) begin
        if (!rst_n) begin
            halted         <= 1'b0;
            last_commit_pc <= 16'h0000;
        end else if (commit_en) begin
            last_commit_pc <= commit_pc;
            if (commit_is_halt) halted <= 1'b1;
        end
    end
    // hlt is raised once HLT has retired and every committed store has
    // reached memory (the store queue drained).
    assign hlt = halted & sq_empty;
    assign pc  = last_commit_pc;

    // ==================================================================
    // Performance counters (read by the testbench)
    // ==================================================================
    reg [31:0] stat_cycles, stat_commits, stat_cond_br, stat_cond_mispred;
    reg [31:0] stat_br_reg, stat_br_reg_mispred, stat_recoveries;
    reg [31:0] stat_stall_rob, stat_stall_iq, stat_stall_sq, stat_ifq_empty;
    reg [31:0] stat_icache_miss, stat_dcache_miss, stat_loads, stat_ld_fwd, stat_ld_miss_cycles;
    reg [31:0] stat_issued, stat_rob_occ_sum, stat_prefetches;

    always @(posedge clk) begin
        if (!rst_n) begin
            stat_cycles <= 0; stat_commits <= 0; stat_cond_br <= 0; stat_cond_mispred <= 0;
            stat_br_reg <= 0; stat_br_reg_mispred <= 0; stat_recoveries <= 0;
            stat_stall_rob <= 0; stat_stall_iq <= 0; stat_stall_sq <= 0; stat_ifq_empty <= 0;
            stat_icache_miss <= 0; stat_dcache_miss <= 0; stat_loads <= 0; stat_ld_fwd <= 0;
            stat_ld_miss_cycles <= 0; stat_issued <= 0; stat_rob_occ_sum <= 0; stat_prefetches <= 0;
        end else if (!hlt) begin
            stat_cycles      <= stat_cycles + 1;
            stat_rob_occ_sum <= stat_rob_occ_sum + rob_occ;
            if (commit_en) stat_commits <= stat_commits + 1;
            if (commit_en & commit_is_cond_br) stat_cond_br <= stat_cond_br + 1;
            if (commit_en & commit_is_cond_br & commit_mispred) stat_cond_mispred <= stat_cond_mispred + 1;
            if (commit_en & commit_is_br_reg) stat_br_reg <= stat_br_reg + 1;
            if (commit_en & commit_is_br_reg & commit_mispred) stat_br_reg_mispred <= stat_br_reg_mispred + 1;
            if (rec_valid) stat_recoveries <= stat_recoveries + 1;
            if (ifq_valid & !rec_valid & !halted) begin
                if (stall_rob)                        stat_stall_rob <= stat_stall_rob + 1;
                else if (stall_iq)                    stat_stall_iq  <= stat_stall_iq + 1;
                else if (stall_sq)                    stat_stall_sq  <= stat_stall_sq + 1;
            end
            if (!ifq_valid & !halted) stat_ifq_empty <= stat_ifq_empty + 1;
            if (i_fill_start & !pf_start) stat_icache_miss <= stat_icache_miss + 1;
            if (d_fill_start & !pf_start) stat_dcache_miss <= stat_dcache_miss + 1;
            if (pf_start) stat_prefetches <= stat_prefetches + 1;
            if (ld_done) stat_loads <= stat_loads + 1;
            if (ld_forwarded) stat_ld_fwd <= stat_ld_fwd + 1;
            if (ld_miss_cycle) stat_ld_miss_cycles <= stat_ld_miss_cycles + 1;
            stat_issued <= stat_issued + iq_alu_issue + iq_bru_issue + iq_ldu_issue + iq_stu_issue;
        end
    end
endmodule
