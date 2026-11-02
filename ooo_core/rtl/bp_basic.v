// Simple direction predictors (Lecture 3): bimodal (Smith 2-bit counters)
// and gshare (global history XOR PC).
//
// Every predictor in this directory has the same interface:
//   pred_*  combinational lookup for the branch being fetched, using the
//           speculative global history register (GHR)
//   upd_*   training at commit, using the GHR value the branch saw at fetch
// Bit 0 of the GHR is the most recent branch.

module bp_bimodal #(
    parameter IDX_W = 10,
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
    localparam N = 1 << IDX_W;
    reg [1:0] ctr [0:N-1];

    wire [IDX_W-1:0] pi = pred_pc[IDX_W:1];
    wire [IDX_W-1:0] ui = upd_pc[IDX_W:1];
    assign pred_taken = ctr[pi][1];

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) ctr[i] <= 2'b01;      // weakly not-taken
        end else if (upd_en) begin
            if (upd_taken && ctr[ui] != 2'b11)  ctr[ui] <= ctr[ui] + 2'b01;
            if (!upd_taken && ctr[ui] != 2'b00) ctr[ui] <= ctr[ui] - 2'b01;
        end
    end
endmodule


module bp_gshare #(
    parameter IDX_W = 10,
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
    localparam N = 1 << IDX_W;
    reg [1:0] ctr [0:N-1];

    wire [IDX_W-1:0] pi = pred_pc[IDX_W:1] ^ pred_ghr[IDX_W-1:0];
    wire [IDX_W-1:0] ui = upd_pc[IDX_W:1]  ^ upd_ghr[IDX_W-1:0];
    assign pred_taken = ctr[pi][1];

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) ctr[i] <= 2'b01;
        end else if (upd_en) begin
            if (upd_taken && ctr[ui] != 2'b11)  ctr[ui] <= ctr[ui] + 2'b01;
            if (!upd_taken && ctr[ui] != 2'b00) ctr[ui] <= ctr[ui] - 2'b01;
        end
    end
endmodule
