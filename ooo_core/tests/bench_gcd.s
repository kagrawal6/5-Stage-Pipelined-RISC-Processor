# Subtraction-based GCD over a table of 10 pairs: hard-to-predict,
# data-dependent branches.
    LLB R12, 1
    LLB R11, 2
    LI  R1, pairs
    LLB R2, 10
    LI  R9, 0x4A00          # results
next:
    LW  R3, R1, 0
    LW  R4, R1, 1
gcd:
    SUB R0, R3, R4
    B EQ, done
    B LT, a_less
    SUB R3, R3, R4
    B UNCOND, gcd
a_less:
    SUB R4, R4, R3
    B UNCOND, gcd
done:
    SW  R3, R9, 0
    ADD R9, R9, R11
    ADD R1, R1, R11
    ADD R1, R1, R11
    SUB R2, R2, R12
    B NEQ, next
    HLT

pairs:
    .word 48, 18,   270, 192,   17, 5,   1000, 250,   81, 27
    .word 99, 121,  1024, 96,   35, 64,  360, 84,     123, 41
