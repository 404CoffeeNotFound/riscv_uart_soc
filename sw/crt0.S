/* crt0.S — MiniRV bare-metal startup.  Clears BSS, sets sp, jumps to main. */
    .section .text.start,"ax",@progbits
    .globl _start
_start:
    /* Set up stack pointer at top of BRAM. */
    la   sp, _stack_top

    /* Zero .bss */
    la   t0, _sbss
    la   t1, _ebss
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    /* call main() */
    call main

    /* hang forever on return */
3:  j 3b
