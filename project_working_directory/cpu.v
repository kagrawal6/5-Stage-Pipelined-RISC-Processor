module cpu(
	input clk,
	input rst_n,
	output hlt,
	output [15:0]pc
);
wire rst;
assign rst = !rst_n;
reg IF_ID_data_stall;
reg IF_ID_branch_stall;
wire IF_ID_stall;
wire IF_ID_flush;
wire [15:0] IF_ID_instr;
wire [15:0] IF_ID_PC_nxt; 

wire ID_EX_en;
wire ID_EX_flush;

wire [15:0] ID_EX_instruction; 
wire [15:0] ID_EX_PC_nxt; 
wire [3:0] ID_EX_opcode; 
wire [3:0] ID_EX_SrcReg1_intr; 
wire [3:0] ID_EX_SrcReg2_intr; 
wire [3:0] ID_EX_DstReg_intr; 
wire [3:0] ID_EX_immediate; 
wire [8:0] ID_EX_B_Label; 
wire [3:0] ID_EX_SrcReg1; 
wire [3:0] ID_EX_SrcReg2; 
wire [3:0] ID_EX_DstRegReg; 
wire [15:0] ID_EX_SrcData1; 
wire [15:0] ID_EX_SrcData2; 
wire [15:0] ID_EX_immediate_s_ex; 
wire [7:0] ID_EX_LLB_LHB_Byte; 
wire [2:0] ID_EX_Branch_Condition; 
wire [15:0] ID_EX_B_Label_s_ex;
wire ID_EX_Branch_inst;
wire ID_EX_RegSel_SrcReg1;
wire ID_EX_RegSel_SrcReg2;
wire ID_EX_MemRead; 
wire ID_EX_PC_save;
wire ID_EX_Hlt;
wire ID_EX_MemtoReg; 
wire [2:0] ID_EX_ALUOp; 
wire ID_EX_MemWrite; 
wire ID_EX_ALUSrc; 
wire ID_EX_DMEM_en; 
wire ID_EX_LB_mode; 
wire ID_EX_LB_result_sel; 
wire ID_EX_RegWrite; 

wire EX_MEM_en; 
wire EX_MEM_flush; 

wire [3:0] EX_MEM_opcode; 
wire [3:0] EX_MEM_SrcReg1;
wire [3:0] EX_MEM_SrcReg2;
wire [3:0] EX_MEM_rd_reg; 
wire [15:0] EX_MEM_SrcData1; 
wire [15:0] EX_MEM_SrcData2; 
wire [15:0] EX_MEM_immediate_s_ex; 
wire [7:0] EX_MEM_LLB_LHB_Byte; 


wire [15:0] EX_MEM_ALU_out; 
wire [15:0] EX_MEM_LB_result; 
wire [15:0] EX_MEM_Fresult;
wire [15:0] EX_MEM_PC_nxt;
wire [15:0] EX_MEM_operand1; 
wire [15:0] EX_MEM_operand2; 

wire EX_MEM_ovfl; 
wire EX_MEM_zero; 
wire EX_MEM_sign; 

wire EX_MEM_MemRead; 
wire EX_MEM_PC_save;
wire EX_MEM_Hlt;
wire [1:0] EX_MEM_SrcData1_sel; 
wire [1:0] EX_MEM_SrcData2_sel; 
wire [2:0] EX_MEM_ALUOp; 
wire EX_MEM_ALUSrc; 
wire EX_MEM_LB_mode; 
wire EX_MEM_MemWrite; 
wire EX_MEM_DMEM_en; 
wire EX_MEM_MemtoReg; 
wire EX_MEM_LB_result_sel; 
wire EX_MEM_RegWrite; 
wire [15:0] EX_MEM_SrcData2_temp;


wire MEM_WB_en; 
wire MEM_WB_flush; 

