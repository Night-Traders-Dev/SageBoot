import sys

if len(sys.argv) < 2:
    print("Usage: python3 patch_bootloader.py <arch>")
    sys.exit(1)

arch = sys.argv[1]

# Heap configurations corresponding to compat.c
heap_bounds = {
    "x64":   (0x04000000, 0x06000000),
    "rv64":  (0x84000000, 0x86000000),
    "arm64": (0x44000000, 0x46000000),
    "mips":  (0x80800000, 0x82000000)
}

bounds = heap_bounds.get(arch, (0x01000000, 0x02000000))

with open('bootloader.c', 'r') as f:
    code = f.read()

# Define the jump assembly payload based on the target architecture
jump_code = ""
if arch == "mips":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    register uintptr_t handoff_reg __asm__("a0") = (uintptr_t)arg1.as.number;\n'
        '    register uintptr_t zero_reg __asm__("a1") = 0;\n'
        '    __asm__ volatile("jr %0\\n\\tnop" :: "r"(entry), "r"(handoff_reg), "r"(zero_reg));'
    )
elif arch == "rv64":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    register uintptr_t handoff_reg __asm__("a0") = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("fence.i\\n\\tjr %0" :: "r"(entry), "r"(handoff_reg));'
    )
elif arch == "arm64":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    register uintptr_t handoff_reg __asm__("x0") = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("dsb sy\\n\\tisb\\n\\tbr %0" :: "r"(entry), "r"(handoff_reg));'
    )
