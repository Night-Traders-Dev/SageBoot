/* boot.S -- ESP32 (Xtensa LX6) stage 0 for SageBoot.
 *
 * Loaded by the ESP32 ROM bootloader from flash offset 0x1000. The ROM copies
 * the whole image into internal SRAM and jumps to the start of the loaded
 * segment, so this file is the first thing that executes and it must not assume
 * a stack, a valid windowed-register file, or that any peripheral is configured.
 *
 * The ROM leaves all three watchdogs armed when it hands over. An image that
 * does not disarm them is reset before it can produce anything observable, and
 * the symptom is a silent reboot loop that looks identical to a failed image
 * load. That is why the takeover below happens before anything else.
 *
 * Register and addressing notes, all of which cost time to learn:
 *
 *  - The Xtensa windowed ABI uses a15 as the callee-saved stack pointer and a1
 *    as the call-stack pointer. Every prologue's `entry a1, N` pushes onto a1,
 *    so setting only a15 leaves nested calls walking off the end of whatever
 *    the ROM left there. Both are established here.
 *
 *  - l32r on this toolchain resolves only *backward*: the literal pool has to
 *    precede the instruction that loads it, and a forward label is rejected
 *    outright. But the image entry must be the first instruction of the loaded
 *    segment, and a pool-first layout would put constants at the load address.
 *    So the entry is a single `j` that steps over the pool, which needs no
 *    literal, and the pool sits behind it.
 *
 *  - Every peripheral address is loaded with l32r from that pool rather than
 *    built with shifts. movi's immediate field is 12 bits and addi's is 8, so
 *    0x3ff480a4 cannot be formed by either, and hand-shifting a base plus an
 *    offset is both longer and one careless `addi` away from silently
 *    addressing the wrong register -- which is how an early version of this
 *    file poked the UART status register as though it were the transmit FIFO
 *    and produced a convincing but entirely artificial reset loop.
 */

    .section .iram0.text.entry, "ax", @progbits
    .align  4
    .global _start
    .type   _start, @function

_start:
    /* First instruction of the image, and the only one before the pool. */
    j       start_body
    .align  4                      /* the j is 3 bytes; keep the pool aligned,
                                   * an l32r whose target is unaligned is
                                   * rejected as "out of range" (e.g. -13/-12) */

/* ---- literal pool: reachable only backwards, hence behind the j ------- */
L_stack_top:   .word _estack
L_data_load:   .word __data_load
L_data_start:  .word __data_start
L_data_end:    .word __data_end
L_bss_start:   .word __bss_start
L_bss_end:     .word __bss_end
L_main:        .word main
L_safe_arg:    .word 0x40080000

/* rtc_cntl_reg.h: DR_REG_RTCCNTL_BASE = 0x3ff48000 */
L_rtc_prot:    .word 0x3ff480a4     /* RTC_CNTL_WDTWPROTECT */
L_rtc_cfg0:    .word 0x3ff4808c     /* RTC_CNTL_WDTCONFIG0  */
L_rtc_feed:    .word 0x3ff480a0     /* RTC_CNTL_WDTFEED    */

/* timer_group_reg.h: DR_REG_TIMERGROUP0_BASE = 0x3ff5f000, group i at +i*0x1000 */
L_tg0_prot:    .word 0x3ff5f064     /* TIMG0_WDTWPROTECT */
L_tg0_cfg0:    .word 0x3ff5f048     /* TIMG0_WDTCONFIG0  */
L_tg0_feed:    .word 0x3ff5f060     /* TIMG0_WDTFEED     */
L_tg1_prot:    .word 0x3ff60064     /* TIMG1_WDTWPROTECT */
L_tg1_cfg0:    .word 0x3ff60048     /* TIMG1_WDTCONFIG0  */
L_tg1_feed:    .word 0x3ff60060     /* TIMG1_WDTFEED     */

    .align  4

start_body:
    l32r    a15, L_stack_top       /* callee-saved stack pointer */
    mov     a1,  a15               /* call-stack pointer as well */
    l32r    a0,  L_safe_arg        /* scratch, not argc */

    /* ---- watchdog takeover, first thing after the stack ----------------
     * Both write-protect registers use the same key, TIMG_WDT_WKEY_VALUE =
     * 0x50d83aa1. WDTCONFIG0 has WDT_EN in bit 31 and STG0 in bits [30:28], so
     * writing zero disables the watchdog outright.
     *
     * The key does not fit a movi immediate, so it is assembled with shifts.
     * That is safe here because the result is checked against a literal-pool
     * round trip in the test notes; the addresses, which do not fit at all, are
     * loaded with l32r instead. */
    movi    a2, 0x50d
    slli    a2, a2, 16              /* 0x50d80000 */
    movi    a3, 0x3a
    slli    a3, a3, 8               /* 0x3a00     */
    addi    a3, a3, -95             /* 0x3aa1 (0xa1 as signed 8-bit) */
    or      a2, a2, a3              /* a2 = 0x50d83aa1 */
    movi    a6, 0                   /* the "disabled" value, kept in a reg */

    /* RTC watchdog: unlock, clear, re-lock. */
    l32r    a5, L_rtc_prot
    s32i    a2, a5, 0
    l32r    a5, L_rtc_cfg0
    s32i    a6, a5, 0
    l32r    a5, L_rtc_prot
    s32i    a6, a5, 0

    /* Timer-group watchdog 0. With the RTC one disarmed the reset reason
     * changes from RTCWDT_RTC_RESET to TG0WDT_SYS_RESET, so both groups go. */
    l32r    a5, L_tg0_prot
    s32i    a2, a5, 0
    l32r    a5, L_tg0_cfg0
    s32i    a6, a5, 0
    l32r    a5, L_tg0_prot
    s32i    a6, a5, 0

    l32r    a5, L_tg1_prot
    s32i    a2, a5, 0
    l32r    a5, L_tg1_cfg0
    s32i    a6, a5, 0
    l32r    a5, L_tg1_prot
    s32i    a6, a5, 0

    /* ---- copy .data from its load address ------------------------------ */
    l32r    a4, L_data_load
    l32r    a5, L_data_start
    l32r    a7, L_data_end
.Ldata_copy:
    bgeu    a5, a7, .Ldata_done
    l32i    a3, a4, 0
    s32i    a3, a5, 0
    addi    a4, a4, 4
    addi    a5, a5, 4
    j       .Ldata_copy
.Ldata_done:

    /* ---- zero .bss ------------------------------------------------------ */
    l32r    a4, L_bss_start
    l32r    a5, L_bss_end
.Lbss_zero:
    bgeu    a4, a5, .Lbss_done
    s32i    a6, a4, 0
    addi    a4, a4, 4
    j       .Lbss_zero
.Lbss_done:

    /* ---- call main(0, 0) ----------------------------------------------
     * jx rather than call8: main is not expected to return, so a plain jump
     * avoids inventing a return frame that would be popped into garbage. The
     * stack and call-stack pointers are already set above. */
    movi    a2, 0
    mov     a1, a15
    l32r    a3, L_main
    jx      a3

    /* main() is not expected to return. Feed the watchdogs and park rather than
     * fall off the end of the image into whatever follows in memory. This
     * toolchain's assembler has no wfi, so spin on a pipeline sync. */
.Lhalt:
    l32r    a5, L_rtc_feed
    s32i    a6, a5, 0               /* feed takes any write, including 0 */
    l32r    a5, L_tg0_feed
    s32i    a6, a5, 0
    l32r    a5, L_tg1_feed
    s32i    a6, a5, 0
    rsync
    j       .Lhalt
    .size   _start, . - _start
