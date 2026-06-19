# Makefile for SageBoot: Unified Bootloader for SageOS
# Supports: x64, rv64, arm64, mips (mipsel)

ARCH ?= rv64
SAGE_COMPILER = /root/Devel/sagelang/core/sage

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
    CLANG_FLAGS = -march=armv8-a+nosimd
    ARCH_DIR = arch/arm64
else ifeq ($(ARCH),mips)
    CROSS_COMPILE = mipsel-linux-gnu-
    CLANG_TARGET = mipsel-none-elf
    ASFLAGS = -EL -mips32r2 -mno-shared
    LDFLAGS = -EL -N
    CLANG_FLAGS = -mno-abicalls -fno-pic -G0
    ARCH_DIR = arch/mips
else
    $(error Unknown architecture: $(ARCH))
endif

AS      = $(CROSS_COMPILE)as
LD      = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
CC      = clang

# Freestanding C compiler flags
CFLAGS = -target $(CLANG_TARGET) $(CLANG_FLAGS) -ffreestanding -nostdlibinc -Icompat/include -I$(ARCH_DIR) -O2 -Wall -Wextra

# Source files
SAGE_SRCS = src/bootloader.sage src/menu.sage src/config.sage src/verify.sage src/elf.sage src/fs_fat.sage src/handoff.sage
C_COMPAT  = compat/compat.c

OBJS = boot.o bootloader.o compat.o

.PHONY: all clean disassemble test

all: sageboot.bin

# 1. Translate SageLang files to C using the C backend
bootloader.c: $(SAGE_SRCS) $(ARCH_DIR)/config.sage patch_bootloader.py
	cp $(ARCH_DIR)/config.sage src/hardware.sage
	$(SAGE_COMPILER) --emit-c src/bootloader.sage -o bootloader.c
	python3 patch_bootloader.py $(ARCH)

# 2. Compile objects
boot.o: $(ARCH_DIR)/boot.S
	$(AS) $(ASFLAGS) -o boot.o $(ARCH_DIR)/boot.S

compat.o: $(C_COMPAT)
	$(CC) $(CFLAGS) -c -o compat.o $(C_COMPAT)

bootloader.o: bootloader.c
	$(CC) $(CFLAGS) -c -o bootloader.o bootloader.c

# Linker library paths
LIBGCC := $(shell $(CROSS_COMPILE)gcc -print-libgcc-file-name 2>/dev/null)

# 3. Link sageboot
sageboot.elf: $(OBJS) $(ARCH_DIR)/linker.ld
	$(LD) $(LDFLAGS) -T $(ARCH_DIR)/linker.ld -o sageboot.elf $(OBJS) $(LIBGCC)

sageboot.bin: sageboot.elf
	$(OBJCOPY) -O binary sageboot.elf sageboot.bin

disassemble: sageboot.elf
	$(OBJDUMP) -d sageboot.elf > sageboot.disasm

clean:
	rm -f *.o bootloader.c src/hardware.sage sageboot.elf sageboot.bin *.disasm