wire [3:0] MEM_WB_opcode; 
wire [3:0] MEM_WB_rs_reg; 
wire [3:0] MEM_WB_rt_reg; 
wire [3:0] MEM_WB_rd_reg; 
wire [15:0] MEM_WB_rt_reg_data;
wire [15:0] MEM_WB_mem_data_in;


wire [15:0] MEM_WB_ALU_result; 
wire [15:0] MEM_WB_LB_result; 
wire [15:0] MEM_WB_Fresult;
wire [15:0] MEM_WB_data_mem_out; 
wire [15:0] MEM_WB_PC_nxt;
wire MEM_WB_ovfl; 
wire MEM_WB_sign; 
wire MEM_WB_zero; 

wire MEM_WB_data_in_sel; 
wire MEM_WB_MemRead;
wire MEM_WB_PC_save;
wire MEM_WB_Hlt;
wire MEM_WB_MemWrite;
wire MEM_WB_DMEM_en;
wire MEM_WB_MemtoReg; 
wire MEM_WB_LB_result_sel; 
wire MEM_WB_RegWrite; 

wire [3:0] WB_opcode;
wire [3:0] WB_rs_reg;
wire [3:0] WB_rt_reg;
wire [3:0] WB_rd_reg;


wire [15:0] WB_ALU_result;
wire [15:0] WB_LB_result;
wire [15:0] WB_Fresult;
wire [15:0] WB_data_mem_out;
wire [15:0] WB_PC_nxt;

wire [15:0] WB_result;
wire WB_ovfl;
wire WB_zero;
wire WB_sign;

wire WB_PC_save;
wire WB_Hlt;
wire WB_MemtoReg;
wire WB_MemRead;
wire WB_LB_result_sel;
wire WB_RegWrite;


wire RF_bypass_en1;
wire RF_bypass_en2;
wire FLAG_bypass_zero;
wire FLAG_bypass_ovfl;
wire FLAG_bypass_sign;
wire branch_taken;
wire forwarding;
wire instr_miss_stall;
wire data_miss_stall;

wire ovfl, zero, sign;

wire ovfl_o, zero_o, sign_o;

dff OVFL(.q(ovfl_o), .d(WB_ovfl), .clk(clk), .rst(rst), .wen( (!WB_opcode[3]) & (!(&WB_opcode[1:0])) ) ); 

dff ZERO(.q(zero_o), .d(WB_zero), .clk(clk), .rst(rst), .wen( (!WB_opcode[3]) & (!(&WB_opcode[1:0])) ) );

dff SIGN(.q(sign_o), .d(WB_sign), .clk(clk), .rst(rst), .wen( (!WB_opcode[3]) & (!(&WB_opcode[1:0])) ) );

assign ovfl = FLAG_bypass_ovfl ? WB_ovfl : ovfl_o;
assign zero = FLAG_bypass_zero ? WB_zero : zero_o;
assign sign = FLAG_bypass_sign ? WB_sign : sign_o;

wire zero_flag_stall_cntrl;
wire ovfl_flag_stall_cntrl;
wire sign_flag_stall_cntrl;

wire EX_MEM_sets_zero_flag;
wire MEM_WB_sets_zero_flag;
wire WB_sets_zero_flag;

wire EX_MEM_sets_ovfl_flag;
wire MEM_WB_sets_ovfl_flag;
wire WB_sets_ovfl_flag;

wire EX_MEM_sets_sign_flag;
wire MEM_WB_sets_sign_flag;
wire WB_sets_sign_flag;

localparam [3:0] ADD = 4'b0000,
                SUB = 4'b0001,
                XOR = 4'b0010,
                RED = 4'b0011,
                SLL = 4'b0100,
                SRA = 4'b0101,
                ROR = 4'b0110,
                PADDSB = 4'b0111,
                LW = 4'b1000,
                SW = 4'b1001,
                LLB = 4'b1010,
                LHB = 4'b1011,
                B = 4'b1100,
                BR = 4'b1101,
                PCS = 4'b1110,
                HLT = 4'b1111;

