# Bubble sort of 24 signed words (data-dependent branches), then a checksum.
    LLB R12, 1
    LLB R11, 2
    LI  R10, array
    LLB R1, 23              # passes = n - 1
pass:
    MOV R2, R10             # p = &a[0]
    MOV R3, R1              # comparisons this pass
cmp:
    LW  R4, R2, 0
    LW  R5, R2, 1
    SUB R0, R5, R4
    B GTE, noswap           # a[i+1] >= a[i]
    SW  R5, R2, 0
    SW  R4, R2, 1
noswap:
    ADD R2, R2, R11
    SUB R3, R3, R12
    B NEQ, cmp
    SUB R1, R1, R12
    B NEQ, pass
    # checksum: sum and XOR of the sorted array
    MOV R2, R10
    LLB R3, 24
    LLB R6, 0
    LLB R7, 0
sum:
    LW  R4, R2, 0
    ADD R6, R6, R4
    XOR R7, R7, R4
    ADD R2, R2, R11
    SUB R3, R3, R12
    B NEQ, sum
    HLT

.org 0x2000
array:
    .word 0x0123, 0xF00D, 0x7FFF, 0x0001, 0x8000, 0x4444, 0xFFFE, 0x0F0F
    .word 0x1234, 0x0000, 0xC0DE, 0x0042, 0x7000, 0x9999, 0x0101, 0xABCD
    .word 0x0007, 0xFFFF, 0x3333, 0x8001, 0x0FF0, 0x5555, 0x6000, 0x00AA
