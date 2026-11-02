// Execution units. All are single-cycle and combinational; the core latches
// their outputs at the end of the issue cycle.

// ALU unit: reuses the baseline (phase 3) arithmetic blocks -- saturating
// CLA adder/subtractor, XOR, PADDSB, RED and the shifter/rotator -- and adds
// LLB/LHB. The blocks are instantiated directly (rather than through the
// baseline ALU.v mux, which leaves latches and drives 'z' into wire arrays).
// Flags are produced for every op; the ROB only commits the ones the
// instruction actually writes (decoder wr_z / wr_nv).
module alu_unit (
    input  wire [15:0] instr,
    input  wire [15:0] a,          // rs (or rd for LLB/LHB)
    input  wire [15:0] b,          // rt
    output reg  [15:0] result,
    output wire        z,
    output wire        n,
    output wire        v
);
`include "ooo_defs.vh"
    wire [3:0]  op = instr[15:12];

    wire [15:0] add_res, sub_res, xor_res, psa_res, red_res, sh_res;
    wire        add_ovfl, sub_ovfl;
    /* verilator lint_off PINCONNECTEMPTY */
    Adder_ALU   iADD (.a(a), .b(b), .result(add_res), .ovfl(add_ovfl), .zero(), .sign());
    Subtractor  iSUB (.a(a), .b(b), .result(sub_res), .ovfl(sub_ovfl), .zero(), .sign());
    XOR         iXOR (.a(a), .b(b), .result(xor_res), .ovfl(), .zero(), .sign());
    PSA_16bit   iPSA (.a(a), .b(b), .result(psa_res), .ovfl(), .zero(), .sign());
    RED         iRED (.a(a), .b(b), .result(red_res), .ovfl(), .zero(), .sign());
    Shifter_ALU iSH  (.a(a), .b(instr[3:0]), .mode(op[1:0]), .result(sh_res),
                      .ovfl(), .zero(), .sign());
    /* verilator lint_on PINCONNECTEMPTY */

    always @(*) begin
        case (op)
            OP_ADD:                 result = add_res;
            OP_SUB:                 result = sub_res;
            OP_XOR:                 result = xor_res;
            OP_RED:                 result = red_res;
            OP_SLL, OP_SRA, OP_ROR: result = sh_res;   // mode = op[1:0]: 00 SLL, 01 SRA, 10 ROR
            OP_PADDSB:              result = psa_res;
            OP_LLB:                 result = {a[15:8], instr[7:0]};
            default:                result = {instr[7:0], a[7:0]};   // LHB
        endcase
    end

    assign z = (result == 16'h0000);
    assign n = result[15];
    assign v = (op == OP_ADD) ? add_ovfl : (op == OP_SUB) ? sub_ovfl : 1'b0;
endmodule


// Branch unit: evaluates the condition code, computes the real next PC and
// compares it with the PC the front end predicted.
module branch_unit (
    input  wire [15:0] instr,
    input  wire [15:0] pc,
    input  wire [15:0] pred_npc,
    input  wire [15:0] a,          // BR target register
    input  wire        z,
    input  wire        n,
    input  wire        v,
    output reg         taken,
    output wire [15:0] npc,
    output wire        mispred
);
`include "ooo_defs.vh"
    always @(*) begin
        case (instr[11:9])
            3'd0: taken = !z;              // NEQ
            3'd1: taken = z;               // EQ
            3'd2: taken = !z & !n;         // GT
            3'd3: taken = n;               // LT
            3'd4: taken = z | !n;          // GTE
            3'd5: taken = n | z;           // LTE
            3'd6: taken = v;               // OVFL
            default: taken = 1'b1;         // UNCOND
        endcase
    end

    wire [15:0] pc_plus2 = pc + 16'd2;
    wire [15:0] b_target = pc_plus2 + {{6{instr[8]}}, instr[8:0], 1'b0};
    wire [15:0] target   = (instr[15:12] == OP_BR) ? a : b_target;

    assign npc     = taken ? target : pc_plus2;
    assign mispred = (npc != pred_npc);
endmodule
