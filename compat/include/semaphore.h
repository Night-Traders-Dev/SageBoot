#ifndef COMPAT_SEMAPHORE_H
#define COMPAT_SEMAPHORE_H
typedef struct { int dummy; } sem_t;
int sem_init(sem_t* sem, int pshared, unsigned int value);
int sem_wait(sem_t* sem);
int sem_trywait(sem_t* sem);
int sem_post(sem_t* sem);
int sem_destroy(sem_t* sem);
#endif
