.section .text.entry
.globl _start

_start:
    csrci mstatus, 0x8

    la sp, _stack_top

    la t0, __bss_start
    la t1, __bss_end
bss_zero_loop:
    bge t0, t1, bss_zero_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_zero_loop
bss_zero_done:

    li t0, 0
    csrw mcountinhibit, t0

    mv a0, zero
    mv a1, zero
    call main

halt:
    wfi
    j halt

.section .bss
.align 8
stack_bottom:
    .skip 16384
stack_top:
    .set _stack_top, stack_top
