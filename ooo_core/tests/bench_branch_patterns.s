# Branch patterns from the branch-prediction lecture, 64 iterations each:
#   A: alternating T/N          (bimodal fails, history-based predictors learn it)
#   B: taken 1 of every 3       (needs history)
#   C: correlated pair: C2 repeats C1's outcome
#   D: loop with a short inner trip count of 4
    LLB R12, 1
    LLB R13, 64             # iterations
    LLB R1, 0               # i
    LLB R3, 0               # i mod 3
    LLB R9, 3
    LLB R5, 0               # counters for the visible results
    LLB R6, 0
    LLB R7, 0
    LLB R8, 0
loop:
    # A: taken when i is odd
    SLL R2, R1, 15
    B EQ, a_skip
    ADD R5, R5, R12
a_skip:
    # B: taken when i mod 3 == 0
    SUB R0, R3, R0
    B NEQ, b_skip
    ADD R6, R6, R12
b_skip:
    # C1 / C2: same condition (bit 1 of i), the second is predictable
    # from the outcome of the first
    SLL R2, R1, 14
    SRA R2, R2, 15
    B EQ, c1_skip
    ADD R7, R7, R12
c1_skip:
    SUB R0, R2, R0
    B EQ, c2_skip
    ADD R7, R7, R7
c2_skip:
    # D: inner loop of 4
    LLB R4, 4
d_loop:
    ADD R8, R8, R12
    SUB R4, R4, R12
    B NEQ, d_loop
    # i++, i mod 3
    ADD R1, R1, R12
    ADD R3, R3, R12
    SUB R0, R3, R9
    B NEQ, no_wrap
    LLB R3, 0
no_wrap:
    SUB R13, R13, R12
    B NEQ, loop
    HLT
