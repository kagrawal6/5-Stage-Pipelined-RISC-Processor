// TAGE-lite (Seznec, Lecture 3): a bimodal base predictor plus three tagged
// tables indexed with geometrically longer global histories (4, 8, 16).
//
//   * Each tagged entry: valid, 8-bit tag, 3-bit counter (>= 4 = taken),
//     2-bit usefulness counter u.
//   * Provider = the hitting table with the longest history; the alternate
//     prediction comes from the next shorter hit (or the base table).
//   * Update at commit:
//       - provider counter moves toward the outcome (base if no provider)
//       - if provider and alternate disagreed, u++ when the provider was
//         right, u-- when it was wrong
//       - on a misprediction, allocate one entry in a longer table whose
//         u == 0; if none is free, age (u--) all longer candidates.
module bp_tage #(
    parameter GHR_W = 16
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [15:0]      pred_pc,
    input  wire [GHR_W-1:0] pred_ghr,
    output wire             pred_taken,
    input  wire             upd_en,
    input  wire [15:0]      upd_pc,
    input  wire [GHR_W-1:0] upd_ghr,
    input  wire             upd_taken
);
    localparam T_IDX_W = 7;                  // 128 entries per tagged table
    localparam T_N     = 1 << T_IDX_W;

    reg [1:0] base [0:511];

    // Tagged tables 1..3 stored back to back: entry (t, i) is at (t-1)*T_N + i.
    reg       t_valid [0:3*T_N-1];
    reg [7:0] t_tag   [0:3*T_N-1];
    reg [2:0] t_ctr   [0:3*T_N-1];
    reg [1:0] t_u     [0:3*T_N-1];

    function integer hist_len;
        input integer t;
        hist_len = (t == 1) ? 4 : (t == 2) ? 8 : 16;
    endfunction

    // Fold the newest `len` history bits down to 7 bits (index hash).
    function [6:0] fold_idx;
        input [GHR_W-1:0] h;
        input integer len;
        integer j;
        begin
            fold_idx = 7'd0;
            for (j = 0; j < GHR_W; j = j + 1)
                if (j < len) fold_idx[j % 7] = fold_idx[j % 7] ^ h[j];
        end
    endfunction

    // A different fold (8 bits, rotated) for the tag, so index and tag
    // aliasing are not correlated.
    function [7:0] fold_tag;
        input [GHR_W-1:0] h;
        input integer len;
        integer j;
        begin
            fold_tag = 8'd0;
            for (j = 0; j < GHR_W; j = j + 1)
                if (j < len) fold_tag[(j + 3) % 8] = fold_tag[(j + 3) % 8] ^ h[j];
        end
    endfunction

    function [T_IDX_W+1:0] entry;            // flat array position of (t, pc, h)
        input integer t;
        input [15:0] pc;
        input [GHR_W-1:0] h;
        reg [T_IDX_W-1:0] ix;
        begin
            ix = pc[7:1] ^ pc[14:8] ^ fold_idx(h, hist_len(t));
            entry = (t - 1) * T_N + ix;
        end
    endfunction

    function [7:0] tag_of;
        input integer t;
        input [15:0] pc;
        input [GHR_W-1:0] h;
        tag_of = pc[8:1] ^ fold_tag(h, hist_len(t));
    endfunction

    // ------------------------------------------------------------------
    // Lookup, once for the fetch-time prediction (p_*) and once for the
    // branch being trained at commit (u_*). The provider is the longest
    // hitting table; the alternate prediction is the next shorter hit.
    // ------------------------------------------------------------------
    reg [1:0]         p_prov, u_prov;
    reg               p_provpred, p_alt, u_provpred, u_alt;
    reg [T_IDX_W+1:0] pe, ue;
    integer tl;
    always @(*) begin
        p_prov = 2'd0; p_provpred = base[pred_pc[9:1]][1]; p_alt = p_provpred;
        u_prov = 2'd0; u_provpred = base[upd_pc[9:1]][1];  u_alt = u_provpred;
        for (tl = 1; tl <= 3; tl = tl + 1) begin
            pe = entry(tl, pred_pc, pred_ghr);
            if (t_valid[pe] && t_tag[pe] == tag_of(tl, pred_pc, pred_ghr)) begin
                p_alt = p_provpred; p_prov = tl[1:0]; p_provpred = t_ctr[pe][2];
            end
            ue = entry(tl, upd_pc, upd_ghr);
            if (t_valid[ue] && t_tag[ue] == tag_of(tl, upd_pc, upd_ghr)) begin
                u_alt = u_provpred; u_prov = tl[1:0]; u_provpred = t_ctr[ue][2];
            end
        end
    end

    assign pred_taken = p_provpred;
    wire   u_mispred  = (u_provpred != upd_taken);

    wire [T_IDX_W+1:0] u_e1 = entry(1, upd_pc, upd_ghr);
    wire [T_IDX_W+1:0] u_e2 = entry(2, upd_pc, upd_ghr);
    wire [T_IDX_W+1:0] u_e3 = entry(3, upd_pc, upd_ghr);
    wire [T_IDX_W+1:0] u_ep = (u_prov == 2'd1) ? u_e1 : (u_prov == 2'd2) ? u_e2 : u_e3;

    // ------------------------------------------------------------------
    // Update
    // ------------------------------------------------------------------
    integer i, t;
    reg allocated;
    reg [T_IDX_W+1:0] ea;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 512; i = i + 1) base[i] <= 2'b01;
            for (i = 0; i < 3*T_N; i = i + 1) begin
                t_valid[i] <= 1'b0;
                t_tag[i]   <= 8'h00;
                t_ctr[i]   <= 3'b011;
                t_u[i]     <= 2'b00;
            end
        end else if (upd_en) begin
            // 1. train the provider (or the base table)
            if (u_prov == 2'd0) begin
                if (upd_taken && base[upd_pc[9:1]] != 2'b11)  base[upd_pc[9:1]] <= base[upd_pc[9:1]] + 2'b01;
                if (!upd_taken && base[upd_pc[9:1]] != 2'b00) base[upd_pc[9:1]] <= base[upd_pc[9:1]] - 2'b01;
            end else begin
                if (upd_taken && t_ctr[u_ep] != 3'b111)  t_ctr[u_ep] <= t_ctr[u_ep] + 3'b001;
                if (!upd_taken && t_ctr[u_ep] != 3'b000) t_ctr[u_ep] <= t_ctr[u_ep] - 3'b001;
                // 2. usefulness
                if (u_provpred != u_alt) begin
                    if (u_provpred == upd_taken && t_u[u_ep] != 2'b11) t_u[u_ep] <= t_u[u_ep] + 2'b01;
                    if (u_provpred != upd_taken && t_u[u_ep] != 2'b00) t_u[u_ep] <= t_u[u_ep] - 2'b01;
                end
            end

            // 3. allocate on a misprediction in a longer-history table
            if (u_mispred && u_prov != 2'd3) begin
                allocated = 1'b0;
                for (t = 1; t <= 3; t = t + 1) begin
                    ea = (t == 1) ? u_e1 : (t == 2) ? u_e2 : u_e3;
                    if (t > u_prov && !allocated && t_u[ea] == 2'b00) begin
                        allocated  = 1'b1;
                        t_valid[ea] <= 1'b1;
                        t_tag[ea]   <= tag_of(t, upd_pc, upd_ghr);
                        t_ctr[ea]   <= upd_taken ? 3'b100 : 3'b011;
                        t_u[ea]     <= 2'b00;
                    end
                end
                if (!allocated) begin
                    for (t = 1; t <= 3; t = t + 1) begin
                        ea = (t == 1) ? u_e1 : (t == 2) ? u_e2 : u_e3;
                        if (t > u_prov && t_u[ea] != 2'b00) t_u[ea] <= t_u[ea] - 2'b01;
                    end
                end
            end
        end
    end
endmodule
