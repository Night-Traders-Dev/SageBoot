#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <setjmp.h>
#include <ctype.h>
#include <time.h>
#include <pthread.h>
#include <semaphore.h>
#include <sys/stat.h>

void compat_uart_putc(char c);
void compat_uart_print(const char* s);
char compat_uart_getc(void);

/*==========================================================================
 * Heap Allocator (Block Header Bump Allocator)
 *==========================================================================*/

typedef struct {
    size_t size;
} BlockHeader;

static char* heap_ptr = NULL;

#if defined(__x86_64__)
  #define HEAP_START 0x02000000 // 32MB mark
  #define HEAP_MAX   0x04000000 // 64MB max
#elif defined(__riscv) && __riscv_xlen == 64
  #define HEAP_START 0x81000000 // Above kernel entry point (0x80200000)
  #define HEAP_MAX   0x82000000
#elif defined(__riscv) && __riscv_xlen == 32
  #define HEAP_START 0x20001000 // RP2350 RISC-V SRAM
  #define HEAP_MAX   0x20080000
#elif defined(__aarch64__)
  #define HEAP_START 0x41000000 // Above AArch64 load point (0x40080000)
  #define HEAP_MAX   0x42000000
#elif defined(__ARM_ARCH_6M__)
  #define HEAP_START 0x20001000 // RP2040 SRAM
  #define HEAP_MAX   0x20040000
#elif defined(__ARM_ARCH_8M_MAIN__)
  #define HEAP_START 0x20001000 // RP2350 ARM SRAM
  #define HEAP_MAX   0x20080000
#elif defined(__mips__)
  #define HEAP_START 0x80800000 // 8MB mark for Netgear router DDR
  #define HEAP_MAX   0x82000000
#else
  #define HEAP_START 0x01000000
  #define HEAP_MAX   0x02000000
#endif

void* malloc(size_t size) {
    if (heap_ptr == NULL) {
        heap_ptr = (char*)HEAP_START;
    }
    size = (size + 7) & ~7; // Align to 8 bytes
    size_t total_size = size + sizeof(BlockHeader);
    
    if ((uintptr_t)heap_ptr + total_size >= HEAP_MAX) {
        compat_uart_print("compat: OUT OF MEMORY!\n");
        return NULL;
    }
    
    BlockHeader* header = (BlockHeader*)heap_ptr;
    header->size = size;
    
    void* ptr = (void*)(heap_ptr + sizeof(BlockHeader));
    heap_ptr += total_size;
    return ptr;
}

void free(void* ptr) {
    (void)ptr;
    // Bump allocator: free is a no-op
}

void* realloc(void* ptr, size_t size) {
    if (ptr == NULL) return malloc(size);
    
    BlockHeader* header = (BlockHeader*)((char*)ptr - sizeof(BlockHeader));
    size_t old_size = header->size;
    if (size <= old_size) return ptr; // Already large enough
    
    void* new_ptr = malloc(size);
    if (!new_ptr) return NULL;
    
    // Copy old data
    char* src = (char*)ptr;
    char* dest = (char*)new_ptr;
    for (size_t i = 0; i < old_size; i++) {
        dest[i] = src[i];
    }
    return new_ptr;
}

void* calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void* ptr = malloc(total);
    if (ptr) {
        char* p = (char*)ptr;
        for (size_t i = 0; i < total; i++) {
            p[i] = 0;
        }
    }
    return ptr;
}

/*==========================================================================
 * Memory primitives
 *==========================================================================*/

void* memset(void* s, int c, size_t n) {
    unsigned char* p = (unsigned char*)s;
    for (size_t i = 0; i < n; i++) {
        p[i] = (unsigned char)c;
    }
    return s;
}

void* memcpy(void* dest, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* sr = (const unsigned char*)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = sr[i];
    }
    return dest;
}

#if defined(__arm__)
void __aeabi_memcpy4(void* dest, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* sr = (const unsigned char*)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = sr[i];
    }
}
#endif

void* memmove(void* dest, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* sr = (const unsigned char*)src;
    if (d < sr) {
        for (size_t i = 0; i < n; i++) {
            d[i] = sr[i];
        }
    } else if (d > sr) {
        size_t i = n;
        while (i > 0) {
            i--;
            d[i] = sr[i];
        }
    }
    return dest;
}

int memcmp(const void* s1, const void* s2, size_t n) {
    const unsigned char* a = (const unsigned char*)s1;
    const unsigned char* b = (const unsigned char*)s2;
    for (size_t i = 0; i < n; i++) {
        if (a[i] != b[i]) {
            return (int)a[i] - (int)b[i];
        }
    }
    return 0;
}

/*==========================================================================
 * String operations
 *==========================================================================*/

