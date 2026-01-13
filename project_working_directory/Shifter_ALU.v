
module Shifter_ALU(
	input[15:0] a, // Value that is being shifted
	input [3:0] b, // By what value is it being shifter
	input [1:0] mode, // 00 - SLL, 01 - SRA, 10 - ROR; These values are based on project documents
	output [15:0] result,
	output zero,
	output sign,
	output ovfl
);

wire [15:0] shift_result, ror_result;


Shifter iSHIFT (.Shift_Out(shift_result), .Shift_In(a), .Shift_Val(b), .Mode(mode[0]));
Rotater iROT(.Shift_Out(ror_result), .Shift_In(a), .Shift_Val(b));


assign result = ((mode == 2'b00) || (mode == 2'b01)) ? shift_result : (mode == 2'b10) ? ror_result : 16'hxxxx; 

assign zero = !(|result);
assign sign = 1'bz;
assign ovfl = 1'bz;

endmodule