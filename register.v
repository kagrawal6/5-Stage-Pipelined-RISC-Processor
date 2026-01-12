module Register( input clk, input rst, input [15:0] D, input WriteReg, input ReadEnable1, input
ReadEnable2, inout [15:0] Bitline1, inout [15:0] Bitline2);

BitCell BitCells[15:0] (.clk(clk), 
				.rst(rst), 
				.D(D), 
				.WriteEnable(WriteReg), 
				.ReadEnable1(ReadEnable1), 
				.ReadEnable2(ReadEnable2), 
				.Bitline1(Bitline1), 
				.Bitline2(Bitline2));
endmodule 


// module register(
//   input clk,
//   input rst,
//   input [15:0] d,
//   input write_reg,
//   input rden1,
//   input rden2,
//   inout [15:0] bitline1,
//   inout [15:0] bitline2
// );
	
// 	bit_cell regt[15:0](.clk(clk), 
// 											.rst(rst), 
// 											.d(d), 
// 											.wren(write_reg), 
// 											.rden1(rden1), 
// 											.rden2(rden2), 
// 											.bitline1(bitline1), 
// 											.bitline2(bitline2));

// endmodule
