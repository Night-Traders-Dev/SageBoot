#ifndef COMPAT_SYS_STAT_H
#define COMPAT_SYS_STAT_H
struct stat {
    int st_size;
};
int stat(const char* pathname, struct stat* statbuf);
#endif
