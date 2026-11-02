// Shared constants for the out-of-order WISC-S25 core.
// Included inside module bodies.

localparam [3:0] OP_ADD    = 4'h0,
                 OP_SUB    = 4'h1,
                 OP_XOR    = 4'h2,
                 OP_RED    = 4'h3,
                 OP_SLL    = 4'h4,
                 OP_SRA    = 4'h5,
                 OP_ROR    = 4'h6,
                 OP_PADDSB = 4'h7,
                 OP_LW     = 4'h8,
                 OP_SW     = 4'h9,
                 OP_LLB    = 4'hA,
                 OP_LHB    = 4'hB,
                 OP_B      = 4'hC,
                 OP_BR     = 4'hD,
                 OP_PCS    = 4'hE,
                 OP_HLT    = 4'hF;

// Functional-unit classes. Each class has exactly one unit.
localparam [1:0] FU_ALU = 2'd0,
                 FU_BRU = 2'd1,
                 FU_LDU = 2'd2,
                 FU_STU = 2'd3;

// Branch predictor selection (cpu parameter BP_TYPE).
localparam BP_STATIC_NT = 0,
           BP_BTFN      = 1,
           BP_BIMODAL   = 2,
           BP_GSHARE    = 3,
           BP_TOURNAMENT= 4,
           BP_PERCEPTRON= 5,
           BP_TAGE      = 6;
