# RISC-V 64-bit Startup Assembly for SageBoot
# Runs in S-mode (booted by OpenSBI on QEMU Virt platform)

.equ UART_BASE, 0x10000000

.section .text.entry
.globl _start
.globl main

_start:
    # Save hart_id (a0) and dtb_addr (a1) from OpenSBI S-mode entry
    mv   s0, a0
    mv   s1, a1

    # Disable MMU — ensure satp = 0 so we run with physical addresses
    csrw satp, zero
    sfence.vma

    # 1. Set up initial stack pointer (using stack_top defined in BSS)
    la      sp, stack_top

    # Initialize UART (16550A) for early debug
    li   t0, UART_BASE
    sb   zero, 1(t0)         # IER = 0 (disable interrupts)
    li   t1, 0x03
    sb   t1, 3(t0)           # LCR = 0x03 (8N1)
    li   t1, 0xC7
    sb   t1, 2(t0)           # FCR = 0xC7 (enable FIFO)

    # 2. Zero out the BSS section
    la      t0, __bss_start
    la      t1, __bss_end
bss_zero_loop:
    bge     t0, t1, bss_zero_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       bss_zero_loop
bss_zero_done:

    # Save OpenSBI args to global memory for handoff
    la      t0, saved_hart_id
    sd      s0, 0(t0)
    la      t0, saved_dtb_addr
    sd      s1, 0(t0)

    # 3. Jump to the main C function
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

.globl saved_hart_id
.globl saved_dtb_addr
saved_hart_id:
    .dword 0
saved_dtb_addr:
    .dword 0
