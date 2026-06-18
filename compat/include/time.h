#ifndef COMPAT_TIME_H
#define COMPAT_TIME_H
typedef long time_t;
typedef long clock_t;
#define CLOCKS_PER_SEC 1000000L
struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
};
struct timespec {
    long tv_sec;
    long tv_nsec;
};
time_t time(time_t* tloc);
clock_t clock(void);
int nanosleep(const struct timespec* req, struct timespec* rem);
#endif
