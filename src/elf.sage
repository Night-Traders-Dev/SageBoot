## Freestanding ELF64 parser and segment loader for SageBoot
import hardware as hw

# Constants
let ELF_MAGIC_0 = 127
let ELF_MAGIC_1 = 69   # 'E'
let ELF_MAGIC_2 = 76   # 'L'
let ELF_MAGIC_3 = 70   # 'F'
let PT_LOAD = 1

# Dispatch to ELF32 or ELF64 loader based on class
proc load_elf(elf_buf_ptr) -> Int:
    # 1. Verify Magic
    let m0 = mem_read(elf_buf_ptr, 0, "byte")
    let m1 = mem_read(elf_buf_ptr, 1, "byte")
    let m2 = mem_read(elf_buf_ptr, 2, "byte")
    let m3 = mem_read(elf_buf_ptr, 3, "byte")
    
    if m0 != ELF_MAGIC_0 or m1 != ELF_MAGIC_1 or m2 != ELF_MAGIC_2 or m3 != ELF_MAGIC_3:
        hw.uart_println("ELF ERROR: Invalid ELF magic!")
        return 0
        
    let elf_class = mem_read(elf_buf_ptr, 4, "byte")
    if elf_class == 1:
        return load_elf32(elf_buf_ptr)
    elif elf_class == 2:
        return load_elf64(elf_buf_ptr)
    else:
        hw.uart_println("ELF ERROR: Unknown ELF class!")
        return 0

# Parse and load ELF64 binary image into target memory
proc load_elf64(elf_buf_ptr) -> Int:
    # Read ELF64 header fields
    # Entry point at offset 24 (8 bytes)
    let entry_point = mem_read(elf_buf_ptr, 24, "double") | 0
    
    # Program header offset at offset 32 (8 bytes)
    let phoff = mem_read(elf_buf_ptr, 32, "double") | 0
    
    # Program header size at offset 54 (2 bytes)
    let phentsize = mem_read(elf_buf_ptr, 54, "byte") + mem_read(elf_buf_ptr, 55, "byte") * 256
    
    # Program header count at offset 56 (2 bytes)
    let phnum = mem_read(elf_buf_ptr, 56, "byte") + mem_read(elf_buf_ptr, 57, "byte") * 256
    
    hw.uart_print("ELF64 Entry Point: ")
    hw.uart_print_hex(entry_point)
    hw.uart_println("")
    
    hw.uart_print("Program Headers: ")
    hw.uart_println(str(phnum))
    
    let i = 0
    while i < phnum:
        let ph_addr = elf_buf_ptr + phoff + (i * phentsize)
        
        let p_type = mem_read(ph_addr, 0, "int")
        
        if p_type == PT_LOAD:
            # ELF64 phdr: offset 8 (8 bytes)
            let p_offset = mem_read(ph_addr, 8, "double") | 0
            # p_paddr at offset 24 (8 bytes)
            let p_paddr = mem_read(ph_addr, 24, "double") | 0
            # p_filesz at offset 32 (8 bytes)
            let p_filesz = mem_read(ph_addr, 32, "double") | 0
            # p_memsz at offset 40 (8 bytes)
            let p_memsz = mem_read(ph_addr, 40, "double") | 0
            
            hw.uart_print(" Loading Segment: Offset ")
            hw.uart_print_hex(p_offset)
            hw.uart_print(" -> PAddr ")
            hw.uart_print_hex(p_paddr)
            hw.uart_print(" (size ")
            hw.uart_print_hex(p_filesz)
            hw.uart_println(")")
            
            let b = 0
            while b < p_filesz:
                if p_filesz - b >= 4:
                    let word_data = mem_read(elf_buf_ptr + p_offset + b, 0, "int")
                    mem_write(p_paddr + b, 0, "int", word_data)
                    b = b + 4
                else:
                    let byte_data = mem_read(elf_buf_ptr + p_offset + b, 0, "byte")
                    mem_write(p_paddr + b, 0, "byte", byte_data)
                    b = b + 1
                    
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

# Parse and load ELF32 binary image into target memory
proc load_elf32(elf_buf_ptr) -> Int:
    # ELF32 header is 52 bytes
    # Entry point at offset 24 (4 bytes)
    let entry_point = mem_read(elf_buf_ptr, 24, "int")
    
    # Program header offset at offset 28 (4 bytes)
    let phoff = mem_read(elf_buf_ptr, 28, "int")
    
    # Program header size at offset 42 (2 bytes)
    let phentsize = mem_read(elf_buf_ptr, 42, "byte") + mem_read(elf_buf_ptr, 43, "byte") * 256
    
    # Program header count at offset 44 (2 bytes)
    let phnum = mem_read(elf_buf_ptr, 44, "byte") + mem_read(elf_buf_ptr, 45, "byte") * 256
    
    hw.uart_print("ELF32 Entry Point: ")
    hw.uart_print_hex(entry_point)
    hw.uart_println("")
    
    hw.uart_print("Program Headers: ")
    hw.uart_println(str(phnum))
    
    let i = 0
    while i < phnum:
        let ph_addr = elf_buf_ptr + phoff + (i * phentsize)
        
        # ELF32 phdr is 32 bytes
        # p_type at offset 0 (4 bytes)
        let p_type = mem_read(ph_addr, 0, "int")
        
        if p_type == PT_LOAD:
            # p_offset at offset 4 (4 bytes)
            let p_offset = mem_read(ph_addr, 4, "int")
            # p_paddr at offset 12 (4 bytes)
            let p_paddr = mem_read(ph_addr, 12, "int")
            # p_filesz at offset 16 (4 bytes)
            let p_filesz = mem_read(ph_addr, 16, "int")
            # p_memsz at offset 20 (4 bytes)
            let p_memsz = mem_read(ph_addr, 20, "int")
            
            hw.uart_print(" Loading Segment: Offset ")
            hw.uart_print_hex(p_offset)
            hw.uart_print(" -> PAddr ")
            hw.uart_print_hex(p_paddr)
            hw.uart_print(" (size ")
            hw.uart_print_hex(p_filesz)
            hw.uart_println(")")
            
            let b = 0
            while b < p_filesz:
                if p_filesz - b >= 4:
                    let word_data = mem_read(elf_buf_ptr + p_offset + b, 0, "int")
                    mem_write(p_paddr + b, 0, "int", word_data)
                    b = b + 4
                else:
                    let byte_data = mem_read(elf_buf_ptr + p_offset + b, 0, "byte")
                    mem_write(p_paddr + b, 0, "byte", byte_data)
                    b = b + 1
                    
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