size_t strlen(const char* s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

int strcmp(const char* s1, const char* s2) {
    while (*s1 && *s1 == *s2) {
        s1++;
        s2++;
    }
    return (int)(unsigned char)*s1 - (int)(unsigned char)*s2;
}

int strncmp(const char* s1, const char* s2, size_t n) {
    if (n == 0) return 0;
    while (n > 0 && *s1 && *s1 == *s2) {
        s1++;
        s2++;
        n--;
    }
    if (n == 0) return 0;
    return (int)(unsigned char)*s1 - (int)(unsigned char)*s2;
}

char* strcpy(char* dest, const char* src) {
    char* d = dest;
    while ((*d++ = *src++));
    return dest;
}

char* strcat(char* dest, const char* src) {
    char* d = dest;
    while (*d) d++;
    while ((*d++ = *src++));
    return dest;
}

char* strdup(const char* s) {
    size_t len = strlen(s);
    char* d = malloc(len + 1);
    if (d) {
        memcpy(d, s, len + 1);
    }
    return d;
}

char* strchr(const char* s, int c) {
    while (*s) {
        if (*s == (char)c) return (char*)s;
        s++;
    }
    if (c == '\0') return (char*)s;
    return NULL;
}

char* strstr(const char* haystack, const char* needle) {
    if (!*needle) return (char*)haystack;
    for (; *haystack; haystack++) {
        if (*haystack == *needle) {
            const char* h = haystack;
            const char* n = needle;
            while (*h && *n && *h == *n) {
                h++;
                n++;
            }
            if (!*n) return (char*)haystack;
        }
    }
    return NULL;
}

double atof(const char* nptr) {
    double val = 0.0;
    double sign = 1.0;
    if (*nptr == '-') {
        sign = -1.0;
        nptr++;
    } else if (*nptr == '+') {
        nptr++;
    }
    while (*nptr >= '0' && *nptr <= '9') {
        val = val * 10.0 + (*nptr - '0');
        nptr++;
    }
    if (*nptr == '.') {
        nptr++;
        double dec = 0.1;
        while (*nptr >= '0' && *nptr <= '9') {
            val += (*nptr - '0') * dec;
            dec *= 0.1;
            nptr++;
        }
    }
    return sign * val;
}

double strtod(const char* nptr, char** endptr) {
    if (endptr) {
        *endptr = (char*)nptr;
    }
    return atof(nptr);
}

int abs(int j) {
    return j < 0 ? -j : j;
}

static unsigned long long next_rand = 1;

void srand(unsigned int seed) {
    next_rand = seed;
}

int rand(void) {
    next_rand = next_rand * 1103515245 + 12345;
    return (unsigned int)(next_rand / 65536) % 32768;
}

char* getenv(const char* name) {
    (void)name;
    return NULL;
}

int system(const char* command) {
    (void)command;
    return -1;
}

/*==========================================================================
 * UART Redirection & Standard I/O
 *==========================================================================*/

#if defined(__x86_64__)

static inline uint8_t inb(uint16_t port) {
    uint8_t data;
    __asm__ volatile("inb %1, %0" : "=a"(data) : "d"(port));
    return data;
}

static inline void outb(uint16_t port, uint8_t data) {
    __asm__ volatile("outb %0, %1" :: "a"(data), "d"(port));
}

void compat_uart_putc(char c) {
    // Wait for COM1 Line Status Register bit 5 (Transmit Holding Register Empty)
    while ((inb(0x3FD) & 0x20) == 0);
    outb(0x3F8, c);
}

char compat_uart_getc(void) {
    // Wait for COM1 Line Status Register bit 0 (Data Ready)
    while ((inb(0x3FD) & 0x01) == 0);
    return (char)inb(0x3F8);
}

#elif defined(__riscv) && __riscv_xlen == 64

#define RV_UART_BASE 0x10000000 // QEMU RV64 Virt 16550A UART

void compat_uart_putc(char c) {
    volatile uint8_t* lsr = (volatile uint8_t*)(RV_UART_BASE + 5);
    while ((*lsr & 0x20) == 0);
    volatile uint8_t* thr = (volatile uint8_t*)(RV_UART_BASE + 0);
    *thr = (uint8_t)c;
}

char compat_uart_getc(void) {
    volatile uint8_t* lsr = (volatile uint8_t*)(RV_UART_BASE + 5);
    while ((*lsr & 0x01) == 0);
    volatile uint8_t* rbr = (volatile uint8_t*)(RV_UART_BASE + 0);
    return (char)*rbr;
}

#elif defined(__riscv) && __riscv_xlen == 32

#define RV32_UART_BASE 0x40054000 // RP2350 UART0

void compat_uart_putc(char c) {
    volatile uint32_t* fr = (volatile uint32_t*)(RV32_UART_BASE + 0x18);
    while ((*fr & 0x20) != 0);
    volatile uint32_t* dr = (volatile uint32_t*)(RV32_UART_BASE + 0x00);
    *dr = (uint32_t)c;
}

char compat_uart_getc(void) {
    volatile uint32_t* fr = (volatile uint32_t*)(RV32_UART_BASE + 0x18);
    while ((*fr & 0x10) != 0);
    volatile uint32_t* dr = (volatile uint32_t*)(RV32_UART_BASE + 0x00);
    return (char)(*dr & 0xFF);
}

#elif defined(__ARM_ARCH_6M__) || defined(__ARM_ARCH_8M_MAIN__)

#if defined(__ARM_ARCH_8M_MAIN__)
#define PICO_UART_BASE 0x40054000 // RP2350 UART0
#else
#define PICO_UART_BASE 0x40034000 // RP2040 UART0
#endif

void compat_uart_putc(char c) {
    volatile uint32_t* fr = (volatile uint32_t*)(PICO_UART_BASE + 0x18);
    while ((*fr & 0x20) != 0);
    volatile uint32_t* dr = (volatile uint32_t*)(PICO_UART_BASE + 0x00);
    *dr = (uint32_t)c;
}

char compat_uart_getc(void) {
    volatile uint32_t* fr = (volatile uint32_t*)(PICO_UART_BASE + 0x18);
    while ((*fr & 0x10) != 0);
    volatile uint32_t* dr = (volatile uint32_t*)(PICO_UART_BASE + 0x00);
    return (char)(*dr & 0xFF);
}

#elif defined(__aarch64__)

#define ARM_UART_BASE 0x09000000 // QEMU AArch64 Virt PrimeCell PL011 UART

void compat_uart_putc(char c) {
    volatile uint32_t* fr = (volatile uint32_t*)(ARM_UART_BASE + 0x18);
    while (*fr & 0x20); // Wait while TX FIFO is full (TXFF)
    volatile uint32_t* dr = (volatile uint32_t*)(ARM_UART_BASE + 0x00);
    *dr = (uint32_t)c;
}

char compat_uart_getc(void) {
    volatile uint32_t* fr = (volatile uint32_t*)(ARM_UART_BASE + 0x18);
    while (*fr & 0x10); // Wait while RX FIFO is empty (RXFE)
    volatile uint32_t* dr = (volatile uint32_t*)(ARM_UART_BASE + 0x00);
    return (char)(*dr & 0xFF);
}

#elif defined(__mips__)

#define MIPS_UART_BASE 0xB8000300 // Netgear WN3000RP UART

void compat_uart_putc(char c) {
    volatile uint8_t* lsr = (volatile uint8_t*)(MIPS_UART_BASE + 0x14);
    while ((*lsr & 0x20) == 0); // Wait for THRE
    volatile uint8_t* data = (volatile uint8_t*)(MIPS_UART_BASE + 0x00);
    *data = (uint8_t)c;
}

char compat_uart_getc(void) {
    volatile uint8_t* lsr = (volatile uint8_t*)(MIPS_UART_BASE + 0x14);
    while ((*lsr & 0x01) == 0); // Wait for DR
    volatile uint8_t* data = (volatile uint8_t*)(MIPS_UART_BASE + 0x00);
    return (char)*data;
}

#else

void compat_uart_putc(char c) {
    (void)c;
}

char compat_uart_getc(void) {
    return '\0';
}

#endif

void compat_uart_print(const char* s) {
    while (*s) {
        if (*s == '\n') {
            compat_uart_putc('\r');
        }
        compat_uart_putc(*s++);
    }
}

static void int_to_str(char* buf, int val, int base) {
    char tmp[32];
    int i = 0;
    if (val == 0) {
        buf[0] = '0';
        buf[1] = '\0';
        return;
    }
    int is_neg = 0;
    if (val < 0 && base == 10) {
        is_neg = 1;
        val = -val;
    }
    unsigned int uval = (unsigned int)val;
    while (uval > 0) {
        int rem = uval % base;
        tmp[i++] = (rem < 10) ? (rem + '0') : (rem - 10 + 'A');
        uval /= base;
    }
    int j = 0;
    if (is_neg) {
        buf[j++] = '-';
    }
    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';
}

int vsnprintf(char* str, size_t size, const char* format, va_list ap) {
    size_t written = 0;
    while (*format && written < size - 1) {
        if (*format == '%') {
            format++;
            if (*format == 'd') {
                int val = va_arg(ap, int);
                char buf[32];
                int_to_str(buf, val, 10);
                char* p = buf;
                while (*p && written < size - 1) {
                    str[written++] = *p++;
                }
            } else if (*format == 's') {
                char* val = va_arg(ap, char*);
                if (!val) val = "(null)";
                while (*val && written < size - 1) {
                    str[written++] = *val++;
                }
            } else if (*format == 'x') {
                int val = va_arg(ap, int);
                char buf[32];
                int_to_str(buf, val, 16);
                char* p = buf;
                while (*p && written < size - 1) {
                    str[written++] = *p++;
                }
            } else if (*format == 'c') {
                char val = (char)va_arg(ap, int);
                str[written++] = val;
            } else if (*format == '%') {
                str[written++] = '%';
            }
        } else {
            str[written++] = *format;
        }
        format++;
    }
    str[written] = '\0';
    return (int)written;
}

int snprintf(char* str, size_t size, const char* format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(str, size, format, ap);
    va_end(ap);
    return ret;
}

int sprintf(char* str, const char* format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(str, 1024, format, ap);
    va_end(ap);
    return ret;
}

int printf(const char* format, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    compat_uart_print(buf);
    return ret;
}

int fprintf(FILE* stream, const char* format, ...) {
    (void)stream;
    char buf[1024];
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    compat_uart_print(buf);
    return ret;
}

int fputs(const char* s, FILE* stream) {
    (void)stream;
    compat_uart_print(s);
    return 0;
}

int fputc(int c, FILE* stream) {
    (void)stream;
    compat_uart_putc((char)c);
    return c;
}

char* fgets(char* s, int size, FILE* stream) {
    (void)stream;
    if (size <= 0) return NULL;
    int i = 0;
    while (i < size - 1) {
        char c = compat_uart_getc();
        // Echo back
        compat_uart_putc(c);
        if (c == '\r' || c == '\n') {
            s[i++] = '\n';
            compat_uart_putc('\n');
            break;
        } else if (c == 8 || c == 127) { // Backspace
            if (i > 0) {
                i--;
                compat_uart_putc(' ');
                compat_uart_putc(8);
            }
        } else {
            s[i++] = c;
        }
    }
    s[i] = '\0';
    return s;
}

FILE* fopen(const char* pathname, const char* mode) {
    (void)pathname; (void)mode;
    return NULL;
}

int fclose(FILE* stream) {
    (void)stream;
    return -1;
}

size_t fread(void* ptr, size_t size, size_t nmemb, FILE* stream) {
    (void)ptr; (void)size; (void)nmemb; (void)stream;
    return 0;
}

size_t fwrite(const void* ptr, size_t size, size_t nmemb, FILE* stream) {
    (void)ptr; (void)size; (void)nmemb; (void)stream;
    return 0;
}

int fseek(FILE* stream, long offset, int whence) {
    (void)stream; (void)offset; (void)whence;
    return -1;
}

long ftell(FILE* stream) {
    (void)stream;
    return -1;
}

/*==========================================================================
 * Math stubs
 *==========================================================================*/

double fmod(double x, double y) { (void)x; (void)y; return 0.0; }
double pow(double x, double y) { (void)x; (void)y; return 0.0; }
double sqrt(double x) { (void)x; return 0.0; }
double sin(double x) { (void)x; return 0.0; }
double cos(double x) { (void)x; return 0.0; }
double tan(double x) { (void)x; return 0.0; }
double log(double x) { (void)x; return 0.0; }
double exp(double x) { (void)x; return 0.0; }

double fabs(double x) {
    return x < 0 ? -x : x;
}

double floor(double x) {
    int i = (int)x;
    return (double)(x < i ? i - 1 : i);
}

double ceil(double x) {
    int i = (int)x;
    return (double)(x > i ? i + 1 : i);
}

/*==========================================================================
 * Exception handling & Process control stubs
 *==========================================================================*/

void abort(void) {
    compat_uart_print("compat: abort() called! Halting system.\n");
    for (;;);
}

void exit(int status) {
    printf("compat: exit(%d) called! Halting system.\n", status);
    for (;;);
}

int setjmp(jmp_buf env) {
    (void)env;
    return 0;
}

void longjmp(jmp_buf env, int val) {
    (void)env; (void)val;
    compat_uart_print("compat: longjmp() called but setjmp is a stub!\n");
    abort();
}

/*==========================================================================
 * Ctype operations
 *==========================================================================*/

int isspace(int c) {
    return (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f');
}

int isalpha(int c) {
    return ((c >= 'a' && c <= 'z') || ((c >= 'A' && c <= 'Z')));
}

int isdigit(int c) {
    return (c >= '0' && c <= '9');
}

int isalnum(int c) {
    return (isalpha(c) || isdigit(c));
}

int toupper(int c) {
    if (c >= 'a' && c <= 'z') return c - 'a' + 'A';
    return c;
}

int tolower(int c) {
    if (c >= 'A' && c <= 'Z') return c - 'A' + 'a';
    return c;
}

/*==========================================================================
 * Threading & Synchronization stubs
 *==========================================================================*/

int pthread_create(pthread_t* thread, const pthread_attr_t* attr, void* (*start_routine)(void*), void* arg) {
    (void)thread; (void)attr; (void)start_routine; (void)arg;
    return -1;
}

int pthread_join(pthread_t thread, void** retval) {
    (void)thread; (void)retval;
    return -1;
}

pthread_t pthread_self(void) {
    return 1;
}

int pthread_mutex_init(pthread_mutex_t* mutex, const void* attr) {
    (void)mutex; (void)attr;
    return 0;
}

int pthread_mutex_lock(pthread_mutex_t* mutex) {
    (void)mutex;
    return 0;
}

int pthread_mutex_unlock(pthread_mutex_t* mutex) {
    (void)mutex;
    return 0;
}

int pthread_mutex_destroy(pthread_mutex_t* mutex) {
    (void)mutex;
    return 0;
}

int sem_init(sem_t* sem, int pshared, unsigned int value) {
    (void)sem; (void)pshared; (void)value;
    return 0;
}

int sem_wait(sem_t* sem) {
    (void)sem;
    return 0;
}

int sem_trywait(sem_t* sem) {
    (void)sem;
    return 0;
}

int sem_post(sem_t* sem) {
    (void)sem;
    return 0;
}

int sem_destroy(sem_t* sem) {
    (void)sem;
    return 0;
}

/*==========================================================================
 * Virtual Filesystem stubs
 *==========================================================================*/

int close(int fd) {
    (void)fd;
    return -1;
}

int read(int fd, void* buf, size_t count) {
    (void)fd; (void)buf; (void)count;
    return -1;
}

int write(int fd, const void* buf, size_t count) {
    (void)fd; (void)buf; (void)count;
    return -1;
}

unsigned int sleep(unsigned int seconds) {
    volatile unsigned int count = seconds * 30000000;
    while (count > 0) count--;
    return 0;
}

int stat(const char* pathname, struct stat* statbuf) {
    (void)pathname;
    if (statbuf) {
        statbuf->st_size = 0;
    }
    return -1;
}

int nanosleep(const struct timespec* req, struct timespec* rem) {
    (void)rem;
    volatile unsigned int count = req->tv_sec * 30000000 + req->tv_nsec / 33;
    while (count > 0) count--;
    return 0;
}

clock_t clock(void) {
    unsigned long count = 0;
#if defined(__x86_64__)
    unsigned int lo, hi;
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    count = ((unsigned long)hi << 32) | lo;
#elif defined(__riscv) && __riscv_xlen == 64
    __asm__ volatile("rdtime %0" : "=r"(count));
#elif defined(__riscv) && __riscv_xlen == 32
    uint32_t cycle;
    __asm__ volatile("rdcycle %0" : "=r"(cycle));
    count = cycle;
#elif defined(__aarch64__)
    __asm__ volatile("mrs %0, cntpct_el0" : "=r"(count));
#elif defined(__ARM_ARCH_8M_MAIN__)
    volatile uint32_t* dwt_ctrl = (volatile uint32_t*)0xE0001000;
    if (*dwt_ctrl & 1) {
        volatile uint32_t* dwt_cyccnt = (volatile uint32_t*)0xE0001004;
        count = *dwt_cyccnt;
    }
#elif defined(__ARM_ARCH_6M__)
    volatile uint32_t* stk_val = (volatile uint32_t*)0xE000E018;
    count = *stk_val;
#elif defined(__mips__)
    unsigned int c32;
    __asm__ volatile("mfc0 %0, $9" : "=r"(c32));
    count = c32;
#endif
    return (clock_t)count;
}

/*==========================================================================
 * Compiler-rt helpers (IEEE-754 double precision conversions)
 *==========================================================================*/

#if !defined(__arm__) && !defined(__riscv)
int64_t __fixdfdi(double a) {
    union {
        double d;
        uint64_t u;
    } u = {a};
    
    int sign = (u.u >> 63) ? -1 : 1;
    int exp = (int)((u.u >> 52) & 0x7FF) - 1023;
    uint64_t fraction = (u.u & 0xFFFFFFFFFFFFFull) | 0x10000000000000ull;
    
    if (exp < 0) return 0;
    if (exp > 63) return (sign == 1) ? 0x7FFFFFFFFFFFFFFFll : 0x8000000000000000ll;
    
    uint64_t val;
    if (exp > 52) {
        val = fraction << (exp - 52);
    } else {
        val = fraction >> (52 - exp);
    }
    
    return sign * (int64_t)val;
}

double __floatdidf(int64_t a) {
    if (a == 0) return 0.0;
    union {
        double d;
        uint64_t u;
    } u;
    
    uint64_t sign = 0;
    if (a < 0) {
        sign = 1ULL << 63;
        a = -a;
    }
    
    uint64_t val = (uint64_t)a;
    int lz = 0;
    uint64_t temp = val;
    while ((temp & (1ULL << 63)) == 0) {
        temp <<= 1;
        lz++;
    }
    
    int exp = 63 - lz;
    uint64_t fraction;
    if (exp <= 52) {
        fraction = (val ^ (1ULL << exp)) << (52 - exp);
    } else {
        fraction = (val ^ (1ULL << exp)) >> (exp - 52);
    }
    
    u.u = sign | (((uint64_t)(exp + 1023) & 0x7FF) << 52) | (fraction & 0xFFFFFFFFFFFFFull);
    return u.d;
}

double __floatundidf(uint64_t a) {
    if (a == 0) return 0.0;
    union {
        double d;
        uint64_t u;
    } u;
    
    int lz = 0;
    uint64_t temp = a;
    while ((temp & (1ULL << 63)) == 0) {
        temp <<= 1;
        lz++;
    }
    
    int exp = 63 - lz;
    uint64_t fraction;
    if (exp <= 52) {
        fraction = (a ^ (1ULL << exp)) << (52 - exp);
    } else {
        fraction = (a ^ (1ULL << exp)) >> (exp - 52);
    }
    
    u.u = (((uint64_t)(exp + 1023) & 0x7FF) << 52) | (fraction & 0xFFFFFFFFFFFFFull);
    return u.d;
}
#endif

/*==========================================================================
 * RISC-V 32-bit soft-float compiler-rt stubs
 *==========================================================================*/

#if defined(__riscv) && __riscv_xlen == 32

union df_bits {
    double d;
    uint64_t u;
};

#define DF_SIGN  0x8000000000000000ULL
#define DF_EXP   0x7FF0000000000000ULL
#define DF_MANT  0x000FFFFFFFFFFFFFULL
#define DF_HIDDEN 0x0010000000000000ULL
#define DF_BIAS  1023

static int df_isnan(uint64_t u) {
    return (u & DF_EXP) == DF_EXP && (u & DF_MANT) != 0;
}

static int df_isinf(uint64_t u) {
    return (u & DF_EXP) == DF_EXP && (u & DF_MANT) == 0;
}

static int df_iszero(uint64_t u) {
    return (u & ~DF_SIGN) == 0;
}

/* Comparisons: return -1/0/1 */

int __eqdf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u) || df_isnan(ub.u)) return 1;
    return ua.u == ub.u ? 0 : 1;
}

