# SLL / SRA / ROR by every amount 0..15 on two bit patterns; each result
# also sets Z, which is checked with a branch.
    LI R1, 0x8421
    LI R2, 0x7F3C
    LI R14, 0x4000
    SLL R3, R1, 0
    B EQ, z_SLL_1_0
    SW R3, R14, 0
z_SLL_1_0:
    SLL R3, R2, 0
    B EQ, z_SLL_2_0
    SW R3, R14, 0
z_SLL_2_0:
    SRA R3, R1, 0
    B EQ, z_SRA_1_0
    SW R3, R14, 0
z_SRA_1_0:
    SRA R3, R2, 0
    B EQ, z_SRA_2_0
    SW R3, R14, 0
z_SRA_2_0:
    ROR R3, R1, 0
    B EQ, z_ROR_1_0
    SW R3, R14, 0
z_ROR_1_0:
    ROR R3, R2, 0
    B EQ, z_ROR_2_0
    SW R3, R14, 0
z_ROR_2_0:
    SLL R3, R1, 1
    B EQ, z_SLL_1_1
    SW R3, R14, 1
z_SLL_1_1:
    SLL R3, R2, 1
    B EQ, z_SLL_2_1
    SW R3, R14, 1
z_SLL_2_1:
    SRA R3, R1, 1
    B EQ, z_SRA_1_1
    SW R3, R14, 1
z_SRA_1_1:
    SRA R3, R2, 1
    B EQ, z_SRA_2_1
    SW R3, R14, 1
z_SRA_2_1:
    ROR R3, R1, 1
    B EQ, z_ROR_1_1
    SW R3, R14, 1
z_ROR_1_1:
    ROR R3, R2, 1
    B EQ, z_ROR_2_1
    SW R3, R14, 1
z_ROR_2_1:
    SLL R3, R1, 2
    B EQ, z_SLL_1_2
    SW R3, R14, 2
z_SLL_1_2:
    SLL R3, R2, 2
    B EQ, z_SLL_2_2
    SW R3, R14, 2
z_SLL_2_2:
    SRA R3, R1, 2
    B EQ, z_SRA_1_2
    SW R3, R14, 2
z_SRA_1_2:
    SRA R3, R2, 2
    B EQ, z_SRA_2_2
    SW R3, R14, 2
z_SRA_2_2:
    ROR R3, R1, 2
    B EQ, z_ROR_1_2
    SW R3, R14, 2
z_ROR_1_2:
    ROR R3, R2, 2
    B EQ, z_ROR_2_2
    SW R3, R14, 2
z_ROR_2_2:
    SLL R3, R1, 3
    B EQ, z_SLL_1_3
    SW R3, R14, 3
z_SLL_1_3:
    SLL R3, R2, 3
    B EQ, z_SLL_2_3
    SW R3, R14, 3
z_SLL_2_3:
    SRA R3, R1, 3
    B EQ, z_SRA_1_3
    SW R3, R14, 3
z_SRA_1_3:
    SRA R3, R2, 3
    B EQ, z_SRA_2_3
    SW R3, R14, 3
z_SRA_2_3:
    ROR R3, R1, 3
    B EQ, z_ROR_1_3
    SW R3, R14, 3
z_ROR_1_3:
    ROR R3, R2, 3
    B EQ, z_ROR_2_3
    SW R3, R14, 3
z_ROR_2_3:
    SLL R3, R1, 4
    B EQ, z_SLL_1_4
    SW R3, R14, 4
z_SLL_1_4:
    SLL R3, R2, 4
    B EQ, z_SLL_2_4
    SW R3, R14, 4
z_SLL_2_4:
    SRA R3, R1, 4
    B EQ, z_SRA_1_4
    SW R3, R14, 4
z_SRA_1_4:
    SRA R3, R2, 4
    B EQ, z_SRA_2_4
    SW R3, R14, 4
z_SRA_2_4:
    ROR R3, R1, 4
    B EQ, z_ROR_1_4
    SW R3, R14, 4
z_ROR_1_4:
    ROR R3, R2, 4
    B EQ, z_ROR_2_4
    SW R3, R14, 4
z_ROR_2_4:
    SLL R3, R1, 5
    B EQ, z_SLL_1_5
    SW R3, R14, 5
