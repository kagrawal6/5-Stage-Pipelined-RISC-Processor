// Memory system: one refill engine shared by the I- and D-cache, plus the
// write-through path for stores, in front of the course main memory
// (memory4c: 1-cycle writes, 4-cycle pipelined reads).
//
// Policy (one memory operation per cycle), when no refill is in progress:
//   1. D-cache demand miss  (a waiting load / store beats instruction fetch)
//   2. I-cache demand miss
//   3. store write-through  (wr_ok)
//   4. I-cache next-line prefetch: the line after the one being fetched
//   5. D-cache next-line prefetch: the line after the last D demand miss
// A refill issues 8 back-to-back word reads; the words come back 4 cycles
// later and are written into the cache as they arrive. Stores may use the
// port once all 8 reads are issued (memory4c samples read data at issue).
// A store can never write the line being refilled: the victim way is
// invalidated at refill start, so such a store misses and waits.
//
// EARLY_RESTART: demand refills start with the missing word
// (critical-word-first) and wrap around the line; the cache lets the
// requester use each word as soon as it has arrived.
module mem_system #(
    parameter EARLY_RESTART = 1,
    parameter I_PREFETCH    = 1,
    parameter D_PREFETCH    = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        i_req,
    input  wire [15:0] i_addr,
    input  wire        d_req,
    input  wire [15:0] d_addr,

    output wire        wr_ok,
    input  wire        wr_en,
    input  wire [15:0] wr_addr,
    input  wire [15:0] wr_data,

    // prefetch candidates and cache probe results
    input  wire [15:0] ipf_addr,      // next line after the fetch PC
    input  wire        ipf_present,   // ... already in the I-cache
    output wire [15:0] dpf_addr,      // next line after the last D miss
    input  wire        dpf_present,   // ... already in the D-cache

    output wire        i_fill_start,
    output wire        d_fill_start,
    output wire [15:0] fill_addr,
    output wire        i_fill_we,
    output wire        d_fill_we,
    output wire [2:0]  fill_word,
    output wire [15:0] fill_data,
    output wire        i_fill_done,
    output wire        d_fill_done,
    output wire        pf_start,      // stat: a prefetch refill started
    output wire        busy
);
    reg        busy_r;
    reg        for_d;
    reg [11:0] line;
    reg [2:0]  first;       // word the refill started with
    reg [3:0]  issued;      // words requested so far (0..8)
    reg [2:0]  recv;        // words received so far (mod 8)
    reg        dpf_valid;
    reg [11:0] dpf_line;

    // ---- choose what to start ----
    wire want_ipf  = (I_PREFETCH != 0) && !ipf_present;
    wire want_dpf  = (D_PREFETCH != 0) && dpf_valid && !dpf_present;
    wire start_dem = !busy_r & (d_req | i_req);
    wire start_ipf = !busy_r & !(d_req | i_req) & !wr_en & want_ipf;
    wire start_dpf = !busy_r & !(d_req | i_req) & !wr_en & !want_ipf & want_dpf;
    wire start     = start_dem | start_ipf | start_dpf;
    wire start_d   = start_dem ? d_req : start_dpf;

    wire [11:0] start_line = start_dem ? (d_req ? d_addr[15:4] : i_addr[15:4]) :
                             start_ipf ? ipf_addr[15:4] : dpf_line;
    wire [2:0]  start_word = ((EARLY_RESTART != 0) && start_dem) ?
                             (d_req ? d_addr[3:1] : i_addr[3:1]) : 3'd0;

    assign i_fill_start = start & !start_d;
    assign d_fill_start = start &  start_d;
    assign fill_addr    = {start_line, 4'h0};
    assign wr_ok        = busy_r ? (issued == 4'd8) : !start_dem;
    assign busy         = busy_r;
    assign pf_start     = start_ipf | start_dpf;
    assign dpf_addr     = {dpf_line, 4'h0};

    // ---- main memory port ----
    reg  [15:0] m_addr;
    reg         m_en, m_wr;
    always @(*) begin
        m_addr = wr_addr;
        m_en   = 1'b0;
        m_wr   = 1'b0;
        if (start) begin
            m_addr = {start_line, start_word, 1'b0};
            m_en   = 1'b1;
        end else if (busy_r && issued != 4'd8) begin
            m_addr = {line, first + issued[2:0], 1'b0};
            m_en   = 1'b1;
        end else if (wr_ok && wr_en) begin
            m_addr = wr_addr;
            m_en   = 1'b1;
            m_wr   = 1'b1;
        end
    end

    wire [15:0] m_data_out;
    wire        m_data_valid;

    memory4c u_main_mem (
        .data_out   (m_data_out),
        .data_in    (wr_data),
        .addr       (m_addr),
        .enable     (m_en),
        .wr         (m_wr),
        .clk        (clk),
        .rst        (~rst_n),
        .data_valid (m_data_valid)
    );

    wire arrive = busy_r & m_data_valid;
    wire last   = (recv == 3'd7);
    assign i_fill_we   = arrive & !for_d;
    assign d_fill_we   = arrive &  for_d;
    assign fill_word   = first + recv;
    assign fill_data   = m_data_out;
    assign i_fill_done = arrive & !for_d & last;
    assign d_fill_done = arrive &  for_d & last;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy_r    <= 1'b0;
            for_d     <= 1'b0;
            line      <= 12'h000;
            first     <= 3'd0;
            issued    <= 4'd0;
            recv      <= 3'd0;
            dpf_valid <= 1'b0;
            dpf_line  <= 12'h000;
        end else begin
            if (start) begin
                busy_r <= 1'b1;
                for_d  <= start_d;
                line   <= start_line;
                first  <= start_word;
                issued <= 4'd1;
                recv   <= 3'd0;
            end else if (busy_r) begin
                if (issued != 4'd8) issued <= issued + 4'd1;
                if (m_data_valid) begin
                    recv <= recv + 3'd1;
                    if (last) busy_r <= 1'b0;
                end
            end
            // remember the line after each D demand miss for the D prefetcher
            if (start_dem & d_req) begin
                dpf_valid <= 1'b1;
                dpf_line  <= start_line + 12'd1;
            end else if (start_dpf) begin
                dpf_valid <= 1'b0;
            end
        end
    end
endmodule
