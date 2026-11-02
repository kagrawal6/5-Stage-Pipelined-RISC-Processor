# Store-to-load forwarding and memory disambiguation:
#  * a load right after a store to the same word must see the store data
#  * with several older stores to one word, the youngest one wins
#  * loads to other words may bypass the pending stores
#  * a store whose data comes from a load (load -> store -> load chain)
    LI  R14, 0x4200
    LI  R1, 0x1111
    LI  R2, 0x2222
    LI  R3, 0x3333
    SW  R1, R14, 0
    LW  R4, R14, 0          # forwarded 0x1111
    SW  R2, R14, 0
    SW  R3, R14, 0
    LW  R5, R14, 0          # youngest older store: 0x3333
    SW  R1, R14, 1
    LW  R6, R14, 2          # different word: bypasses (reads 0)
    LW  R7, R14, 1          # 0x1111
    # chain through memory
    SW  R2, R14, 3
    LW  R8, R14, 3
    SW  R8, R14, 4
    LW  R9, R14, 4
    ADD R10, R9, R8
    SW  R10, R14, 5
    LW  R11, R14, 5
    # store address depends on a load (address not known early)
    LI  R12, 0x4210
    SW  R12, R14, 6
    LW  R13, R14, 6         # R13 = 0x4210
    SW  R3, R13, 0          # store to 0x4210
    LW  R1, R14, 7          # 0x420E: independent of the store above
    LW  R2, R13, 0          # same word: 0x3333
    # same word reached through two different base registers
    LI  R12, 0x4202
    SW  R1, R12, -1         # 0x4200
    LW  R3, R14, 0
    HLT
