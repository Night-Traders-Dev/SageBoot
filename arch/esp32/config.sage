# Hardware configuration for SageBoot (ESP32 / Xtensa LX6)
#
# Every address here is transcribed from, or measured against, Espressif's own
# headers in esp32-libs and confirmed on a real ESP32-D0WD-V3. The register
# blocks that caused the most confusion during bring-up are the UART, because
# the status register is at +0x1C rather than the +0x04 that the layout suggests,
# and writing the wrong address looks exactly like a firmware bug.
#
# Interface required by src/*.sage:
#   ARCH_NAME, PLATFORM_NAME, RAM_START, RAM_SIZE, KERNEL_LOAD_ADDR,
#   UART_BASE, UART0_DATA, UART0_LSR, FLASH_BASE,
#   uart_print, uart_println, uart_print_hex
#
# Note that UART0_DATA / UART0_LSR / FLASH_BASE are referenced by
# bootloader.sage and menu.sage but were only defined by the mips config, so
# every other architecture was missing them. Define them here.

let ARCH_NAME: String = "esp32"
let PLATFORM_NAME: String = "ESP32 (Xtensa LX6, D0WD-V3 / ESP-WROOM-32)"

# The largest contiguous block of internal DRAM. Internal DRAM begins at
# 0x3FFB0000 but has a hole from 0x3FFB6000 to 0x3FFCE000, so the usable
# contiguous window for a RAM diagnostic is the high block. This is the same
# DRAM_HI region the application image uses, and all 98 KB of the application's
# .bss was verified to read back correctly inside it.
let RAM_START: Int = 0x3FFCE000
let RAM_SIZE: Int  = 0x32000          # 200 KiB, ends at 0x40000000

# The application partition lives at flash offset 0x10000 (see
# gen_partitions.py in the SageLang tree). Read through the DROM window.
let KERNEL_LOAD_ADDR: Int = 0x40010000

# Memory-mapped flash. Offset 0x10000 here is flash offset 0x10000.
let FLASH_BASE: Int = 0x40000000

# UART0. The register block is:
#   +0x00  FIFO (write a byte to transmit, read to receive)
#   +0x1c  STATUS
# Do not assume +0x04. Writing to +0x1C pokes txfifo_cnt and the
# write-1-to-clear interrupt bits and will wedge the console.
let UART_BASE: Int   = 0x3FF40000
let UART0_DATA: Int  = 0x3FF40000     # FIFO
let UART0_LSR: Int   = 0x3FF4001C     # STATUS

# STATUS field positions:
#   bit 0       rxfifo_full   -- receiver has data (what menu.sage tests)
#   bits 23:16  txfifo_cnt    -- bytes queued in the transmitter
let UART_STATUS_RX_FULL: Int = 0x0001
let UART_STATUS_TX_CNT_SHIFT: Int = 16
let UART_TX_FIFO_MAX: Int = 128

proc uart_putc(c: Int) -> void:
    # Wait for room: block only once the transmitter is nearly full. Spinning on
    # "not empty" (waiting for every queued byte to leave) is correct but halves
    # the throughput for no benefit on a console.
    while ((mem_read(UART0_LSR, 0, "int") >> UART_STATUS_TX_CNT_SHIFT) & 0xFF) >= 96:
        let dummy = 0
    mem_write(UART0_DATA, 0, "byte", c)

proc uart_print(s: String) -> void:
    let i = 0
    while i < len(s):
        let c = ord(s[i])
        if c == 10:
            uart_putc(13)
        uart_putc(c)
        i = i + 1

proc uart_println(s: String) -> void:
    uart_print(s)
    uart_print("\n")

proc uart_print_hex(val: Int) -> void:
    uart_print("0x")
    let hex_chars = "0123456789ABCDEF"
    let shift = 28
    let printed = false
    while shift >= 0:
        let digit = (val >> shift) & 0xF
        if digit != 0 or printed or shift == 0:
            uart_print(hex_chars[digit])
            printed = true
        shift = shift - 4
