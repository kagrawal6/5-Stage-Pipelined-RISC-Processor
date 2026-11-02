// 2-way set-associative cache, 64 sets x 16-byte (8-word) blocks = 2 KB,
// true LRU per set -- the same geometry as the phase-3 caches.
//
//   address = | tag [15:10] | set [9:4] | word [3:1] | 0 |
//
// Ports:
//   rd_*    combinational lookup + read (fetch or load)
//   wr_*    combinational lookup + word write on hit (store drain)
//   probe_* lookup only (used by the prefetchers to skip lines already present)
//   fill_*  line refill driven by mem_system: fill_start picks and
//           invalidates the victim way, fill_we writes the arriving words,
//           fill_done marks the line valid.
//
// EARLY_RESTART: while a line is being filled, words that have already
// arrived can be read (combined with critical-word-first ordering in
// mem_system, the missing word is usable after the first memory access
// instead of after the whole line).
module cache #(
    parameter SET_W         = 6,
    parameter EARLY_RESTART = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] rd_addr,
    input  wire        rd_en,
    output wire        rd_hit,
    output wire [15:0] rd_data,

    input  wire [15:0] wr_addr,
    output wire        wr_hit,
    input  wire        wr_en,
    input  wire [15:0] wr_data,

    input  wire [15:0] probe_addr,
    output wire        probe_hit,

    input  wire        fill_start,
    input  wire [15:0] fill_addr,
    input  wire        fill_we,
    input  wire [2:0]  fill_word,
    input  wire [15:0] fill_data,
    input  wire        fill_done
);
    localparam SETS  = 1 << SET_W;
    localparam TAG_W = 12 - SET_W;

    reg [TAG_W-1:0] tag0 [0:SETS-1];
    reg [TAG_W-1:0] tag1 [0:SETS-1];
    reg [SETS-1:0]  val0, val1;
    reg [SETS-1:0]  lru;                      // way to evict next
    reg [15:0]      data0 [0:SETS*8-1];
    reg [15:0]      data1 [0:SETS*8-1];

    // ---- line currently being filled ----
    reg             fill_active;
    reg             fill_way;
    reg [SET_W-1:0] fill_set;
    reg [TAG_W-1:0] fill_tag;
    reg [7:0]       fill_have;                // words already written

    // ---- read port ----
    wire [SET_W-1:0] r_set  = rd_addr[4 +: SET_W];
    wire [TAG_W-1:0] r_tag  = rd_addr[15 -: TAG_W];
    wire [SET_W+2:0] r_word = {r_set, rd_addr[3:1]};
    wire r_h0 = val0[r_set] && (tag0[r_set] == r_tag);
    wire r_h1 = val1[r_set] && (tag1[r_set] == r_tag);
    wire r_hf = (EARLY_RESTART != 0) && fill_active && (r_set == fill_set) &&
                (r_tag == fill_tag) && fill_have[rd_addr[3:1]];
    wire r_way1 = r_hf ? fill_way : r_h1;
    assign rd_hit  = r_h0 | r_h1 | r_hf;
    assign rd_data = r_way1 ? data1[r_word] : data0[r_word];

    // ---- write port ----
    wire [SET_W-1:0] w_set  = wr_addr[4 +: SET_W];
    wire [TAG_W-1:0] w_tag  = wr_addr[15 -: TAG_W];
    wire [SET_W+2:0] w_word = {w_set, wr_addr[3:1]};
    wire w_h0 = val0[w_set] && (tag0[w_set] == w_tag);
    wire w_h1 = val1[w_set] && (tag1[w_set] == w_tag);
    assign wr_hit = w_h0 | w_h1;

    // ---- probe port ----
    wire [SET_W-1:0] p_set = probe_addr[4 +: SET_W];
    wire [TAG_W-1:0] p_tag = probe_addr[15 -: TAG_W];
    assign probe_hit = (val0[p_set] && (tag0[p_set] == p_tag)) ||
                       (val1[p_set] && (tag1[p_set] == p_tag));

    // ---- fill victim ----
    wire [SET_W-1:0] f_set = fill_addr[4 +: SET_W];
    wire [TAG_W-1:0] f_tag = fill_addr[15 -: TAG_W];
    wire f_victim = !val0[f_set] ? 1'b0 :
                    !val1[f_set] ? 1'b1 : lru[f_set];

    always @(posedge clk) begin
        if (!rst_n) begin
            val0 <= {SETS{1'b0}};
            val1 <= {SETS{1'b0}};
            lru  <= {SETS{1'b0}};
            fill_active <= 1'b0;
            fill_have   <= 8'h00;
        end else begin
            if (rd_en && (r_h0 | r_h1))
                lru[r_set] <= r_h0;           // way 0 used -> way 1 is LRU
            if (wr_en && wr_hit) begin
                if (w_h0) data0[w_word] <= wr_data;
                else      data1[w_word] <= wr_data;
                lru[w_set] <= w_h0;
            end
            if (fill_start) begin
                fill_active <= 1'b1;
                fill_have   <= 8'h00;
                fill_way    <= f_victim;
                fill_set    <= f_set;
                fill_tag    <= f_tag;
                if (f_victim) val1[f_set] <= 1'b0;
                else          val0[f_set] <= 1'b0;
            end
            if (fill_we) begin
                fill_have[fill_word] <= 1'b1;
                if (fill_way) data1[{fill_set, fill_word}] <= fill_data;
                else          data0[{fill_set, fill_word}] <= fill_data;
            end
            if (fill_done) begin
                fill_active <= 1'b0;
                if (fill_way) begin val1[fill_set] <= 1'b1; tag1[fill_set] <= fill_tag; end
                else          begin val0[fill_set] <= 1'b1; tag0[fill_set] <= fill_tag; end
                lru[fill_set] <= ~fill_way;
            end
        end
    end
endmodule
