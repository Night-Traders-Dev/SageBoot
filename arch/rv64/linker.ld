ENTRY(_start)

MEMORY
{
    ram (rwx) : ORIGIN = 0x80200000, LENGTH = 16M
}

SECTIONS
{
    .text : {
        _code = .;
        *(.text.entry)
        *(.text*)
        *(.rodata*)
        *(.data*)
        . = ALIGN(8);
        _code_end = .;
    } > ram

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end = .;
    } > ram

    /DISCARD/ : {
        *(.note*)
        *(.comment)
        *(.eh_frame)
    }
}
