
module PSA_16bit(
	input [15:0] a, 
	input [15:0] b,
	output [15:0] result,
	output ovfl,
	output zero,
	output sign
); 


wire [3:0] overflow_vector;

wire [15:0] Sum_intr;
CLA_4b adders[3:0] (.A(a), .B(b), .S(Sum_intr), .Cin(4'h0), .Cout(), .Ovfl(overflow_vector), .P(), .G());

assign same_sign = (~(a[3] ^ b[3]));
wire [15:0] Sum;
assign Sum[3:0] = overflow_vector[0] ? (a[3] ? 4'h8 : 4'h7) : Sum_intr[3:0];
assign Sum[7:4] = overflow_vector[1] ? (a[7] ? 4'h8 : 4'h7) : Sum_intr[7:4];
assign Sum[11:8] = overflow_vector[2] ? (a[11] ? 4'h8 : 4'h7) : Sum_intr[11:8];
assign Sum[15:12] = overflow_vector[3] ? (a[15] ? 4'h8 : 4'h7) : Sum_intr[15:12];

assign result = Sum;

assign ovfl = 1'bz;
assign zero = 1'bz;
assign sign = 1'bz;


endmodule 