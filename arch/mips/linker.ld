ENTRY(_start)

MEMORY
{
    flash (rx) : ORIGIN = 0xBFC00000, LENGTH = 256K
    ram   (wx) : ORIGIN = 0x80000000, LENGTH = 32M
}

SECTIONS
{
    .text.stage0 : {
        _stage0_start = .;
        *(.text.entry)
        *(.text.stage0)
        _stage0_end = .;
    } > flash

    .stage1 0x80000000 : AT(LOADADDR(.text.stage0) + SIZEOF(.text.stage0)) {
        _stage1_start = .;
        *(.text.stage1)
        *(.text*)
        *(.rodata*)
        *(.data*)
        *(.bss*)
        . = ALIGN(4);
        _stage1_end = .;
    }

    _stage1_lma = LOADADDR(.stage1);

    /DISCARD/ : {
        *(.reginfo)
        *(.MIPS.abiflags)
        *(.note*)
        *(.comment)
        *(.eh_frame)
    }
}
