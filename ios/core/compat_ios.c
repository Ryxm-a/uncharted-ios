/* compat_ios.c — iOS implementations of the Linux-only surfaces the PC runtime uses.
 * Everything here is deliberately small and boring: strings, fds, mmap, threads.
 * Details: docs/02-ARCHITECTURE.md (memory) and docs/03-CPU_FEX.md (TLS/faults). */
#include "platform_ios.h"
#include "compat_ios.h"

#include <assert.h>
#include <stdarg.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/statvfs.h>

/* ---------------------------------------------------------- memfd_create shim */
int bbi_memfd_create(const char *name, unsigned int flags) {
    (void)flags;
    char path[NAME_MAX];
    unsigned tid = 0;
    pthread_threadid_np(NULL, &tid);
    snprintf(path, sizeof path, "/bbios-%s-%u", name ? name : "mem", tid);
    int fd = shm_open(path, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return fd;
    shm_unlink(path);           /* fd lives on; the name is throwaway */
    return fd;
}

/* ------------------------------------------------- arch_prctl: FEX owns guest TLS */
int bbi_arch_set_gs(uint64_t base) {
    (void)base;
    return 0;
}

long bbi_syscall(long number, ...) {
    if (number == (long)BB_SYS_ARCH_PRCTL) {
        va_list ap;
        va_start(ap, number);
        long op  = va_arg(ap, long);
        long raw = va_arg(ap, long);
        va_end(ap);
        if (op == ARCH_SET_GS) { bbi_arch_set_gs((uint64_t)raw); return 0; }
        if (op == ARCH_GET_FS || op == ARCH_GET_GS) { return 0; }
        errno = EINVAL;
        return -1;
    }
    /* Anything else reaching here is an upstream regression we want loudly: */
    fprintf(stderr, "bbios: unsupported syscall(%ld) - runtime regression\n", number);
    errno = ENOSYS;
    return -1;
}

/* ------------------------------------------------------- sched_getaffinity shim */
long bbi_sched_getaffinity_impl(pid_t pid, size_t sz, void *vset) {
    (void)pid; (void)sz;
    cpu_set_t *set = (cpu_set_t *)vset;
    if (set) set->_bbmask = ~0UL;      /* all cores; filter via BbThreads policy */
    return 0;
}

/* --------------------------------------------------- Linux-shaped getdents shim */
int64_t bbi_getdents(int fd, char *buffer, uint64_t size) {
    uint64_t out = 0;
    char path[PATH_MAX];
    if (fcntl(fd, F_GETPATH, path) != 0) { errno = EBADF; return -1; }
    DIR *dir = opendir(path);
    if (!dir) return -errno;
    while (out + 304 < size) {
        struct dirent *de = readdir(dir);
        if (!de) break;
        unsigned char type = de->d_type == DT_DIR  ? 4
                           : de->d_type == DT_LNK  ? 10
                           : de->d_type == DT_REG  ? 8
                           : 0;
        size_t reclen = (19 + strlen(de->d_name) + 1 + 7) & ~7ULL;
        memset(buffer + out, 0, reclen);
        uint64_t ino = (uint64_t)de->d_ino;
        memcpy(buffer + out + 0,  &ino, 8);
        uint64_t off = out + reclen;
        memcpy(buffer + out + 8,  &off, 8);
        uint16_t rl = (uint16_t)reclen;
        memcpy(buffer + out + 16, &rl, 2);
        memcpy(buffer + out + 18, &type, 1);
        strcpy(buffer + out + 19, de->d_name);
        out += reclen;
    }
    closedir(dir);
    return (int64_t)out;
}

/* -------------------------------------------------------- JIT capability probe */
int bbi_jit_supported(void) {
    void *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_ANONYMOUS | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) return 0;
    pthread_jit_write_protect_np(0);
    memset(p, 0x1f, 8);
    pthread_jit_write_protect_np(1);
    munmap(p, 4096);
    return 1;
}

void bbi_app_backgrounded(int entering) { (void)entering; }