localparam [2:0] BNE = 3'h0,
                BE = 3'h1,
                BGT = 3'h2,
                BLT = 3'h3,
                BGE = 3'h4,
                BLE = 3'h5,
                BO = 3'h6,
                UCD = 3'h7;

always@(*) begin
    case (ID_EX_Branch_Condition)
        BNE, BE: IF_ID_branch_stall = zero_flag_stall_cntrl;
        BGT, BGE, BLE: IF_ID_branch_stall = zero_flag_stall_cntrl | sign_flag_stall_cntrl;
        BLT: IF_ID_branch_stall = sign_flag_stall_cntrl;
        BO: IF_ID_branch_stall = ovfl_flag_stall_cntrl;
        UCD: IF_ID_branch_stall = 1'b0;
    endcase
end

assign zero_flag_stall_cntrl = ID_EX_Branch_inst ? 
                               (EX_MEM_sets_zero_flag | MEM_WB_sets_zero_flag) ? 1'b1 :
                               1'b0 : 1'b0;
assign ovfl_flag_stall_cntrl = ID_EX_Branch_inst ? 
                               (EX_MEM_sets_ovfl_flag | MEM_WB_sets_ovfl_flag) ? 1'b1 :
                               1'b0 : 1'b0;
assign sign_flag_stall_cntrl = ID_EX_Branch_inst ? 
                               (EX_MEM_sets_sign_flag | MEM_WB_sets_sign_flag) ? 1'b1 :
                               1'b0 : 1'b0;

assign EX_MEM_sets_ovfl_flag = (EX_MEM_opcode == ADD) | (EX_MEM_opcode == SUB);
assign EX_MEM_sets_sign_flag = (EX_MEM_opcode == ADD) | (EX_MEM_opcode == SUB);
assign EX_MEM_sets_zero_flag = (~EX_MEM_opcode[3] & ~EX_MEM_opcode[1]) | (~EX_MEM_opcode[3] & ~EX_MEM_opcode[0]); 

assign MEM_WB_sets_ovfl_flag = (MEM_WB_opcode == ADD) | (MEM_WB_opcode == SUB);
assign MEM_WB_sets_sign_flag = (MEM_WB_opcode == ADD) | (MEM_WB_opcode == SUB);
assign MEM_WB_sets_zero_flag = (~MEM_WB_opcode[3] & ~MEM_WB_opcode[1]) | (~MEM_WB_opcode[3] & ~MEM_WB_opcode[0]); 

assign WB_sets_ovfl_flag = (WB_opcode == ADD) | (WB_opcode == SUB);
assign WB_sets_sign_flag = (WB_opcode == ADD) | (WB_opcode == SUB);
assign WB_sets_zero_flag = (~WB_opcode[3] & ~WB_opcode[1]) | (~WB_opcode[3] & ~WB_opcode[0]); 
    
assign FLAG_bypass_ovfl = (ID_EX_Branch_inst & !IF_ID_branch_stall & (ID_EX_Branch_Condition == BO)) & WB_sets_ovfl_flag;
assign FLAG_bypass_sign = (ID_EX_Branch_inst & !IF_ID_branch_stall & (ID_EX_Branch_Condition[2] ^ ID_EX_Branch_Condition[1]) ) & WB_sets_sign_flag;
assign FLAG_bypass_zero = (ID_EX_Branch_inst & !IF_ID_branch_stall & (~ID_EX_Branch_Condition[1] | (~ID_EX_Branch_Condition[2] & ~ID_EX_Branch_Condition[0])) ) & WB_sets_zero_flag;



wire [15:0] PC;
wire [15:0] next_PC; 
dff PC_reg[15:0] (.q(PC), .d(next_PC), .clk(clk), .rst(rst), .wen(!ID_EX_Hlt & !EX_MEM_Hlt & !MEM_WB_Hlt & !WB_Hlt & !IF_ID_stall & !data_miss_stall & !instr_miss_stall));
assign pc = PC; 

 
CLA_16b default_pc(.A(PC), .B(16'h0002), .Cin(1'b0), .S(IF_ID_PC_nxt));

