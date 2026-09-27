#ifndef COMPAT_STDATOMIC_H
#define COMPAT_STDATOMIC_H

/* C11 <stdatomic.h> for SageBoot's freestanding builds.
 *
 * This header previously declared only `atomic_int` and `atomic_long` and
 * nothing else. The Sage compiler now emits C11 atomics into the generated C --
 * atomic_load_explicit, atomic_fetch_add_explicit,
 * atomic_compare_exchange_weak_explicit, memory_order_acquire and friends --
 * and the emitted C does include <stdatomic.h>, so every clang-built
 * architecture was failing to compile with "call to undeclared function
 * 'atomic_load_explicit'". Implicit function declarations are a hard error
 * under current clang defaults, so it was not a warning that could be ignored.
 *
 * Implementation choice, and it is a real trade-off.
 *
 * The types here are plain integers and all the atomicity comes from the
 * __atomic_* builtins, rather than the types being `_Atomic`. Both compiler
 * families were tried and neither covers everything:
 *
 *   - The older __atomic_* family is complete -- compare_exchange,
 *     test_and_set, is_lock_free, the lot -- but clang rejects a pointer to an
 *     _Atomic type as its address argument ("address argument to atomic
 *     operation must be a pointer to integer"). It wants a plain pointer.
 *   - The C11-aware __c11_atomic_* family accepts _Atomic pointers, but clang
 *     21 does not provide __c11_atomic_compare_exchange,
 *     __c11_atomic_is_lock_free, __c11_atomic_test_and_set or
 *     __c11_atomic_clear at all. Verified by probing each one on
 *     riscv64-none-elf.
 *
 * So keeping the types _Atomic would mean hand-writing those four in terms of
 * casts or a CAS loop built on __c11_atomic_exchange, which does not actually
 * compare. Plain typedefs plus __atomic_* is the honest, portable option.
 *
 * What that costs: a *bare* read or write of an atomic_int, outside one of
 * these functions, is not atomic. C11 already leaves that undefined, and the
 * generated C does not do it. What it buys: layout and alignment are identical
 * to a genuine _Atomic int, so these objects stay interoperable with anything
 * built against the real header; and the operations the compiler actually
 * emits are real atomic instructions, not emulated ones.
 *
 * SageBoot is single-core in any case -- it never releases CPU1, never starts
 * another core, never enables SMP -- so on these targets the distinction is not
 * observable either way.
 */

#include <stdint.h>

/* ---- memory order constants (C11 7.17.1) ------------------------------ */
#define memory_order_relaxed 0
#define memory_order_consume 1
#define memory_order_acquire 2
#define memory_order_release 3
#define memory_order_acq_rel 4
#define memory_order_seq_cst 5

/* ---- atomic types ------------------------------------------------------
 * Plain integers, deliberately; see the note at the top. */
typedef int                    atomic_int;
typedef unsigned int           atomic_uint;
typedef long                   atomic_long;
typedef unsigned long          atomic_ulong;
typedef long long              atomic_llong;
typedef unsigned long long     atomic_ullong;
typedef short                  atomic_short;
typedef unsigned short         atomic_ushort;
typedef char                   atomic_char;
typedef signed char            atomic_schar;
typedef unsigned char          atomic_uchar;
typedef _Bool                  atomic_bool;
typedef int_least8_t           atomic_int_least8_t;
typedef uint_least8_t          atomic_uint_least8_t;
typedef int_least16_t          atomic_int_least16_t;
typedef uint_least16_t         atomic_uint_least16_t;
typedef int_least32_t          atomic_int_least32_t;
typedef uint_least32_t         atomic_uint_least32_t;
typedef int_least64_t          atomic_int_least64_t;
typedef uint_least64_t         atomic_uint_least64_t;
typedef int_fast8_t            atomic_int_fast8_t;
typedef uint_fast8_t           atomic_uint_fast8_t;
typedef int_fast16_t           atomic_int_fast16_t;
typedef uint_fast16_t          atomic_uint_fast16_t;
typedef int_fast32_t           atomic_int_fast32_t;
typedef uint_fast32_t          atomic_uint_fast32_t;
typedef int_fast64_t           atomic_int_fast64_t;
typedef uint_fast64_t          atomic_uint_fast64_t;
typedef intptr_t               atomic_intptr_t;
typedef uintptr_t              atomic_uintptr_t;
typedef size_t                 atomic_size_t;
typedef ptrdiff_t              atomic_ptrdiff_t;
typedef intmax_t               atomic_intmax_t;
typedef uintmax_t              atomic_uintmax_t;

