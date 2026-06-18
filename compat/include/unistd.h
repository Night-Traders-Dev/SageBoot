#ifndef COMPAT_UNISTD_H
#define COMPAT_UNISTD_H
#include <stddef.h>
typedef int ssize_t;
int close(int fd);
ssize_t read(int fd, void* buf, size_t count);
ssize_t write(int fd, const void* buf, size_t count);
unsigned int sleep(unsigned int seconds);
#endif