reg hazard;
reg en_RF_bypass_en1;
reg en_RF_bypass_en2;


always @(*) begin
    
    case (ID_EX_opcode)
         SLL, SRA, ROR, LW, LLB, LHB :   begin 
                                        
                                        IF_ID_data_stall = (EX_MEM_MemRead & |EX_MEM_rd_reg)   ?   (EX_MEM_rd_reg == ID_EX_SrcReg1)   :   1'h0;
                                        en_RF_bypass_en1 = (ID_EX_SrcReg1 == WB_rd_reg);
                                        en_RF_bypass_en2 = 1'h0;
                                    end

        ADD, SUB, XOR, RED, PADDSB, SW: begin 
                                        
                                        IF_ID_data_stall = (EX_MEM_MemRead & |EX_MEM_rd_reg)   ?   ((EX_MEM_rd_reg == ID_EX_SrcReg1) | ((EX_MEM_rd_reg == ID_EX_SrcReg2) & ~ID_EX_MemWrite))   :   1'h0;
                                        en_RF_bypass_en1 = (ID_EX_SrcReg1 == WB_rd_reg);
                                        en_RF_bypass_en2 = (ID_EX_SrcReg2 == WB_rd_reg);

                                    end
        BR:                         begin
                                        IF_ID_data_stall = ID_EX_Branch_inst   ?   ((ID_EX_SrcReg1 == MEM_WB_rd_reg) | (ID_EX_SrcReg1 == EX_MEM_rd_reg))   :   1'h0;
                                        en_RF_bypass_en1 = (ID_EX_SrcReg1 == WB_rd_reg);
                                        en_RF_bypass_en2 = 1'h0;
                                    end
        
        default:                    begin
                                        IF_ID_data_stall = 1'h0;      
                                        en_RF_bypass_en1 = 1'h0;
                                        en_RF_bypass_en2 = 1'h0;
                                    end
    endcase
end

assign RF_bypass_en1 = WB_RegWrite   ?   en_RF_bypass_en1   :   1'h0;
assign RF_bypass_en2 = WB_RegWrite   ?   en_RF_bypass_en2   :   1'h0;

	
wire mem_to_ex_A;
wire mem_to_ex_B;
wire ex_to_ex_A;
wire ex_to_ex_B;


assign ex_to_ex_A = (MEM_WB_RegWrite & |MEM_WB_rd_reg)   ?   (MEM_WB_rd_reg == EX_MEM_SrcReg1)  :    1'h0;
assign ex_to_ex_B = (MEM_WB_RegWrite & |MEM_WB_rd_reg)   ?   (MEM_WB_rd_reg == EX_MEM_SrcReg2)  :    1'h0;


assign mem_to_ex_A = (WB_RegWrite & |WB_rd_reg)   ?    (WB_rd_reg == EX_MEM_SrcReg1)   :   1'h0;
assign mem_to_ex_B = (WB_RegWrite & |WB_rd_reg)   ?    (WB_rd_reg == EX_MEM_SrcReg2)   :   1'h0;       


assign EX_MEM_SrcData1_sel = ex_to_ex_A   ?   2'b10   :   (mem_to_ex_A   ?   2'b01   :   2'b00);       
assign EX_MEM_SrcData2_sel = ex_to_ex_B   ?   2'b10   :   (mem_to_ex_B   ?   2'b01   :   2'b00);  


assign MEM_WB_data_in_sel = (WB_MemRead & |WB_rd_reg & MEM_WB_MemWrite)   ?   (WB_rd_reg == MEM_WB_rt_reg)   :   1'h0;

