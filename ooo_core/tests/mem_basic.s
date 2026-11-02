# LW / SW addressing: every offset -8..7, odd base addresses (bit 0 is
# ignored), and round trips through memory.
    LI  R14, 0x4100
    LI  R13, 0x4101         # odd base: same as 0x4100
    LLB R1, 1
    LLB R2, 0
    # store 16 distinct values using offsets -8..7
    SW R1, R14, -8
    ADD R1, R1, R1
    SW R1, R14, -7
    ADD R1, R1, R1
    SW R1, R14, -6
    ADD R1, R1, R1
    SW R1, R14, -5
    ADD R1, R1, R1
    SW R1, R14, -4
    ADD R1, R1, R1
    SW R1, R14, -3
    ADD R1, R1, R1
    SW R1, R14, -2
    ADD R1, R1, R1
    SW R1, R14, -1
    ADD R1, R1, R1
    SW R1, R14, 0
    ADD R1, R1, R1
    SW R1, R14, 1
    ADD R1, R1, R1
    SW R1, R14, 2
    ADD R1, R1, R1
    SW R1, R14, 3
    ADD R1, R1, R1
    SW R1, R14, 4
    ADD R1, R1, R1
    SW R1, R14, 5
    ADD R1, R1, R1
    SW R1, R14, 6
    ADD R1, R1, R1
    SW R1, R14, 7
    # read them back through the odd base and sum them
    LW R3, R13, -8
    LW R4, R13, -7
    ADD R2, R3, R4
    LW R3, R13, -6
    ADD R2, R2, R3
    LW R3, R13, -5
    ADD R2, R2, R3
    LW R3, R13, -4
    ADD R2, R2, R3
    LW R3, R13, -3
    ADD R2, R2, R3
    LW R3, R13, -2
    ADD R2, R2, R3
    LW R3, R13, -1
    ADD R2, R2, R3
    LW R3, R13, 0
    ADD R2, R2, R3
    LW R3, R13, 1
    ADD R2, R2, R3
    LW R3, R13, 2
    ADD R2, R2, R3
    LW R3, R13, 3
    ADD R2, R2, R3
    LW R3, R13, 4
    ADD R2, R2, R3
    LW R3, R13, 5
    ADD R2, R2, R3
    LW R3, R13, 6
    ADD R2, R2, R3
    LW R3, R13, 7
    ADD R2, R2, R3          # 0xFFFF summed with saturation
    # load a word that the program image initialised
    LI  R5, table
    LW  R6, R5, 0
    LW  R7, R5, 1
    LW  R8, R5, 2
    HLT
table:
    .word 0xBEEF, 0x1357, 0x2468
