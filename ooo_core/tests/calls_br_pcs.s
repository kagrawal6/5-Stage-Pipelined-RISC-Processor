# Subroutine calls with BR returns from several call sites (the same BR
# jumps to different targets, which the BTB keeps getting wrong), PCS, and a
# computed jump table.
    LLB R12, 1
    LLB R1, 0
    LI  R11, ret1
    B UNCOND, add5
ret1:
    LI  R11, ret2
    B UNCOND, add5
ret2:
    LI  R11, ret3
    B UNCOND, double
ret3:
    LI  R11, ret4
    B UNCOND, add5
ret4:
    PCS R2                  # R2 = address of the next instruction
    PCS R3
    SUB R4, R3, R2          # = 2
    # jump table: go to case[R5] for R5 = 0, 1, 2, 0, 1, 2
    LLB R5, 0
    LLB R7, 6               # iterations
    LLB R8, 3
loop:
    LI  R6, cases
    ADD R6, R6, R5
    ADD R6, R6, R5
    LW  R6, R6, 0           # R6 = cases[R5]
    BR  UNCOND, R6
case0:
    ADD R1, R1, R12
    B UNCOND, next
case1:
    ADD R1, R1, R1
    B UNCOND, next
case2:
    SUB R1, R1, R12
next:
    ADD R5, R5, R12
    SUB R0, R5, R8
    B NEQ, nowrap
    LLB R5, 0
nowrap:
    SUB R7, R7, R12
    B NEQ, loop
    # conditional BR: taken and not taken
    LI  R9, skip
    SUB R0, R1, R1
    BR  NEQ, R9             # not taken (Z = 1)
    LLB R10, 0x77
    BR  EQ, R9              # taken
    LLB R10, 0x88
skip:
    HLT

add5:
    LLB R9, 5
    ADD R1, R1, R9
    BR  UNCOND, R11
double:
    ADD R1, R1, R1
    BR  UNCOND, R11

cases:
    .word case0, case1, case2
