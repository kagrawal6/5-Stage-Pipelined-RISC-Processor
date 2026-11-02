// Direction-predictor wrapper: picks one predictor with BP_TYPE
// (see ooo_defs.vh) behind a common interface.
module branch_predictor #(
    parameter BP_TYPE = 6,
    parameter GHR_W   = 16
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [15:0]      pred_pc,
    input  wire [GHR_W-1:0] pred_ghr,
    input  wire             pred_backward,   // B with a negative offset (for BTFN)
    output wire             pred_taken,
    input  wire             upd_en,
    input  wire [15:0]      upd_pc,
    input  wire [GHR_W-1:0] upd_ghr,
    input  wire             upd_taken
);
`include "ooo_defs.vh"
    generate
        if (BP_TYPE == BP_STATIC_NT) begin : g_nt
            assign pred_taken = 1'b0;
        end else if (BP_TYPE == BP_BTFN) begin : g_btfn
            assign pred_taken = pred_backward;
        end else if (BP_TYPE == BP_BIMODAL) begin : g_bimodal
            bp_bimodal #(.GHR_W(GHR_W)) u_bp (
                .clk(clk), .rst_n(rst_n),
                .pred_pc(pred_pc), .pred_ghr(pred_ghr), .pred_taken(pred_taken),
                .upd_en(upd_en), .upd_pc(upd_pc), .upd_ghr(upd_ghr), .upd_taken(upd_taken));
        end else if (BP_TYPE == BP_GSHARE) begin : g_gshare
            bp_gshare #(.GHR_W(GHR_W)) u_bp (
                .clk(clk), .rst_n(rst_n),
                .pred_pc(pred_pc), .pred_ghr(pred_ghr), .pred_taken(pred_taken),
                .upd_en(upd_en), .upd_pc(upd_pc), .upd_ghr(upd_ghr), .upd_taken(upd_taken));
        end else if (BP_TYPE == BP_TOURNAMENT) begin : g_tournament
            bp_tournament #(.GHR_W(GHR_W)) u_bp (
                .clk(clk), .rst_n(rst_n),
                .pred_pc(pred_pc), .pred_ghr(pred_ghr), .pred_taken(pred_taken),
                .upd_en(upd_en), .upd_pc(upd_pc), .upd_ghr(upd_ghr), .upd_taken(upd_taken));
        end else if (BP_TYPE == BP_PERCEPTRON) begin : g_perceptron
            bp_perceptron #(.GHR_W(GHR_W)) u_bp (
                .clk(clk), .rst_n(rst_n),
                .pred_pc(pred_pc), .pred_ghr(pred_ghr), .pred_taken(pred_taken),
                .upd_en(upd_en), .upd_pc(upd_pc), .upd_ghr(upd_ghr), .upd_taken(upd_taken));
        end else begin : g_tage
            bp_tage #(.GHR_W(GHR_W)) u_bp (
                .clk(clk), .rst_n(rst_n),
                .pred_pc(pred_pc), .pred_ghr(pred_ghr), .pred_taken(pred_taken),
                .upd_en(upd_en), .upd_pc(upd_pc), .upd_ghr(upd_ghr), .upd_taken(upd_taken));
        end
    endgenerate
endmodule


// Branch target buffer for BR (register-indirect) branches. B targets are
// computed directly from the instruction bits during fetch, so only BR needs
// a stored target. Direct-mapped, 16 entries, trained at commit.
module btb #(
    parameter IDX_W = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pc,
    output wire        hit,
    output wire [15:0] target,
    input  wire        upd_en,
    input  wire [15:0] upd_pc,
    input  wire [15:0] upd_target
);
    localparam N     = 1 << IDX_W;
    localparam TAG_W = 15 - IDX_W;

    reg             valid [0:N-1];
    reg [TAG_W-1:0] tag   [0:N-1];
    reg [15:0]      tgt   [0:N-1];

    wire [IDX_W-1:0] pi = pc[IDX_W:1];
    wire [IDX_W-1:0] ui = upd_pc[IDX_W:1];
    assign hit    = valid[pi] && (tag[pi] == pc[15:IDX_W+1]);
    assign target = tgt[pi];

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) valid[i] <= 1'b0;
        end else if (upd_en) begin
            valid[ui] <= 1'b1;
            tag[ui]   <= upd_pc[15:IDX_W+1];
            tgt[ui]   <= upd_target;
        end
    end
endmodule
