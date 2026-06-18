# Hardware configuration for SageBoot (MIPS 74Kc - mipsel)
# Targets Netgear WN3000RP v1 WiFi Extender (Broadcom BCM5357)

let ARCH_NAME: String = "mips"
let PLATFORM_NAME: String = "Netgear WN3000RP v1 (MIPS)"

# Memory Map Configuration
let RAM_START: Int = 0x80000000       # kseg0 cached DDR RAM start (32 MiB)
let RAM_SIZE: Int = 32 * 1024 * 1024  # 32 MiB DDR Size
let KERNEL_LOAD_ADDR: Int = 0x80002000

# SiliconBackplane ChipCommon Base
let CHIPCOMMON_BASE: Int = 0xB8000000 # Uncached memory-mapped core registers
let CC_CHIPID: Int = CHIPCOMMON_BASE + 0x000
let CC_CLKDIV: Int = CHIPCOMMON_BASE + 0x04C

# UART Registers (8250-compatible)
let UART0_DATA: Int = CHIPCOMMON_BASE + 0x300
let UART0_IER: Int  = CHIPCOMMON_BASE + 0x304
let UART0_FCR: Int  = CHIPCOMMON_BASE + 0x308
let UART0_LCR: Int  = CHIPCOMMON_BASE + 0x30C
let UART0_MCR: Int  = CHIPCOMMON_BASE + 0x310
let UART0_LSR: Int  = CHIPCOMMON_BASE + 0x314

# Flash and NVRAM Offsets
let FLASH_PHYS: Int = 0x1C000000     # SPI Flash physical offset
let FLASH_BASE: Int = 0xBC000000     # Memory mapped SPI Flash uncached (CS0)
let NVRAM_BASE: Int = 0xBFFF0000     # Broadcom NVRAM region

# Wait for UART Transmitter Holding Register to empty
proc uart_wait_tx() -> void:
    while true:
        let lsr = mem_read(UART0_LSR, 0, "byte")
        if (lsr & 0x20) != 0:
            return

# Send a single character over UART
proc uart_putc(c: Int) -> void:
    uart_wait_tx()
    mem_write(UART0_DATA, 0, "byte", c)

# Print a null-terminated string over UART
proc uart_print(s: String) -> void:
    let i = 0
    let length = len(s)
    while i < length:
        let char_code = ord(s[i])
        uart_putc(char_code)
        i = i + 1

# Print a newline over UART
proc uart_println(s: String) -> void:
    uart_print(s)
    uart_putc(13) # Carriage Return (\r)
    uart_putc(10) # Line Feed (\n)

# Print a 32-bit integer in hexadecimal format
proc uart_print_hex(val: Int) -> void:
    uart_print("0x")
    let hex_chars = "0123456789ABCDEF"
    let shift = 28
    let printed = false
    while shift >= 0:
        let digit = (val >> shift) & 0xF
        if digit != 0 or printed or shift == 0:
            uart_putc(ord(hex_chars[digit]))
            printed = true
        shift = shift - 4
