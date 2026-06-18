## Freestanding ELF64 parser and segment loader for SageBoot
import hardware as hw

# Constants
let ELF_MAGIC_0 = 127
let ELF_MAGIC_1 = 69   # 'E'
let ELF_MAGIC_2 = 76   # 'L'
let ELF_MAGIC_3 = 70   # 'F'
let PT_LOAD = 1

# Parse and load ELF64 binary image into target memory
proc load_elf(elf_buf_ptr) -> Int:
    # 1. Verify Magic
    let m0 = mem_read(elf_buf_ptr, 0, "byte")
    let m1 = mem_read(elf_buf_ptr, 1, "byte")
    let m2 = mem_read(elf_buf_ptr, 2, "byte")
    let m3 = mem_read(elf_buf_ptr, 3, "byte")
    
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
    let entry_point = mem_read(elf_buf_ptr, 24, "double") | 0 # Cast to Int
    
    # Program header offset is at offset 32 (8 bytes)
    let phoff = mem_read(elf_buf_ptr, 32, "double") | 0
    
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
            let p_offset = mem_read(ph_addr, 8, "double") | 0
            # Physical Address: offset 24 (8 bytes)
            let p_paddr = mem_read(ph_addr, 24, "double") | 0
            # File Size: offset 32 (8 bytes)
            let p_filesz = mem_read(ph_addr, 32, "double") | 0
            # Memory Size: offset 40 (8 bytes)
            let p_memsz = mem_read(ph_addr, 40, "double") | 0
            
            hw.uart_print(" Loading Segment: Offset ")
            hw.uart_print_hex(p_offset)
            hw.uart_print(" -> PAddr ")
            hw.uart_print_hex(p_paddr)
            hw.uart_print(" (size ")
            hw.uart_print_hex(p_filesz)
            hw.uart_println(")")
            
            # Copy segment payload from file buffer to RAM destination
            let b = 0
            while b < p_filesz:
                # Copy word-by-word if possible to speed up
                if p_filesz - b >= 4:
                    let word_data = mem_read(elf_buf_ptr + p_offset + b, 0, "int")
                    mem_write(p_paddr + b, 0, "int", word_data)
                    b = b + 4
                else:
                    let byte_data = mem_read(elf_buf_ptr + p_offset + b, 0, "byte")
                    mem_write(p_paddr + b, 0, "byte", byte_data)
                    b = b + 1
                    
            # Zero out remaining memory size if memsz > filesz (BSS padding)
            if p_memsz > p_filesz:
                hw.uart_print("   Zeroing BSS padding: ")
                hw.uart_print_hex(p_memsz - p_filesz)
                hw.uart_println(" bytes")
                
                let z = p_filesz
                while z < p_memsz:
                    if p_memsz - z >= 4:
                        mem_write(p_paddr + z, 0, "int", 0)
                        z = z + 4
                    else:
                        mem_write(p_paddr + z, 0, "byte", 0)
                        z = z + 1
                        
        i = i + 1
        
    return entry_point
