let ARCH_NAME: String = "rp2350_arm"
let PLATFORM_NAME: String = "Raspberry Pi Pico 2 (RP2350 ARM)"

let RAM_START: Int = 0x20000000
let RAM_SIZE: Int = 532480
let KERNEL_LOAD_ADDR: Int = 0x20006000

let UART_BASE: Int = 0x40054000

proc uart_putc(c: Int) -> void:
    while (mem_read(UART_BASE + 0x18, 0, "int") & 0x20) != 0:
        let dummy = 0
    mem_write(UART_BASE + 0x00, 0, "int", c)

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
