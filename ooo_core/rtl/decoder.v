// Decoder: turns one WISC-S25 instruction into the fields rename and
// dispatch need (which unit runs it, which registers/flags it reads and
// writes). Purely combinational.
module decoder (
    input  wire [15:0] instr,
    output reg  [1:0]  fu,          // functional-unit class (FU_*)
    output reg         needs_iq,    // 0: complete at dispatch (PCS, HLT, B unconditional)
    output reg         use_s1,
    output reg  [3:0]  s1_reg,
    output reg         use_s2,
    output reg  [3:0]  s2_reg,
    output reg         use_z,       // reads the Z flag
    output reg         use_nv,      // reads the N and V flags
    output reg         wr_rd,       // writes instr[11:8]
    output reg         wr_z,        // writes Z
    output reg         wr_nv,       // writes N and V
    output wire        is_load,
    output wire        is_store,
    output wire        is_cond_br,  // B or BR with condition != 111
    output wire        is_br_reg,   // BR (target from register)
    output wire        is_pcs,
    output wire        is_halt
);
`include "ooo_defs.vh"

    wire [3:0] op   = instr[15:12];
    wire [2:0] cond = instr[11:9];

    // Flags each condition code looks at (see ISA table):
    // NEQ/EQ: Z   GT/GTE/LTE: Z,N   LT: N   OVFL: V   UNCOND: none
    wire cond_z  = (cond == 3'd0) | (cond == 3'd1) | (cond == 3'd2) |
                   (cond == 3'd4) | (cond == 3'd5);
    wire cond_nv = (cond == 3'd2) | (cond == 3'd3) | (cond == 3'd4) |
                   (cond == 3'd5) | (cond == 3'd6);

    assign is_load    = (op == OP_LW);
    assign is_store   = (op == OP_SW);
    assign is_cond_br = ((op == OP_B) | (op == OP_BR)) & (cond != 3'b111);
    assign is_br_reg  = (op == OP_BR);
    assign is_pcs     = (op == OP_PCS);
    assign is_halt    = (op == OP_HLT);

    always @(*) begin
        fu       = FU_ALU;
        needs_iq = 1'b1;
        use_s1   = 1'b0;
        s1_reg   = instr[7:4];
        use_s2   = 1'b0;
        s2_reg   = instr[3:0];
        use_z    = 1'b0;
        use_nv   = 1'b0;
        wr_rd    = 1'b0;
        wr_z     = 1'b0;
        wr_nv    = 1'b0;
        case (op)
            OP_ADD, OP_SUB: begin
                use_s1 = 1'b1; use_s2 = 1'b1;
                wr_rd = 1'b1; wr_z = 1'b1; wr_nv = 1'b1;
            end
            OP_XOR: begin
                use_s1 = 1'b1; use_s2 = 1'b1;
                wr_rd = 1'b1; wr_z = 1'b1;
            end
            OP_RED, OP_PADDSB: begin
                use_s1 = 1'b1; use_s2 = 1'b1;
                wr_rd = 1'b1;
            end
            OP_SLL, OP_SRA, OP_ROR: begin
                use_s1 = 1'b1;
                wr_rd = 1'b1; wr_z = 1'b1;
            end
            OP_LW: begin
                fu = FU_LDU;
                use_s1 = 1'b1;
                wr_rd = 1'b1;
            end
            OP_SW: begin
                fu = FU_STU;
                use_s1 = 1'b1;                       // base register
                use_s2 = 1'b1; s2_reg = instr[11:8]; // store data register
            end
            OP_LLB, OP_LHB: begin
                use_s1 = 1'b1; s1_reg = instr[11:8]; // keeps half of the old value
                wr_rd = 1'b1;
            end
            OP_B: begin
                fu = FU_BRU;
                needs_iq = (cond != 3'b111);         // fetch already followed B UNCOND
                use_z = cond_z; use_nv = cond_nv;
            end
            OP_BR: begin
                fu = FU_BRU;
                use_s1 = 1'b1;
                use_z = cond_z; use_nv = cond_nv;
            end
            OP_PCS: begin
                needs_iq = 1'b0;                     // value (PC+2) known at dispatch
                wr_rd = 1'b1;
            end
            default: begin                           // HLT
                needs_iq = 1'b0;
            end
        endcase
    end
endmodule
