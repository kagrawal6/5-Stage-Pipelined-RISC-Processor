// In-order front end: fetch one instruction per cycle from the I-cache,
// predict its next PC, and push it into the instruction fetch queue (IFQ).
//
// Next-PC prediction (decided in the fetch cycle, so a correctly predicted
// taken branch costs no bubbles):
//   B  UNCOND     -> always taken, target = PC + 2 + (imm9 << 1)
//   B  cond       -> direction predictor; same target
//   BR (any cond) -> taken only if the BTB has a target (and the direction
//                    predictor says taken for conditional BR)
//   HLT           -> fetch stops until a redirect (it may be on a wrong path)
//
// The global history register (GHR) is updated speculatively with every
// predicted conditional branch. Each IFQ entry carries the GHR value seen
// before its own prediction so that, on a misprediction, the back end can
// restore the history as {saved GHR, actual outcome}.
module frontend #(
    parameter BP_TYPE = 6,
    parameter GHR_W   = 16,
    parameter IFQ_W   = 2               // IFQ has 2**IFQ_W entries
) (
    input  wire             clk,
    input  wire             rst_n,

    // ---- I-cache ----
    output wire [15:0]      ic_addr,
    output wire             ic_en,
    input  wire             ic_hit,
    input  wire [15:0]      ic_data,
    output wire             i_miss_req,

    // ---- IFQ head (to dispatch) ----
    output wire             ifq_valid,
    output wire [15:0]      ifq_pc,
    output wire [15:0]      ifq_instr,
    output wire [15:0]      ifq_pred_npc,
    output wire [GHR_W-1:0] ifq_ghr,
    input  wire             ifq_deq,

    // ---- redirect from the back end ----
    input  wire             redirect,
    input  wire [15:0]      redirect_pc,
    input  wire [GHR_W-1:0] redirect_ghr,

    // ---- training at commit ----
    input  wire             upd_dir,
    input  wire [15:0]      upd_pc,
    input  wire [GHR_W-1:0] upd_ghr,
    input  wire             upd_taken,
    input  wire             upd_btb,
    input  wire [15:0]      upd_btb_target,

    output wire             fetch_fire       // stat
);
`include "ooo_defs.vh"
    localparam IFQ_N = 1 << IFQ_W;

    reg [15:0]      fetch_pc;
    reg [GHR_W-1:0] ghr;
    reg             stopped;            // fetched a HLT

    // ------------------------------------------------------------------
    // Predecode + prediction
    // ------------------------------------------------------------------
    wire [3:0]  op      = ic_data[15:12];
    wire [2:0]  cond    = ic_data[11:9];
    wire        is_b    = (op == OP_B);
    wire        is_br   = (op == OP_BR);
    wire        is_cond = (is_b | is_br) & (cond != 3'b111);
    wire [15:0] pc_plus2 = fetch_pc + 16'd2;
    wire [15:0] b_target = pc_plus2 + {{6{ic_data[8]}}, ic_data[8:0], 1'b0};

    wire        dir_taken;
    wire        btb_hit;
    wire [15:0] btb_target;

    branch_predictor #(.BP_TYPE(BP_TYPE), .GHR_W(GHR_W)) u_bp (
        .clk(clk), .rst_n(rst_n),
        .pred_pc(fetch_pc), .pred_ghr(ghr), .pred_backward(ic_data[8]),
        .pred_taken(dir_taken),
        .upd_en(upd_dir), .upd_pc(upd_pc), .upd_ghr(upd_ghr), .upd_taken(upd_taken));

    btb u_btb (
        .clk(clk), .rst_n(rst_n),
        .pc(fetch_pc), .hit(btb_hit), .target(btb_target),
        .upd_en(upd_btb), .upd_pc(upd_pc), .upd_target(upd_btb_target));

    reg        pred_taken;
    reg [15:0] pred_npc;
    always @(*) begin
        pred_taken = 1'b0;
        pred_npc   = pc_plus2;
        if (is_b) begin
            pred_taken = !is_cond | dir_taken;
            if (pred_taken) pred_npc = b_target;
        end else if (is_br) begin
            pred_taken = (!is_cond | dir_taken) & btb_hit;
            if (pred_taken) pred_npc = btb_target;
        end
    end

    // ------------------------------------------------------------------
    // IFQ
    // ------------------------------------------------------------------
    reg [15:0]      q_pc    [0:IFQ_N-1];
    reg [15:0]      q_instr [0:IFQ_N-1];
    reg [15:0]      q_npc   [0:IFQ_N-1];
    reg [GHR_W-1:0] q_ghr   [0:IFQ_N-1];
    reg [IFQ_W-1:0] q_head, q_tail;
    reg [IFQ_W:0]   q_count;

    assign ic_addr    = fetch_pc;
    assign ic_en      = !stopped;
    assign i_miss_req = !stopped & !ic_hit;
    assign fetch_fire = !redirect & !stopped & ic_hit & (q_count != IFQ_N);

    assign ifq_valid    = (q_count != 0);
    assign ifq_pc       = q_pc[q_head];
    assign ifq_instr    = q_instr[q_head];
    assign ifq_pred_npc = q_npc[q_head];
    assign ifq_ghr      = q_ghr[q_head];

    always @(posedge clk) begin
        if (!rst_n) begin
            fetch_pc <= 16'h0000;
            ghr      <= {GHR_W{1'b0}};
            stopped  <= 1'b0;
            q_head   <= {IFQ_W{1'b0}};
            q_tail   <= {IFQ_W{1'b0}};
            q_count  <= {(IFQ_W+1){1'b0}};
        end else if (redirect) begin
            fetch_pc <= redirect_pc;
            ghr      <= redirect_ghr;
            stopped  <= 1'b0;
            q_head   <= {IFQ_W{1'b0}};
            q_tail   <= {IFQ_W{1'b0}};
            q_count  <= {(IFQ_W+1){1'b0}};
        end else begin
            if (fetch_fire) begin
                q_pc[q_tail]    <= fetch_pc;
                q_instr[q_tail] <= ic_data;
                q_npc[q_tail]   <= pred_npc;
                q_ghr[q_tail]   <= ghr;
                q_tail          <= q_tail + 1'b1;
                fetch_pc        <= pred_npc;
                if (is_cond) ghr <= {ghr[GHR_W-2:0], pred_taken};
                if (op == OP_HLT) stopped <= 1'b1;
            end
            if (ifq_deq) q_head <= q_head + 1'b1;
            q_count <= q_count + {{IFQ_W{1'b0}}, fetch_fire} - {{IFQ_W{1'b0}}, ifq_deq};
        end
    end
endmodule
