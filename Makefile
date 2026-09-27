# Makefile for SageBoot: Unified Bootloader for SageOS
# Supports: x64, rv64, arm64, mips, rp2040, rp2350_arm, rp2350_rv, esp32

ARCH ?= rv64
SAGE_COMPILER = /usr/local/bin/sage

# Target Architecture configurations
ifeq ($(ARCH),x64)
    CROSS_COMPILE = x86_64-linux-gnu-
    CLANG_TARGET = x86_64-none-elf
    ASFLAGS = --64
    LDFLAGS = -m elf_x86_64 -N
    CLANG_FLAGS = -mno-red-zone -mno-mmx
    ARCH_DIR = arch/x64
else ifeq ($(ARCH),rv64)
    CROSS_COMPILE = riscv64-linux-gnu-
    CLANG_TARGET = riscv64-none-elf
    ASFLAGS = -march=rv64g -mabi=lp64d
    LDFLAGS = -m elf64lriscv -N
    CLANG_FLAGS = -march=rv64g -mabi=lp64d -mcmodel=medany
    ARCH_DIR = arch/rv64
else ifeq ($(ARCH),arm64)
    CROSS_COMPILE = aarch64-linux-gnu-
    CLANG_TARGET = aarch64-none-elf
    ASFLAGS = 
    LDFLAGS = -m aarch64elf -N
    CLANG_FLAGS = 
    ARCH_DIR = arch/arm64
else ifeq ($(ARCH),mips)
    CROSS_COMPILE = mipsel-linux-gnu-
    CLANG_TARGET = mipsel-none-elf
    ASFLAGS = -EL -mips32r2 -mno-shared
    LDFLAGS = -EL -N
    CLANG_FLAGS = -mno-abicalls -fno-pic -G0
    ARCH_DIR = arch/mips
else ifeq ($(ARCH),rp2040)
    CROSS_COMPILE = arm-none-eabi-
    CLANG_TARGET = thumbv6m-none-eabi
    ASFLAGS =
    LDFLAGS =
    CLANG_FLAGS = -mcpu=cortex-m0plus -mthumb
    ARCH_DIR = arch/rp2040
    LIBGCC = $(shell arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -print-libgcc-file-name 2>/dev/null)
    CLANG_FLAGS += -fno-unwind-tables -fno-exceptions
else ifeq ($(ARCH),rp2350_arm)
    CROSS_COMPILE = arm-none-eabi-
    CLANG_TARGET = thumbv8m.main-none-eabi
    ASFLAGS =
    LDFLAGS =
    CLANG_FLAGS = -mcpu=cortex-m33 -mthumb -fno-unwind-tables -fno-exceptions
    ARCH_DIR = arch/rp2350_arm
    LIBGCC = $(shell arm-none-eabi-gcc -mcpu=cortex-m33 -mthumb -print-libgcc-file-name 2>/dev/null)
else ifeq ($(ARCH),rp2350_rv)
    CROSS_COMPILE = riscv64-linux-gnu-
    CLANG_TARGET = riscv32-none-elf
    ASFLAGS = -march=rv32imac -mabi=ilp32
    LDFLAGS = -m elf32lriscv
    CLANG_FLAGS = -march=rv32imac -mabi=ilp32
    ARCH_DIR = arch/rp2350_rv
    LIBGCC =
    LINK_CMD = $(CC)
    LINK_FLAGS = --ld-path=/usr/bin/riscv64-linux-gnu-ld -nostdlib $(CFLAGS) -T $(ARCH_DIR)/linker.ld
else ifeq ($(ARCH),esp32)
    # The Xtensa toolchain ships with the Arduino ESP32 core rather than on PATH.
    # Override XTENSA_PREFIX to point elsewhere; it must end in a directory whose
    # bin/ holds the xtensa-esp32-elf-* tools.
    XTENSA_PREFIX ?= $(HOME)/.arduino15/packages/esp32/tools/esp-x32/2601
    CROSS_COMPILE = $(XTENSA_PREFIX)/bin/xtensa-esp32-elf-
    ASFLAGS =
    ASM_VIA_CC = 1
    # No clang target: the Xtensa backend is not enabled in the system clang, so
    # the whole build has to go through the vendor GCC. See the CFLAGS note below.
    CLANG_TARGET = xtensa-esp32-elf
    CLANG_FLAGS = -mlongcalls -mtext-section-literals -Os
    ARCH_DIR = arch/esp32
    LIBGCC = $(shell $(CROSS_COMPILE)gcc -mlongcalls -print-libgcc-file-name 2>/dev/null)
    LINK_CMD = $(CROSS_COMPILE)gcc
    LINK_FLAGS = -mlongcalls -nostartfiles -Wl,--gc-sections -T $(ARCH_DIR)/linker.ld
    # --emit-c, not --emit-pico-c. The Pico emitter injects `#include
    # "pico/stdlib.h"` and friends, which only the RP2040 SageLang build
    # satisfies. SageBoot's esp32 target uses the generic emitter and the
    # compat/ shims, like every other architecture here.
    SAGE_EMIT_FLAG = --emit-c
