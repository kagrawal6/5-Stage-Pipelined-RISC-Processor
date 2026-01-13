// multi-bit dff with synchronous rst for Pipeline Registers only.
/* To instantiate a 4-bit pipeline register to hold an opcode for Decode:
pldff #(.WIDTH(4)) if_id_instr_pldff (
  .q(ifid_opcode),        // Course textbook would call this IF/ID.instruction
  .d(instruction[15:12]), // output from ID stage instruction memory
  .wen(1'b1),             // Always write-enable F to D
  .clk(clk),
  .rst(rst | flush),      // Set dff q output to 0 on reset or flush
);
*/
module pldff #(
    parameter WIDTH = 2
) (
    output reg [WIDTH-1:0] q,  // DFF output
    input [WIDTH-1:0] d,  // DFF input
    input wen,  // One Write Enable for all bits
    input clk,
    input rst  // synchronous reset
);

  always @(posedge clk) begin
    q <= rst ? 'h0 : (wen ? d : q);
  end

endmodule  // pldff