z_SLL_1_5:
    SLL R3, R2, 5
    B EQ, z_SLL_2_5
    SW R3, R14, 5
z_SLL_2_5:
    SRA R3, R1, 5
    B EQ, z_SRA_1_5
    SW R3, R14, 5
z_SRA_1_5:
    SRA R3, R2, 5
    B EQ, z_SRA_2_5
    SW R3, R14, 5
z_SRA_2_5:
    ROR R3, R1, 5
    B EQ, z_ROR_1_5
    SW R3, R14, 5
z_ROR_1_5:
    ROR R3, R2, 5
    B EQ, z_ROR_2_5
    SW R3, R14, 5
z_ROR_2_5:
    SLL R3, R1, 6
    B EQ, z_SLL_1_6
    SW R3, R14, 6
z_SLL_1_6:
    SLL R3, R2, 6
    B EQ, z_SLL_2_6
    SW R3, R14, 6
z_SLL_2_6:
    SRA R3, R1, 6
    B EQ, z_SRA_1_6
    SW R3, R14, 6
z_SRA_1_6:
    SRA R3, R2, 6
    B EQ, z_SRA_2_6
    SW R3, R14, 6
z_SRA_2_6:
    ROR R3, R1, 6
    B EQ, z_ROR_1_6
    SW R3, R14, 6
z_ROR_1_6:
    ROR R3, R2, 6
    B EQ, z_ROR_2_6
    SW R3, R14, 6
z_ROR_2_6:
    SLL R3, R1, 7
    B EQ, z_SLL_1_7
    SW R3, R14, 7
z_SLL_1_7:
    SLL R3, R2, 7
    B EQ, z_SLL_2_7
    SW R3, R14, 7
z_SLL_2_7:
    SRA R3, R1, 7
    B EQ, z_SRA_1_7
    SW R3, R14, 7
z_SRA_1_7:
    SRA R3, R2, 7
    B EQ, z_SRA_2_7
    SW R3, R14, 7
z_SRA_2_7:
    ROR R3, R1, 7
    B EQ, z_ROR_1_7
    SW R3, R14, 7
z_ROR_1_7:
    ROR R3, R2, 7
    B EQ, z_ROR_2_7
    SW R3, R14, 7
z_ROR_2_7:
    SLL R3, R1, 8
    B EQ, z_SLL_1_8
    SW R3, R14, 0
z_SLL_1_8:
    SLL R3, R2, 8
    B EQ, z_SLL_2_8
    SW R3, R14, 0
z_SLL_2_8:
    SRA R3, R1, 8
    B EQ, z_SRA_1_8
    SW R3, R14, 0
z_SRA_1_8:
    SRA R3, R2, 8
    B EQ, z_SRA_2_8
    SW R3, R14, 0
z_SRA_2_8:
    ROR R3, R1, 8
    B EQ, z_ROR_1_8
    SW R3, R14, 0
z_ROR_1_8:
    ROR R3, R2, 8
    B EQ, z_ROR_2_8
    SW R3, R14, 0
z_ROR_2_8:
    SLL R3, R1, 9
    B EQ, z_SLL_1_9
    SW R3, R14, 1
z_SLL_1_9:
    SLL R3, R2, 9
    B EQ, z_SLL_2_9
    SW R3, R14, 1
z_SLL_2_9:
    SRA R3, R1, 9
    B EQ, z_SRA_1_9
    SW R3, R14, 1
z_SRA_1_9:
    SRA R3, R2, 9
    B EQ, z_SRA_2_9
    SW R3, R14, 1
z_SRA_2_9:
    ROR R3, R1, 9
    B EQ, z_ROR_1_9
    SW R3, R14, 1
z_ROR_1_9:
    ROR R3, R2, 9
    B EQ, z_ROR_2_9
    SW R3, R14, 1
z_ROR_2_9:
    SLL R3, R1, 10
    B EQ, z_SLL_1_10
    SW R3, R14, 2
z_SLL_1_10:
    SLL R3, R2, 10
    B EQ, z_SLL_2_10
    SW R3, R14, 2
z_SLL_2_10:
    SRA R3, R1, 10
    B EQ, z_SRA_1_10
    SW R3, R14, 2
z_SRA_1_10:
    SRA R3, R2, 10
    B EQ, z_SRA_2_10
    SW R3, R14, 2
