// AArch64 Startup Assembly for SageBoot
// Targets bare-metal ARM64 (e.g. QEMU Virt, Raspberry Pi)

.section .text.entry
.globl _start
.globl main

_start:
    // 1. Disable all interrupts (mask DAIF)
    msr     daifset, #0xf

    // 2. Determine current exception level
    mrs     x0, CurrentEL
    and     x0, x0, #12         // CurrentEL[3:2]
    cmp     x0, #12             // EL3 = 12
    b.ne    .Lcheck_el2
    // At EL3: drop to EL2
    // Set SCR_EL3: NS=1, RW=1 (AArch64 at lower levels), ST=1, FIQ=0, IRQ=0
    mov     x0, #0x5            // NS | RW
    msr     scr_el3, x0
    // Set SPSR_EL3 to jump to EL2h with interrupts masked
    mov     x0, #0x3cd          // EL2h mode with D, A, I, F masked
    msr     spsr_el3, x0
    adr     x0, .Lel2_setup
    msr     elr_el3, x0
    eret

.Lcheck_el2:
    cmp     x0, #8              // EL2 = 8
    b.ne    .Lel1_setup

.Lel2_setup:
    // At EL2: set up and drop to EL1
    // Set HCR_EL2: RW=1 (EL1 is AArch64)
    mov     x0, #(1 << 31)
    msr     hcr_el2, x0

    // Set up Saved Program Status Register (SPSR_EL2) to mask interrupts and jump to EL1h
    mov     x0, #0x3c5          // EL1h mode with D, A, I, F masked
    msr     spsr_el2, x0

    // Load EL1 entry point address and execute ERET
    adr     x0, .Lel1_setup
    msr     elr_el2, x0
    eret

.Lel1_setup:
    // 3. Enable Floating Point and NEON (CPACR_EL1 bits [21:20] = 0b11)
    mov     x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb

    // 4. Set up the stack pointer
    ldr     x0, =stack_top
    mov     sp, x0

    // 5. Zero out the BSS section
    ldr     x1, =__bss_start
    ldr     x2, =__bss_end
bss_zero_loop:
    cmp     x1, x2
    b.ge    bss_zero_done
    stp     xzr, xzr, [x1], #16  // Store zero quadwords and post-increment
    b       bss_zero_loop
bss_zero_done:

    // 6. Call main
    // Pass 0 for argc/argv in standard AAPCS64 (x0, x1)
    mov     x0, #0
    mov     x1, #0
    bl      main

    // 7. Halt loop
halt_arm64:
    wfe
    b       halt_arm64

.section .bss
.align 16
stack_bottom:
    .skip 32768      // 32KB stack for SageBoot
stack_top:
