# Building SageBoot

## Prerequisites

### Required Tools

- **SageLang compiler** (`sage` binary) — the Sage compiler C backend
- **LLVM/Clang** — version 14+ recommended, with cross-target support
- **GNU binutils** — arch-specific cross-linkers and assemblers
- **GNU make**
- **Python 3** — for `patch_bootloader.py`

### Cross-Toolchains

| Target | Prefix | Package (Debian/Ubuntu) |
|--------|--------|------------------------|
| x86_64 | `x86_64-linux-gnu-` | `binutils-x86-64-linux-gnu` |
| AArch64 | `aarch64-linux-gnu-` | `binutils-aarch64-linux-gnu` |
| RISC-V 64 | `riscv64-linux-gnu-` | `binutils-riscv64-linux-gnu` |
| RISC-V 32 | `riscv64-linux-gnu-` | (same as rv64) |
| ARM (rp2040/rp2350) | `arm-none-eabi-` | `binutils-arm-none-eabi` |
| MIPS (mipsel) | `mipsel-linux-gnu-` | `binutils-mipsel-linux-gnu` |

Install example (Debian/Ubuntu):

```bash
sudo apt install clang llvm make python3 \
  binutils-x86-64-linux-gnu \
  binutils-aarch64-linux-gnu \
  binutils-riscv64-linux-gnu \
  binutils-arm-none-eabi \
  binutils-mipsel-linux-gnu
```

### QEMU for Testing

```bash
sudo apt install qemu-system-x86 qemu-system-arm qemu-system-riscv
```

## Build Commands

```bash
# Build all 7 architectures (sequential)
make ARCH=rv64 clean && make ARCH=rv64
make ARCH=arm64 clean && make ARCH=arm64
make ARCH=x64 clean && make ARCH=x64
make ARCH=rp2040 clean && make ARCH=rp2040
make ARCH=rp2350_arm clean && make ARCH=rp2350_arm
make ARCH=rp2350_rv clean && make ARCH=rp2350_rv
make ARCH=mips clean && make ARCH=mips

# Run the full test suite
bash test/test_all.sh
```

## Output Files

Each build produces:

- `sageboot.elf` — ELF executable with debug symbols
- `sageboot.bin` — Raw binary (for flashing or QEMU `-kernel`)

## Known Build Issues

| Issue | Architecture | Workaround |
|-------|-------------|-----------|
| `mipsel-linux-gnu-as: not found` | mips | Install `binutils-mipsel-linux-gnu` |
| `arm-none-eabi-as: not found` | rp2040, rp2350_arm | Install `binutils-arm-none-eabi` |
| RISC-V 32 link: `cannot find -lgcc` | rp2350_rv | Use `-nostdlib` (handled by Makefile) |
