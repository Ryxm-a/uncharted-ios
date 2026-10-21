/* start_ios.c — iOS replacement for upstream `src/probe.c`'s host startup path.
 *
 * Why probe.c is excluded from the iOS build (docs/03-CPU_FEX.md):
 *   1. probe.c emits x86-64 trap stubs and rewrites `mov rax,fs:[0]` — meaningless on ARM64,
 *      every guest instruction executes under FEX anyway.
 *   2. probe.c installs host signal/VEH fault handlers; on iOS faults come through FEXCore
 *      callbacks plus the page-protection path of runtime_memory_gpu_protect.
 *   3. probe.c enters guest code with hand-written x86 assembly (`enter_on_stack`);
 *      on iOS FEXCore::Context::RunThread enters guest code.
 *
 * Two build modes (docs/01 Phase table):
 *   BB_FULL_ENGINE  — upstream C runtime + FEX core are linked; full boot path below.
 *   (lite default)  — shim layer only; Play() validates the boot image and reports
 *                     honestly that engine bring-up is pending. Never half-boots. */
#include "platform_ios.h"
#include "compat_ios.h"
#include "fex/FexLoader.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#ifdef BB_FULL_ENGINE
/* Extern surface from the upstream C runtime (same contracts as runtime.h): */
extern void  runtime_file_configure(const char *app0, const char *user);
extern int   runtime_file_mount(const char *guest, const char *host);
extern void  runtime_set_main_tls(const void *data, uint64_t filesz, uint64_t memsz, uint64_t align);
extern int   vulkan_smoke(void);
extern void *runtime_image_map(size_t size, int prot);
#endif

extern int bbi_boot_image_parse(const void *blob, size_t size);   /* below (Phase-1 stub) */

int bbi_boot_load(const char *path, void **out_image, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0) { fclose(f); errno = EIO; return -1; }
    void *img = malloc((size_t)len);
    if (!img) { fclose(f); errno = ENOMEM; return -1; }
    size_t got = fread(img, 1, (size_t)len, f);
    fclose(f);
    if (got != (size_t)len) { free(img); errno = EIO; return -1; }
    *out_image = img;
    *out_size  = (size_t)got;
    return 0;
}

static void boot_log(const char *line, void *user) {
    (void)user;
    fprintf(stderr, "[bbios] %s\n", line);
}

/* Phase-1 stub: the real `bbi_boot_image_parse` (BBPROBE5 header + segment/relocation/
 * import tables + per-module TLS setup, mirroring probe.c) lands in the image-loader
 * bring-up. This stub validates the "BBPROBE5" magic only — enough for launcher plumbing. */
int bbi_boot_image_parse(const void *blob, size_t size) {
    if (!blob || size < 16) return -1;
    return memcmp(blob, "BBPROBE5", 8) == 0 ? 0 : -1;
}

#ifdef BB_FULL_ENGINE
int bbi_run_game(const char *game_dir, const char *user_dir, const char *boot_file) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s", game_dir, boot_file);

    void *image = NULL;
    size_t size = 0;
    if (bbi_boot_load(path, &image, &size) != 0) {
        fprintf(stderr, "STOP: cannot load %s\n", path);
        return 21;
    }
    if (bbi_boot_image_parse(image, size) != 0) {
        fprintf(stderr, "STOP: boot image rejected (BBPROBE5 parse)\n");
        free(image);
        return 21;
    }

    runtime_file_configure(game_dir, user_dir);
    runtime_file_mount("/app0",   game_dir);
    runtime_file_mount("/hostapp", game_dir);
    runtime_file_mount("/data",   user_dir);
    runtime_file_mount("/temp0",  user_dir);

    /* Guest execution: FEX owns TLS, faults, and code generation (docs/03). */
    bbi_fex_run_guest(image, size, game_dir, user_dir, boot_log, NULL);
    return 0;
}
#else  /* lite build: self-contained, no upstream symbols referenced */
int bbi_run_game(const char *game_dir, const char *user_dir, const char *boot_file) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s", game_dir, boot_file);

    void *image = NULL;
    size_t size = 0;
    if (bbi_boot_load(path, &image, &size) != 0) {
        fprintf(stderr, "STOP: cannot load %s\n", path);
        return 21;
    }
    if (bbi_boot_image_parse(image, size) != 0) {
        fprintf(stderr, "STOP: boot image rejected (BBPROBE5 parse)\n");
        free(image);
        return 21;
    }
    char msg[512];
    snprintf(msg, sizeof msg,
             "STOP: lite build — boot image OK (%zu bytes, user dir %s), but the engine "
             "core is not linked yet. Build in full mode (docs/01 Phase 1) to run games.",
             size, user_dir);
    boot_log(msg, NULL);
    free(image);
    return 21;
}
#endif

/* Vulkan canary for the Phase-1 bring-up (docs/04): PASS/FAIL console check. */
int bbi_vulkan_smoke_with_driver(const char *icd_json) {
#ifdef BB_FULL_ENGINE
    setenv("VK_ICD_FILENAMES", icd_json ? icd_json : "MoltenVK_icd.json", 1);
    return vulkan_smoke();
#else
    (void)icd_json;
    boot_log("lite build: vulkan_smoke available only in full mode", NULL);
    return 0;
#endif
}