int __nedf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u) || df_isnan(ub.u)) return 1;
    return ua.u != ub.u ? 1 : 0;
}

int __gtdf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u) || df_isnan(ub.u)) return 0;
    int sa = (ua.u >> 63) & 1, sb = (ub.u >> 63) & 1;
    if (sa != sb) return sb - sa;
    return (ua.u > ub.u) ? 1 : (ua.u == ub.u ? 0 : -1);
}

int __gedf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u) || df_isnan(ub.u)) return -1;
    return __gtdf2(a, b) >= 0 ? 1 : -1;
}

int __ltdf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u) || df_isnan(ub.u)) return 1;
    int sa = (ua.u >> 63) & 1, sb = (ub.u >> 63) & 1;
    if (sa != sb) return sa - sb;
    return (ua.u < ub.u) ? -1 : (ua.u == ub.u ? 0 : 1);
}

int __ledf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u) || df_isnan(ub.u)) return 1;
    return __ltdf2(a, b) <= 0 ? -1 : 1;
}

/* Conversions */

float __truncdfsf2(double a) {
    union df_bits ua = {a};
    if (df_isnan(ua.u)) {
        uint32_t n = 0x7FC00000;
        float f;
        __builtin_memcpy(&f, &n, 4);
        return f;
    }
    if (df_isinf(ua.u)) {
        uint32_t n = ((ua.u >> 63) ? 0xFF800000 : 0x7F800000);
        float f;
        __builtin_memcpy(&f, &n, 4);
        return f;
    }
    if (df_iszero(ua.u)) {
        uint32_t n = (uint32_t)(ua.u >> 32) & 0x80000000;
        float f;
        __builtin_memcpy(&f, &n, 4);
        return f;
    }
    int exp = (int)((ua.u >> 52) & 0x7FF);
    uint64_t mant = ua.u & DF_MANT;
    if (exp == 0) mant |= 0; else mant |= DF_HIDDEN;
    int newexp = exp - DF_BIAS + 127;
    if (newexp >= 255) {
        uint32_t n = ((ua.u >> 63) ? 0xFF800000 : 0x7F800000);
        float f;
        __builtin_memcpy(&f, &n, 4);
        return f;
    }
    if (newexp <= 0) {
        uint32_t n = (uint32_t)(ua.u >> 32) & 0x80000000;
        float f;
        __builtin_memcpy(&f, &n, 4);
        return f;
    }
    uint32_t fmant = (uint32_t)(mant >> (52 - 23));
    uint32_t fu = ((uint32_t)(ua.u >> 32) & 0x80000000) | ((uint32_t)newexp << 23) | (fmant & 0x7FFFFF);
    float f;
    __builtin_memcpy(&f, &fu, 4);
    return f;
}

