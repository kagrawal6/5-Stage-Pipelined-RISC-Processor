# Copy 128 words (16 cache lines) and verify the copy by summing it.
# Streams through the D-cache, so misses and the store queue matter.
    LLB R12, 1
    LLB R11, 2
    LI  R1, 0x3000          # source
    LI  R2, 0x3800          # destination
    LLB R3, 128
    # initialise the source with a pattern
    MOV R4, R1
    LI  R5, 0x1357
    MOV R6, R3
init:
    SW  R5, R4, 0
    ADD R5, R5, R11
    ADD R4, R4, R11
    SUB R6, R6, R12
    B NEQ, init
    # copy, 4 words per iteration
    LLB R6, 32
copy:
    LW  R7, R1, 0
    LW  R8, R1, 1
    LW  R9, R1, 2
    LW  R10, R1, 3
    SW  R7, R2, 0
    SW  R8, R2, 1
    SW  R9, R2, 2
    SW  R10, R2, 3
    LLB R13, 8
    ADD R1, R1, R13
    ADD R2, R2, R13
    SUB R6, R6, R12
    B NEQ, copy
    # checksum of the destination
    LI  R2, 0x3800
    LLB R6, 128
    LLB R14, 0
check:
    LW  R7, R2, 0
    XOR R14, R14, R7
    ADD R2, R2, R11
    SUB R6, R6, R12
    B NEQ, check
    HLT