unified_memory iUNIFIEDMEM(.clk(clk), .rst(rst), .instr_addr(PC), .instr(IF_ID_instr), .instr_miss_stall(instr_miss_stall),
						   .data_in(MEM_WB_mem_data_in), .address_in(MEM_WB_Fresult), .data_cache_enable(MEM_WB_DMEM_en),
						   .data_cache_wen(MEM_WB_MemWrite), .data_out(MEM_WB_data_mem_out), .data_miss_stall(data_miss_stall));


assign IF_ID_stall = (IF_ID_branch_stall | IF_ID_data_stall); 

pldff #(16) iIF_ID_EX_instruction  (.clk(clk), .rst(rst | (branch_taken & (!IF_ID_stall & !data_miss_stall))), .d(instr_miss_stall ? 16'hE000 : IF_ID_instr), .q(ID_EX_instruction), .wen(!IF_ID_stall & !data_miss_stall));
pldff #(16) iIF_ID_EX_PC_nxt  (.clk(clk), .rst(rst | (branch_taken & (!IF_ID_stall & !data_miss_stall))), .d(IF_ID_PC_nxt), .q(ID_EX_PC_nxt), .wen(!IF_ID_stall & !data_miss_stall));

assign ID_EX_opcode = ID_EX_instruction[15:12];
assign ID_EX_DstReg_intr = ID_EX_instruction[11:8];
assign ID_EX_SrcReg1_intr = ID_EX_instruction[7:4];
assign ID_EX_SrcReg2_intr = ID_EX_instruction[3:0];
assign ID_EX_LLB_LHB_Byte = ID_EX_instruction[7:0];
assign ID_EX_immediate = ID_EX_instruction[3:0];
assign ID_EX_Branch_Condition = ID_EX_instruction[11:9];
assign ID_EX_B_Label = ID_EX_instruction[8:0];

assign ID_EX_B_Label_s_ex = {{7{ID_EX_B_Label[8]}}, ID_EX_B_Label[8:0]};

pc_control iPC_CNTRL(.branch(ID_EX_Branch_inst), .cnd(ID_EX_Branch_Condition), .imm(ID_EX_B_Label_s_ex), .f({sign, ovfl, zero}), .stall(IF_ID_branch_stall), 
					 .bLabel_sel(ID_bLabel_sel), .nxt_addr(ID_EX_SrcData1), .pc_in(IF_ID_PC_nxt), .pc_out(next_PC), .branch_taken(branch_taken));

ControlSignal iCU(.opcode(ID_EX_opcode), .RegSel_rt(ID_EX_RegSel_SrcReg2), .RegSel_rs(ID_EX_RegSel_SrcReg1), .Branch(ID_EX_Branch_inst), .MemtoReg(ID_EX_MemtoReg),
				  .ALUOp(ID_EX_ALUOp), .MemWrite(ID_EX_MemWrite), .ALUSrc(ID_EX_ALUSrc), .PC_save(ID_EX_PC_save), .Hlt(ID_EX_Hlt), .DMEM_en(ID_EX_DMEM_en),
				  .LB_mode(ID_EX_LB_mode), .LB_result_sel(ID_EX_LB_result_sel), .bLabel_sel(ID_bLabel_sel), .RegWrite(ID_EX_RegWrite), .MemRead(ID_EX_MemRead));

assign ID_EX_immediate_s_ex = ({{12{ID_EX_immediate[3]}}, ID_EX_immediate});

assign ID_EX_SrcReg1 = ID_EX_RegSel_SrcReg1 ? ID_EX_DstReg_intr : ID_EX_SrcReg1_intr;

assign ID_EX_SrcReg2 = ID_EX_RegSel_SrcReg2 ? ID_EX_DstReg_intr : ID_EX_SrcReg2_intr;

assign ID_EX_DstRegReg = ID_EX_DstReg_intr;

