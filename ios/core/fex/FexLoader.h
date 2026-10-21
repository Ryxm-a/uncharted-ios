/* fex/FexLoader.h — FEX CPU-engine integration point (docs/03-CPU_FEX.md). */
#ifndef BB_FEX_LOADER_H
#define BB_FEX_LOADER_H
#include <stddef.h>

#if defined(BB_PLATFORM_IOS)
void bbi_fex_run_guest(const void *image, size_t size,
                       const char *app0_dir, const char *user_dir,
                       void (*on_log)(const char *, void *), void *user);
int  bbi_fex_can_boot(void);   /* returns 1 when libFEXCore is linked and usable */
#else
static inline void bbi_fex_run_guest(const void *i, size_t s, const char *a, const char *u,
                                     void (*l)(const char *, void *), void *user) {
    (void)i; (void)s; (void)a; (void)u; (void)l; (void)user;
}
static inline int bbi_fex_can_boot(void) { return 0; }
#endif
#endif
