
module pc_control(input branch,
	input [2:0] cnd, 
	input [15:0] imm,
	input [2:0] f, // f[2] = N; f[1] = O; f[0] = Z
	input bLabel_sel,
	input [15:0] nxt_addr,
	input [15:0] pc_in,
	input stall,
	output [15:0] pc_out,
	output branch_taken);

localparam [2:0] BNE = 3'h0,
	BE = 3'h1,
	BGT = 3'h2,
	BLT = 3'h3,
	BGE = 3'h4,
	BLE = 3'h5,
	BO = 3'h6,
	UCD = 3'h7;

wire [15:0] default_nxt_pc;
wire [15:0] branch_nxt_pc;
wire [15:0] signext_immediate;
reg branch_cntrl;

always@(*) begin
	case(cnd) 
		BNE: 	branch_cntrl = (!f[0]) ? 1 : 0;
		BE:		branch_cntrl = (f[0]) ? 1 : 0;
		BGT:	branch_cntrl = (!f[0] && !f[2]) ? 1 : 0;
		BLT:	branch_cntrl = (f[2]) ? 1 : 0;
		BGE:	branch_cntrl = (f[0] || (!f[0] && !f[2])) ? 1 : 0;
		BLE:	branch_cntrl = (f[0] || f[2]) ? 1 : 0;
		BO:		branch_cntrl = (f[1]) ? 1 : 0;
		UCD:	branch_cntrl = 1;
	endcase
end

CLA_16b default_pc(.A(pc_in), .B(~(16'h0002)), .Cin(1'b1), .S(default_nxt_pc));
CLA_16b branch_pc(.A(default_nxt_pc), .B(imm << 1), .Cin(1'b0), .S(branch_nxt_pc));
assign pc_out = (branch & branch_cntrl) ? bLabel_sel ? nxt_addr : branch_nxt_pc : pc_in;
assign branch_taken = (branch & branch_cntrl) & ~stall;

endmodule