elif arch == "x64":
    jump_code = (
        '    uintptr_t entry = (uintptr_t)arg0.as.number;\n'
        '    register uintptr_t handoff_reg __asm__("rdi") = (uintptr_t)arg1.as.number;\n'
        '    __asm__ volatile("jmp *%0" :: "r"(entry), "r"(handoff_reg));'
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



# 2. Patch SagePointer struct definition and sage_mem_alloc to use magic validation
target_struct = (
    'typedef struct {\n'
    '    void* ptr;\n'
    '    size_t size;\n'
    '    int owned;\n'
    '} SagePointer;'
)
replacement_struct = (
    'typedef struct {\n'
    '    uint32_t magic;\n'
    '    void* ptr;\n'
    '    size_t size;\n'
    '    int owned;\n'
    '} SagePointer;'
)
if target_struct in code:
    code = code.replace(target_struct, replacement_struct)
    print("Patched SagePointer struct definition with magic field")
else:
    print("Warning: Could not patch SagePointer struct definition")

target_alloc = (
    '    sp->size = size;\n'
    '    sp->owned = 1;\n'
    '    SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = (double)(uintptr_t)sp;'
)
replacement_alloc = (
    '    sp->magic = 0x50545236;\n'
    '    sp->size = size;\n'
    '    sp->owned = 1;\n'
    '    SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = (double)(uintptr_t)sp->ptr;'
)
if target_alloc in code:
    code = code.replace(target_alloc, replacement_alloc)
    print("Patched sage_mem_alloc to return sp->ptr")
else:
    print("Warning: Could not patch sage_mem_alloc to return sp->ptr")

# 3. Patch sage_as_pointer to differentiate between SagePointer structs and raw physical addresses
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
    f'        SagePointer* sp = (SagePointer*)addr;\n'
    f'        if (sp->magic == 0x50545236) {{\n'
    f'            return sp;\n'
    f'        }}\n'
    f'    }}\n'
    f'    static SagePointer raw_pointers[16];\n'
    f'    static int next_ptr = 0;\n'
    f'    SagePointer* sp = &raw_pointers[next_ptr];\n'
    f'    next_ptr = (next_ptr + 1) % 16;\n'
    f'    sp->magic = 0;\n'
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

# 4. Patch sage_clock_fn to return raw ticks instead of dividing by CLOCKS_PER_SEC
target_clock = (
    'static SageValue sage_clock_fn(void) {\n'
    '    return sage_number((double)clock() / CLOCKS_PER_SEC);\n'
    '}'
)
replacement_clock = (
    'static SageValue sage_clock_fn(void) {\n'
    '    return sage_number((double)clock());\n'
    '}'
)
if target_clock in code:
    code = code.replace(target_clock, replacement_clock)
    print("Patched sage_clock_fn to return raw ticks")
else:
    # Heuristic replacement
    code = code.replace('return sage_number((double)clock() / CLOCKS_PER_SEC);', 'return sage_number((double)clock());')
    print("Patched sage_clock_fn via heuristic")

# 5. Patch elf_memset and elf_memcpy to use standard C library functions
import re

pattern_memset = r"(static SageValue sage_fn_elf_memset_\d+\(SageValue arg0, SageValue arg1, SageValue arg2\) \{)[\s\S]*?\n\}"
replacement_memset = r"""\1
    void* dest = (void*)(uintptr_t)arg0.as.number;
    int val = (int)arg1.as.number;
    size_t size = (size_t)arg2.as.number;
    memset(dest, val, size);
    return sage_nil();
}"""

pattern_memcpy = r"(static SageValue sage_fn_elf_memcpy_\d+\(SageValue arg0, SageValue arg1, SageValue arg2\) \{)[\s\S]*?\n\}"
replacement_memcpy = r"""\1
    void* dest = (void*)(uintptr_t)arg0.as.number;
    const void* src = (const void*)(uintptr_t)arg1.as.number;
    size_t size = (size_t)arg2.as.number;
    memcpy(dest, src, size);
    return sage_nil();
}"""

if re.search(pattern_memset, code):
    code = re.sub(pattern_memset, replacement_memset, code)
    print("Patched elf_memset to call native memset")
else:
    print("Warning: Could not find elf_memset definition to patch")

if re.search(pattern_memcpy, code):
    code = re.sub(pattern_memcpy, replacement_memcpy, code)
    print("Patched elf_memcpy to call native memcpy")
else:
    print("Warning: Could not find elf_memcpy definition to patch")

# 6. Patch sage_mem_read and sage_mem_write to treat "double" as 64-bit integer (uint64_t) instead of floating-point double
target_read_double = 'if (strcmp(type, "double") == 0) { double v; memcpy(&v, base, sizeof(double)); return sage_number(v); }'
replacement_read_double = 'if (strcmp(type, "double") == 0) { uint64_t v; memcpy(&v, base, sizeof(uint64_t)); return sage_number((double)v); }'

target_write_double = 'else if (strcmp(type, "double") == 0 && val.type == SAGE_TAG_NUMBER) { double v = val.as.number; memcpy(base, &v, sizeof(double)); }'
replacement_write_double = 'else if (strcmp(type, "double") == 0 && val.type == SAGE_TAG_NUMBER) { uint64_t v = (uint64_t)val.as.number; memcpy(base, &v, sizeof(uint64_t)); }'

if target_read_double in code:
    code = code.replace(target_read_double, replacement_read_double)
    print("Patched sage_mem_read to treat 'double' as uint64_t")
else:
    # Heuristic replace
    code = code.replace('strcmp(type, "double") == 0) { double v; memcpy(&v, base, sizeof(double)); return sage_number(v); }', 'strcmp(type, "double") == 0) { uint64_t v; memcpy(&v, base, sizeof(uint64_t)); return sage_number((double)v); }')
    print("Patched sage_mem_read 'double' via heuristic")

if target_write_double in code:
    code = code.replace(target_write_double, replacement_write_double)
    print("Patched sage_mem_write to treat 'double' as uint64_t")
else:
    # Heuristic replace
    code = code.replace('strcmp(type, "double") == 0 && val.type == SAGE_TAG_NUMBER) { double v = val.as.number; memcpy(base, &v, sizeof(double)); }', 'strcmp(type, "double") == 0 && val.type == SAGE_TAG_NUMBER) { uint64_t v = (uint64_t)val.as.number; memcpy(base, &v, sizeof(uint64_t)); }')
    print("Patched sage_mem_write 'double' via heuristic")

if arch == "arm64":
    # Force 16-byte alignment of SageValue and SageSlot to prevent unaligned 128-bit SIMD faults
    code = code.replace("struct SageValue {", "struct __attribute__((aligned(16))) SageValue {")
    code = code.replace(
        "typedef struct {\n    int defined;\n    SageValue value;\n} SageSlot;",
        "typedef struct {\n    int defined;\n    SageValue value;\n} __attribute__((aligned(16))) SageSlot;"
    )
    print("Patched SageValue and SageSlot alignment for arm64")



with open('bootloader.c', 'w') as f:
    f.write(code)
