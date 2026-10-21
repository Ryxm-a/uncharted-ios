/* platform_ios.h — force-included on every engine TU when BB_PLATFORM_IOS=1.
 * Scope strictly limited to OS-ABI compatibility (no vendor glue, no build logic). */
#pragma once
#ifdef BB_PLATFORM_IOS
#ifndef BB_PLATFORM_IOS_IMPL
#define BB_PLATFORM_IOS_IMPL 1

#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/shm.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include <dirent.h>

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MAP_NORESERVE
#define MAP_NORESERVE 0    /* iOS commits on first write; acceptable (docs/02) */
#endif
#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE MAP_FIXED
#endif

/* The runtime builds a Linux-shaped `struct dirent64` buffer; helpers below. */
#ifndef DT_DIR
#define DT_DIR 4
#endif
#ifndef DT_REG
#define DT_REG 8
#endif
#ifndef DT_LNK
#define DT_LNK 10
#endif
#ifndef DT_UNKNOWN
#define DT_UNKNOWN 0
#endif

/* ---- memfd_create shim (linux-only upstream surface) ---- */
extern int bbi_memfd_create(const char *name, unsigned int flags);
#define memfd_create(name, flags) bbi_memfd_create((name), (flags))

/* ---- syscall interception: only SYS_arch_prctl exists in the compiled subsurface ----
 * runtime_thread.c (Linux path) does `syscall(SYS_arch_prctl, ARCH_SET_GS, base)`.
 * On iOS FEX owns guest TLS: our dispatcher short-circuits exactly that one number. */
#define SYS_arch_prctl BB_SYS_ARCH_PRCTL
#define BB_SYS_ARCH_PRCTL ((long)166)          /* dispatcher key; Linux x86 numbers vary */
#define ARCH_SET_GS 0x1001
#define ARCH_GET_FS 0x1003
#define ARCH_GET_GS 0x1004
extern long bbi_syscall(long number, ...);
#define syscall(num, ...) bbi_syscall((num), ##__VA_ARGS__)

/* ---- sched_getaffinity etc. (cover BbThreads on Apple) ---- */
typedef struct { unsigned long _bbmask; } cpu_set_t;
extern long bbi_sched_getaffinity_impl(pid_t pid, size_t sz, void *mask);
#define sched_getaffinity(...) bbi_sched_getaffinity_impl(__VA_ARGS__)
#define CPU_COUNT(m) (__builtin_popcountl(((cpu_set_t *)(m))->_bbmask))
#define CPU_ISSET(i, m) (((cpu_set_t *)(m))->_bbmask & (1UL << ((i) & 63)))
#define CPU_SET(i, m) (((cpu_set_t *)(m))->_bbmask |= (1UL << ((i) & 63)))
#define CPU_ZERO(m) (((cpu_set_t *)(m))->_bbmask = 0)

#ifndef CLOCK_REALTIME_COARSE
#define CLOCK_REALTIME_COARSE CLOCK_REALTIME
#endif

/* JIT availability helpers exposed to the launcher (docs/03 §8). */
#define BB_JIT_PROBE 1

#endif /* BB_PLATFORM_IOS_IMPL */
#endif /* BB_PLATFORM_IOS */
