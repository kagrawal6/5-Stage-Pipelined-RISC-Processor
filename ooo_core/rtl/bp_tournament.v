// Tournament (hybrid) predictor in the style of the Alpha 21264 (Lecture 3):
//   * global component: gshare, 1024 x 2-bit
//   * local component : 64-entry local history table (10 bits per branch)
//                       indexing a 1024 x 3-bit counter table (PAg)
//   * chooser         : 1024 x 2-bit, indexed by global history;
//                       >= 2 means "trust the global component"
// Local histories are updated at commit (non-speculatively).
module bp_tournament #(
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
    reg [1:0] gpht   [0:1023];
    reg [9:0] lht    [0:63];
    reg [2:0] lpht   [0:1023];
    reg [1:0] chooser[0:1023];

    // ---- prediction ----
    wire [9:0] p_gi = pred_pc[10:1] ^ pred_ghr[9:0];
    wire [9:0] p_li = lht[pred_pc[6:1]];
    wire       p_g  = gpht[p_gi][1];
    wire       p_l  = lpht[p_li][2];
    assign pred_taken = chooser[pred_ghr[9:0]][1] ? p_g : p_l;

    // ---- update ----
    wire [9:0] u_gi = upd_pc[10:1] ^ upd_ghr[9:0];
    wire [9:0] u_li = lht[upd_pc[6:1]];
    wire [9:0] u_ci = upd_ghr[9:0];
    wire       u_g  = gpht[u_gi][1];
    wire       u_l  = lpht[u_li][2];

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 1024; i = i + 1) begin
                gpht[i]    <= 2'b01;
                lpht[i]    <= 3'b011;
                chooser[i] <= 2'b01;     // start out weakly trusting local
            end
            for (i = 0; i < 64; i = i + 1) lht[i] <= 10'h000;
        end else if (upd_en) begin
            if (upd_taken && gpht[u_gi] != 2'b11)  gpht[u_gi] <= gpht[u_gi] + 2'b01;
            if (!upd_taken && gpht[u_gi] != 2'b00) gpht[u_gi] <= gpht[u_gi] - 2'b01;

            if (upd_taken && lpht[u_li] != 3'b111)  lpht[u_li] <= lpht[u_li] + 3'b001;
            if (!upd_taken && lpht[u_li] != 3'b000) lpht[u_li] <= lpht[u_li] - 3'b001;

            if (u_g != u_l) begin
                if (u_g == upd_taken && chooser[u_ci] != 2'b11) chooser[u_ci] <= chooser[u_ci] + 2'b01;
                if (u_l == upd_taken && chooser[u_ci] != 2'b00) chooser[u_ci] <= chooser[u_ci] - 2'b01;
            end

            lht[upd_pc[6:1]] <= {lht[upd_pc[6:1]][8:0], upd_taken};
        end
    end
endmodule
