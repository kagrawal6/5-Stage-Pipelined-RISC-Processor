# Build a 32-node linked list whose nodes are scattered over many cache
# lines, then walk it twice. The walk is a chain of dependent loads
# (pointer chasing), the classic case where out-of-order execution helps
# only with the independent work around the loads.
    LLB R12, 1
    LLB R11, 2
    LI  R1, 0x5000          # node address
    LI  R2, 0x0130          # stride between nodes (crosses lines and sets)
    LLB R3, 31
    LLB R4, 1               # node value
build:
    ADD R5, R1, R2          # next node
    SW  R5, R1, 0           # node.next
    SW  R4, R1, 1           # node.value
    MOV R1, R5
    ADD R4, R4, R4
    B NEQ, nz
    LLB R4, 3
nz:
    SUB R3, R3, R12
    B NEQ, build
    SW  R0, R1, 0           # last node: next = 0
    SW  R4, R1, 1
    LLB R13, 2              # walk twice
walk_again:
    LI  R1, 0x5000
    LLB R6, 0               # sum of values
    LLB R7, 0               # node count
walk:
    LW  R8, R1, 1
    LW  R1, R1, 0
    ADD R6, R6, R8
    ADD R7, R7, R12
    SUB R0, R1, R0
    B NEQ, walk
    SUB R13, R13, R12
    B NEQ, walk_again
    HLT
