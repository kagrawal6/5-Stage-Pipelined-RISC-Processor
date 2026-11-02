// Reorder buffer + register renaming (ARF + ROB style, as in the P6 / Lecture 5
// "ARF + ROB" organization).
//
//  * Architectural state lives in the ARF (R0-R15) and the flag ARF (Z, N, V).
//  * Speculative results live in the ROB entry of the producing instruction.
//  * The map table says, for every architectural register, whether its newest
//    value is still in flight (busy) and which ROB entry (tag) produces it.
//    The flags are renamed as two extra "registers": Z, and N+V together
//    (ADD/SUB write all three flags; XOR/SLL/SRA/ROR write only Z).
//  * Dispatch reads source operands from ARF -> ROB -> result buses (CDB).
//  * Commit retires the head entry: writes the ARF and clears map entries
//    that still point at it.
//  * Recovery (branch mispredict) truncates the ROB after the branch and
//    rebuilds the map table from the surviving ROB entries, so no per-branch
//    map checkpoints are needed.
module rob #(
    parameter ROB_W = 4,              // ROB has 2**ROB_W entries
    parameter SQ_PW = 4,              // store-queue pointer width (with wrap bit)
    parameter GHR_W = 16
) (
    input  wire               clk,
    input  wire               rst_n,

    // ---- dispatch (allocate at tail) ----
    input  wire               disp_en,
    input  wire [15:0]        disp_pc,
    input  wire [15:0]        disp_instr,
    input  wire               disp_wr_rd,     // already qualified with rd != 0
    input  wire [3:0]         disp_rd,
    input  wire               disp_wr_z,
    input  wire               disp_wr_nv,
    input  wire               disp_done,      // completes at dispatch
    input  wire [15:0]        disp_value,     // result for disp_done entries (PCS)
    input  wire               disp_is_store,
    input  wire               disp_is_cond_br,
    input  wire               disp_is_br_reg,
    input  wire               disp_is_halt,
    input  wire [GHR_W-1:0]   disp_ghr,       // global history before this branch
    input  wire [SQ_PW-1:0]   disp_sqp,       // store-queue tail at dispatch
    output wire [ROB_W-1:0]   tail,
    output wire [ROB_W-1:0]   head,
    output wire               full,
    output wire               empty,
    output wire [ROB_W:0]     occupancy,

    // ---- rename: source lookup for the instruction being dispatched ----
    input  wire [3:0]         s1_reg,
    input  wire [3:0]         s2_reg,
    output reg                s1_rdy,
    output reg  [ROB_W-1:0]   s1_tag,
    output reg  [15:0]        s1_val,
    output reg                s2_rdy,
    output reg  [ROB_W-1:0]   s2_tag,
    output reg  [15:0]        s2_val,
    output reg                z_rdy,
    output reg  [ROB_W-1:0]   z_tag,
    output reg                z_val,
    output reg                nv_rdy,
    output reg  [ROB_W-1:0]   nv_tag,
    output reg  [1:0]         nv_val,         // {N, V}

    // ---- completion ----
    input  wire               cdba_valid,     // ALU result bus (value + flags)
    input  wire [ROB_W-1:0]   cdba_tag,
    input  wire [15:0]        cdba_val,
    input  wire               cdba_z,
    input  wire               cdba_n,
    input  wire               cdba_v,
    input  wire               cdbb_valid,     // load result bus (value only)
    input  wire [ROB_W-1:0]   cdbb_tag,
    input  wire [15:0]        cdbb_val,
    input  wire               bru_valid,      // branch resolved
    input  wire [ROB_W-1:0]   bru_tag,
    input  wire               bru_taken,
    input  wire [15:0]        bru_npc,
    input  wire               bru_mispred,
    input  wire               stu_valid,      // store address+data written to SQ
    input  wire [ROB_W-1:0]   stu_tag,

    // ---- query port: branch bookkeeping by tag (used by early recovery) ----
    input  wire [ROB_W-1:0]   q_tag,
    output wire [GHR_W-1:0]   q_ghr,
    output wire [SQ_PW-1:0]   q_sqp,
    output wire               q_is_cond_br,

    // ---- recovery: squash everything younger than rec_tag ----
    input  wire               rec_valid,
    input  wire [ROB_W-1:0]   rec_tag,

    // ---- commit (head) ----
    input  wire               commit_stall,
    output wire               commit_en,
    output wire [15:0]        commit_pc,
    output wire [15:0]        commit_instr,
    output wire               commit_wr_rd,
    output wire [3:0]         commit_rd,
    output wire [15:0]        commit_val,
    output wire               commit_is_store,
    output wire               commit_is_cond_br,
    output wire               commit_is_br_reg,
    output wire               commit_is_halt,
    output wire               commit_taken,
    output wire [15:0]        commit_npc,
    output wire               commit_mispred,
    output wire [GHR_W-1:0]   commit_ghr,
    output wire [SQ_PW-1:0]   commit_sqp
);
    localparam ROB_N = 1 << ROB_W;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    reg [ROB_W-1:0] head_r, tail_r;
    reg [ROB_W:0]   count;

    reg             e_done      [0:ROB_N-1];
    reg [15:0]      e_val       [0:ROB_N-1];
    reg             e_z         [0:ROB_N-1];
    reg             e_n         [0:ROB_N-1];
    reg             e_v         [0:ROB_N-1];
    reg             e_wr_rd     [0:ROB_N-1];
    reg [3:0]       e_rd        [0:ROB_N-1];
    reg             e_wr_z      [0:ROB_N-1];
    reg             e_wr_nv     [0:ROB_N-1];
    reg [15:0]      e_pc        [0:ROB_N-1];
    reg [15:0]      e_instr     [0:ROB_N-1];
    reg             e_is_store  [0:ROB_N-1];
    reg             e_is_cond   [0:ROB_N-1];
    reg             e_is_brr    [0:ROB_N-1];
    reg             e_is_halt   [0:ROB_N-1];
    reg             e_taken     [0:ROB_N-1];
    reg [15:0]      e_npc       [0:ROB_N-1];
    reg             e_mispred   [0:ROB_N-1];
    reg [GHR_W-1:0] e_ghr       [0:ROB_N-1];
    reg [SQ_PW-1:0] e_sqp       [0:ROB_N-1];

    reg [15:0]      arf [0:15];
    reg             arf_z, arf_n, arf_v;

    reg [15:0]      map_busy;                 // bit r: R[r] has an in-flight producer
    reg [ROB_W-1:0] map_tag [0:15];
    reg             mz_busy, mnv_busy;
    reg [ROB_W-1:0] mz_tag, mnv_tag;

    assign head      = head_r;
    assign tail      = tail_r;
    assign full      = (count == ROB_N);
    assign empty     = (count == 0);
    assign occupancy = count;

    // ------------------------------------------------------------------
    // Source lookup: ARF -> ROB -> result buses
    // (written out per source: a function reading module state would not be
    //  re-evaluated by every simulator when that state changes)
    // ------------------------------------------------------------------
    always @(*) begin
        s1_tag = map_tag[s1_reg];
        if (s1_reg == 4'd0 || !map_busy[s1_reg])           begin s1_rdy = 1'b1; s1_val = arf[s1_reg]; end
        else if (e_done[s1_tag])                           begin s1_rdy = 1'b1; s1_val = e_val[s1_tag]; end
        else if (cdba_valid && cdba_tag == s1_tag)         begin s1_rdy = 1'b1; s1_val = cdba_val; end
        else if (cdbb_valid && cdbb_tag == s1_tag)         begin s1_rdy = 1'b1; s1_val = cdbb_val; end
        else                                               begin s1_rdy = 1'b0; s1_val = 16'h0000; end
    end

    always @(*) begin
        s2_tag = map_tag[s2_reg];
        if (s2_reg == 4'd0 || !map_busy[s2_reg])           begin s2_rdy = 1'b1; s2_val = arf[s2_reg]; end
        else if (e_done[s2_tag])                           begin s2_rdy = 1'b1; s2_val = e_val[s2_tag]; end
        else if (cdba_valid && cdba_tag == s2_tag)         begin s2_rdy = 1'b1; s2_val = cdba_val; end
        else if (cdbb_valid && cdbb_tag == s2_tag)         begin s2_rdy = 1'b1; s2_val = cdbb_val; end
        else                                               begin s2_rdy = 1'b0; s2_val = 16'h0000; end
    end

    always @(*) begin
        z_tag = mz_tag;
        if (!mz_busy)                                 begin z_rdy = 1'b1; z_val = arf_z; end
        else if (e_done[mz_tag])                      begin z_rdy = 1'b1; z_val = e_z[mz_tag]; end
        else if (cdba_valid && cdba_tag == mz_tag)    begin z_rdy = 1'b1; z_val = cdba_z; end
        else                                          begin z_rdy = 1'b0; z_val = 1'b0; end

        nv_tag = mnv_tag;
        if (!mnv_busy)                                begin nv_rdy = 1'b1; nv_val = {arf_n, arf_v}; end
        else if (e_done[mnv_tag])                     begin nv_rdy = 1'b1; nv_val = {e_n[mnv_tag], e_v[mnv_tag]}; end
        else if (cdba_valid && cdba_tag == mnv_tag)   begin nv_rdy = 1'b1; nv_val = {cdba_n, cdba_v}; end
        else                                          begin nv_rdy = 1'b0; nv_val = 2'b00; end
    end

    // ------------------------------------------------------------------
    // Commit
    // ------------------------------------------------------------------
    assign commit_en         = !empty && e_done[head_r] && !commit_stall;
    assign commit_pc         = e_pc[head_r];
    assign commit_instr      = e_instr[head_r];
    assign commit_wr_rd      = e_wr_rd[head_r];
    assign commit_rd         = e_rd[head_r];
    assign commit_val        = e_val[head_r];
    assign commit_is_store   = e_is_store[head_r];
    assign commit_is_cond_br = e_is_cond[head_r];
    assign commit_is_br_reg  = e_is_brr[head_r];
    assign commit_is_halt    = e_is_halt[head_r];
    assign commit_taken      = e_taken[head_r];
    assign commit_npc        = e_npc[head_r];
    assign commit_mispred    = e_mispred[head_r];
    assign commit_ghr        = e_ghr[head_r];
    assign commit_sqp        = e_sqp[head_r];

    assign q_ghr        = e_ghr[q_tag];
    assign q_sqp        = e_sqp[q_tag];
    assign q_is_cond_br = e_is_cond[q_tag];

    // ------------------------------------------------------------------
    // Map-table rebuild used on recovery: for every register, the youngest
    // surviving ROB entry (head .. rec_tag, minus the one committing this
    // cycle) that writes it.
    // ------------------------------------------------------------------
    wire [ROB_W-1:0] rec_age = rec_tag - head_r;

    reg [15:0]          rb_busy;
    reg [16*ROB_W-1:0]  rb_tag;
    reg                 rb_zb, rb_nvb;
    reg [ROB_W-1:0]     rb_zt, rb_nvt;
    integer a;
    reg [ROB_W-1:0] idx;
    always @(*) begin
        rb_busy = 16'h0000;
        rb_tag  = {16*ROB_W{1'b0}};
        rb_zb = 1'b0; rb_zt = {ROB_W{1'b0}};
        rb_nvb = 1'b0; rb_nvt = {ROB_W{1'b0}};
        for (a = 0; a < ROB_N; a = a + 1) begin
            idx = head_r + a[ROB_W-1:0];
            if (a <= rec_age && !(a == 0 && commit_en)) begin
                if (e_wr_rd[idx]) begin
                    rb_busy[e_rd[idx]] = 1'b1;
                    rb_tag[e_rd[idx]*ROB_W +: ROB_W] = idx;
                end
                if (e_wr_z[idx])  begin rb_zb  = 1'b1; rb_zt  = idx; end
                if (e_wr_nv[idx]) begin rb_nvb = 1'b1; rb_nvt = idx; end
            end
        end
    end

    // ------------------------------------------------------------------
    // Sequential update
    // ------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            head_r <= {ROB_W{1'b0}};
            tail_r <= {ROB_W{1'b0}};
            count  <= {(ROB_W+1){1'b0}};
            for (i = 0; i < 16; i = i + 1) begin
                arf[i]     <= 16'h0000;
                map_tag[i] <= {ROB_W{1'b0}};
            end
            map_busy <= 16'h0000;
            arf_z <= 1'b0; arf_n <= 1'b0; arf_v <= 1'b0;
            mz_busy <= 1'b0; mnv_busy <= 1'b0;
            mz_tag <= {ROB_W{1'b0}}; mnv_tag <= {ROB_W{1'b0}};
            for (i = 0; i < ROB_N; i = i + 1) begin
                e_done[i]   <= 1'b0;
                e_wr_rd[i]  <= 1'b0;
                e_wr_z[i]   <= 1'b0;
                e_wr_nv[i]  <= 1'b0;
            end
        end else begin
            // -- completion writes --
            if (cdba_valid) begin
                e_done[cdba_tag] <= 1'b1;
                e_val[cdba_tag]  <= cdba_val;
                e_z[cdba_tag]    <= cdba_z;
                e_n[cdba_tag]    <= cdba_n;
                e_v[cdba_tag]    <= cdba_v;
            end
            if (cdbb_valid) begin
                e_done[cdbb_tag] <= 1'b1;
                e_val[cdbb_tag]  <= cdbb_val;
            end
            if (bru_valid) begin
                e_done[bru_tag]    <= 1'b1;
                e_taken[bru_tag]   <= bru_taken;
                e_npc[bru_tag]     <= bru_npc;
                e_mispred[bru_tag] <= bru_mispred;
            end
            if (stu_valid)
                e_done[stu_tag] <= 1'b1;

            // -- commit: update architectural state, release map entries --
            if (commit_en) begin
                if (e_wr_rd[head_r]) begin
                    arf[e_rd[head_r]] <= e_val[head_r];
                    if (map_busy[e_rd[head_r]] && map_tag[e_rd[head_r]] == head_r)
                        map_busy[e_rd[head_r]] <= 1'b0;
                end
                if (e_wr_z[head_r]) begin
                    arf_z <= e_z[head_r];
                    if (mz_busy && mz_tag == head_r) mz_busy <= 1'b0;
                end
                if (e_wr_nv[head_r]) begin
                    arf_n <= e_n[head_r];
                    arf_v <= e_v[head_r];
                    if (mnv_busy && mnv_tag == head_r) mnv_busy <= 1'b0;
                end
            end

            // -- dispatch: allocate tail entry, rename destination --
            if (disp_en) begin
                e_done[tail_r]     <= disp_done;
                e_val[tail_r]      <= disp_value;
                e_z[tail_r]        <= 1'b0;
                e_n[tail_r]        <= 1'b0;
                e_v[tail_r]        <= 1'b0;
                e_wr_rd[tail_r]    <= disp_wr_rd;
                e_rd[tail_r]       <= disp_rd;
                e_wr_z[tail_r]     <= disp_wr_z;
                e_wr_nv[tail_r]    <= disp_wr_nv;
                e_pc[tail_r]       <= disp_pc;
                e_instr[tail_r]    <= disp_instr;
                e_is_store[tail_r] <= disp_is_store;
                e_is_cond[tail_r]  <= disp_is_cond_br;
                e_is_brr[tail_r]   <= disp_is_br_reg;
                e_is_halt[tail_r]  <= disp_is_halt;
                e_taken[tail_r]    <= 1'b0;
                e_npc[tail_r]      <= disp_pc + 16'd2;
                e_mispred[tail_r]  <= 1'b0;
                e_ghr[tail_r]      <= disp_ghr;
                e_sqp[tail_r]      <= disp_sqp;
                if (disp_wr_rd) begin
                    map_busy[disp_rd] <= 1'b1;
                    map_tag[disp_rd]  <= tail_r;
                end
                if (disp_wr_z)  begin mz_busy  <= 1'b1; mz_tag  <= tail_r; end
                if (disp_wr_nv) begin mnv_busy <= 1'b1; mnv_tag <= tail_r; end
            end

            // -- recovery: rebuild the map from the surviving entries --
            if (rec_valid) begin
                map_busy <= rb_busy;
                for (i = 0; i < 16; i = i + 1)
                    map_tag[i] <= rb_tag[i*ROB_W +: ROB_W];
                mz_busy  <= rb_zb;  mz_tag  <= rb_zt;
                mnv_busy <= rb_nvb; mnv_tag <= rb_nvt;
            end

            // -- pointers --
            head_r <= head_r + {{(ROB_W-1){1'b0}}, commit_en};
            if (rec_valid) begin
                tail_r <= rec_tag + 1'b1;
                count  <= {1'b0, rec_age} + 1'b1 - {{ROB_W{1'b0}}, commit_en};
            end else begin
                tail_r <= tail_r + {{(ROB_W-1){1'b0}}, disp_en};
                count  <= count + {{ROB_W{1'b0}}, disp_en} - {{ROB_W{1'b0}}, commit_en};
            end
        end
    end
endmodule
