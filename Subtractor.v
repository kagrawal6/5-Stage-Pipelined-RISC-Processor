module Subtractor(
	input [15:0] a,       // First operand
 	 input [15:0] b,       // Second operand
  	output [15:0] result, // Result of the subtraction
  	output ovfl,      // Overflow flag (V)
  	output zero,      // Zero flag (Z)
  	output sign       // Sign flag (N)
);

	wire [15:0] diff;     // Difference of a and b
	wire cout;            // Carry-out from CLA
	wire ovfl_internal;   // Overflow flag from CLA

	// CLA 16-bit adder instantiation for subtraction (mode 1 for subtraction)
	CLA_16b cla_sub (
		.A(a),
		.B(~b), 
		.Cin(1'b1),         // Mode 1 for subtraction (a - b)
		.S(diff), 
		.Cout(cout), 
		.Ovfl(ovfl_internal)
	);
	

    assign result = ovfl_internal ? cout ? 16'h8000 : 16'h7FFF : diff;

	assign ovfl = ovfl_internal;

	assign zero = !(|result);
	
	assign sign = result[15];


endmodule