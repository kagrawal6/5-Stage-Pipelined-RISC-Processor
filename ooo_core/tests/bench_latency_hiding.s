# Memory latency hiding: each iteration starts a load that misses in the
# D-cache, followed by a block of ALU work that does not depend on it.
# An in-order pipeline stalls for the whole miss; the out-of-order core keeps
# executing the independent instructions while the miss is outstanding
# (until the ROB fills up).
    LLB R12, 1
    LI  R1, 0x6000          # each iteration touches a new cache line
    LLB R13, 16
    LLB R10, 0
    LI  R2, 0x1234
    LI  R3, 0x0F0F
iter:
    LW  R4, R1, 0           # miss
    ADD R5, R2, R3          # independent work
    XOR R6, R2, R5
    SLL R7, R6, 3
    ADD R2, R7, R3
    SRA R8, R2, 2
    ROR R3, R8, 5
    PADDSB R9, R3, R2
    XOR R2, R9, R3
    ADD R11, R2, R3
    RED R3, R11, R2
    ADD R10, R10, R4        # finally consume the load
    LLB R14, 16
    ADD R1, R1, R14
    SUB R13, R13, R12
    B NEQ, iter
    HLT
