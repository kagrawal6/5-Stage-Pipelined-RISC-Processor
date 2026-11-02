// Perceptron predictor (Jimenez & Lin, Lecture 3).
//   * 32 perceptrons selected by PC, each with a bias weight w0 and one
//     weight per global-history bit (H = 12), all 8-bit signed.
//   * y = w0 + sum_i (h_i ? +w_i : -w_i); predict taken when y >= 0.
//   * Train at commit when the prediction was wrong or |y| <= theta,
//     with theta = floor(1.93*H + 14) = 37.
module bp_perceptron #(
    parameter IDX_W = 5,
    parameter H     = 12,
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
    localparam N     = 1 << IDX_W;
    localparam W     = H + 1;               // weights per perceptron
    localparam THETA = 37;

    reg signed [7:0] w [0:N*W-1];

    function signed [7:0] bump;               // saturating +/-1
        input signed [7:0] x;
        input up;
        begin
            if (up) bump = (x == 8'sd127)  ? x : x + 8'sd1;
            else    bump = (x == -8'sd128) ? x : x - 8'sd1;
        end
    endfunction

    wire [IDX_W-1:0] pi = pred_pc[IDX_W:1];
    wire [IDX_W-1:0] ui = upd_pc[IDX_W:1];

    // y = w0 + sum(h_i ? w_i : -w_i), for the fetch lookup and the update
    reg signed [11:0] y_pred, y_upd;
    integer j;
    always @(*) begin
        y_pred = {{4{w[pi*W][7]}}, w[pi*W]};
        y_upd  = {{4{w[ui*W][7]}}, w[ui*W]};
        for (j = 0; j < H; j = j + 1) begin
            if (pred_ghr[j]) y_pred = y_pred + {{4{w[pi*W+1+j][7]}}, w[pi*W+1+j]};
            else             y_pred = y_pred - {{4{w[pi*W+1+j][7]}}, w[pi*W+1+j]};
            if (upd_ghr[j])  y_upd  = y_upd  + {{4{w[ui*W+1+j][7]}}, w[ui*W+1+j]};
            else             y_upd  = y_upd  - {{4{w[ui*W+1+j][7]}}, w[ui*W+1+j]};
        end
    end
    assign pred_taken = !y_pred[11];

    wire        upd_pred_taken = !y_upd[11];
    wire [11:0] y_abs  = y_upd[11] ? -y_upd : y_upd;
    wire        train  = (upd_pred_taken != upd_taken) || (y_abs <= THETA);

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < N*W; i = i + 1) w[i] <= 8'sd0;
        end else if (upd_en && train) begin
            w[ui*W] <= bump(w[ui*W], upd_taken);
            for (i = 0; i < H; i = i + 1)
                w[ui*W+1+i] <= bump(w[ui*W+1+i], upd_taken == upd_ghr[i]);
        end
    end
endmodule