/* ---- atomic_flag storage (C11 7.17.8) ---------------------------------
 * Declared before the operation blocks because both paths below provide
 * inline functions taking a pointer to it. */
typedef struct atomic_flag {
    unsigned char __val;
} atomic_flag;

#define ATOMIC_FLAG_INIT { 0 }

/* ---- target capability -------------------------------------------------
 * ARMv6-M -- Cortex-M0 and M0+, which is the rp2040 -- has no LDREX/STREX and
 * no 64-bit support, so *none* of the 4-byte atomics can be inlined. GCC then
 * emits calls to __atomic_load_4, __atomic_fetch_add_4 and
 * __atomic_compare_exchange_4 in libatomic, which does not exist for a
 * freestanding bare-metal link. That is a hardware limitation rather than a
 * missing header, so the whole family is provided in software below.
 *
 * Every other supported target (rv64, x86-64, AArch64, RP2350 ARM, Xtensa LX6)
 * has native compare-and-swap and inlines all of it. */
#if defined(__arm__) && defined(__ARM_ARCH) && (__ARM_ARCH < 7)
#define SAGE_ATOMIC_NO_HW_CAS 1
#endif

#ifndef SAGE_ATOMIC_NO_HW_CAS
#define ATOMIC_BOOL_LOCK_FREE     2
#define ATOMIC_CHAR_LOCK_FREE     2
#define ATOMIC_CHAR16_T_LOCK_FREE 2
#define ATOMIC_CHAR32_T_LOCK_FREE 2
#define ATOMIC_WCHAR_T_LOCK_FREE  2
#define ATOMIC_SHORT_LOCK_FREE    2
#define ATOMIC_INT_LOCK_FREE      2
#define ATOMIC_LONG_LOCK_FREE     2
#define ATOMIC_LLONG_LOCK_FREE    2
#define ATOMIC_POINTER_LOCK_FREE  2
#endif /* !SAGE_ATOMIC_NO_HW_CAS */

#ifdef SAGE_ATOMIC_NO_HW_CAS
/* Nothing here is lock-free without LDREX/STREX. Report that rather than
 * claiming 2, so any code that cares can see it. */
#define ATOMIC_BOOL_LOCK_FREE     0
#define ATOMIC_CHAR_LOCK_FREE     0
#define ATOMIC_SHORT_LOCK_FREE    0
#define ATOMIC_INT_LOCK_FREE      0
#define ATOMIC_LONG_LOCK_FREE     0
#define ATOMIC_LLONG_LOCK_FREE    0
#define ATOMIC_POINTER_LOCK_FREE  0
#endif

/* ---- initialisation ---------------------------------------------------- */
#define ATOMIC_VAR_INIT(value) (value)
#define atomic_init(obj, value) \
    __atomic_store_n((obj), (value), __ATOMIC_RELAXED)

/* ---- fences ------------------------------------------------------------ */
#define atomic_thread_fence(order) __atomic_thread_fence(order)
#define atomic_signal_fence(order) __atomic_signal_fence(order)

/* ---- lock-freedom ------------------------------------------------------
 * Queried rather than assumed, so a future 128-bit type or a target without
 * native 64-bit CAS reports honestly instead of lying. */
#define atomic_is_lock_free(obj) __atomic_is_lock_free(sizeof(*(obj)), (obj))

#ifndef SAGE_ATOMIC_NO_HW_CAS

/* ---- load / store (C11 7.17.7.1) -------------------------------------- */
#define atomic_store_explicit(obj, desired, order) \
    __atomic_store_n((obj), (desired), (order))
#define atomic_store(obj, desired) \
    __atomic_store_n((obj), (desired), __ATOMIC_SEQ_CST)

#define atomic_load_explicit(obj, order) \
    __atomic_load_n((obj), (order))
#define atomic_load(obj) \
    __atomic_load_n((obj), __ATOMIC_SEQ_CST)

