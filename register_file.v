module RegisterFile(
  input clk,
  input rst,
  input [3:0] SrcReg1,
  input [3:0] SrcReg2,
  input [3:0] DstReg,
  input WriteReg,
  input RF_bypass_en1,
  input RF_bypass_en2,
  input [15:0] DstData,
  input write_en,
  inout [15:0] SrcData1,
  inout [15:0] SrcData2
);

wire [15:0] src_data1;
wire [15:0] src_data2;

wire [15:0]rd1_reg_select;
wire [15:0]rd2_reg_select;
wire [15:0]wr1_reg_select;
wire [15:0]wr2_reg_select;

read_decoder_4_16 rd_dec_1(.reg_id(SrcReg1), .wordline(rd1_reg_select));
read_decoder_4_16 rd_dec_2(.reg_id(SrcReg2), .wordline(rd2_reg_select));
write_decoder_4_16 wr_dec(.reg_id(DstReg), .wordline(wr1_reg_select));

Register reg_file16[15:0] (.clk(clk),
													 .rst(rst),
													 .D(DstData),
													 .WriteReg(wr2_reg_select & {16{write_en}}),
										 			 .ReadEnable1(rd1_reg_select),
													 .ReadEnable2(rd2_reg_select),
													 .Bitline1(src_data1),
													 .Bitline2(src_data2));
assign src_data1 = (SrcReg1 == 4'h0) ? 16'h0000 : 16'hzzzz;
assign src_data2 = (SrcReg2 == 4'h0) ? 16'h0000 : 16'hzzzz;
assign wr2_reg_select = WriteReg ? wr1_reg_select : 16'h0000;

assign SrcData1 = RF_bypass_en1 ? DstData : src_data1;
assign SrcData2 = RF_bypass_en2 ? DstData : src_data2;

endmodule