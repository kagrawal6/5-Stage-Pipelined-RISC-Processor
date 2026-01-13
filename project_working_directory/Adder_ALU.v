
module Adder_ALU(
	input [15:0] a,    // First operand
	input [15:0] b,    // Second operand
	output [15:0] result, // Result of the addition
	output ovfl,   // Overflow flag	
	output zero,   // Zero flag
	output sign    // Sign flag
);
    
	wire [15:0] sum;      // Sum of a and b
	wire cout;            // Carry-out from CLA
	wire ovfl_internal;   // Overflow flag from CLA

	// CLA 16-bit adder instantiation
	CLA_16b cla_add (
		.A(a), 
		.B(b), 
		.Cin(1'b0),         // Mode 0 for addition
		.S(sum), 
		.Cout(cout), 
		.Ovfl(ovfl_internal)
	);

  
	assign result = ovfl_internal ? cout ? 16'h8000 : 16'h7FFF : sum;
	assign ovfl = ovfl_internal;
	assign zero = !(|result);
	assign sign = result[15];
	
endmodule