#define atomic_exchange_explicit(obj, desired, order) \
    __atomic_exchange_n((obj), (desired), (order))
#define atomic_exchange(obj, desired) \
    __atomic_exchange_n((obj), (desired), __ATOMIC_SEQ_CST)

/* ---- read-modify-write (C11 7.17.7.2) --------------------------------- */
#define atomic_fetch_add_explicit(obj, arg, order) \
    __atomic_fetch_add((obj), (arg), (order))
#define atomic_fetch_add(obj, arg) \
    __atomic_fetch_add((obj), (arg), __ATOMIC_SEQ_CST)

#define atomic_fetch_sub_explicit(obj, arg, order) \
    __atomic_fetch_sub((obj), (arg), (order))
#define atomic_fetch_sub(obj, arg) \
    __atomic_fetch_sub((obj), (arg), __ATOMIC_SEQ_CST)

#define atomic_fetch_or_explicit(obj, arg, order) \
    __atomic_fetch_or((obj), (arg), (order))
#define atomic_fetch_or(obj, arg) \
    __atomic_fetch_or((obj), (arg), __ATOMIC_SEQ_CST)

#define atomic_fetch_xor_explicit(obj, arg, order) \
    __atomic_fetch_xor((obj), (arg), (order))
#define atomic_fetch_xor(obj, arg) \
    __atomic_fetch_xor((obj), (arg), __ATOMIC_SEQ_CST)

#define atomic_fetch_and_explicit(obj, arg, order) \
    __atomic_fetch_and((obj), (arg), (order))
#define atomic_fetch_and(obj, arg) \
    __atomic_fetch_and((obj), (arg), __ATOMIC_SEQ_CST)



#define atomic_compare_exchange_strong_explicit(obj, expected, desired, succ, fail) \
    __atomic_compare_exchange_n((obj), (expected), (desired), 0, (succ), (fail))
#define atomic_compare_exchange_strong(obj, expected, desired) \
    __atomic_compare_exchange_n((obj), (expected), (desired), 0, \
                                __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)

#define atomic_compare_exchange_weak_explicit(obj, expected, desired, succ, fail) \
    __atomic_compare_exchange_n((obj), (expected), (desired), 1, (succ), (fail))
#define atomic_compare_exchange_weak(obj, expected, desired) \
    __atomic_compare_exchange_n((obj), (expected), (desired), 1, \
                                __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)

#endif /* !SAGE_ATOMIC_NO_HW_CAS */

#ifdef SAGE_ATOMIC_NO_HW_CAS

/* ---- software implementations for ARMv6-M ------------------------------
 * Mask interrupts around every read-modify-write. On ARM this is CPSID/CPSIE,
 * available from ARMv6-M onwards. Without masking, an interrupt firing between
 * the load and the store would observe a half-updated value.
 *
 * Sound only because SageBoot is single-core: no other core can run between
 * the load and the store, and it never enables interrupts or releases a second
 * core. That is what makes a software CAS sound at all, so it is stated here
 * rather than assumed.
 *
 * The success/failure order arguments to compare-exchange are accepted and
 * ignored: this implementation always applies the stricter ordering, and a
 * spurious failure is impossible in software, so weak and strong behave
 * identically -- which is conforming, since spurious failure is permitted, not
 * required. */
static inline void __sage_atomic_enter(void) {
    __asm__ volatile("cpsid i" ::: "memory");
}

static inline void __sage_atomic_exit(void) {
    __asm__ volatile("cpsie i" ::: "memory");
}

#define atomic_init(obj, value) ({            \
    __sage_atomic_enter();                    \
    *(obj) = (value);                         \
    __sage_atomic_exit();                     \
})

#define atomic_load_explicit(obj, order) ({   \
    __typeof__(*(obj)) __v;                   \
    (void)(order);                            \
    __sage_atomic_enter();                    \
    __v = *(obj);                             \
    __sage_atomic_exit();                     \
    __v;                                      \
})
#define atomic_load(obj) atomic_load_explicit((obj), memory_order_seq_cst)

#define atomic_store_explicit(obj, desired, order) ({ \
    (void)(order);                            \
    __sage_atomic_enter();                    \
    *(obj) = (desired);                       \
    __sage_atomic_exit();                     \
})
#define atomic_store(obj, desired) \
    atomic_store_explicit((obj), (desired), memory_order_seq_cst)

