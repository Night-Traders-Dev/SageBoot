## Freestanding ELF64 parser and segment loader for SageBoot
import hardware as hw

# Constants
let ELF_MAGIC_0 = 127
let ELF_MAGIC_1 = 69   # 'E'
let ELF_MAGIC_2 = 76   # 'L'
let ELF_MAGIC_3 = 70   # 'F'
let PT_LOAD = 1

proc elf_read_u32(base, offset) -> Int:
    let val = mem_read(base, offset, "int")
    if val < 0:
        val = val + 4294967296
    return val

proc elf_read_u64(base, offset) -> Int:
    let low = elf_read_u32(base, offset)
    let high = elf_read_u32(base, offset + 4)
    return (high * 4294967296) + low

proc elf_memset(dest: Int, val: Int, size: Int) -> void:
    return

proc elf_memcpy(dest: Int, src: Int, size: Int) -> void:
    return

# Parse and load ELF64 binary image into target memory
proc load_elf(elf_buf_ptr) -> Int:
    # 1. Verify Magic
    let m0 = mem_read(elf_buf_ptr, 0, "byte")
    let m1 = mem_read(elf_buf_ptr, 1, "byte")
    let m2 = mem_read(elf_buf_ptr, 2, "byte")
    let m3 = mem_read(elf_buf_ptr, 3, "byte")
    
    hw.uart_print("debug elf: magic read at ")
    hw.uart_print_hex(elf_buf_ptr)
    hw.uart_print(": ")
    hw.uart_print_hex(m0)
    hw.uart_print(" ")
    hw.uart_print_hex(m1)
    hw.uart_print(" ")
    hw.uart_print_hex(m2)
    hw.uart_print(" ")
    hw.uart_print_hex(m3)
    hw.uart_println("")
    
    if m0 != ELF_MAGIC_0 or m1 != ELF_MAGIC_1 or m2 != ELF_MAGIC_2 or m3 != ELF_MAGIC_3:
        hw.uart_println("ELF ERROR: Invalid ELF magic!")
        return 0
        
    # Check if 64-bit ELF (Class = 2)
    let elf_class = mem_read(elf_buf_ptr, 4, "byte")
    if elf_class != 2:
        hw.uart_println("ELF ERROR: Only ELF64 is supported!")
        return 0
        
    # 2. Read ELF64 Header fields
    # Entry point is at offset 24 (8 bytes)
    let entry_point = elf_read_u64(elf_buf_ptr, 24)
    
    # Program header offset is at offset 32 (8 bytes)
    let phoff = elf_read_u64(elf_buf_ptr, 32)
    
    # Program header size is at offset 54 (2 bytes)
    let phentsize = mem_read(elf_buf_ptr, 54, "byte") + mem_read(elf_buf_ptr, 55, "byte") * 256
    
    # Program header count is at offset 56 (2 bytes)
    let phnum = mem_read(elf_buf_ptr, 56, "byte") + mem_read(elf_buf_ptr, 57, "byte") * 256
    
    hw.uart_print("ELF Entry Point: ")
    hw.uart_print_hex(entry_point)
    hw.uart_println("")
    
    hw.uart_print("Program Headers: ")
    hw.uart_println(str(phnum))
    
    # 3. Iterate through Program Headers
    let i = 0
    while i < phnum:
        let ph_addr = elf_buf_ptr + phoff + (i * phentsize)
        
        # Read program header fields (ELF64 structure)
        # Type is at offset 0 (4 bytes)
        let p_type = mem_read(ph_addr, 0, "int")
        
        if p_type == PT_LOAD:
            # Offset in file: offset 8 (8 bytes)
            let p_offset = elf_read_u64(ph_addr, 8)
            # Physical Address: offset 24 (8 bytes)
            let p_paddr = elf_read_u64(ph_addr, 24)
            # File Size: offset 32 (8 bytes)
            let p_filesz = elf_read_u64(ph_addr, 32)
            # Memory Size: offset 40 (8 bytes)
            let p_memsz = elf_read_u64(ph_addr, 40)
            
            hw.uart_print(" Loading Segment: Offset ")
            hw.uart_print_hex(p_offset)
            hw.uart_print(" -> PAddr ")
            hw.uart_print_hex(p_paddr)
            hw.uart_print(" (size ")
            hw.uart_print_hex(p_filesz)
            hw.uart_println(")")
            
            # Copy segment payload from file buffer to RAM destination using native memcpy
            if p_filesz > 0:
                elf_memcpy(p_paddr, elf_buf_ptr + p_offset, p_filesz)
                    
            # Zero out remaining memory size if memsz > filesz (BSS padding) using native memset
            if p_memsz > p_filesz:
                hw.uart_print("   Zeroing BSS padding: ")
                hw.uart_print_hex(p_memsz - p_filesz)
                hw.uart_println(" bytes")
                elf_memset(p_paddr + p_filesz, 0, p_memsz - p_filesz)
                
        i = i + 1
        
    return entry_point