double __extendsfdf2(float a) {
    uint32_t fu;
    __builtin_memcpy(&fu, &a, 4);
    if ((fu & 0x7F800000) == 0x7F800000) {
        union df_bits u;
        if (fu & 0x7FFFFF) {
            u.u = ((uint64_t)(fu >> 31) << 63) | 0x7FF8000000000000ULL;
        } else {
            u.u = ((uint64_t)(fu >> 31) << 63) | 0x7FF0000000000000ULL;
        }
        return u.d;
    }
    if ((fu & 0x7F800000) == 0) {
        union df_bits u;
        u.u = (uint64_t)(fu >> 31) << 63;
        return u.d;
    }
    int exp = (fu >> 23) & 0xFF;
    uint32_t mant = fu & 0x7FFFFF;
    uint64_t dmant = (uint64_t)mant << (52 - 23);
    int newexp = exp - 127 + DF_BIAS;
    union df_bits u;
    u.u = ((uint64_t)(fu >> 31) << 63) | ((uint64_t)newexp << 52) | dmant;
    return u.d;
}

unsigned int __fixunsdfsi(double a) {
    union df_bits ua = {a};
    if (ua.u <= 0x3FF0000000000000ULL) return 0;
    if ((ua.u >> 63) & 1) return 0;
    int exp = (int)((ua.u >> 52) & 0x7FF) - DF_BIAS;
    if (exp > 31) return 0xFFFFFFFF;
    uint64_t mant = (ua.u & DF_MANT) | DF_HIDDEN;
    uint64_t result;
    if (exp > 52) result = mant << (exp - 52);
    else result = mant >> (52 - exp);
    return (unsigned int)result;
}

