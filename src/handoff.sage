## Boot Information Handoff Protocol for SageBoot
import hardware as hw

# Create the standard SAGEOSBI handoff struct in memory
proc create_handoff() -> Int:
    # Allocate a tracking structure using mem_alloc
    # SAGEOSBI structure layout:
    # Offset 0:  Magic (8 bytes) - 0x534147454F534249 ("SAGEOSBI")
    # Offset 8:  Memory Map Address (8 bytes)
    # Offset 16: Memory Map Size (8 bytes)
    # Offset 24: Framebuffer Base Address (8 bytes)
    # Offset 32: Framebuffer Width (4 bytes)
    # Offset 36: Framebuffer Height (4 bytes)
    # Offset 40: Framebuffer Pitch (4 bytes)
    # Offset 44: ACPI RSDP Address (8 bytes)
    # Offset 52: Command Line String Address (8 bytes)
    # Offset 60: Kernel Phys Address (8 bytes)
    # Offset 68: Kernel Virt Address (8 bytes)
    # Offset 76: Kernel Size (8 bytes)
    
    let info = mem_alloc(96)
    if info == nil:
        return 0
        
    # Write magic identifier: "SAGEOSBI" (0x534147454F534249)
    # To write a 64-bit value, we can use "double" mapping or write it in two 32-bit halves
    mem_write(info, 0, "int", 0x4F534249) # "OSBI"
    mem_write(info, 4, "int", 0x53414745) # "SAGE"
    
    # Initialize other fields to 0
    let offset = 8
    while offset < 96:
        mem_write(info, offset, "int", 0)
        offset = offset + 4
        
    return info

proc set_mmap(info, mmap_addr, mmap_size: Int) -> void:
    mem_write(info + 8, 0, "double", mmap_addr)
    mem_write(info + 16, 0, "double", mmap_size)

proc set_framebuffer(info, base, width, height, pitch: Int) -> void:
    mem_write(info + 24, 0, "double", base)
    mem_write(info + 32, 0, "int", width)
    mem_write(info + 36, 0, "int", height)
    mem_write(info + 40, 0, "int", pitch)

proc set_rsdp(info, rsdp_addr: Int) -> void:
    mem_write(info + 44, 0, "double", rsdp_addr)

proc set_cmdline(info, cmdline_ptr: Int) -> void:
    mem_write(info + 52, 0, "double", cmdline_ptr)

proc set_kernel(info, phys, virt, size: Int) -> void:
    mem_write(info + 60, 0, "double", phys)
    mem_write(info + 68, 0, "double", virt)
    mem_write(info + 76, 0, "double", size)
