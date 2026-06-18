# Hardware configuration for SageBoot (RISC-V 64)

let ARCH_NAME: String = "rv64"
let PLATFORM_NAME: String = "QEMU Virt (RISC-V 64)"

# RAM starts at 0x80000000. QEMU Virt has 128MB RAM on base.
let RAM_START: Int = 0x80000000
let RAM_SIZE: Int = 0x08000000  # 128 MiB
let KERNEL_LOAD_ADDR: Int = 0x80200000

let UART_BASE: Int = 0x10000000

# Write a character to the 16550A MMIO UART
proc uart_putc(c: Int) -> void:
    # Line Status Register (LSR) offset is 5.
    # Wait until Transmit Holding Register Empty (THRE, bit 5) is set
    while (mem_read(UART_BASE + 5, 0, "byte") & 0x20) == 0:
        let dummy = 0
    # Transmitter Holding Register (THR) offset is 0
    mem_write(UART_BASE + 0, 0, "byte", c)

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
