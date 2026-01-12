module RED(
	input [15:0] a,       // First operand
	input [15:0] b,       // Second operand
	output [15:0] result, // Result of the reduction
	output ovfl,      // Overflow flag (V)
	output zero,      // Zero flag (Z)
	output sign       // Sign flag (N)
);

wire [4:0] upper_sum, upper_middle_sum, lower_middle_sum, lower_sum;
CLA_4b upper (.A(a[15:12]) , .B(b[15:12]), .Cin(1'b0), .Cout(upper_sum[4]), .S(upper_sum[3:0]), .P(), .G(), .Ovfl());
CLA_4b upper_middle (.A(a[11:8]) , .B(b[11:8]), .Cin(1'b0), .Cout(upper_middle_sum[4]), .S(upper_middle_sum[3:0]), .P(), .G(), .Ovfl());
CLA_4b lower_middle (.A(a[7:4]) , .B(b[7:4]), .Cin(1'b0), .Cout(lower_middle_sum[4]), .S(lower_middle_sum[3:0]), .P(), .G(), .Ovfl());
CLA_4b lower (.A(a[3:0]) , .B(b[3:0]), .Cin(1'b0), .Cout(lower_sum[4]), .S(lower_sum[3:0]), .P(), .G(), .Ovfl());

wire [7:0] second_level_upper_sum, second_level_lower_sum;
CLA_4b second_level_upper[1:0] (.A({{3{upper_sum[4]}}, upper_sum}) , .B({{3{upper_middle_sum[4]}}, upper_middle_sum}), .Cin({Cout_s_1,1'b0}), .Cout({ignored_1, Cout_s_1}), .S(second_level_upper_sum), .P(), .G(), .Ovfl());
CLA_4b second_level_lower[1:0] (.A({{3{lower_middle_sum[4]}}, lower_middle_sum}) , .B({{3{lower_sum[4]}}, lower_sum}), .Cin({Cout_s_2,1'b0}), .Cout({ignored_2, Cout_s_2}), .S(second_level_lower_sum), .P(), .G(), .Ovfl());

wire [7:0] final_sum;
CLA_4b final_level[1:0] (.A(second_level_upper_sum) , .B(second_level_lower_sum), .Cin({Cout_f,1'b0}), .Cout({ignored_1, Cout_f}), .S(final_sum), .P(), .G(), .Ovfl());
assign result  = {{8{final_sum[7]}}, final_sum};

assign ovfl = 1'bz;
assign sign = 1'bz;
assign zero = 1'bz;

endmodule