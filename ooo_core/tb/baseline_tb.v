// Lightweight testbench for the phase-3 in-order core (project_working_directory),
// used only to measure its cycle count on the same programs as the OoO core.
// Unlike the course testbench it does not dump a VCD, so it runs quickly.
//
// Plusargs: +IMG=<file>  +MAX_CYCLES=<n>
// Prints:   BASELINE cycles=<n>  and the final register file.
module baseline_tb;
    reg clk, rst_n;
    wire hlt;
    wire [15:0] pc;
    integer cycle, max_cycles, i;

    cpu DUT(.clk(clk), .rst_n(rst_n), .hlt(hlt), .pc(pc));

    // Final register values, read from the bit cells of the register file.
    wire [15:0] regval [0:15];
    genvar r, b;
    generate
        for (r = 0; r < 16; r = r + 1) begin : g_r
            for (b = 0; b < 16; b = b + 1) begin : g_b
                assign regval[r][b] = DUT.iREGFILE.reg_file16[r].BitCells[b].dff_q;
            end
        end
    endgenerate

    initial begin
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 500000;
        for (i = 0; i < 65536; i = i + 1) DUT.iUNIFIEDMEM.iBRIDGE.iMEM.mem[i] = 16'h0000;
        cycle = 0;
        clk   = 1'b0;
        rst_n = 1'b0;
        #201 rst_n = 1'b1;
    end

    always #50 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            if (hlt) begin
                $display("BASELINE cycles=%0d", cycle);
                $write("REGS");
                for (i = 1; i < 16; i = i + 1) $write(" %04x", regval[i]);
                $write("\n");
                $finish;
            end
            cycle = cycle + 1;
            if (cycle >= max_cycles) begin
                $display("TIMEOUT after %0d cycles", cycle);
                $finish;
            end
        end
    end
endmodule
