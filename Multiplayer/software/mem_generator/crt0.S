.section .text.startup
.globl _start
_start:
    lui sp, 0x2
    addi sp, sp, -16
    jal ra, main

1:
    j 1b
