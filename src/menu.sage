## Interactive text boot menu for SageBoot
import hardware as hw

proc show_menu(options: Array, timeout_sec: Int) -> Int:
    let selected = 0
    
    # Calculate target ticks for timeout
    let start_tick = clock()
    # Assume standard clock frequency (e.g., 24MHz timer clock for MIPS count register, or TSC for x86)
    # For a generic loop, we can estimate ticks. Let's do a countdown.
    let ticks_per_sec = 24000000
    if hw.ARCH_NAME == "x64":
        ticks_per_sec = 2000000000 # ~2GHz TSC
    elif hw.ARCH_NAME == "rv64":
        ticks_per_sec = 10000000   # QEMU rv64 timer frequency is 10MHz
    elif hw.ARCH_NAME == "arm64":
        ticks_per_sec = 62500000   # QEMU arm64 system counter frequency
    elif hw.ARCH_NAME == "rp2040":
        ticks_per_sec = 125000000  # RP2040 125MHz SysTick
    elif hw.ARCH_NAME == "rp2350_arm":
        ticks_per_sec = 150000000  # RP2350 150MHz DWT cycle counter
    elif hw.ARCH_NAME == "rp2350_rv":
        ticks_per_sec = 150000000  # RP2350 150MHz rdcycle

    let elapsed_sec = 0
    let last_printed_sec = -1

    hw.uart_println("==================================================")
    hw.uart_println("               SageBoot Boot Menu                 ")
    hw.uart_println("==================================================")

    # Main menu loop
    while true:
        let cur_tick = clock()
        let current_elapsed = ((cur_tick - start_tick) / ticks_per_sec) | 0
        
        if timeout_sec > 0 and current_elapsed >= timeout_sec:
            hw.uart_println("\nTimeout expired! Booting default choice...")
            return 0
            
        if current_elapsed != last_printed_sec:
            last_printed_sec = current_elapsed
            if timeout_sec > 0:
                hw.uart_print("\rBooting default in " + str(timeout_sec - current_elapsed) + " seconds... ")
                hw.uart_print("(Use arrow keys/WASD to select)  ")
        
        # Display menu options (only print once or when selection changes)
        # For simplicity in bare-metal, we can print the current state or just check keys.
        # Let's check for character input.
        # In compat.c, getchar() or read() is mapped. But we want a non-blocking check.
        # Wait, since compat.c's getchar/fgets is blocking, can we perform a check using memory reading of UART Line Status Register?
        # Yes! We know UART LSR address from hw module!
        let has_char = false
        let input_char = 0
        
        if hw.ARCH_NAME == "x64":
            # Read COM1 Line Status Register (0x3FD)
            # In C: inb(0x3FD) & 0x01
            # If we call a custom MMIO/IOPort check:
            if (mem_read(hw.UART_BASE + 5, 0, "byte") & 0x01) != 0:
                input_char = mem_read(hw.UART_BASE, 0, "byte")
                has_char = true
        elif hw.ARCH_NAME == "rv64":
            # QEMU Virt UART 16550A LSR (offset 5)
            if (mem_read(hw.UART_BASE + 5, 0, "byte") & 0x01) != 0:
                input_char = mem_read(hw.UART_BASE, 0, "byte")
                has_char = true
        elif hw.ARCH_NAME == "arm64":
            # PL011 FR Register (offset 0x18), RXFE (Receive FIFO Empty) is bit 4.
            # If RXFE == 0 (FIFO not empty), we can read DR (offset 0x00).
            if (mem_read(hw.UART_BASE + 0x18, 0, "int") & 0x10) == 0:
                input_char = mem_read(hw.UART_BASE, 0, "int") & 0xFF
                has_char = true
        elif hw.ARCH_NAME == "mips":
            # BCM5357 ChipCommon UART LSR (offset 0x14)
            if (mem_read(hw.UART0_LSR, 0, "byte") & 0x01) != 0:
                input_char = mem_read(hw.UART0_DATA, 0, "byte")
                has_char = true
        elif hw.ARCH_NAME == "rp2040" or hw.ARCH_NAME == "rp2350_arm" or hw.ARCH_NAME == "rp2350_rv":
            # PL011 UARTFR at offset 0x18, RXFE bit 4 (0 = data available)
            if (mem_read(hw.UART_BASE + 0x18, 0, "int") & 0x10) == 0:
                input_char = mem_read(hw.UART_BASE, 0, "int") & 0xFF
                has_char = true

        if has_char:
            # We got a character! Disable timeout countdown.
            timeout_sec = 0
            
            # Match standard keystrokes
            if input_char == 119 or input_char == 87: # 'w' or 'W'
                selected = selected - 1
            elif input_char == 115 or input_char == 83: # 's' or 'S'
                selected = selected + 1
            elif input_char == 13 or input_char == 10: # Enter / Carriage Return
                hw.uart_println("")
                return selected
                
            # Clamp selection to bounds
            if selected < 0:
                selected = len(options) - 1
            if selected >= len(options):
                selected = 0
                
            # Re-draw options list
            hw.uart_println("\n--- Current Selections ---")
            let op = 0
            while op < len(options):
                let marker = "   "
                if op == selected:
                    marker = " > "
                let title = options[op]["title"]
                hw.uart_println(marker + "[" + str(op) + "] " + title)
                op = op + 1
            hw.uart_println("-------------------------")

        # Sleep a little to prevent high CPU utilization
        let delay_count = 100000
        while delay_count > 0:
            delay_count = delay_count - 1
