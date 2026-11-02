# Fibonacci numbers fib(0..22) stored to memory, computed twice: once with
# a register recurrence (serial dependence chain) and once from memory.
    LLB R12, 1
    LLB R11, 2
    LI  R10, 0x4800
    LLB R1, 0               # fib(i)
    LLB R2, 1               # fib(i+1)
    LLB R3, 23
    MOV R4, R10
loop:
    SW  R1, R4, 0
    ADD R5, R1, R2
    MOV R1, R2
    MOV R2, R5
    ADD R4, R4, R11
    SUB R3, R3, R12
    B NEQ, loop
    # recompute fib(i) = mem[i-1] + mem[i-2] from memory and compare
    LI  R4, 0x4804
    LLB R3, 21
    LLB R9, 0               # mismatch count
check:
    LW  R6, R4, -2
    LW  R7, R4, -1
    LW  R8, R4, 0
    ADD R6, R6, R7
    SUB R0, R6, R8
    B EQ, same
    ADD R9, R9, R12
same:
    ADD R4, R4, R11
    SUB R3, R3, R12
    B NEQ, check
    HLT
