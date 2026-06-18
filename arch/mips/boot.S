# MIPS 74Kc Stage 0 Bootstrap for Netgear WN3000RP v1 (BCM5357)
# Runs from reset vector 0xBFC00000 (uncached flash, kseg1)
# Register-only, no stack, position-independent.

.set noreorder
.globl _start
.globl main

.section .text.entry
_start:
    # 1. Disable interrupts and configure CP0 Status
    # Set BEV=1 (Bootstrap Exception Vectors), clear IE/EXL/ERL
    mfc0    $t0, $12            # Read CP0 Status (register 12)
    li      $t1, 0x10400000     # Set CU0 (Coprocessor 0 usable) and BEV (Bootstrap vectors)
    mtc0    $t1, $12            # Write CP0 Status
    ehb                         # Execution hazard barrier

    # 2. Set clock divider / PLL in ChipCommon if necessary (standard settings)
    li      $t0, 0xB800004C     # CC_CLKDIV register
    li      $t1, 0x00000002     # Set clock division ratio
    sw      $t1, 0($t0)

    # 3. Initialize ChipCommon UART 0 (8250-compatible) for status output
    # Set LCR to 0x83 to enable DLAB (Divisor Latch Access Bit)
    li      $t0, 0xB800030C     # UART0 LCR
    li      $t1, 0x83
    sb      $t1, 0($t0)

    # Set DLL divisor to 13 (assuming 24MHz UART clock for 115200 baud)
    li      $t0, 0xB8000300     # UART0 DLL
    li      $t1, 13
    sb      $t1, 0($t0)
    li      $t0, 0xB8000304     # UART0 DLM
    sb      $zero, 0($t0)

    # Disable DLAB, set word length to 8 bits, no parity, 1 stop bit (8N1)
    li      $t0, 0xB800030C     # UART0 LCR
    li      $t1, 0x03
    sb      $t1, 0($t0)

    # Enable and clear RX/TX FIFOs
    li      $t0, 0xB8000308     # UART0 FCR
    li      $t1, 0x07
    sb      $t1, 0($t0)

    # Disable interrupts
    li      $t0, 0xB8000304     # UART0 IER
    sb      $zero, 0($t0)

    # 4. Write "X" to UART TX to signal successful reset
    li      $t0, 0xB8000300     # UART0 DATA register (TX)
    li      $t1, 0x58           # ASCII 'X'
    sb      $t1, 0($t0)

    # Wait for TX FIFO to empty (LSR bit 5 - THRE)
wait_tx:
    li      $t0, 0xB8000314     # UART0 LSR
    lb      $t1, 0($t0)
    andi    $t1, $t1, 0x20      # Transmit Holding Register Empty
    beqz    $t1, wait_tx
    nop

    # 5. DDR Controller Timings & Init (offsets from 0xB8005000)
    li      $t0, 0xB8005000
    # Enable memory controller, setCAS latency = 3, 32-bit bus
    li      $t1, 0x00002133
    sw      $t1, 0x00($t0)
    # Timing registers
    li      $t1, 0x1919240A
    sw      $t1, 0x04($t0)
    # Refresh intervals
    li      $t1, 0x00000310
    sw      $t1, 0x08($t0)
    # Issue command: NOP + Precharge All
    li      $t1, 0x00000003
    sw      $t1, 0x10($t0)
    # Issue MRS (Mode Register Set) to activate DDR
    li      $t1, 0x00000132
    sw      $t1, 0x14($t0)
    # Enable normal DRAM operations
    li      $t1, 0x00000007
    sw      $t1, 0x10($t0)

    # Write 'D' to UART to signal DDR is ready
    li      $t0, 0xB8000300
    li      $t1, 0x44           # ASCII 'D'
    sb      $t1, 0($t0)

    # 6. Copy Stage 1 from SPI Flash LMA to DDR VMA (0x80000000)
    la      $t2, _stage1_lma    # Load Address in Flash (LMA)
    la      $t3, _stage1_start  # Virtual Address in RAM (VMA)
    la      $t4, _stage1_end    # End Virtual Address in RAM

copy_loop:
    lw      $t0, 0($t2)
    sw      $t0, 0($t3)
    addiu   $t2, $t2, 4
    addiu   $t3, $t3, 4
    slt     $t1, $t3, $t4
    bnez    $t1, copy_loop
    nop

    # Write 'R' to UART to signal Copy to RAM complete
    li      $t0, 0xB8000300
    li      $t1, 0x52           # ASCII 'R'
    sb      $t1, 0($t0)

    # 7. Initialize Stack Pointer and Jump to main in DDR
    li      $sp, 0x803F0000     # Safe stack below 4MB
    move    $a0, $zero          # argc = 0
    move    $a1, $zero          # argv = NULL
    la      $t0, main
    jr      $t0
    nop
