// Load/store unit: store queue + load pipeline (Lecture 7/8: store buffer,
// load bypassing and load forwarding).
//
// Store queue (circular, pointers carry a wrap bit):
//     sq_head .. sq_cmt-1   committed stores waiting to drain to the D-cache
//     sq_cmt  .. sq_tail-1  speculative stores (may be squashed)
//   A store is allocated at dispatch, gets its address+data when the store
//   unit executes it ("resolved"), is marked committed when it retires from
//   the ROB, and is finally written to the D-cache/memory in program order.
//
// Loads:
//   The issue queue only sends a load here once every older store is
//   resolved, so the load can safely bypass older stores to other
//   addresses. If an older store writes the same word, the youngest such
//   store forwards its data. Otherwise the D-cache is read; on a miss the
//   load waits in a pending register (and blocks further loads) until the
//   line has been filled.
module lsu #(
    parameter SQ_W  = 3,
    parameter ROB_W = 4
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [ROB_W-1:0]   rob_head,

    // ---- dispatch ----
    input  wire               sq_alloc,
    output wire [SQ_W:0]      sq_tail_o,
    output wire               sq_full,

    // ---- store execute ----
    input  wire               stu_valid,
    input  wire [SQ_W:0]      stu_sqp,
    input  wire [15:0]        stu_addr,
    input  wire [15:0]        stu_data,

    // ---- commit ----
    input  wire               sq_commit,
    output wire [15:0]        cm_addr,       // store being committed (for the trace)
    output wire [15:0]        cm_data,

    // ---- recovery ----
    input  wire               rec_valid,
    input  wire [ROB_W-1:0]   rec_tag,
    input  wire [SQ_W:0]      rec_sqp,

    // ---- load issue / completion ----
    input  wire               ld_valid,
    input  wire [ROB_W-1:0]   ld_tag,
    input  wire [15:0]        ld_addr,
    input  wire [SQ_W:0]      ld_sqp,
    output wire               ld_busy,
    output wire               ld_done,
    output wire [ROB_W-1:0]   ld_done_tag,
    output wire [15:0]        ld_done_val,
    output wire               ld_forwarded,  // stat: data came from the SQ
    output wire               ld_miss_cycle, // stat: load waiting on a miss

    // ---- scheduling info for the issue queue ----
    output wire [SQ_W:0]      sq_head_o,
    output wire [(1<<SQ_W)-1:0] sq_unresolved,
    output wire               sq_empty,

    // ---- D-cache ----
    output wire [15:0]        dc_rd_addr,
    output wire               dc_rd_en,
    input  wire               dc_rd_hit,
    input  wire [15:0]        dc_rd_data,
    output wire [15:0]        dc_wr_addr,
    input  wire               dc_wr_hit,
    output wire               dc_wr_en,
    output wire [15:0]        dc_wr_data,

    // ---- memory system ----
    output wire               d_miss_req,
    output wire [15:0]        d_miss_addr,
    input  wire               mem_wr_ok,
    output wire               mem_wr_en,
    output wire [15:0]        mem_wr_addr,
    output wire [15:0]        mem_wr_data
);
    localparam SQ_N = 1 << SQ_W;

    // ------------------------------------------------------------------
    // Store queue
    // ------------------------------------------------------------------
    reg [SQ_W:0]  sq_head, sq_cmt, sq_tail;
    reg           e_res  [0:SQ_N-1];
    reg [15:0]    e_addr [0:SQ_N-1];
    reg [15:0]    e_data [0:SQ_N-1];

    wire [SQ_W:0] sq_count = sq_tail - sq_head;
    assign sq_full   = (sq_count == SQ_N);
    assign sq_empty  = (sq_count == 0);
    assign sq_tail_o = sq_tail;
    assign sq_head_o = sq_head;
    assign cm_addr   = e_addr[sq_cmt[SQ_W-1:0]];
    assign cm_data   = e_data[sq_cmt[SQ_W-1:0]];

    reg [SQ_N-1:0] unres;
    integer k;
    reg [SQ_W-1:0] rel;
    always @(*) begin
        for (k = 0; k < SQ_N; k = k + 1) begin
            rel = k[SQ_W-1:0] - sq_head[SQ_W-1:0];
            unres[k] = ({1'b0, rel} < sq_count) && !e_res[k];
        end
    end
    assign sq_unresolved = unres;

    // ------------------------------------------------------------------
    // Load pipeline
    // ------------------------------------------------------------------
    reg             pend_valid;
    reg [ROB_W-1:0] pend_tag;
    reg [15:0]      pend_addr;
    reg [SQ_W:0]    pend_sqp;

    wire             cur_valid = pend_valid | ld_valid;
    wire [ROB_W-1:0] cur_tag   = pend_valid ? pend_tag  : ld_tag;
    wire [15:0]      cur_addr  = pend_valid ? pend_addr : ld_addr;
    wire [SQ_W:0]    cur_sqp   = pend_valid ? pend_sqp  : ld_sqp;

    wire [ROB_W-1:0] rec_age = rec_tag - rob_head;
    wire [ROB_W-1:0] cur_age = cur_tag - rob_head;
    wire             cur_kill = rec_valid && (cur_age > rec_age);

    // Forwarding: youngest older store to the same word.
    reg        fwd_hit;
    reg [15:0] fwd_data;
    reg [SQ_W:0] n_older;
    reg [SQ_W-1:0] slot;
    integer a;
    always @(*) begin
        fwd_hit  = 1'b0;
        fwd_data = 16'h0000;
        n_older  = cur_sqp - sq_head;
        for (a = 0; a < SQ_N; a = a + 1) begin
            slot = sq_head[SQ_W-1:0] + a[SQ_W-1:0];
            if (a < n_older && e_res[slot] && e_addr[slot][15:1] == cur_addr[15:1]) begin
                fwd_hit  = 1'b1;
                fwd_data = e_data[slot];
            end
        end
    end

    assign dc_rd_addr  = cur_addr;
    assign dc_rd_en    = cur_valid & !fwd_hit;
    wire   ld_hit      = fwd_hit | dc_rd_hit;
    assign ld_done     = cur_valid & ld_hit & !cur_kill;
    assign ld_done_tag = cur_tag;
    assign ld_done_val = fwd_hit ? fwd_data : dc_rd_data;
    assign ld_forwarded  = ld_done & fwd_hit;
    assign ld_busy       = pend_valid;
    assign ld_miss_cycle = cur_valid & !ld_hit;

    // ------------------------------------------------------------------
    // Store drain (write-through, write-allocate)
    // ------------------------------------------------------------------
    wire [SQ_W-1:0] hd = sq_head[SQ_W-1:0];
    wire drain_ready = (sq_head != sq_cmt);
    wire drain_fire  = drain_ready & dc_wr_hit & mem_wr_ok;

    assign dc_wr_addr  = e_addr[hd];
    assign dc_wr_data  = e_data[hd];
    assign dc_wr_en    = drain_fire;
    assign mem_wr_en   = drain_fire;
    assign mem_wr_addr = e_addr[hd];
    assign mem_wr_data = e_data[hd];

    wire ld_miss_req = cur_valid & !ld_hit & !cur_kill;
    wire st_miss_req = drain_ready & !dc_wr_hit;
    assign d_miss_req  = ld_miss_req | st_miss_req;
    assign d_miss_addr = ld_miss_req ? cur_addr : e_addr[hd];

    // ------------------------------------------------------------------
    // Sequential
    // ------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            sq_head    <= 0;
            sq_cmt     <= 0;
            sq_tail    <= 0;
            pend_valid <= 1'b0;
            for (i = 0; i < SQ_N; i = i + 1) e_res[i] <= 1'b0;
        end else begin
            if (sq_alloc)
                e_res[sq_tail[SQ_W-1:0]] <= 1'b0;
            if (stu_valid) begin
                e_res[stu_sqp[SQ_W-1:0]]  <= 1'b1;
                e_addr[stu_sqp[SQ_W-1:0]] <= stu_addr;
                e_data[stu_sqp[SQ_W-1:0]] <= stu_data;
            end

            if (rec_valid)      sq_tail <= rec_sqp;
            else if (sq_alloc)  sq_tail <= sq_tail + 1'b1;
            if (sq_commit)      sq_cmt  <= sq_cmt + 1'b1;
            if (drain_fire)     sq_head <= sq_head + 1'b1;

            if (cur_valid && !ld_hit && !cur_kill) begin
                pend_valid <= 1'b1;
                pend_tag   <= cur_tag;
                pend_addr  <= cur_addr;
                pend_sqp   <= cur_sqp;
            end else begin
                pend_valid <= 1'b0;
            end
        end
    end
endmodule