RegisterFile iREGFILE(.clk(clk), .rst(rst), .SrcReg1(ID_EX_SrcReg1), .SrcReg2(ID_EX_SrcReg2), .DstReg(WB_rd_reg), .WriteReg(WB_RegWrite), .write_en(!data_miss_stall),
					   .DstData(WB_result), .SrcData1(ID_EX_SrcData1), .SrcData2(ID_EX_SrcData2), .RF_bypass_en1(RF_bypass_en1), .RF_bypass_en2(RF_bypass_en2));

pldff #(4)  iID_EX_opcode (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_opcode), .q(EX_MEM_opcode), .wen(ID_EX_en));
pldff #(4)  iID_EX_rs_reg (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_SrcReg1), .q(EX_MEM_SrcReg1), .wen(ID_EX_en));
pldff #(4)  iID_EX_rt_reg (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_SrcReg2), .q(EX_MEM_SrcReg2), .wen(ID_EX_en));
pldff #(4)  iID_EX_rd_reg (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_DstRegReg), .q(EX_MEM_rd_reg), .wen(ID_EX_en));
pldff #(16) iID_EX_rs_reg_data  (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_SrcData1), .q(EX_MEM_SrcData1), .wen(ID_EX_en));
pldff #(16) iID_EX_rt_reg_data  (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_SrcData2), .q(EX_MEM_SrcData2), .wen(ID_EX_en));
pldff #(16) iID_EX_imm_signext  (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_immediate_s_ex), .q(EX_MEM_immediate_s_ex), .wen(ID_EX_en));
pldff #(8)  iID_EX_load_byte (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_LLB_LHB_Byte), .q(EX_MEM_LLB_LHB_Byte), .wen(ID_EX_en));
pldff #(16)  iID_EX_PC_nxt (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_PC_nxt), .q(EX_MEM_PC_nxt), .wen(ID_EX_en));

dff iID_EX_MemRead (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_MemRead), .q(EX_MEM_MemRead), .wen(ID_EX_en));
dff iID_EX_MemtoReg (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_MemtoReg), .q(EX_MEM_MemtoReg), .wen(ID_EX_en));
dff iID_EX_PC_save (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_PC_save), .q(EX_MEM_PC_save), .wen(ID_EX_en));
dff iID_EX_Hlt (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_Hlt), .q(EX_MEM_Hlt), .wen(ID_EX_en));
pldff #(3) iID_EX_ALUOp (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_ALUOp), .q(EX_MEM_ALUOp), .wen(ID_EX_en));
dff iID_EX_MemWrite (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_MemWrite), .q(EX_MEM_MemWrite), .wen(ID_EX_en));
dff iID_EX_ALUSrc (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_ALUSrc), .q(EX_MEM_ALUSrc), .wen(ID_EX_en));
dff iID_EX_DMEM_en (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_DMEM_en), .q(EX_MEM_DMEM_en), .wen(ID_EX_en));
dff iID_EX_LB_mode (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_LB_mode), .q(EX_MEM_LB_mode), .wen(ID_EX_en));
dff iID_EX_LB_result_sel (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_LB_result_sel), .q(EX_MEM_LB_result_sel), .wen(ID_EX_en));
dff iID_EX_RegWrite (.clk(clk), .rst(rst | ID_EX_flush), .d(ID_EX_RegWrite), .q(EX_MEM_RegWrite), .wen(ID_EX_en));

assign EX_MEM_operand1 = (EX_MEM_SrcData1_sel == 2'b00) ? (EX_MEM_DMEM_en ? (EX_MEM_SrcData1 & 16'hFFFE) : EX_MEM_SrcData1) :
					 (EX_MEM_SrcData1_sel == 2'b01) ? (EX_MEM_DMEM_en ? (WB_result & 16'hFFFE) : WB_result) :
					 (EX_MEM_SrcData1_sel == 2'b10) ? (EX_MEM_DMEM_en ? (MEM_WB_Fresult & 16'hFFFE) : MEM_WB_Fresult) : 
					 16'hxxxx;


