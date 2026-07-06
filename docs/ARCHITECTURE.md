# SageBoot Architecture Reference

## Overview

SageBoot is a two-stage bootloader. Stage 0 is architecture-specific assembly
that initializes minimal hardware, sets up a C-compatible environment (stack,
BSS), and jumps to Stage 1. Stage 1 is a unified SageLang program that handles
configuration, menu, filesystem, ELF loading, and kernel handoff.

## Stage 0 — `arch/*/boot.S`

Each `arch/<name>/boot.S` performs:

1. Entry from reset vector / firmware (M-mode, EL3, or BIOS)
2. Minimal CPU initialization (stack pointer, exception levels, core frequency)
3. Debug UART initialization
4. BSS clearing (if applicable)
5. C runtime setup and jump to `main()` in the transpiled `bootloader.c`

## Stage 1 — `src/bootloader.sage`

Transpiled to C by the Sage compiler, then compiled with clang and linked
against `compat/compat.c`. All architecture-specific details are provided via
`arch/<name>/config.sage` which defines register addresses, UART MMIO bases,
and PSCI/SBI call interfaces.

## Memory Layout

Each architecture defines its own memory layout in `arch/<name>/linker.ld`:

| Arch | Text/RO | RW Data | Stack | Notes |
|------|---------|---------|-------|-------|
| x64  | 0x100000 | after text | BSS | Multiboot v1 convention |
| rv64 | 0x80000000 | after text | BSS | QEMU Virt DRAM base |
| arm64| 0x40080000 | after text | BSS | QEMU Virt DRAM base |
| mips | 0x80001000 (VMA) | after text | BSS | Flash at 0x9F000000 (LMA) |
| rp2040 | 0x10000100 | after text | BSS | Flash XIP |
| rp2350_arm | 0x10000100 | after text | BSS | Flash XIP |
| rp2350_rv | 0x10000100 | 0x20000000 | BSS | Flash XIP, SRAM |

## Boot Handoff — SAGEOSBI

The Stage 1 bootloader constructs a `SAGEOSBI` structure before jumping to the
kernel. The structure contains:

- Memory map (regions, type, size)
- Framebuffer address and dimensions (if available)
- Kernel entry point, ELF type, and parse status
- ACPI RSDP pointer (x64) or device tree pointer (ARM/RISC-V)
- Boot arguments string

## Cross-Platform Compat Layer (`compat/compat.c`)

Provides freestanding implementations of:

- `memset`, `memcpy`, `memmove`, `memcmp`
- `strlen`, `strcmp`, `strncmp`, `strcpy`, `strcat`
- `snprintf` / `vsnprintf` (minimal)
- `putchar` (wraps arch UART)
- Software IEEE 754 double-precision math (RISC-V 32-bit only, ~130 functions)
