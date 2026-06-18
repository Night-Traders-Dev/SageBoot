ENTRY(_start)

MEMORY
{
    ram (rwx) : ORIGIN = 0x00100000, LENGTH = 16M
}

SECTIONS
{
    .multiboot : {
        *(.multiboot)
    } > ram

    .text : {
        _code = .;
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
