# Hacking on SageBoot — Adding a New Architecture

## Directory Template

To add a new architecture, create `arch/<name>/` with three files:

```
arch/<name>/
├── boot.S          # Stage 0 assembly entry
├── config.sage     # Hardware configuration constants
└── linker.ld       # Memory layout
```

Then add a block to `Makefile` following the existing pattern.

## `boot.S` Requirements

1. **Entry point**: Label `_start` (or arch-specific reset vector)
2. **Stack pointer**: Set `sp` to a valid writable address
3. **BSS**: Zero `.bss` section
4. **UART**: Initialize a debug serial port (minimal — 1-2 register writes)
5. **Jump**: Call `main()` (the transpiled Sage entry point)
6. **Loop**: If `main()` returns, spin indefinitely

## `config.sage` Requirements

Must define at minimum:

- `sage_print_char(c)` — writes `c` to the debug UART
- `sage_init_serial()` — one-time UART initialization
- `sage_serial_clock_init()` — serial timing setup
- `sage_get_tick_count()` → `int` — monotonic timer (milliseconds or cycles)
- `sage_get_address_mask()` → `int` — address mask for pointer tagging

## `linker.ld` Requirements

- Section `.text` starting at the boot image base
- Section `.data` after `.text`
- Section `.bss` after `.data` (NOLOAD)
- Symbol `_code_end` marking the end of loaded data
- Entry point matching `boot.S`

## `patch_bootloader.py`

The `jump_target` table in `patch_bootloader.py` must have an entry for the
new arch with the expected kernel entry address in the `SAGEOSBI` handoff.

## Makefile Block

Each arch needs:

```makefile
ifeq ($(ARCH),<name>)
  CROSS_COMPILE := <prefix>-
  ARCH_ASM_FLAGS := ...
  ARCH_C_FLAGS := ...
  ARCH_LD_FLAGS := ...
  ARCH_LINK_CMD := ...
  ARCH_OBJCOPY_FLAGS := ...
endif
```

## QEMU Testing

If the new architecture has QEMU support, add an entry in `test/test_all.sh`:

- `QEMU_MAP[<name>]` — the QEMU command line
- `EXPECTED_MAP[<name>]` — the banner string to grep for

## Checklist

- [ ] `arch/<name>/boot.S` assembles cleanly
- [ ] `arch/<name>/config.sage` provides required constants
- [ ] `arch/<name>/linker.ld` places sections correctly
- [ ] `patch_bootloader.py` has the new arch entry
- [ ] `Makefile` has the new `ifeq` block
- [ ] `test/test_all.sh` has the new arch (build and/or QEMU)
- [ ] `make ARCH=<name>` produces a bootable image
- [ ] (optional) QEMU boots the image and prints the banner
