#ifndef COMPAT_STDIO_H
#define COMPAT_STDIO_H
#include <stddef.h>
typedef struct FILE FILE;
#define stderr ((FILE*)2)
#define stdout ((FILE*)1)
#define stdin ((FILE*)0)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
int fprintf(FILE* stream, const char* format, ...);
int printf(const char* format, ...);
int snprintf(char* str, size_t size, const char* format, ...);
int sprintf(char* str, const char* format, ...);
int fputs(const char* s, FILE* stream);
int fputc(int c, FILE* stream);
char* fgets(char* s, int size, FILE* stream);
FILE* fopen(const char* pathname, const char* mode);
int fclose(FILE* stream);
size_t fread(void* ptr, size_t size, size_t nmemb, FILE* stream);
size_t fwrite(const void* ptr, size_t size, size_t nmemb, FILE* stream);
int fseek(FILE* stream, long offset, int whence);
long ftell(FILE* stream);

/* The Sage runtime exposes a shell-command helper that is implemented with
 * popen/pclose. A bootloader has no shell and no process to spawn, so these are
 * declared here and stubbed to fail in compat.c. Without them the emitted C
 * does not compile for any freestanding target. */
FILE* popen(const char* command, const char* type);
int pclose(FILE* stream);
#endif
