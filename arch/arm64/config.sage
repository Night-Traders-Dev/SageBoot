# Hardware configuration for SageBoot (AArch64)

let ARCH_NAME: String = "arm64"
let PLATFORM_NAME: String = "QEMU Virt (AArch64)"

# RAM starts at 0x40000000 on QEMU virt ARM64.
let RAM_START: Int = 0x40000000
let RAM_SIZE: Int = 128 * 1024 * 1024  # 128 MiB
let KERNEL_LOAD_ADDR: Int = 0x40200000

let UART_BASE: Int = 0x09000000 # PL011 UART

# Write a character to the PL011 MMIO UART
proc uart_putc(c: Int) -> void:
    # PL011 Flag Register (FR) offset is 0x18.
    # Wait until Transmit FIFO is not full (TXFF, bit 5) is clear
    while (mem_read(UART_BASE + 0x18, 0, "int") & 0x20) != 0:
        let dummy = 0
    # PL011 Data Register (DR) offset is 0x00
    mem_write(UART_BASE + 0x00, 0, "int", c)

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