#define atomic_exchange_explicit(obj, desired, order) ({ \
    __typeof__(*(obj)) __old;                   \
    (void)(order);                              \
    __sage_atomic_enter();                      \
    __old = *(obj);                             \
    *(obj) = (desired);                         \
    __sage_atomic_exit();                       \
    __old;                                      \
})
#define atomic_exchange(obj, desired) \
    atomic_exchange_explicit((obj), (desired), memory_order_seq_cst)

/* One macro generates the whole fetch family: the caller supplies the
 * expression that combines the old and new values. */
#define __sage_atomic_rmw(obj, arg, order, combine) ({ \
    __typeof__(*(obj)) __old;                   \
    (void)(order);                              \
    __sage_atomic_enter();                      \
    __old = *(obj);                             \
    *(obj) = (combine);                         \
    __sage_atomic_exit();                       \
    __old;                                      \
})

#define atomic_fetch_add_explicit(obj, arg, order) \
    __sage_atomic_rmw((obj), (arg), (order), __old + (arg))
#define atomic_fetch_add(obj, arg) \
    atomic_fetch_add_explicit((obj), (arg), memory_order_seq_cst)

#define atomic_fetch_sub_explicit(obj, arg, order) \
    __sage_atomic_rmw((obj), (arg), (order), __old - (arg))
#define atomic_fetch_sub(obj, arg) \
    atomic_fetch_sub_explicit((obj), (arg), memory_order_seq_cst)

#define atomic_fetch_or_explicit(obj, arg, order) \
    __sage_atomic_rmw((obj), (arg), (order), __old | (arg))
#define atomic_fetch_or(obj, arg) \
    atomic_fetch_or_explicit((obj), (arg), memory_order_seq_cst)

#define atomic_fetch_xor_explicit(obj, arg, order) \
    __sage_atomic_rmw((obj), (arg), (order), __old ^ (arg))
#define atomic_fetch_xor(obj, arg) \
    atomic_fetch_xor_explicit((obj), (arg), memory_order_seq_cst)

#define atomic_fetch_and_explicit(obj, arg, order) \
    __sage_atomic_rmw((obj), (arg), (order), __old & (arg))
#define atomic_fetch_and(obj, arg) \
    atomic_fetch_and_explicit((obj), (arg), memory_order_seq_cst)

#define __sage_cas(obj, expected, desired) ({   \
    __typeof__(*(obj)) __old;                   \
    __typeof__(*(obj)) __want = *(expected);    \
    __typeof__(*(obj)) __next = (desired);      \
    __sage_atomic_enter();                      \
    __old = *(obj);                             \
    if (__old == __want) { *(obj) = __next; }   \
    __sage_atomic_exit();                       \
    *(expected) = __old;                        \
    __old == __want;                            \
})

#define atomic_compare_exchange_strong_explicit(obj, expected, desired, succ, fail) \
    __sage_cas((obj), (expected), (desired))
#define atomic_compare_exchange_strong(obj, expected, desired) \
    __sage_cas((obj), (expected), (desired))
#define atomic_compare_exchange_weak_explicit(obj, expected, desired, succ, fail) \
    __sage_cas((obj), (expected), (desired))
#define atomic_compare_exchange_weak(obj, expected, desired) \
    __sage_cas((obj), (expected), (desired))

/* atomic_flag is a byte, so the generic __atomic builtins do handle it. */
static inline int atomic_flag_test_and_set(volatile atomic_flag *obj) {
    return __atomic_test_and_set(&obj->__val, __ATOMIC_SEQ_CST);
}
static inline int atomic_flag_test_and_set_explicit(volatile atomic_flag *obj,
                                                    int order) {
    return __atomic_test_and_set(&obj->__val, order);
}
static inline void atomic_flag_clear(volatile atomic_flag *obj) {
    __atomic_clear(&obj->__val, __ATOMIC_SEQ_CST);
}
static inline void atomic_flag_clear_explicit(volatile atomic_flag *obj,
                                              int order) {
    __atomic_clear(&obj->__val, order);
}

#endif /* SAGE_ATOMIC_NO_HW_CAS */

#endif /* COMPAT_STDATOMIC_H */