assign EX_MEM_operand2 = (EX_MEM_SrcData2_sel == 2'b00) ? (EX_MEM_ALUSrc ? EX_MEM_DMEM_en ? (EX_MEM_immediate_s_ex << 1) : EX_MEM_immediate_s_ex : EX_MEM_SrcData2) :
					 (EX_MEM_SrcData2_sel == 2'b01) ? (EX_MEM_ALUSrc ? EX_MEM_DMEM_en ? (EX_MEM_immediate_s_ex << 1) : EX_MEM_immediate_s_ex : WB_result) : 
					 (EX_MEM_SrcData2_sel == 2'b10) ? (EX_MEM_ALUSrc ? EX_MEM_DMEM_en ? (EX_MEM_immediate_s_ex << 1) : EX_MEM_immediate_s_ex : MEM_WB_Fresult) :
					 16'hxxxx;

ALU iALU(.a(EX_MEM_operand1), .b(EX_MEM_operand2), .ALUOp(EX_MEM_ALUOp), .result(EX_MEM_ALU_out), .ovfl(EX_MEM_ovfl), .zero(EX_MEM_zero), .sign(EX_MEM_sign));

wire [15:0] clr_result;

assign clr_result = EX_MEM_LB_mode ? (EX_MEM_operand1 & 16'h00FF) : (EX_MEM_operand1 & 16'hFF00) ;
assign EX_MEM_LB_result = EX_MEM_LB_mode ? (clr_result | {EX_MEM_LLB_LHB_Byte, 8'h00}) : (clr_result | {8'h00, EX_MEM_LLB_LHB_Byte});
	
assign EX_MEM_Fresult = EX_MEM_LB_result_sel ? EX_MEM_LB_result : EX_MEM_ALU_out;


assign EX_MEM_SrcData2_temp = (EX_MEM_SrcData2_sel == 2'b00) ? (EX_MEM_SrcData2) :
							(EX_MEM_SrcData2_sel == 2'b01) ? (WB_result) : 
							(EX_MEM_SrcData2_sel == 2'b10) ? ( MEM_WB_Fresult) :
							16'hxxxx;

EX_MEM_Register iEX_MEM_REG(.clk(clk), .rst(rst), .EX_MEM_en(EX_MEM_en), .EX_MEM_flush(ID_EX_flush), .EX_opcode(EX_MEM_opcode), .EX_rs_reg(EX_MEM_SrcReg1),
						  .EX_rt_reg(EX_MEM_SrcReg2), .EX_rd_reg(EX_MEM_rd_reg), .EX_rt_reg_data(EX_MEM_SrcData2_temp), .EX_ALU_result(EX_MEM_ALU_out),
						  .EX_LB_result(EX_MEM_LB_result), .EX_Fresult(EX_MEM_Fresult), .EX_PC_nxt(EX_MEM_PC_nxt), .EX_ovfl(EX_MEM_ovfl), .EX_zero(EX_MEM_zero), .EX_sign(EX_MEM_sign), 
						  .EX_PC_save(EX_MEM_PC_save), .EX_Hlt(EX_MEM_Hlt), .EX_MemtoReg(EX_MEM_MemtoReg), .EX_MemWrite(EX_MEM_MemWrite), .EX_DMEM_en(EX_MEM_DMEM_en),
						  .EX_LB_result_sel(EX_MEM_LB_result_sel), .EX_RegWrite(EX_MEM_RegWrite), .EX_MemRead(EX_MEM_MemRead),
						  
						  .MEM_opcode(MEM_WB_opcode), .MEM_rs_reg(MEM_WB_rs_reg), .MEM_rt_reg(MEM_WB_rt_reg), .MEM_rd_reg(MEM_WB_rd_reg), .MEM_rt_reg_data(MEM_WB_rt_reg_data),
						  .MEM_ALU_result(MEM_WB_ALU_result), .MEM_LB_result(MEM_WB_LB_result), .MEM_Fresult(MEM_WB_Fresult), .MEM_PC_nxt(MEM_WB_PC_nxt), .MEM_ovfl(MEM_WB_ovfl),  
						  .MEM_zero(MEM_WB_zero), .MEM_sign(MEM_WB_sign), .MEM_PC_save(MEM_WB_PC_save), .MEM_Hlt(MEM_WB_Hlt), .MEM_MemtoReg(MEM_WB_MemtoReg), .MEM_MemWrite(MEM_WB_MemWrite), 
						  .MEM_DMEM_en(MEM_WB_DMEM_en), .MEM_LB_result_sel(MEM_WB_LB_result_sel), .MEM_RegWrite(MEM_WB_RegWrite), .MEM_MemRead(MEM_WB_MemRead));
						  

assign MEM_WB_mem_data_in = MEM_WB_data_in_sel ? WB_result : MEM_WB_rt_reg_data;


pldff #(4)  iMEM_WB_opcode (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_opcode), .q(WB_opcode), .wen(MEM_WB_en));
pldff #(4)  iMEM_WB_rs_reg (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_rs_reg), .q(WB_rs_reg), .wen(MEM_WB_en));
pldff #(4)  iMEM_WB_rt_reg (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_rt_reg), .q(WB_rt_reg), .wen(MEM_WB_en));
pldff #(4)  iMEM_WB_rd_reg (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_rd_reg), .q(WB_rd_reg), .wen(MEM_WB_en));


pldff #(16)  iMEM_WB_ALU_result (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_ALU_result), .q(WB_ALU_result), .wen(MEM_WB_en));
pldff #(16)  iMEM_WB_LB_result (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_LB_result), .q(WB_LB_result), .wen(MEM_WB_en));
pldff #(16)  iMEM_WB_Fresult (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_Fresult), .q(WB_Fresult), .wen(MEM_WB_en));
pldff #(16)  iMEM_WB_data_mem_out (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_data_mem_out), .q(WB_data_mem_out), .wen(MEM_WB_en));
pldff #(16)  iMEM_WB_PC_nxt (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_PC_nxt), .q(WB_PC_nxt), .wen(MEM_WB_en));
dff iMEM_WB_ovfl (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_ovfl), .q(WB_ovfl), .wen(MEM_WB_en));
dff iMEM_WB_sign (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_sign), .q(WB_sign), .wen(MEM_WB_en));
dff iMEM_WB_zero (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_zero), .q(WB_zero), .wen(MEM_WB_en));
dff iMEM_WB_MemRead (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_MemRead), .q(WB_MemRead), .wen(MEM_WB_en));

dff iMEM_WB_PC_save (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_PC_save), .q(WB_PC_save), .wen(MEM_WB_en));
dff iMEM_WB_Hlt (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_Hlt), .q(WB_Hlt), .wen(MEM_WB_en));
dff iMEM_WB_MemtoReg (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_MemtoReg), .q(WB_MemtoReg), .wen(MEM_WB_en));
dff iMEM_WB_LB_result_sel (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_LB_result_sel), .q(WB_LB_result_sel), .wen(MEM_WB_en));
dff iMEM_WB_RegWrite (.clk(clk), .rst(rst | MEM_WB_flush), .d(MEM_WB_RegWrite), .q(WB_RegWrite), .wen(MEM_WB_en));




assign hlt = WB_Hlt;


assign WB_result = WB_PC_save ? WB_PC_nxt : 
				   WB_MemtoReg ? WB_data_mem_out :
				   WB_Fresult;


assign ID_EX_en = !data_miss_stall;
assign EX_MEM_en = !data_miss_stall;
assign MEM_WB_en = !data_miss_stall;

assign IF_ID_flush = 1'b0;
assign ID_EX_flush = 1'b0;
assign EX_MEM_flush = 1'b0;
assign MEM_WB_flush = 1'b0;


endmodule