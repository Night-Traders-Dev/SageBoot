# RISC-V 64-bit Startup Assembly for SageBoot
# Targets OpenSBI / QEMU Virt platform

.section .text.entry
.globl _start
.globl main

_start:
    # 1. Disable all machine interrupts (clear MIE in mstatus)
    csrci   mstatus, 0x8

    # 2. Enable FPU (set mstatus.FS bits 14:13 = 0b01, Initial state)
    # This prevents illegal instruction exceptions when running double-precision float operations.
    li      t0, (1 << 13)
    csrs    mstatus, t0

    # 3. Set up initial stack pointer (using stack_top defined in BSS)
    la      sp, stack_top

    # 4. Zero out the BSS section
    la      t0, __bss_start
    la      t1, __bss_end
bss_zero_loop:
    bge     t0, t1, bss_zero_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       bss_zero_loop
bss_zero_done:

    # 5. Jump to the main C function
    # Pass 0 for argc/argv in standard calling convention (a0, a1)
    mv      a0, zero
    mv      a1, zero
    call    main

    # 6. Halt if main returns
halt_rv64:
    wfi
    j       halt_rv64

.section .bss
.align 16
stack_bottom:
    .skip 32768      # 32KB stack for SageBoot
stack_top:
