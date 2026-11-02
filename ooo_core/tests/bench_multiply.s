# Software multiply (shift-and-add) used for a 12-element dot product.
# The inner loop's branch depends on the multiplier bits, a pattern that
# history-based predictors can partly learn.
    LLB R12, 1
    LLB R11, 2
    LI  R1, vec_a
    LI  R2, vec_b
    LLB R3, 12
    LLB R10, 0              # dot product
elem:
    LW  R4, R1, 0           # multiplicand
    LW  R5, R2, 0           # multiplier (8-bit)
    LLB R6, 0               # product
    LLB R7, 8               # bit counter
mul:
    SLL R8, R5, 15          # isolate bit 0 into the sign position
    B EQ, skip              # bit is 0
    ADD R6, R6, R4
skip:
    SLL R4, R4, 1
    SRA R5, R5, 1
    SUB R7, R7, R12
    B NEQ, mul
    ADD R10, R10, R6
    ADD R1, R1, R11
    ADD R2, R2, R11
    SUB R3, R3, R12
    B NEQ, elem
    HLT

vec_a:
    .word 3, 17, 25, 101, 7, 12, 40, 9, 66, 2, 13, 31
vec_b:
    .word 5, 0x0B, 0x96, 0x03, 0xFF, 0x55, 0x10, 0x81, 0x07, 0xAA, 0x2C, 0x01
