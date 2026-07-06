# x86_64 Startup Assembly for SageBoot
# Compliant with Multiboot1 specification, transitions to 64-bit Long Mode

.code32
.section .multiboot
.align 4
multiboot_header:
    .long 0x1BADB002           # magic
    .long 0x00010003           # flags: MODALIGN(1) | MEMINFO(2) | ADDRFIELDS(0x10000)
    .long -(0x1BADB002 + 0x00010003)  # checksum
    .long 0x100000             # header_addr
    .long 0x100000             # load_addr
    .long 0                    # load_end_addr (0 = entire file)
    .long _code_end            # bss_end_addr (for completeness)
    .long _start               # entry_addr
multiboot_header_end:

.section .rodata
.align 16
gdt64:
    .quad 0 # Null descriptor
gdt64_code:
    .quad 0x00209A0000000000 # Code descriptor: 64-bit, present, executable, read
gdt64_data:
    .quad 0x0000920000000000 # Data descriptor: present, writable
gdt64_end:

gdt64_pointer:
    .short gdt64_end - gdt64 - 1
    .long gdt64

.section .text
.global _start
.global main

_start:
    # Save Multiboot2 info pointer in %ebx and magic in %eax
    movl    %ebx, %edi          # First argument to main (pointer to multiboot struct)
    
    # 1. Set up initial 32-bit stack
    movl    $stack_top, %esp

    # 2. Enable A20 Line via fast port 0x92
    inb     $0x92, %al
    orb     $0x02, %al
    andb    $0xFE, %al
    outb    %al, $0x92

    # 3. Setup temporary page tables for identity mapping
    # Clear PML4 and PDP tables
    movl    $pml4_table, %edi
    xorl    %eax, %eax
    movl    $2048, %ecx
    rep     stosl

    # PML4[0] points to PDP table
    movl    $pdp_table, %eax
    orl     $0x03, %eax         # Present + Writable
    movl    %eax, (pml4_table)

    # PDP entries: identity map first 4GB of memory using 1GB pages
    movl    $0x00000083, (pdp_table)       # Page size + Present + Writable (0-1GB)
    movl    $0x40000083, (pdp_table + 8)   # (1-2GB)
    movl    $0x80000083, (pdp_table + 16)  # (2-3GB)
    movl    $0xC0000083, (pdp_table + 24)  # (3-4GB)

    # 4. Enable PAE (Physical Address Extension) in CR4
    movl    %cr4, %eax
    orl     $0x20, %eax
    movl    %eax, %cr4

    # 5. Load PML4 address into CR3
    movl    $pml4_table, %eax
    movl    %eax, %cr3

    # 6. Enable Long Mode in EFER MSR (0xC0000080)
    movl    $0xC0000080, %ecx
    rdmsr
    orl     $0x00000100, %eax   # LME bit 8
    wrmsr

    # 7. Enable Paging (PG) and Protected Mode (PE) in CR0
    movl    %cr0, %eax
    orl     $0x80000001, %eax
    movl    %eax, %cr0

    # 8. Load 64-bit GDT pointer
    lgdt    (gdt64_pointer)

    # 9. Far jump to 64-bit code segment
    ljmp    $0x08, $long_mode_entry

.code64
long_mode_entry:
    # 10. Load 64-bit data segments
    movw    $0x10, %ax
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %fs
    movw    %ax, %gs
    movw    %ax, %ss

    # 11. Enable FPU & SSE
    # Clear CR0.EM bit 2, set CR0.MP bit 1
    movq    %cr0, %rax
    andq    $0xFFFFFFFFFFFFFFFB, %rax
    orq     $0x02, %rax
    movq    %rax, %cr0

    # Set CR4.OSFXSR bit 9, set CR4.OSXMMEXCPT bit 10
    movq    %cr4, %rax
    orq     $0x600, %rax
    movq    %rax, %cr4

    # Initialize FPU
    fninit

    # 12. Load 64-bit stack pointer
    movq    $stack_top, %rsp

    # 13. Clear BSS
    movq    $__bss_start, %rdi
    movq    $__bss_end, %rcx
    subq    %rdi, %rcx
    shrq    $3, %rcx            # Clear quadwords
    xorq    %rax, %rax
    rep     stosq

    # 14. Call C main
    # Argument 1: Multiboot2 info struct pointer (passed in %rdi from System V ABI)
    movq    %rbx, %rdi          # Restore from saved register
    xorq    %rsi, %rsi          # argv = NULL
    call    main

halt_x64:
    cli
    hlt
    jmp     halt_x64

.section .bss
.align 4096
pml4_table:
    .skip 4096
pdp_table:
    .skip 4096

.align 16
stack_bottom:
    .skip 32768      # 32KB stack for SageBoot
stack_top:
