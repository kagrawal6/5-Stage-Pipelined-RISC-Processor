# Nested counted loops (inner trip count depends on the outer index) that
# accumulate into memory.
    LLB R12, 1
    LI  R14, 0x4400
    LLB R1, 8               # outer counter
    LLB R5, 0               # running total
outer:
    MOV R2, R1              # inner counter = outer index
inner:
    ADD R5, R5, R2
    SUB R2, R2, R12
    B NEQ, inner
    SW  R5, R14, 0
    ADD R14, R14, R12
    ADD R14, R14, R12
    SUB R1, R1, R12
    B GT, outer
    # read the 8 partial sums back
    LI  R14, 0x4400
    LW  R6, R14, 0
    LW  R7, R14, 3
    LW  R8, R14, 7
    HLT
