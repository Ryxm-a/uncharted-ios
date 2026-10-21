/* include/bbi_public.h — the C ABI the SwiftUI launcher calls into (bridging header). */
#ifndef BBI_PUBLIC_H
#define BBI_PUBLIC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*bbi_event_cb)(const char *kind, const char *payload, void *user);

/* Lifecycle (docs/05): launches the engine thread in-process. */
int  bbi_start_game(const char *game_key,     /* "u1" | "u2" | "u3"   */
                    const char *game_dir,     /* imported dump folder */
                    const char *user_dir,     /* Documents/user       */
                    const char *boot_file,    /* boot-linked.bin      */
                    bbi_event_cb on_event,
                    void *user);
void bbi_stop_game(void);

/* In-process relaunch contract (sceSystemServiceLoadExec equivalent). */
void bbi_request_exec(const char *game_key);

/* JIT availability probe — docs/03 section 8 — 0 when RWX+MAP_JIT fails. */
int  bbi_jit_supported(void);

/* Phase-1 canary: standalone Vulkan fill-buffer test unless disabled. */
int  bbi_vulkan_smoke_with_driver(const char *icd_json);

/* Engine env contract (upstream run.py names) set before launch. */
void bbi_set_env(const char *k, const char *v);

/* Dump validation helpers used before a multi-GB copy: */
int       bbi_dump_looks_valid(const char *dir, const char *exe);
long long bbi_dump_free_space(void);

#ifdef __cplusplus
}
#endif
#endif /* BBI_PUBLIC_H */
