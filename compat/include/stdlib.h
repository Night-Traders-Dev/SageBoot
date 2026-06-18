#ifndef COMPAT_STDLIB_H
#define COMPAT_STDLIB_H
#include <stddef.h>
#define RAND_MAX 32767
void* malloc(size_t size);
void* realloc(void* ptr, size_t size);
void* calloc(size_t nmemb, size_t size);
void free(void* ptr);
void abort(void) __attribute__((noreturn));
void exit(int status) __attribute__((noreturn));
double strtod(const char* nptr, char** endptr);
double atof(const char* nptr);
int abs(int j);
int rand(void);
char* getenv(const char* name);
int system(const char* command);
#endif
