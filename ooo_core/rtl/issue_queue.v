// Unified issue queue (reservation stations), data-capture style (Lecture 6).
//
//  * Each entry holds up to four source operands: s1, s2 (registers), Z and
//    N+V (flags). A source is either ready (value captured) or waiting on the
//    ROB tag of its producer.
//  * Wakeup: every cycle both result buses (CDB A = ALU, CDB B = loads) are
//    compared against all waiting tags; matches capture the value.
//  * Select: one instruction per functional-unit class per cycle (ALU, BRU,
//    LDU, STU), oldest first (age = distance from the ROB head).
//  * The result buses are also bypassed into select, so a dependent
//    instruction can issue the cycle after its producer (back-to-back).
//  * Loads may only issue when every older store has a known address
//    (conservative memory disambiguation) and the load unit is free.
module issue_queue #(
    parameter IQ_N  = 8,
    parameter ROB_W = 4,
    parameter SQ_W  = 3
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [ROB_W-1:0]   rob_head,

    // ---- dispatch ----
    input  wire               disp_en,
    input  wire [1:0]         disp_fu,
    input  wire [ROB_W-1:0]   disp_tag,
    input  wire [15:0]        disp_instr,
    input  wire [15:0]        disp_pc,
    input  wire [15:0]        disp_pred_npc,
    input  wire [SQ_W:0]      disp_sqp,
    input  wire               disp_s1_rdy,
    input  wire [ROB_W-1:0]   disp_s1_tag,
    input  wire [15:0]        disp_s1_val,
    input  wire               disp_s2_rdy,
    input  wire [ROB_W-1:0]   disp_s2_tag,
    input  wire [15:0]        disp_s2_val,
    input  wire               disp_z_rdy,
    input  wire [ROB_W-1:0]   disp_z_tag,
    input  wire               disp_z_val,
    input  wire               disp_nv_rdy,
    input  wire [ROB_W-1:0]   disp_nv_tag,
    input  wire [1:0]         disp_nv_val,
    output wire               full,
    output reg  [$clog2(IQ_N):0] occupancy,

    // ---- wakeup ----
    input  wire               cdba_valid,
    input  wire [ROB_W-1:0]   cdba_tag,
    input  wire [15:0]        cdba_val,
    input  wire               cdba_z,
    input  wire               cdba_n,
    input  wire               cdba_v,
    input  wire               cdbb_valid,
    input  wire [ROB_W-1:0]   cdbb_tag,
    input  wire [15:0]        cdbb_val,

    // ---- load scheduling constraints ----
    input  wire               ldu_busy,
    input  wire [SQ_W:0]      sq_head,
    input  wire [(1<<SQ_W)-1:0] sq_unresolved,

    // ---- recovery ----
    input  wire               rec_valid,
    input  wire [ROB_W-1:0]   rec_tag,

    // ---- issue: ALU ----
    output wire               alu_issue,
    output wire [ROB_W-1:0]   alu_tag,
    output wire [15:0]        alu_instr,
    output wire [15:0]        alu_a,
    output wire [15:0]        alu_b,
    // ---- issue: branch unit ----
    output wire               bru_issue,
    output wire [ROB_W-1:0]   bru_tag,
    output wire [15:0]        bru_instr,
    output wire [15:0]        bru_pc,
    output wire [15:0]        bru_pred_npc,
    output wire [15:0]        bru_a,
    output wire               bru_z,
    output wire               bru_n,
    output wire               bru_v,
    // ---- issue: load unit ----
    output wire               ldu_issue,
    output wire [ROB_W-1:0]   ldu_tag,
    output wire [15:0]        ldu_instr,
    output wire [15:0]        ldu_a,
    output wire [SQ_W:0]      ldu_sqp,
    // ---- issue: store unit ----
    output wire               stu_issue,
    output wire [ROB_W-1:0]   stu_tag,
    output wire [15:0]        stu_instr,
    output wire [15:0]        stu_a,
    output wire [15:0]        stu_b,
    output wire [SQ_W:0]      stu_sqp
);
`include "ooo_defs.vh"
    localparam IQ_W = $clog2(IQ_N);
    localparam SQ_N = 1 << SQ_W;

    // ------------------------------------------------------------------
    // Entries
    // ------------------------------------------------------------------
    reg [IQ_N-1:0]  valid;
    reg [1:0]       fu       [0:IQ_N-1];
    reg [ROB_W-1:0] tag      [0:IQ_N-1];
    reg [15:0]      instr    [0:IQ_N-1];
    reg [15:0]      pc       [0:IQ_N-1];
    reg [15:0]      pred_npc [0:IQ_N-1];
    reg [SQ_W:0]    sqp      [0:IQ_N-1];
    reg             s1_rdy   [0:IQ_N-1];
    reg [ROB_W-1:0] s1_tag   [0:IQ_N-1];
    reg [15:0]      s1_val   [0:IQ_N-1];
    reg             s2_rdy   [0:IQ_N-1];
    reg [ROB_W-1:0] s2_tag   [0:IQ_N-1];
    reg [15:0]      s2_val   [0:IQ_N-1];
    reg             z_rdy    [0:IQ_N-1];
    reg [ROB_W-1:0] z_tag    [0:IQ_N-1];
    reg             z_val    [0:IQ_N-1];
    reg             nv_rdy   [0:IQ_N-1];
    reg [ROB_W-1:0] nv_tag   [0:IQ_N-1];
    reg [1:0]       nv_val   [0:IQ_N-1];

    // ------------------------------------------------------------------
    // Per-entry readiness with result-bus bypass (packed for comb logic)
    // ------------------------------------------------------------------
    reg [IQ_N-1:0]       ready;
    reg [IQ_N*16-1:0]    a_eff, b_eff;
    reg [IQ_N-1:0]       z_eff;
    reg [IQ_N*2-1:0]     nv_eff;
    reg [IQ_N*ROB_W-1:0] age;
    reg [IQ_N-1:0]       older_unres;

    integer e, k;
    reg s1_ok, s2_ok, z_ok, nv_ok;
    reg [SQ_W:0] n_older;
    reg [SQ_W-1:0] rel;

    always @(*) begin
        for (e = 0; e < IQ_N; e = e + 1) begin
            age[e*ROB_W +: ROB_W] = tag[e] - rob_head;

            s1_ok = s1_rdy[e] | (cdba_valid & (cdba_tag == s1_tag[e])) |
                                (cdbb_valid & (cdbb_tag == s1_tag[e]));
            a_eff[e*16 +: 16] = s1_rdy[e] ? s1_val[e] :
                                (cdba_valid & (cdba_tag == s1_tag[e])) ? cdba_val : cdbb_val;

            s2_ok = s2_rdy[e] | (cdba_valid & (cdba_tag == s2_tag[e])) |
                                (cdbb_valid & (cdbb_tag == s2_tag[e]));
            b_eff[e*16 +: 16] = s2_rdy[e] ? s2_val[e] :
                                (cdba_valid & (cdba_tag == s2_tag[e])) ? cdba_val : cdbb_val;

            z_ok     = z_rdy[e] | (cdba_valid & (cdba_tag == z_tag[e]));
            z_eff[e] = z_rdy[e] ? z_val[e] : cdba_z;

            nv_ok    = nv_rdy[e] | (cdba_valid & (cdba_tag == nv_tag[e]));
            nv_eff[e*2 +: 2] = nv_rdy[e] ? nv_val[e] : {cdba_n, cdba_v};

            // Any older store (SQ slots sq_head .. sqp-1) with unknown address?
            older_unres[e] = 1'b0;
            n_older = sqp[e] - sq_head;
            for (k = 0; k < SQ_N; k = k + 1) begin
                rel = k[SQ_W-1:0] - sq_head[SQ_W-1:0];
                if ({1'b0, rel} < n_older && sq_unresolved[k])
                    older_unres[e] = 1'b1;
            end

            ready[e] = valid[e] & s1_ok & s2_ok & z_ok & nv_ok &
                       ((fu[e] != FU_LDU) | (!ldu_busy & !older_unres[e]));
        end
    end

    // ------------------------------------------------------------------
    // Select: oldest ready entry for each functional-unit class
    // ------------------------------------------------------------------
    reg [3:0]        sel_found;
    reg [4*IQ_W-1:0] sel_idx;
    reg [4*ROB_W-1:0] best_age;
    integer f, es;
    always @(*) begin
        sel_found = 4'b0000;
        sel_idx   = {4*IQ_W{1'b0}};
        best_age  = {4*ROB_W{1'b0}};
        for (f = 0; f < 4; f = f + 1) begin
            for (es = 0; es < IQ_N; es = es + 1) begin
                if (ready[es] && fu[es] == f[1:0] &&
                    (!sel_found[f] || age[es*ROB_W +: ROB_W] < best_age[f*ROB_W +: ROB_W])) begin
                    sel_found[f] = 1'b1;
                    sel_idx[f*IQ_W +: IQ_W] = es[IQ_W-1:0];
                    best_age[f*ROB_W +: ROB_W] = age[es*ROB_W +: ROB_W];
                end
            end
        end
    end

    wire [IQ_W-1:0] alu_i = sel_idx[FU_ALU*IQ_W +: IQ_W];
    wire [IQ_W-1:0] bru_i = sel_idx[FU_BRU*IQ_W +: IQ_W];
    wire [IQ_W-1:0] ldu_i = sel_idx[FU_LDU*IQ_W +: IQ_W];
    wire [IQ_W-1:0] stu_i = sel_idx[FU_STU*IQ_W +: IQ_W];

    assign alu_issue    = sel_found[FU_ALU];
    assign alu_tag      = tag[alu_i];
    assign alu_instr    = instr[alu_i];
    assign alu_a        = a_eff[alu_i*16 +: 16];
    assign alu_b        = b_eff[alu_i*16 +: 16];

    assign bru_issue    = sel_found[FU_BRU];
    assign bru_tag      = tag[bru_i];
    assign bru_instr    = instr[bru_i];
    assign bru_pc       = pc[bru_i];
    assign bru_pred_npc = pred_npc[bru_i];
    assign bru_a        = a_eff[bru_i*16 +: 16];
    assign bru_z        = z_eff[bru_i];
    assign {bru_n, bru_v} = nv_eff[bru_i*2 +: 2];

    assign ldu_issue    = sel_found[FU_LDU];
    assign ldu_tag      = tag[ldu_i];
    assign ldu_instr    = instr[ldu_i];
    assign ldu_a        = a_eff[ldu_i*16 +: 16];
    assign ldu_sqp      = sqp[ldu_i];

    assign stu_issue    = sel_found[FU_STU];
    assign stu_tag      = tag[stu_i];
    assign stu_instr    = instr[stu_i];
    assign stu_a        = a_eff[stu_i*16 +: 16];
    assign stu_b        = b_eff[stu_i*16 +: 16];
    assign stu_sqp      = sqp[stu_i];

    // ------------------------------------------------------------------
    // Free-slot allocation
    // ------------------------------------------------------------------
    reg [IQ_W-1:0] free_idx;
    reg            free_found;
    integer ef;
    always @(*) begin
        free_found = 1'b0;
        free_idx   = {IQ_W{1'b0}};
        occupancy  = 0;
        for (ef = IQ_N - 1; ef >= 0; ef = ef - 1) begin
            if (!valid[ef]) begin
                free_found = 1'b1;
                free_idx   = ef[IQ_W-1:0];
            end else begin
                occupancy = occupancy + 1'b1;
            end
        end
    end
    assign full = !free_found;

    // ------------------------------------------------------------------
    // Sequential: wakeup, issue, squash, dispatch
    // ------------------------------------------------------------------
    wire [ROB_W-1:0] rec_age = rec_tag - rob_head;
    integer eq;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid <= {IQ_N{1'b0}};
        end else begin
            for (eq = 0; eq < IQ_N; eq = eq + 1) begin
                if (valid[eq]) begin
                    if (!s1_rdy[eq] && cdba_valid && cdba_tag == s1_tag[eq]) begin s1_rdy[eq] <= 1'b1; s1_val[eq] <= cdba_val; end
                    if (!s1_rdy[eq] && cdbb_valid && cdbb_tag == s1_tag[eq]) begin s1_rdy[eq] <= 1'b1; s1_val[eq] <= cdbb_val; end
                    if (!s2_rdy[eq] && cdba_valid && cdba_tag == s2_tag[eq]) begin s2_rdy[eq] <= 1'b1; s2_val[eq] <= cdba_val; end
                    if (!s2_rdy[eq] && cdbb_valid && cdbb_tag == s2_tag[eq]) begin s2_rdy[eq] <= 1'b1; s2_val[eq] <= cdbb_val; end
                    if (!z_rdy[eq]  && cdba_valid && cdba_tag == z_tag[eq])  begin z_rdy[eq]  <= 1'b1; z_val[eq]  <= cdba_z; end
                    if (!nv_rdy[eq] && cdba_valid && cdba_tag == nv_tag[eq]) begin nv_rdy[eq] <= 1'b1; nv_val[eq] <= {cdba_n, cdba_v}; end

                    if (sel_found[fu[eq]] && sel_idx[fu[eq]*IQ_W +: IQ_W] == eq[IQ_W-1:0])
                        valid[eq] <= 1'b0;                        // issued
                    if (rec_valid && age[eq*ROB_W +: ROB_W] > rec_age)
                        valid[eq] <= 1'b0;                        // squashed
                end
            end

            if (disp_en) begin
                valid[free_idx]    <= 1'b1;
                fu[free_idx]       <= disp_fu;
                tag[free_idx]      <= disp_tag;
                instr[free_idx]    <= disp_instr;
                pc[free_idx]       <= disp_pc;
                pred_npc[free_idx] <= disp_pred_npc;
                sqp[free_idx]      <= disp_sqp;
                s1_rdy[free_idx]   <= disp_s1_rdy;
                s1_tag[free_idx]   <= disp_s1_tag;
                s1_val[free_idx]   <= disp_s1_val;
                s2_rdy[free_idx]   <= disp_s2_rdy;
                s2_tag[free_idx]   <= disp_s2_tag;
                s2_val[free_idx]   <= disp_s2_val;
                z_rdy[free_idx]    <= disp_z_rdy;
                z_tag[free_idx]    <= disp_z_tag;
                z_val[free_idx]    <= disp_z_val;
                nv_rdy[free_idx]   <= disp_nv_rdy;
                nv_tag[free_idx]   <= disp_nv_tag;
                nv_val[free_idx]   <= disp_nv_val;
            end
        end
    end
endmodule
