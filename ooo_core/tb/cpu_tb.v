// Testbench for the out-of-order core.
//
// Plusargs:
//   +IMG=<file>        memory image to load (read by memory4c)
//   +TRACE=<file>      commit trace output        (default commit.trace)
//   +MEMDUMP=<file>    dump main memory at halt   (optional)
//   +MAX_CYCLES=<n>    timeout                    (default 200000)
//
// The commit trace uses the same format as tools/wisc.py so the two can be
// diffed directly. Performance counters are printed as one "STATS" line.
module cpu_tb;
    parameter BP_TYPE        = 6;
    parameter EARLY_RECOVERY = 1;
    parameter ROB_W          = 4;
    parameter IQ_N           = 8;
    parameter SQ_W           = 3;
    parameter EARLY_RESTART  = 1;
    parameter I_PREFETCH     = 1;
    parameter D_PREFETCH     = 1;

    reg clk;
    reg rst_n;
    wire hlt;
    wire [15:0] pc;

    cpu #(
        .BP_TYPE(BP_TYPE), .EARLY_RECOVERY(EARLY_RECOVERY),
        .ROB_W(ROB_W), .IQ_N(IQ_N), .SQ_W(SQ_W),
        .EARLY_RESTART(EARLY_RESTART), .I_PREFETCH(I_PREFETCH), .D_PREFETCH(D_PREFETCH)
    ) DUT (
        .clk(clk), .rst_n(rst_n), .hlt(hlt), .pc(pc)
    );

    reg [8*256-1:0] trace_name, mem_name;
    integer trace_fd, max_cycles, cycle, i;
    reg dump_mem;

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_name)) trace_name = "commit.trace";
        dump_mem = $value$plusargs("MEMDUMP=%s", mem_name);
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 200000;
        trace_fd = $fopen(trace_name, "w");

        // Unwritten memory reads as zero (memory4c only loads the image words).
        for (i = 0; i < 65536; i = i + 1) DUT.u_mem.u_main_mem.mem[i] = 16'h0000;

        cycle = 0;
        clk   = 1'b0;
        rst_n = 1'b0;
        #201 rst_n = 1'b1;
    end

    always #50 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (DUT.commit_en) begin
                if (DUT.commit_is_store)
                    $fdisplay(trace_fd, "%04x %04x M[%04x]=%04x", DUT.commit_pc, DUT.commit_instr,
                              DUT.cm_addr, DUT.cm_data);
                else if (DUT.commit_wr_rd)
                    $fdisplay(trace_fd, "%04x %04x R%0d=%04x", DUT.commit_pc, DUT.commit_instr,
                              DUT.commit_rd, DUT.commit_val);
                else
                    $fdisplay(trace_fd, "%04x %04x -", DUT.commit_pc, DUT.commit_instr);
            end
            if (hlt) begin
                $display("STATS cycles=%0d commits=%0d cond_br=%0d cond_mispred=%0d br_reg=%0d br_reg_mispred=%0d recoveries=%0d stall_rob=%0d stall_iq=%0d stall_sq=%0d ifq_empty=%0d icache_miss=%0d dcache_miss=%0d loads=%0d ld_fwd=%0d ld_miss_cycles=%0d issued=%0d rob_occ_sum=%0d prefetches=%0d",
                    DUT.stat_cycles, DUT.stat_commits, DUT.stat_cond_br, DUT.stat_cond_mispred,
                    DUT.stat_br_reg, DUT.stat_br_reg_mispred, DUT.stat_recoveries,
                    DUT.stat_stall_rob, DUT.stat_stall_iq, DUT.stat_stall_sq, DUT.stat_ifq_empty,
                    DUT.stat_icache_miss, DUT.stat_dcache_miss, DUT.stat_loads, DUT.stat_ld_fwd,
                    DUT.stat_ld_miss_cycles, DUT.stat_issued, DUT.stat_rob_occ_sum,
                    DUT.stat_prefetches);
                $fclose(trace_fd);
                if (dump_mem) $writememh(mem_name, DUT.u_mem.u_main_mem.mem);
                $finish;
            end
            if (cycle >= max_cycles) begin
                $display("TIMEOUT after %0d cycles (last committed pc %04x)", cycle, pc);
                $fclose(trace_fd);
                $finish;
            end
        end
    end
endmodule
