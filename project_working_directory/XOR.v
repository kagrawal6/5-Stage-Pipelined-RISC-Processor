module XOR(
	input [15:0] a,
	input [15:0] b,
	output [15:0] result,
	output ovfl,
	output zero,
	output sign
);

assign result = a ^ b;
assign zero = !(|result);
assign ovfl = 1'bz;
assign sign = 1'bz;
endmodule