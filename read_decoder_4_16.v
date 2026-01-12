module read_decoder_4_16(
  input [3:0] reg_id,
  output [15:0] wordline
);

wire [15:0] shift_by1;
wire [15:0] shift_by2;
wire [15:0] shift_by4;

assign shift_by1 = 	reg_id[0] ? {15'h0001, 1'b0} : 16'h0001;
assign shift_by2 = 	reg_id[1] ? {shift_by1[13:0],{2{1'b0}}} : shift_by1[15:0];
assign shift_by4 = 	reg_id[2] ? {shift_by2[11:0], {4{1'b0}}} : shift_by2[15:0];
assign wordline = 	(reg_id == 4'd0) ? 16'h0000 : reg_id[3] ? {shift_by4[7:0], {8{1'b0}}} : shift_by4[15:0];
endmodule

