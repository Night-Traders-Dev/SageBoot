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
    .long __bss_end            # bss_end_addr: Multiboot1 zeroes
                             # load_end_addr..bss_end_addr. This used to
                             # be _code_end, which is end-of-.text and
                             # sits *below* __bss_start, so the range was
                             # backwards and .bss was left uninitialised.
    .long _start               # entry_addr
multiboot_header_end:

.section .rodata
.align 16
gdt64:
    .quad 0 # Null descriptor
# These need the Long-mode bit (L) set in the flags nibble, and a non-zero
# limit. The previous values were 0x00209A0000000000 and 0x0000920000000000,
# whose comments claimed "64-bit" but which decode to L=0, D/B=1 and limit 0 --
# that is a 32-bit code segment and a zero-length data segment. The far jump to
# selector 0x08 therefore loaded a 32-bit CS, long mode was never entered, and
# the .code64 instructions that followed faulted on the first segment load
# (8E /r with mod=11 needs REX.B in 64-bit mode).
#
#   code: A=1010 -> L=1 G=0 D/B=0   access 9A = present ring0 code exec/read
#   data: C=1100 -> L=0 D/B=1 G=0   access 92 = present ring0 data write/read
gdt64_code:
    .quad 0x00AF9A000000FFFF
gdt64_data:
    .quad 0x00CF92000000FFFF
gdt64_end:

gdt64_pointer:
    .short gdt64_end - gdt64 - 1
    .long gdt64

.section .text
.global _start
.global main

_start:
    # Multiboot1 puts the info struct pointer in %ebx. It is saved in %edi
    # because %ebx is caller-saved and main() is a C function.

    # 1. Set up initial 32-bit stack
    movl    $stack_top, %esp

    # 2. Clear .bss *first*.
    #
    # This has to happen before the page tables are built, because pml4_table and
    # pdp_table live in .bss (below) and this same clear would otherwise wipe
    # them out from under CR3. It was previously step 13, after the tables were
    # populated at step 3, which left CR3 pointing at zeroes.
    movl    $__bss_start, %edi
    movl    $__bss_end, %ecx
    subl    %edi, %ecx
    shrl    $2, %ecx
    xorl    %eax, %eax
    rep     stosl

    # 3. Enable A20 Line via fast port 0x92
    inb     $0x92, %al
    orb     $0x02, %al
    andb    $0xFE, %al
    outb    %al, $0x92

    # 4. Setup page tables for identity mapping
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

    # 5. Enable PAE (Physical Address Extension) in CR4
    movl    %cr4, %eax
    orl     $0x20, %eax
    movl    %eax, %cr4

    # 6. Load PML4 address into CR3
    movl    $pml4_table, %eax
    movl    %eax, %cr3

    # 7. Enable Long Mode in EFER MSR (0xC0000080)
    movl    $0xC0000080, %ecx
    rdmsr
    orl     $0x00000100, %eax   # LME bit 8
    wrmsr

    # 8. Load the 64-bit GDT, *then* far jump to a 64-bit code segment, and only
    # then enable paging. Enabling CR0.PG before the far jump is what broke
    # this: the very next instruction fetch would run in long mode under the
    # bootloader's 32-bit CS, which is invalid, and the resulting fault found an
    # IDT still describing the real-mode IVT. This ordering is the canonical
    # one: page tables, PAE, CR3, LME, lgdt, ljmp, then CR0.PG.
    lgdt    (gdt64_pointer)
    ljmp    $0x08, $long_mode_entry

.code64
long_mode_entry:
    # 9. Now in 64-bit mode with a 64-bit CS. Load the data segments before
    # touching any memory, because %ds/%es still carry the bootloader's values.
    movw    $0x10, %ax
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %fs
    movw    %ax, %gs
    movw    %ax, %ss

    # 10. Enable Paging (PG). Protected mode (PE) is already set by the
    # Multiboot loader, but set it again so the sequence is correct regardless
    # of what handed control over.
    # 10. Enable paging now that CS is a 64-bit segment.
    # btsq rather than `orq $0x80000001`: an or with a 64-bit immediate that
    # large cannot be encoded in a single instruction (only a sign-extended
    # imm32 fits), and the assembler rejects it outright.
    movq    %cr0, %rax
    btsq    $31, %rax            # CR0.PG
    btsq    $0, %rax             # CR0.PE
    movq    %rax, %cr0

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

    # FPU init: CR0.EM cleared, CR0.MP set and CR4.OSFXSR/OSXMMEXCPT set above
    # are sufficient. An explicit fninit here raised #NM (Device Not Available)
    # on QEMU's pc machine, so it is omitted; the SSE state is initialised by
    # the C runtime instead.

    # 12. Load 64-bit stack pointer
    movq    $stack_top, %rsp

    # 13. Call C main
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
