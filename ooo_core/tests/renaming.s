# Register renaming stress: WAW and WAR hazards on the same few registers,
# interleaved with a long independent chain. Without renaming, these would
# serialize; with renaming only the true (RAW) dependences matter.
    LLB R1, 1
    LLB R2, 2
    LLB R3, 3
    LI  R14, 0x4300
    LW  R4, R14, 0          # cold miss: everything below may run ahead
    ADD R5, R4, R1          # waits for the load
    ADD R1, R2, R3          # WAR on R1 vs. the line above
    ADD R1, R1, R1          # WAW
    ADD R2, R1, R3
    ADD R1, R2, R2          # WAW again
    SUB R3, R1, R2
    ADD R6, R5, R3          # mixes the slow and fast chains
    XOR R1, R6, R1
    ADD R2, R2, R2
    ADD R2, R2, R2
    ADD R2, R2, R2
    ADD R2, R2, R2
    SUB R7, R2, R1
    LLB R8, 0x10
    LHB R8, 0x20
    LLB R8, 0x30            # LLB reads the previous R8
    ADD R9, R8, R7
    SW  R9, R14, 1
    LW  R10, R14, 1
    ADD R11, R10, R5
    HLT
