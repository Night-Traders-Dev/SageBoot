import sys

if len(sys.argv) < 2:
    print("Usage: python3 patch_bootloader.py <arch>")
    sys.exit(1)

arch = sys.argv[1]

# Heap configurations corresponding to compat.c
heap_bounds = {
    "x64":        (0x02000000, 0x04000000),
    "rv64":       (0x81000000, 0x82000000),
    "arm64":      (0x41000000, 0x42000000),
    "mips":       (0x80800000, 0x82000000),
    "rp2040":     (0x20001000, 0x20040000),
    "rp2350_arm": (0x20001000, 0x20080000),
    "rp2350_rv":  (0x20001000, 0x20080000)
}

bounds = heap_bounds.get(arch, (0x01000000, 0x02000000))

with open('bootloader.c', 'r') as f:
    code = f.read()

# Define the jump assembly payload based on the target architecture
jump_code = ""
if arch == "mips":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    uintptr_t handoff = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("move $a0, %0\\n\\tmove $a1, $zero\\n\\tjr %1\\n\\tnop" :: "r"(handoff), "r"(entry));'
    )
elif arch == "rv64":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    uintptr_t handoff = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("mv a0, %0\\n\\tjr %1" :: "r"(handoff), "r"(entry));'
    )
elif arch == "arm64":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    uintptr_t handoff = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("mov x0, %0\\n\\tbr %1" :: "r"(handoff), "r"(entry));'
    )
elif arch == "x64":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    uintptr_t handoff = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("movq %0, %%rdi\\n\\tjmp *%1" :: "r"(handoff), "r"(entry));'
    )
elif arch == "rp2040" or arch == "rp2350_arm":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    uintptr_t handoff = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("mov r0, %1\\n\\tbx %0" :: "r"(entry), "r"(handoff));'
    )
elif arch == "rp2350_rv":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    uintptr_t handoff = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("mv a0, %0\\n\\tjr %1" :: "r"(handoff), "r"(entry));'
    )

# 1. Locate line with the jump hook and insert the jump code
lines = code.split('\n')
found_jump = False
for idx, line in enumerate(lines):
    if '[JUMPING TO EXECUTABLE REGION]' in line:
        lines[idx] = line + "\n" + jump_code
        found_jump = True
        break

if found_jump:
    code = '\n'.join(lines)
    print(f"Patched kernel jump for arch: {arch}")
else:
    print("Error: Could not locate jump hook in bootloader.c")
    sys.exit(1)

# 2. Patch sage_as_pointer to differentiate between SagePointer structs and raw physical addresses
target_pointer = (
    'static SagePointer* sage_as_pointer(SageValue v) {\n'
    '    if (v.type != SAGE_TAG_NUMBER) return NULL;\n'
    '    return (SagePointer*)(uintptr_t)v.as.number;\n'
    '}'
)

replacement_pointer = (
    f'static SagePointer* sage_as_pointer(SageValue v) {{\n'
    f'    if (v.type != SAGE_TAG_NUMBER) return NULL;\n'
    f'    uintptr_t addr = (uintptr_t)v.as.number;\n'
    f'    if (addr >= {bounds[0]} && addr < {bounds[1]}) {{\n'
    f'        return (SagePointer*)addr;\n'
    f'    }}\n'
    f'    static SagePointer raw_pointers[16];\n'
    f'    static int next_ptr = 0;\n'
    f'    SagePointer* sp = &raw_pointers[next_ptr];\n'
    f'    next_ptr = (next_ptr + 1) % 16;\n'
    f'    sp->ptr = (void*)addr;\n'
    f'    sp->size = 0xFFFFFFFF;\n'
    f'    sp->owned = 0;\n'
    f'    return sp;\n'
    f'}}'
)

if target_pointer in code:
    code = code.replace(target_pointer, replacement_pointer)
    print(f"Patched sage_as_pointer for arch: {arch}")
else:
    # Try alternate line-by-line patch
    lines = code.split('\n')
    found_pointer = False
    for idx, line in enumerate(lines):
        if 'static SagePointer* sage_as_pointer' in line:
            # Replace next 3 lines with replacement
            lines[idx] = replacement_pointer
            lines[idx+1] = ''
            lines[idx+2] = ''
            lines[idx+3] = ''
            found_pointer = True
            break
    if found_pointer:
        code = '\n'.join(lines)
        print(f"Patched sage_as_pointer via lines for arch: {arch}")
    else:
        print("Warning: Could not patch sage_as_pointer.")

# 3. For x86_64, patch sage_mem_read and sage_mem_write to support port-mapped I/O (0x3F8-0x3FD)
if arch == "x64":
    # Patch sage_mem_read byte access
    target_read_byte = 'if (strcmp(type, "byte") == 0) { return sage_number((double)*base); }'
    replacement_read_byte = (
        'if (strcmp(type, "byte") == 0) {\n'
        '        uintptr_t addr = (uintptr_t)sp->ptr + offset;\n'
        '        if (addr >= 0x3F8 && addr <= 0x3FD) {\n'
        '            uint8_t data;\n'
        '            __asm__ volatile("inb %1, %0" : "=a"(data) : "d"((uint16_t)addr));\n'
        '            return sage_number((double)data);\n'
        '        }\n'
        '        return sage_number((double)*base);\n'
        '    }'
    )
    
    # Patch sage_mem_write byte access
    target_write_byte = 'if (strcmp(type, "byte") == 0 && val.type == SAGE_TAG_NUMBER) { *base = (unsigned char)val.as.number; }'
    replacement_write_byte = (
        'if (strcmp(type, "byte") == 0 && val.type == SAGE_TAG_NUMBER) {\n'
        '        uintptr_t addr = (uintptr_t)sp->ptr + offset;\n'
        '        if (addr >= 0x3F8 && addr <= 0x3FD) {\n'
        '            __asm__ volatile("outb %0, %1" :: "a"((uint8_t)val.as.number), "d"((uint16_t)addr));\n'
        '        } else {\n'
        '            *base = (unsigned char)val.as.number;\n'
        '        }\n'
        '    }'
    )
    
    if target_read_byte in code:
        code = code.replace(target_read_byte, replacement_read_byte)
        print("Patched sage_mem_read for x86 port I/O")
    else:
        # Heuristic search
        code = code.replace('strcmp(type, "byte") == 0) { return sage_number((double)*base); }', 'strcmp(type, "byte") == 0) { uintptr_t addr = (uintptr_t)sp->ptr + offset; if (addr >= 0x3F8 && addr <= 0x3FD) { uint8_t data; __asm__ volatile("inb %1, %0" : "=a"(data) : "d"((uint16_t)addr)); return sage_number((double)data); } return sage_number((double)*base); }')

    if target_write_byte in code:
        code = code.replace(target_write_byte, replacement_write_byte)
        print("Patched sage_mem_write for x86 port I/O")
    else:
        # Heuristic search
        code = code.replace('strcmp(type, "byte") == 0 && val.type == SAGE_TAG_NUMBER) { *base = (unsigned char)val.as.number; }', 'strcmp(type, "byte") == 0 && val.type == SAGE_TAG_NUMBER) { uintptr_t addr = (uintptr_t)sp->ptr + offset; if (addr >= 0x3F8 && addr <= 0x3FD) { __asm__ volatile("outb %0, %1" :: "a"((uint8_t)val.as.number), "d"((uint16_t)addr)); } else { *base = (unsigned char)val.as.number; } }')

with open('bootloader.c', 'w') as f:
    f.write(code)