int __fixdfsi(double a) {
    union df_bits ua = {a};
    if (ua.u == 0x8000000000000000ULL) return 0;
    int sign = (ua.u >> 63) & 1;
    if (sign) {
        double pos = -a;
        uint64_t u;
        __builtin_memcpy(&u, &pos, 8);
        int exp = (int)((u >> 52) & 0x7FF) - DF_BIAS;
        if (exp < 0) return 0;
        if (exp > 31) return 0x80000000;
        uint64_t mant = (u & DF_MANT) | DF_HIDDEN;
        uint64_t val;
        if (exp > 52) val = mant << (exp - 52);
        else val = mant >> (52 - exp);
        return -(int)val;
    }
    int exp = (int)((ua.u >> 52) & 0x7FF) - DF_BIAS;
    if (exp < 0) return 0;
    if (exp > 31) return 0x7FFFFFFF;
    uint64_t mant = (ua.u & DF_MANT) | DF_HIDDEN;
    uint64_t val;
    if (exp > 52) val = mant << (exp - 52);
    else val = mant >> (52 - exp);
    return (int)val;
}

double __floatunsidf(unsigned int a) {
    if (a == 0) {
        union df_bits u;
        u.u = 0;
        return u.d;
    }
    uint64_t val = a;
    int lz = 0;
    uint64_t t = val;
    while ((t & (1ULL << 63)) == 0) { t <<= 1; lz++; }
    int exp = 63 - lz;
    uint64_t fraction;
    if (exp <= 52) fraction = (val ^ (1ULL << exp)) << (52 - exp);
    else fraction = (val ^ (1ULL << exp)) >> (exp - 52);
    union df_bits u;
    u.u = (((uint64_t)(exp + DF_BIAS) & 0x7FF) << 52) | (fraction & DF_MANT);
    return u.d;
}

