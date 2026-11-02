# Every compute opcode on edge-case operands. Most instructions are
# independent of each other, so the out-of-order core can overlap them.
    LI  R1, 0x1234
    LI  R2, 0x0F0F
    LI  R3, 0x7FF0
    LI  R4, 0x8010
    LI  R5, 0xFFFF
    LI  R6, 0x0020
    # ADD / SUB, including both saturation directions
    ADD R7, R1, R2          # 0x2143
    ADD R8, R3, R6          # +overflow -> 0x7FFF
    ADD R9, R4, R5          # 0x800F
    ADD R10, R4, R4         # -overflow -> 0x8000
    SUB R11, R1, R2         # 0x0325
    SUB R12, R4, R6         # -overflow -> 0x8000
    SUB R13, R3, R4         # +overflow -> 0x7FFF
    SUB R14, R5, R5         # 0
    # XOR / RED / PADDSB
    XOR R15, R1, R2
    XOR R7, R7, R5
    RED R8, R1, R2
    RED R9, R5, R5
    RED R10, R3, R4
    PADDSB R11, R1, R2
    PADDSB R12, R4, R5
    PADDSB R13, R3, R3      # nibble saturation 7+7 -> 7
    PADDSB R14, R4, R4      # 8+8 (-8 + -8) -> -8
    # shifts
    SLL R15, R1, 4
    SRA R7, R4, 3
    SRA R8, R3, 15
    ROR R9, R1, 8
    ROR R10, R1, 0
    # LLB / LHB keep the other byte
    LLB R11, 0xAB
    LHB R11, 0xCD
    LHB R12, 0x00
    LLB R13, 0xFF
    # results feeding results (dependence chain through the ALU bypass)
    ADD R1, R1, R1
    ADD R1, R1, R1
    SUB R1, R1, R2
    XOR R1, R1, R5
    SLL R1, R1, 1
    RED R1, R1, R1
    PADDSB R1, R1, R1
    HLT
