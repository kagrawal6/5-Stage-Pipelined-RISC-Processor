
module EX_MEM_Register(
    input clk,
    input rst,
    input EX_MEM_en, // Enable signal to IF_ID_Register
    input EX_MEM_flush, // Incase Predict-not-taken policy fails, we flush the pipeline register

    input [3:0] EX_opcode, // Opcode required for writing back to flag registers in WB stage
    input [3:0] EX_rs_reg, // rs reg ID for data hazards
    input [3:0] EX_rt_reg, // rt reg ID for data hazards
    input [3:0] EX_rd_reg, // rd reg ID for data hazards
    input [15:0] EX_rt_reg_data, // rt reg data to be stored incase of SW operation
    // input [2:0] EX_branch_cnd,
    // input [15:0] EX_blabel_signext,
    input [15:0] EX_ALU_result, // Output of ALU block
    input [15:0] EX_LB_result, // Output of LB block
    input [15:0] EX_Fresult, //  Final result from the EX stage, selects between ALU and LB result based on LB_result_sel
    input [15:0] EX_PC_nxt,
    input EX_ovfl, // Ovfl flag from ALU
    input EX_zero, // Zero flag from ALU
    input EX_sign, // Sign Flag from ALU
    // input EX_Branch,
    input EX_MemRead, // Control signal to read from data mem for LW instr
    input EX_PC_save,
    input EX_Hlt,
    input EX_MemtoReg, // Control signal for LW instr to store data into register
    input EX_MemWrite, // Control signal for SW instr to write into data memory
    input EX_DMEM_en, // Control signal to enable data memory block for SW and LW instr
    input EX_LB_result_sel, // Selects between ALU and LB result in WB stage
    input EX_RegWrite, // Control signal to enable writing to the register file

    output [3:0] MEM_opcode,
    output [3:0] MEM_rs_reg,
    output [3:0] MEM_rt_reg,
    output [3:0] MEM_rd_reg,
    output [15:0] MEM_rt_reg_data,
    // output [2:0] MEM_branch_cnd,
    // output [15:0] MEM_blabel_signext,
    output [15:0] MEM_ALU_result,
    output [15:0] MEM_LB_result,
    output [15:0] MEM_Fresult,
    output [15:0] MEM_PC_nxt,
    output MEM_ovfl,
    output MEM_zero,
    output MEM_sign,
    // output MEM_Branch,
    output MEM_MemRead,
    output MEM_PC_save,
    output MEM_Hlt,
    output MEM_MemtoReg,
    output MEM_MemWrite,
    output MEM_DMEM_en,
    output MEM_LB_result_sel,
    output MEM_RegWrite
);

pldff #(4)  iEX_MEM_opcode (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_opcode), .q(MEM_opcode), .wen(EX_MEM_en));
pldff #(4)  iEX_MEM_rs_reg (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_rs_reg), .q(MEM_rs_reg), .wen(EX_MEM_en));
pldff #(4)  iEX_MEM_rt_reg (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_rt_reg), .q(MEM_rt_reg), .wen(EX_MEM_en));
pldff #(4)  iEX_MEM_rd_reg (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_rd_reg), .q(MEM_rd_reg), .wen(EX_MEM_en));
pldff #(16) iEX_MEM_rt_reg_data  (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_rt_reg_data), .q(MEM_rt_reg_data), .wen(EX_MEM_en));
pldff #(16) iEX_MEM_ALU_result  (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_ALU_result), .q(MEM_ALU_result), .wen(EX_MEM_en));
pldff #(16) iEX_MEM_LB_result  (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_LB_result), .q(MEM_LB_result), .wen(EX_MEM_en));
pldff #(16) iEX_MEM_Fresult  (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_Fresult), .q(MEM_Fresult), .wen(EX_MEM_en));
pldff #(16) iEX_MEM_PC_nxt  (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_PC_nxt), .q(MEM_PC_nxt), .wen(EX_MEM_en));
// pldff #(3)  iEX_MEM_branch_cnd (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_branch_cnd), .q(MEM_branch_cnd), .wen(EX_MEM_en));
// pldff #(16) iEX_MEM_blabel_signext  (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_blabel_signext), .q(MEM_blabel_signext), .wen(EX_MEM_en));
dff iEX_MEM_ovfl (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_ovfl), .q(MEM_ovfl), .wen(EX_MEM_en));
dff iEX_MEM_sign (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_sign), .q(MEM_sign), .wen(EX_MEM_en));
dff iEX_MEM_zero (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_zero), .q(MEM_zero), .wen(EX_MEM_en));
// dff iEX_MEM_Branch (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_Branch), .q(MEM_Branch), .wen(EX_MEM_en));
dff iEX_MEM_MemRead (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_MemRead), .q(MEM_MemRead), .wen(EX_MEM_en));
dff iEX_MEM_PC_save (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_PC_save), .q(MEM_PC_save), .wen(EX_MEM_en));
dff iEX_MEM_Hlt (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_Hlt), .q(MEM_Hlt), .wen(EX_MEM_en));
dff iEX_MEM_MemtoReg (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_MemtoReg), .q(MEM_MemtoReg), .wen(EX_MEM_en));
dff iEX_MEM_MemWrite (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_MemWrite), .q(MEM_MemWrite), .wen(EX_MEM_en));
dff iEX_MEM_DMEM_en (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_DMEM_en), .q(MEM_DMEM_en), .wen(EX_MEM_en));
dff iEX_MEM_LB_result_sel (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_LB_result_sel), .q(MEM_LB_result_sel), .wen(EX_MEM_en));
dff iEX_MEM_RegWrite (.clk(clk), .rst(rst | EX_MEM_flush), .d(EX_RegWrite), .q(MEM_RegWrite), .wen(EX_MEM_en));
endmodule