/* Arithmetic */

double __adddf3(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u)) return a;
    if (df_isnan(ub.u)) return b;
    if (df_iszero(ua.u)) return b;
    if (df_iszero(ub.u)) return a;
    if (df_isinf(ua.u)) {
        if (df_isinf(ub.u) && ua.u != ub.u) {
            union df_bits nan;
            nan.u = 0x7FF8000000000000ULL;
            return nan.d;
        }
        return a;
    }
    if (df_isinf(ub.u)) return b;
    int sa = (ua.u >> 63) & 1, sb = (ub.u >> 63) & 1;
    int ea = (int)((ua.u >> 52) & 0x7FF), eb = (int)((ub.u >> 52) & 0x7FF);
    uint64_t ma = (ua.u & DF_MANT), mb = (ub.u & DF_MANT);
    if (ea) ma |= DF_HIDDEN; else ea = 1;
    if (eb) mb |= DF_HIDDEN; else eb = 1;
    uint64_t sign = 0;
    if (ea < eb || (ea == eb && ma < mb)) {
        int te = ea; ea = eb; eb = te;
        uint64_t tm = ma; ma = mb; mb = tm;
        int ts = sa; sa = sb; sb = ts;
    }
    int exp = ea;
    int shift = ea - eb;
    if (shift > 64) shift = 64;
    mb >>= shift;
    if (sa == sb) {
        ma += mb;
        if (ma & (1ULL << 53)) {
            ma >>= 1;
            exp++;
        }
    } else {
        if (ma < mb) { uint64_t t = ma; ma = mb; mb = t; }
        ma -= mb;
        if (ma == 0) { union df_bits z; z.u = 0; return z.d; }
        while ((ma & DF_HIDDEN) == 0) {
            ma <<= 1;
            exp--;
        }
        ma &= ~DF_HIDDEN;
    }
    sign = (uint64_t)sa << 63;
    if (exp >= 0x7FF) {
        union df_bits inf;
        inf.u = sign | 0x7FF0000000000000ULL;
        return inf.d;
    }
    if (exp <= 0) {
        ma >>= (1 - exp);
        exp = 0;
    }
    union df_bits r;
    r.u = sign | ((uint64_t)exp << 52) | (ma & DF_MANT);
    return r.d;
}

