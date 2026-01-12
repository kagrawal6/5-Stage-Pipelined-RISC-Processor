module ControlSignal(
    input [3:0] opcode,
    output reg RegSel_rt,
    output reg Branch,
    output reg MemRead,
    output reg MemtoReg,
    output reg [2:0] ALUOp,
    output reg MemWrite,
    output reg ALUSrc,
    output reg PC_save,
    output reg Hlt,
    output reg DMEM_en,
	output reg LB_result_sel,
    output reg LB_mode,
    output reg RegSel_rs,
    output reg bLabel_sel,
    output reg RegWrite
);


localparam [2:0] ADD    = 3'b000;
localparam [2:0] SUB    = 3'b001;
localparam [2:0] XOR    = 3'b010;
localparam [2:0] RED    = 3'b011;
localparam [2:0] SLL    = 3'b100;
localparam [2:0] SRA    = 3'b101;
localparam [2:0] ROR    = 3'b110;
localparam [2:0] PADDSB = 3'b111;

always @(*) begin
    RegSel_rt = 1'b0;    
    Branch = 1'b0;   
    MemtoReg = 1'b0; 
    MemRead = 1'b0;   
    PC_save = 1'b0;
    Hlt = 1'b0;
    MemWrite = 1'b0;  
    ALUSrc = 1'b0;
    RegWrite = 1'b0;
    DMEM_en = 1'b0;
    LB_mode = 1'b0;
    LB_result_sel = 1'b0;
    RegSel_rs = 1'b0;
    bLabel_sel = 1'b0; 

    case (opcode)
        4'b0000: begin // ADD   
            RegWrite = 1'b1; 
            ALUOp = ADD;      // ALU operation for addition
        end
        4'b0001: begin // SUB 
            RegWrite = 1'b1; 
            ALUOp = SUB;      // ALU operation for subtraction
        end
        4'b0010: begin // XOR
            RegWrite = 1'b1; 
            ALUOp = XOR;      // ALU operation for XOR
        end
        4'b0011: begin // RED 
            RegWrite = 1'b1; 
            ALUOp = RED;      // ALU operation for RED
        end
        4'b0100: begin // SLL   
            RegWrite = 1'b1;
						ALUSrc = 1'b1; 
            ALUOp = SLL;      // ALU operation for SLL
        end
        4'b0101: begin // SRA  
            RegWrite = 1'b1; 
						ALUSrc = 1'b1;
            ALUOp = SRA;      // ALU operation for SRA
        end
        4'b0110: begin // ROR 
            RegWrite = 1'b1; 
						ALUSrc = 1'b1;
            ALUOp = ROR;      // ALU operation for ROR
        end
        4'b0111: begin // PADDSB
            RegWrite = 1'b1; 
            ALUOp = PADDSB;   // ALU operation for PADDSB
        end
        4'b1000: begin // LW
            ALUSrc = 1'b1;   
            MemRead = 1'b1;  
            MemtoReg = 1'b1; 
            RegWrite = 1'b1;
            DMEM_en = 1'b1; 
            ALUOp = ADD;      // Addition of base address and offset
        end
        4'b1001: begin // SW
			RegSel_rt = 1'b1;
            ALUSrc = 1'b1;   
            MemWrite = 1'b1;
            DMEM_en = 1'b1;  
            ALUOp = ADD;      // Addition of base address and offset
        end
        4'b1010: begin // LLB  
            RegWrite = 1'b1;
            LB_result_sel =1'b1;
            RegSel_rs = 1'b1;
            LB_mode = 1'b0;  
            ALUOp = ADD;      // Addition of base address and offset
        end
        4'b1011: begin // LHB 
            RegWrite = 1'b1;
            LB_result_sel =1'b1;
            RegSel_rs = 1'b1;
            LB_mode = 1'b1; 
            ALUOp = ADD;      // Addition of base address and offset
        end
        4'b1100: begin // B (Branch)
            Branch = 1'b1;    // Enable branch
        end
        4'b1101: begin // BR (Branch Register)
            Branch = 1'b1;
            bLabel_sel=1'b1;
            
        end
        4'b1110: begin // PC
          RegWrite = 1'b1;
          PC_save =1'b1;
        end
        4'b1111: begin // HLT (Halt)
          Hlt =1'b1;

        end
       
    endcase
end

endmodule   
