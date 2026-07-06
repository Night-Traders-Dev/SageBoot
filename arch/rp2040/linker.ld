ENTRY(_start)

MEMORY
{
    flash (rx)  : ORIGIN = 0x10000100, LENGTH = 16M
    sram  (rwx) : ORIGIN = 0x20000000, LENGTH = 264K
}

SECTIONS
{
    .text : {
        _code = .;
        *(.text.entry)
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
        _code_end = .;
    } > flash

    .data : AT(ADDR(.text) + SIZEOF(.text)) {
        __data_start = .;
        *(.data*)
        . = ALIGN(4);
        __data_end = .;
    } > sram

    __data_load = LOADADDR(.data);

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > sram

    .stack : {
        . = ALIGN(8);
        stack_bottom = .;
        . += 16384;
        stack_top = .;
    } > sram

    _estack = stack_top;

    /DISCARD/ : {
        *(.note*)
        *(.comment)
        *(.eh_frame)
        *(.ARM.exidx)
        *(.ARM.attributes)
    }
}
