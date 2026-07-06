## Stage 1 Bootloader entry point for SageBoot
## Written in SageLang, coordinates the bootloader sequence.

gc_disable()

import hardware as hw
import menu
import config
import verify
import elf
import handoff
import fs_fat

# Default kernel options list
let kernel_options = [
    {"title": "SageOS Multi-Tasking Kernel (Normal)", "kernel": "sageos.elf", "cmdline": "init=/usr/bin/init console=ttyS0 loglevel=info"},
    {"title": "SageOS Single-User Recovery (Console Debug)", "kernel": "sageos_dbg.elf", "cmdline": "init=/bin/sh console=ttyS0 debug=true"},
    {"title": "SageBoot Diagnostics & Self-Test", "kernel": "test.elf", "cmdline": "test=all"}
]

proc stage1_entry() -> void:
    hw.uart_println("--------------------------------------------------")
    hw.uart_println("SageBoot Stage 1 Unified Bootloader Initialized!")
    hw.uart_print("Running on architecture: ")
    hw.uart_println(hw.ARCH_NAME)
    hw.uart_print("Target Platform: ")
    hw.uart_println(hw.PLATFORM_NAME)
    hw.uart_println("--------------------------------------------------")

    # 1. Run basic hardware diagnostics / RAM checks
    hw.uart_print("Checking RAM stability... ")
    let ram_ok = run_ram_diagnostics()
    if ram_ok:
        hw.uart_println("PASSED")
    else:
        hw.uart_println("FAILED! System unstable.")
        return

    # 2. Look for configuration files and parse boot settings
    # For bare-metal simulation, we check for a mock/flash boot.cfg.
    let boot_cfg_text = "# SageBoot configuration\ntimeout=5\ndefault=0\n"
    let settings = config.parse_config(boot_cfg_text)
    
    let default_choice = config.get_int(settings, "default", 0)
    let timeout_val = config.get_int(settings, "timeout", 5)

    # 3. Present the Interactive Boot Menu
    let choice = menu.show_menu(kernel_options, timeout_val)
    if choice < 0 or choice >= len(kernel_options):
        choice = default_choice
        
    let selected_op = kernel_options[choice]
    hw.uart_print("Selected boot profile: ")
    hw.uart_println(selected_op["title"])

    # 4. Locate and load the kernel binary
    # On MIPS Netgear router: relocates from SPI flash using TRX offset
    # On others: loads from EFI FAT/memory-mapped storage
    let kernel_ptr = 0
    let kernel_size = 0
    
    if hw.ARCH_NAME == "mips":
        # Broadcom SPI Flash maps TRX kernel header at offset 0x040000 -> 0xBC040000
        let trx_addr = hw.FLASH_BASE + 0x040000
        hw.uart_print("Reading TRX container at ")
        hw.uart_print_hex(trx_addr)
        hw.uart_println("...")
        
        let trx_magic = mem_read(trx_addr, 0, "int")
        if trx_magic != 0x30525448: # "HDR0"
            hw.uart_println("Error: Invalid TRX partition header!")
            return
            
        # Offset partitions
        let part1_offset = mem_read(trx_addr, 20, "int") # Kernel payload offset
        let part2_offset = mem_read(trx_addr, 24, "int") # RootFS payload offset
        kernel_ptr = trx_addr + part1_offset
        kernel_size = part2_offset - part1_offset
    elif hw.ARCH_NAME == "rp2040" or hw.ARCH_NAME == "rp2350_arm" or hw.ARCH_NAME == "rp2350_rv":
        # RP2040/RP2350: kernel stored in flash at a 1MB offset (0x10300000 XIP address)
        # The kernel is a raw binary or ELF file placed at a known offset in flash.
        let kernel_flash_addr = 0x10300000
        hw.uart_print("Reading kernel from XIP flash at ")
        hw.uart_print_hex(kernel_flash_addr)
        hw.uart_println("...")
        
        # Check the first 4 bytes for ELF magic to determine if it's a valid kernel
        let check_magic = mem_read(kernel_flash_addr, 0, "int")
        if check_magic == 0x464C457F: # "\x7fELF" little-endian
            hw.uart_println("Found ELF kernel in flash.")
            kernel_ptr = kernel_flash_addr
            kernel_size = 0x100000 # Assume 1MB max for size discovery
        else:
            hw.uart_println("No valid kernel found at flash offset. Using mock kernel.")
            kernel_ptr = hw.RAM_START + 0x01000000
            kernel_size = 0x100000
    else:
        # For x86_64, RISC-V, and ARM64:
        # We simulate a mapped FAT filesystem disk image loaded in upper memory mark (e.g. at 20MB)
        # or load a pre-compiled kernel payload directly mapped after bootloader.
        # Let's map a mock kernel buffer.
        kernel_ptr = hw.RAM_START + 0x01000000 # Map at 16MB offset
        # Set a mock size for verification
        kernel_size = 0x100000
        
        # If FAT image pointer is mapped at 32MB mark, try parsing BPB
        let fat_img = hw.RAM_START + 0x02000000
        let vol = fs_fat.parse_fat_bpb(fat_img)
        if vol != nil:
            hw.uart_println("Found FAT boot partition. Scanning for config and kernel...")
            let file_meta = fs_fat.find_fat_file(vol, selected_op["kernel"])
            if file_meta != nil:
                hw.uart_print("Found FAT kernel: ")
                hw.uart_print(selected_op["kernel"])
                hw.uart_print(" (")
                hw.uart_print(str(file_meta["size"]))
                hw.uart_println(" bytes)")
                kernel_ptr = fs_fat.load_fat_file(vol, file_meta)
                kernel_size = file_meta["size"]

    # 5. Cryptographic signature and checksum validation
    let verified = verify.verify_kernel(kernel_ptr, kernel_size)
    if not verified:
        hw.uart_println("FAILED secure boot signature checks. Halting.")
        return

    # 6. Parse and relocate ELF segments
    let entry_addr = elf.load_elf(kernel_ptr)
    if entry_addr == 0:
        hw.uart_println("Error: Failed to parse kernel ELF binary.")
        return

    # 7. Construct SAGEOSBI boot info handoff structure
    let handoff_addr = handoff.create_handoff()
    handoff.set_kernel(handoff_addr, kernel_ptr, entry_addr, kernel_size)
    
    # Store boot command line string
    let cmdline_text = selected_op["cmdline"]
    let cmdline_ptr = mem_alloc(len(cmdline_text) + 1)
    let c = 0
    while c < len(cmdline_text):
        mem_write(cmdline_ptr, c, "byte", ord(cmdline_text[c]))
        c = c + 1
    mem_write(cmdline_ptr, len(cmdline_text), "byte", 0) # Null terminate
    
    handoff.set_cmdline(handoff_addr, cmdline_ptr)
    handoff.set_mmap(handoff_addr, hw.RAM_START, hw.RAM_SIZE)

    # 8. Handoff control to SageOS Kernel
    hw.uart_println("SageBoot handoff ready. Booting SageOS...")
    
    # Trigger inline jump. This string is patched with the assembly jr/br/jmp instructions
    boot_kernel(entry_addr, handoff_addr)

# Perform simple memory write-read test at boundaries
proc run_ram_diagnostics() -> Bool:
    let base = hw.RAM_START
    let size = hw.RAM_SIZE
    
    # Check 1MB and 16MB marks
    let offset1 = base + 0x100000
    let offset2 = base + 0x1000000
    
    # Skip if offset exceeds RAM size
    if 0x1000000 >= size:
        offset2 = base + (size / 2) | 0
        
    mem_write(offset1, 0, "int", 0x55AA55AA)
    mem_write(offset2, 0, "int", 0xAA55AA55)
    
    let val1 = mem_read(offset1, 0, "int")
    let val2 = mem_read(offset2, 0, "int")
    
    if val1 != 0x55AA55AA or val2 != 0xAA55AA55:
        return false
    return true

# Mock boot jump, replaced by python patch script
proc boot_kernel(entry_addr: Int, handoff_addr: Int) -> void:
    hw.uart_println("[JUMPING TO EXECUTABLE REGION]")

# Execute entry point
stage1_entry()
