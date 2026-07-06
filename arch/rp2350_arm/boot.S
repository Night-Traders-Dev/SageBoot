.syntax unified
.cpu cortex-m33
.fpu softvfp
.thumb

.section .text.entry
.globl _start
.type _start, %function
_start:
    .word _estack
    .word Reset_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler

.section .text
.globl Reset_Handler
.type Reset_Handler, %function
Reset_Handler:
    ldr r0, =_estack
    mov sp, r0

    ldr r0, =__data_start
    ldr r1, =__data_end
    ldr r2, =__data_load
    b .Ldata_copy_check
.Ldata_copy_loop:
    ldr r3, [r2], #4
    str r3, [r0], #4
.Ldata_copy_check:
    cmp r0, r1
    blo .Ldata_copy_loop

    ldr r0, =__bss_start
    ldr r1, =__bss_end
    mov r2, #0
    b .Lbss_zero_check
.Lbss_zero_loop:
    str r2, [r0], #4
.Lbss_zero_check:
    cmp r0, r1
    blo .Lbss_zero_loop

    ldr r0, =0xE000EDFC
    ldr r1, =0x01000000
    str r1, [r0]

    ldr r0, =0xE0001000
    ldr r1, [r0]
    mov r2, #1
    orr r1, r1, r2
    str r1, [r0]

    mov r0, #0
    mov r1, #0
    bl main

.Lhalt:
    wfi
    b .Lhalt

.globl Default_Handler
.type Default_Handler, %function
Default_Handler:
    b Default_Handler

.section .bss
.align 8
stack_bottom:
    .skip 16384
stack_top:
    .set _estack, stack_top