double __subdf3(double a, double b) {
    union df_bits ub = {b};
    ub.u ^= DF_SIGN;
    return __adddf3(a, ub.d);
}

double __muldf3(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u)) return a;
    if (df_isnan(ub.u)) return b;
    if (df_isinf(ua.u)) {
        if (df_iszero(ub.u)) { union df_bits n; n.u = 0x7FF8000000000000ULL; return n.d; }
        union df_bits r; r.u = (ua.u ^ ub.u) & DF_SIGN; r.u |= 0x7FF0000000000000ULL; return r.d;
    }
    if (df_isinf(ub.u)) {
        if (df_iszero(ua.u)) { union df_bits n; n.u = 0x7FF8000000000000ULL; return n.d; }
        union df_bits r; r.u = (ua.u ^ ub.u) & DF_SIGN; r.u |= 0x7FF0000000000000ULL; return r.d;
    }
    if (df_iszero(ua.u) || df_iszero(ub.u)) {
        union df_bits z;
        z.u = (ua.u ^ ub.u) & DF_SIGN;
        return z.d;
    }
    int result_sign = ((ua.u >> 63) & 1) ^ ((ub.u >> 63) & 1);
    int ea = (int)((ua.u >> 52) & 0x7FF);
    int eb = (int)((ub.u >> 52) & 0x7FF);
    uint64_t ma = (ua.u & DF_MANT) | DF_HIDDEN;
    uint64_t mb = (ub.u & DF_MANT) | DF_HIDDEN;
    /* 64x64 -> 128 using 32-bit limbs */
    uint32_t a0 = (uint32_t)ma, a1 = (uint32_t)(ma >> 32);
    uint32_t b0 = (uint32_t)mb, b1 = (uint32_t)(mb >> 32);
    uint64_t p00 = (uint64_t)a0 * b0;
    uint64_t p01 = (uint64_t)a0 * b1;
    uint64_t p10 = (uint64_t)a1 * b0;
    uint64_t p11 = (uint64_t)a1 * b1;
    uint64_t lo = p00;
    uint64_t mid = p01 + p10 + (p00 >> 32);
    uint64_t hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);
    lo = (mid << 32) | (uint32_t)lo;
    /* Determine if product has bit at position 105 (hi bit 41) */
    int exp_adj;
    uint64_t mant;
    if (hi & 0x0000020000000000ULL) {
        exp_adj = 53;
        mant = (hi << 11) | (lo >> 53);
    } else {
        exp_adj = 52;
        mant = (hi << 12) | (lo >> 52);
    }
    int exp = ea + eb - DF_BIAS + exp_adj;
    if (exp >= 0x7FF) {
        union df_bits inf;
        inf.u = ((uint64_t)result_sign << 63) | 0x7FF0000000000000ULL;
        return inf.d;
    }
    if (exp <= 0) {
        mant >>= (1 - exp);
        exp = 0;
    }
    union df_bits r;
    r.u = ((uint64_t)result_sign << 63) | ((uint64_t)exp << 52) | (mant & DF_MANT);
    return r.d;
}

