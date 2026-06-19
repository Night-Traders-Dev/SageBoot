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
  #define HEAP_START 0x04000000 // 64MB mark (above kernel ELF buffer)
  #define HEAP_MAX   0x06000000
#elif defined(__riscv)
  #define HEAP_START 0x84000000 // 64MB mark (above kernel ELF buffer)
  #define HEAP_MAX   0x86000000
#elif defined(__aarch64__)
  #define HEAP_START 0x44000000 // 64MB mark (above kernel ELF buffer)
  #define HEAP_MAX   0x46000000
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

#elif defined(__riscv)

#define RV_UART_BASE 0x10000000 // QEMU RV64 Virt 16550A UART

void compat_uart_putc(char c) {
    volatile uint8_t* lsr = (volatile uint8_t*)(RV_UART_BASE + 5);
    while ((*lsr & 0x20) == 0); // Wait for THRE
    volatile uint8_t* thr = (volatile uint8_t*)(RV_UART_BASE + 0);
    *thr = (uint8_t)c;
}

char compat_uart_getc(void) {
    volatile uint8_t* lsr = (volatile uint8_t*)(RV_UART_BASE + 5);
    while ((*lsr & 0x01) == 0); // Wait for DR
    volatile uint8_t* rbr = (volatile uint8_t*)(RV_UART_BASE + 0);
    return (char)*rbr;
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

static void long_to_str(char* buf, long long val, int base) {
    char tmp[64];
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
    unsigned long long uval = (unsigned long long)val;
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

static void int_to_str(char* buf, int val, int base) {
    long_to_str(buf, val, base);
}

int vsnprintf(char* str, size_t size, const char* format, va_list ap) {
    size_t written = 0;
    while (*format && written < size - 1) {
        if (*format == '%') {
            format++;
            int is_long_long = 0;
            if (*format == 'l') {
                format++;
                if (*format == 'l') {
                    format++;
                    is_long_long = 1;
                } else {
                    // Just single 'l', treat as long (same size as int or long long depending on target, but we'll fall back to standard)
                    // For simplicity, do nothing special, format will be 'd' next
                }
            }
            if (*format == 'd') {
                char buf[64];
                if (is_long_long) {
                    long long val = va_arg(ap, long long);
                    long_to_str(buf, val, 10);
                } else {
                    int val = va_arg(ap, int);
                    long_to_str(buf, val, 10);
                }
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
                char buf[64];
                if (is_long_long) {
                    long long val = va_arg(ap, long long);
                    long_to_str(buf, val, 16);
                } else {
                    int val = va_arg(ap, int);
                    long_to_str(buf, val, 16);
                }
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
#elif defined(__riscv)
    __asm__ volatile("rdtime %0" : "=r"(count));
#elif defined(__aarch64__)
    __asm__ volatile("mrs %0, cntpct_el0" : "=r"(count));
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
