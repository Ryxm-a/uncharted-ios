/* compat_ios.h — declarations shared across the iOS core additions. */
#pragma once
#ifdef BB_PLATFORM_IOS
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

/* syscall dispatcher (platform_ios.h forces all syscall() calls here) */
long bbi_syscall(long number, ...);

int      bbi_memfd_create(const char *name, unsigned int flags);
int      bbi_arch_set_gs(uint64_t base);
long     bbi_sched_getaffinity_impl(pid_t pid, size_t sz, void *mask);
int64_t  bbi_getdents(int fd, char *buffer, uint64_t size);

/* JIT availability probe (docs/03 section 8): true when FEX-class RWX pages work. */
int bbi_jit_supported(void);

/* App lifecycle hints the renderer adapter listens to. */
void bbi_app_backgrounded(int entering);
#endif
