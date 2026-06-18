# Hardware configuration for SageBoot (x86_64)

let ARCH_NAME: String = "x64"
let PLATFORM_NAME: String = "PC Bare-Metal (x86_64)"

# RAM starts at 0x100000 (1MB) as loaded by Multiboot.
let RAM_START: Int = 0x00100000
let RAM_SIZE: Int = 128 * 1024 * 1024  # 128 MiB
let KERNEL_LOAD_ADDR: Int = 0x00200000

let UART_BASE: Int = 0x3F8 # COM1

# Write a character to the serial UART COM1
proc uart_putc(c: Int) -> void:
    # COM1 Line Status Register is 0x3FD
    # Wait until Transmit Holding Register is empty (bit 5)
    while (mem_read(UART_BASE + 5, 0, "byte") & 0x20) == 0:
        let dummy = 0
    # Write to Transmitter Holding Register (THR) at 0x3F8
    mem_write(UART_BASE, 0, "byte", c)

proc uart_print(s: String) -> void:
    let i = 0
    while i < len(s):
        let c = ord(s[i])
        if c == 10: # \n
            uart_putc(13) # \r
        uart_putc(c)
        i = i + 1

proc uart_println(s: String) -> void:
    uart_print(s)
    uart_print("\n")

proc uart_print_hex(val: Int) -> void:
    uart_print("0x")
    let hex_chars = "0123456789ABCDEF"
    let shift = 60
    let printed = false
    while shift >= 0:
        let digit = (val >> shift) & 0xF
        if digit != 0 or printed or shift == 0:
            uart_print(hex_chars[digit])
            printed = true
        shift = shift - 4