else
    $(error Unknown architecture: $(ARCH))
endif

AS      = $(CROSS_COMPILE)as
LD      = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
ifneq ($(ARCH),esp32)
CC      = clang
endif

# Link command (can be overridden per-arch to use CC)
LINK_CMD ?= $(LD)
LINK_FLAGS ?= $(LDFLAGS) -T $(ARCH_DIR)/linker.ld

# Freestanding C compiler flags.
# These drive clang, which is what every other architecture uses. ESP32 is the
# exception: the Xtensa backend is not enabled in the system clang, so for that
# target CFLAGS/CC are replaced with vendor-GCC equivalents below.
SAGE_EMIT_FLAG ?= --emit-c
CFLAGS = -target $(CLANG_TARGET) $(CLANG_FLAGS) -ffreestanding -nostdlibinc -Icompat/include -I$(ARCH_DIR) -O2 -Wall -Wextra
ifneq ($(ARCH),esp32)
CC = clang
else
# Vendor GCC, and no -target: that is a clang spelling, and the Xtensa backend
# is not enabled in the system clang anyway. -nostdlibinc keeps GCC from
# pulling in the host's newlib headers.
CC = $(CROSS_COMPILE)gcc
# -nostdinc, not clang's -nostdlibinc: GCC has no -nostdlibinc. -nostdinc also
# hides GCC's own builtin headers, which the emitted C does need (stdarg.h,
# stddef.h), so GCC's internal include directory is added back explicitly. That
# keeps the host's /usr/include and its glibc/newlib headers out of a
# freestanding ESP32 build while leaving the compiler's own headers reachable.
GCC_INTERNAL_INC = $(shell $(CROSS_COMPILE)gcc -print-file-name=include 2>/dev/null)
CFLAGS = $(CLANG_FLAGS) -ffreestanding -nostdinc -I$(GCC_INTERNAL_INC) -Icompat/include -I$(ARCH_DIR) -O2 -Wall -Wextra
endif

# Source files
SAGE_SRCS = src/bootloader.sage src/menu.sage src/config.sage src/verify.sage src/elf.sage src/fs_fat.sage src/handoff.sage
C_COMPAT  = compat/compat.c

OBJS = boot.o bootloader.o compat.o

.PHONY: all clean disassemble test

all: sageboot.bin

# 1. Translate SageLang files to C using the C backend
bootloader.c: $(SAGE_SRCS) $(ARCH_DIR)/config.sage patch_bootloader.py
	cp $(ARCH_DIR)/config.sage src/hardware.sage
	$(SAGE_COMPILER) $(SAGE_EMIT_FLAG) src/bootloader.sage -o bootloader.c
	python3 patch_bootloader.py $(ARCH)

# 2. Compile objects
boot.o: $(ARCH_DIR)/boot.S
ifeq ($(ASM_VIA_CC),1)
	$(CC) $(filter-out -nostdlibinc,$(CFLAGS)) $(ASFLAGS) -c -o boot.o $(ARCH_DIR)/boot.S
else
	$(AS) $(ASFLAGS) -o boot.o $(ARCH_DIR)/boot.S
endif

compat.o: $(C_COMPAT)
	$(CC) $(CFLAGS) -c -o compat.o $(C_COMPAT)

# The Xtensa port-indexed assembly in compat.c is newlib's, not GCC's:
# the register names GCC's inline assembler accepts differ.
ifeq ($(ARCH),esp32)
CFLAGS += -Wno-unused-parameter -Wno-override-init
endif

bootloader.o: bootloader.c
	$(CC) $(CFLAGS) -c -o bootloader.o bootloader.c

# Linker library paths
LIBGCC ?= $(shell $(CROSS_COMPILE)gcc -print-libgcc-file-name 2>/dev/null)

# 3. Link sageboot
sageboot.elf: $(OBJS) $(ARCH_DIR)/linker.ld
	$(LINK_CMD) $(LINK_FLAGS) -o sageboot.elf $(OBJS) $(LIBGCC)

sageboot.bin: sageboot.elf
	$(OBJCOPY) -O binary sageboot.elf sageboot.bin

disassemble: sageboot.elf
	$(OBJDUMP) -d sageboot.elf > sageboot.disasm

clean:
	rm -f *.o bootloader.c src/hardware.sage sageboot.elf sageboot.bin *.disasm

