#ifndef COMPAT_PTHREAD_H
#define COMPAT_PTHREAD_H
typedef unsigned long pthread_t;
typedef struct { int dummy; } pthread_mutex_t;
typedef struct { int dummy; } pthread_cond_t;
typedef struct { int dummy; } pthread_attr_t;
int pthread_create(pthread_t* thread, const pthread_attr_t* attr, void* (*start_routine)(void*), void* arg);
int pthread_join(pthread_t thread, void** retval);
pthread_t pthread_self(void);
int pthread_mutex_init(pthread_mutex_t* mutex, const void* attr);
int pthread_mutex_lock(pthread_mutex_t* mutex);
int pthread_mutex_unlock(pthread_mutex_t* mutex);
int pthread_mutex_destroy(pthread_mutex_t* mutex);
#endif
