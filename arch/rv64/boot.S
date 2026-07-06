# RISC-V 64-bit Startup Assembly for SageBoot
# Runs in S-mode (booted by OpenSBI on QEMU Virt platform)

.section .text.entry
.globl _start
.globl main

_start:
    # 1. Set up initial stack pointer (using stack_top defined in BSS)
    la      sp, stack_top

    # 2. Zero out the BSS section
    la      t0, __bss_start
    la      t1, __bss_end
bss_zero_loop:
    bge     t0, t1, bss_zero_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       bss_zero_loop
bss_zero_done:

    # 3. Jump to the main C function
    mv      a0, zero
    mv      a1, zero
    call    main

    # 4. Halt if main returns
halt_rv64:
    wfi
    j       halt_rv64

.section .bss
.align 16
stack_bottom:
    .skip 32768      # 32KB stack for SageBoot
stack_top:
