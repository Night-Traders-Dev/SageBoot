/* linker.ld -- SageBoot for the ESP32 (Xtensa LX6).
 *
 * The image is flashed at 0x1000, loaded by the ESP32 ROM bootloader into
 * internal SRAM, and entered at the start of the loaded segment. So despite
 * being a bootloader this is not a flash-resident image: the ROM copies all of
 * it into IRAM0 before jumping, and the flash offset only decides where the
 * ROM reads it from.
 *
 * The regions below are the ones verified on real hardware. Two earlier
 * versions of the ESP32 memory map in this tree were wrong in ways that are
 * invisible at link time:
 *
 *   - 0x3FFB0000 was treated as a 320 KB "IRAM0". It is DRAM0, and only 24 KB
 *     of it is real.
 *   - 0x3FF80000 was treated as 512 KB of DRAM. It is not DRAM at all.
 *
 * The ROM's loader will happily write a .data image to an arbitrary address, so
 * a bogus placement links and flashes cleanly and only fails at run time, which
 * is exactly the kind of failure that gets misattributed to the handoff.
 *
 * Internal DRAM begins at 0x3FFB0000 and has a hole from 0x3FFB6000 to
 * 0x3FFCE000, so the only large contiguous window is the high block ending at
 * the top of internal SRAM, 0x40000000. SageBoot is small enough to live
 * entirely in it.
 */

ENTRY(_start)

MEMORY
{
  /* Code, rodata and the .data initialisers. The ROM jumps to the entry before
   * the flash cache is live, so text must be executable without the cache. */
  IRAM0 (rx)  : ORIGIN = 0x40080000, LENGTH = 0x20000   /* 128 KiB */
  /* .bss, heap, stack: the one contiguous DRAM block. */
  DRAM (rwx)  : ORIGIN = 0x3FFCE000, LENGTH = 0x32000   /* 200 KiB */
}

SECTIONS
{
  .iram0.text :
  {
    . = ALIGN(4);
    /* The entry must survive --gc-sections: it is what the ROM jumps to and
     * nothing references it. */
    KEEP(*(.iram0.text.entry))
    *(.literal .literal.*)
    *(.text .text.* .gnu.linkonce.t.*)
    . = ALIGN(4);
    _code_end = .;
  } > IRAM0

  .iram0.rodata :
  {
    . = ALIGN(4);
    *(.rodata .rodata.* .gnu.linkonce.r.*)
    . = ALIGN(8);
  } > IRAM0

  /* .data runs from DRAM and is loaded from IRAM0. */
  .data : ALIGN(4)
  {
    __data_start = ABSOLUTE(.);
    *(.data .data.* .gnu.linkonce.d.*)
    . = ALIGN(4);
    __data_end = ABSOLUTE(.);
  } > DRAM AT > IRAM0

  __data_load = LOADADDR(.data);

  .bss (NOLOAD) :
  {
    . = ALIGN(8);
    __bss_start = ABSOLUTE(.);
    *(.bss .bss.* .gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(8);
    __bss_end = ABSOLUTE(.);
  } > DRAM

  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    stack_bottom = .;
    . = . + 0x8000;                /* 32 KiB */
    . = ALIGN(16);
    stack_top = .;
  } > DRAM

  _estack = stack_top;

  /DISCARD/ :
  {
    *(.note*)
    *(.comment)
    *(.eh_frame)
    *(.xt.prop)
    *(.xt.lit*)
  }

  ASSERT(__bss_start >= ORIGIN(DRAM),
         "SageBoot .bss must start at the base of the DRAM window")
  ASSERT(stack_top <= ORIGIN(DRAM) + LENGTH(DRAM),
         "SageBoot stack does not fit in the DRAM window")
  ASSERT(_code_end <= ORIGIN(IRAM0) + LENGTH(IRAM0),
         "SageBoot does not fit in IRAM0")
}