z_SRA_2_10:
    ROR R3, R1, 10
    B EQ, z_ROR_1_10
    SW R3, R14, 2
z_ROR_1_10:
    ROR R3, R2, 10
    B EQ, z_ROR_2_10
    SW R3, R14, 2
z_ROR_2_10:
    SLL R3, R1, 11
    B EQ, z_SLL_1_11
    SW R3, R14, 3
z_SLL_1_11:
    SLL R3, R2, 11
    B EQ, z_SLL_2_11
    SW R3, R14, 3
z_SLL_2_11:
    SRA R3, R1, 11
    B EQ, z_SRA_1_11
    SW R3, R14, 3
z_SRA_1_11:
    SRA R3, R2, 11
    B EQ, z_SRA_2_11
    SW R3, R14, 3
z_SRA_2_11:
    ROR R3, R1, 11
    B EQ, z_ROR_1_11
    SW R3, R14, 3
z_ROR_1_11:
    ROR R3, R2, 11
    B EQ, z_ROR_2_11
    SW R3, R14, 3
z_ROR_2_11:
    SLL R3, R1, 12
    B EQ, z_SLL_1_12
    SW R3, R14, 4
z_SLL_1_12:
    SLL R3, R2, 12
    B EQ, z_SLL_2_12
    SW R3, R14, 4
z_SLL_2_12:
    SRA R3, R1, 12
    B EQ, z_SRA_1_12
    SW R3, R14, 4
z_SRA_1_12:
    SRA R3, R2, 12
    B EQ, z_SRA_2_12
    SW R3, R14, 4
z_SRA_2_12:
    ROR R3, R1, 12
    B EQ, z_ROR_1_12
    SW R3, R14, 4
z_ROR_1_12:
    ROR R3, R2, 12
    B EQ, z_ROR_2_12
    SW R3, R14, 4
z_ROR_2_12:
    SLL R3, R1, 13
    B EQ, z_SLL_1_13
    SW R3, R14, 5
z_SLL_1_13:
    SLL R3, R2, 13
    B EQ, z_SLL_2_13
    SW R3, R14, 5
z_SLL_2_13:
    SRA R3, R1, 13
    B EQ, z_SRA_1_13
    SW R3, R14, 5
z_SRA_1_13:
    SRA R3, R2, 13
    B EQ, z_SRA_2_13
    SW R3, R14, 5
z_SRA_2_13:
    ROR R3, R1, 13
    B EQ, z_ROR_1_13
    SW R3, R14, 5
z_ROR_1_13:
    ROR R3, R2, 13
    B EQ, z_ROR_2_13
    SW R3, R14, 5
z_ROR_2_13:
    SLL R3, R1, 14
    B EQ, z_SLL_1_14
    SW R3, R14, 6
z_SLL_1_14:
    SLL R3, R2, 14
    B EQ, z_SLL_2_14
    SW R3, R14, 6
z_SLL_2_14:
    SRA R3, R1, 14
    B EQ, z_SRA_1_14
    SW R3, R14, 6
z_SRA_1_14:
    SRA R3, R2, 14
    B EQ, z_SRA_2_14
    SW R3, R14, 6
z_SRA_2_14:
    ROR R3, R1, 14
    B EQ, z_ROR_1_14
    SW R3, R14, 6
z_ROR_1_14:
    ROR R3, R2, 14
    B EQ, z_ROR_2_14
    SW R3, R14, 6
z_ROR_2_14:
    SLL R3, R1, 15
    B EQ, z_SLL_1_15
    SW R3, R14, 7
z_SLL_1_15:
    SLL R3, R2, 15
    B EQ, z_SLL_2_15
    SW R3, R14, 7
z_SLL_2_15:
    SRA R3, R1, 15
    B EQ, z_SRA_1_15
    SW R3, R14, 7
z_SRA_1_15:
    SRA R3, R2, 15
    B EQ, z_SRA_2_15
    SW R3, R14, 7
z_SRA_2_15:
    ROR R3, R1, 15
    B EQ, z_ROR_1_15
    SW R3, R14, 7
z_ROR_1_15:
    ROR R3, R2, 15
    B EQ, z_ROR_2_15
    SW R3, R14, 7
z_ROR_2_15:
    HLT