double __divdf3(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    if (df_isnan(ua.u)) return a;
    if (df_isnan(ub.u)) return b;
    if (df_isinf(ua.u) && df_isinf(ub.u)) {
        union df_bits n; n.u = 0x7FF8000000000000ULL; return n.d;
    }
    if (df_iszero(ua.u) && df_iszero(ub.u)) {
        union df_bits n; n.u = 0x7FF8000000000000ULL; return n.d;
    }
    if (df_iszero(ua.u)) {
        union df_bits z; z.u = (ua.u ^ ub.u) & DF_SIGN; return z.d;
    }
    if (df_isinf(ua.u)) {
        union df_bits r; r.u = (ua.u ^ ub.u) & DF_SIGN; r.u |= 0x7FF0000000000000ULL; return r.d;
    }
    if (df_isinf(ub.u)) {
        union df_bits z; z.u = (ua.u ^ ub.u) & DF_SIGN; return z.d;
    }
    if (df_iszero(ub.u)) {
        union df_bits r; r.u = (ua.u ^ ub.u) & DF_SIGN; r.u |= 0x7FF0000000000000ULL; return r.d;
    }
    int sa = (ua.u >> 63) & 1, sb = (ub.u >> 63) & 1;
    int result_sign = sa ^ sb;
    int ea = (int)((ua.u >> 52) & 0x7FF), eb = (int)((ub.u >> 52) & 0x7FF);
    uint64_t ma = (ua.u & DF_MANT), mb = (ub.u & DF_MANT);
    if (ea) ma |= DF_HIDDEN;
    if (eb) mb |= DF_HIDDEN;
    int exp = ea - eb + DF_BIAS;
    if (ma < mb) { ma <<= 1; exp--; }
    uint64_t q = 0;
    uint64_t rv = ma;
    for (int i = 0; i < 53; i++) {
        q <<= 1;
        if (rv >= mb) { rv -= mb; q |= 1; }
        rv <<= 1;
    }
    if (exp >= 0x7FF) {
        union df_bits inf;
        inf.u = ((uint64_t)result_sign << 63) | 0x7FF0000000000000ULL;
        return inf.d;
    }
    if (exp <= 0) {
        q >>= (1 - exp);
        exp = 0;
    }
    union df_bits r;
    r.u = ((uint64_t)result_sign << 63) | ((uint64_t)exp << 52) | (q & DF_MANT);
    return r.d;
}

int __unorddf2(double a, double b) {
    union df_bits ua = {a}, ub = {b};
    return df_isnan(ua.u) || df_isnan(ub.u);
}

double __floatsidf(int a) {
    if (a == 0) { union df_bits z; z.u = 0; return z.d; }
    uint64_t sign = 0;
    uint64_t val;
    if (a < 0) { sign = DF_SIGN; val = (uint64_t)-(int64_t)a; }
    else { val = (uint64_t)a; }
    int lz = 0;
    uint64_t t = val;
    while ((t & (1ULL << 63)) == 0) { t <<= 1; lz++; }
    int exp = 63 - lz;
    uint64_t fraction;
    if (exp <= 52) fraction = (val ^ (1ULL << exp)) << (52 - exp);
    else fraction = (val ^ (1ULL << exp)) >> (exp - 52);
    union df_bits u;
    u.u = sign | (((uint64_t)(exp + DF_BIAS) & 0x7FF) << 52) | (fraction & DF_MANT);
    return u.d;
}

uint64_t __fixunsdfdi(double a) {
    union df_bits ua = {a};
    if (ua.u <= 0x3FF0000000000000ULL) return 0;
    if ((ua.u >> 63) & 1) return 0;
    int exp = (int)((ua.u >> 52) & 0x7FF) - DF_BIAS;
    if (exp > 63) return 0xFFFFFFFFFFFFFFFFULL;
    uint64_t mant = (ua.u & DF_MANT) | DF_HIDDEN;
    if (exp > 52) return mant << (exp - 52);
    else return mant >> (52 - exp);
}

int64_t __fixdfdi(double a) {
    union df_bits u = {a};
    int sign = (u.u >> 63) ? -1 : 1;
    int exp = (int)((u.u >> 52) & 0x7FF) - DF_BIAS;
    uint64_t fraction = (u.u & DF_MANT) | DF_HIDDEN;
    if (exp < 0) return 0;
    if (exp > 63) return (sign == 1) ? 0x7FFFFFFFFFFFFFFFll : 0x8000000000000000ll;
    uint64_t val;
    if (exp > 52) val = fraction << (exp - 52);
    else val = fraction >> (52 - exp);
    return sign * (int64_t)val;
}

double __floatdidf(int64_t a) {
    union df_bits u;
    if (a == 0) { u.u = 0; return u.d; }
    uint64_t sign = 0;
    uint64_t val;
    if (a < 0) { sign = DF_SIGN; val = (uint64_t)(-(int64_t)a); }
    else { val = (uint64_t)a; }
    int lz = 0;
    uint64_t temp = val;
    while ((temp & (1ULL << 63)) == 0) { temp <<= 1; lz++; }
    int exp = 63 - lz;
    uint64_t fraction;
    if (exp <= 52) fraction = (val ^ (1ULL << exp)) << (52 - exp);
    else fraction = (val ^ (1ULL << exp)) >> (exp - 52);
    u.u = sign | (((uint64_t)(exp + DF_BIAS) & 0x7FF) << 52) | (fraction & DF_MANT);
    return u.d;
}

double __floatundidf(uint64_t a) {
    union df_bits u;
    if (a == 0) { u.u = 0; return u.d; }
    int lz = 0;
    uint64_t temp = a;
    while ((temp & (1ULL << 63)) == 0) { temp <<= 1; lz++; }
    int exp = 63 - lz;
    uint64_t fraction;
    if (exp <= 52) fraction = (a ^ (1ULL << exp)) << (52 - exp);
    else fraction = (a ^ (1ULL << exp)) >> (exp - 52);
    u.u = (((uint64_t)(exp + DF_BIAS) & 0x7FF) << 52) | (fraction & DF_MANT);
    return u.d;
}

#endif
