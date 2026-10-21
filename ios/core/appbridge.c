/* appbridge.c — implements the bbi_public.h surface for the SwiftUI launcher.
 * Pure C, no UIKit: keep this file engine-side to avoid recompiling the app for engine
 * changes during bring-up. */
#include "bbi_public.h"
#include "platform_ios.h"
#include "compat_ios.h"

#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

static pthread_t game_thread;
static volatile int running_game;
static void (*s_event_user_cb)(const char *, const char *, void *);
static void *s_event_user;

struct LaunchArgs {
    char game_key[8];
    char game_dir[1024];
    char user_dir[1024];
    char boot_file[128];
};

static void *launch_thread(void *raw) {
    struct LaunchArgs *a = raw;
    extern int bbi_run_game(const char *, const char *, const char *);
    running_game = 1;
    if (s_event_user_cb) s_event_user_cb("state", "starting", s_event_user);
    int rc = bbi_run_game(a->game_dir, a->user_dir, a->boot_file);
    running_game = 0;
    if (s_event_user_cb) {
        char buf[32];
        snprintf(buf, sizeof buf, "exit:%d", rc);
        s_event_user_cb("exit", buf, s_event_user);
    }
    free(a);
    return NULL;
}

int bbi_start_game(const char *game_key, const char *game_dir, const char *user_dir,
                   const char *boot_file,
                   void (*on_event)(const char *, const char *, void *), void *user) {
    if (running_game) return EALREADY;
    s_event_user_cb = on_event;
    s_event_user    = user;
    struct LaunchArgs *a = calloc(1, sizeof *a);
    if (!a) return ENOMEM;
    snprintf(a->game_key,   sizeof a->game_key,   "%s", game_key   ? game_key   : "u1");
    snprintf(a->game_dir,   sizeof a->game_dir,   "%s", game_dir   ? game_dir   : ".");
    snprintf(a->user_dir,   sizeof a->user_dir,   "%s", user_dir   ? user_dir   : ".");
    snprintf(a->boot_file,  sizeof a->boot_file,  "%s", boot_file  ? boot_file  : "boot-linked.bin");
    if (pthread_create(&game_thread, NULL, launch_thread, a) != 0) {
        free(a);
        return errno;
    }
    pthread_detach(game_thread);
    return 0;
}

void bbi_stop_game(void)          { running_game = 0; }
void bbi_request_exec(const char *game_key) { (void)game_key; /* docs/03 §8 roadmap */ }
void bbi_set_env(const char *k, const char *v) { if (k && v) setenv(k, v, 1); }

int bbi_dump_looks_valid(const char *dir, const char *exe) {
    if (!dir || !exe) return 0;
    char path[512];
    struct stat st;
    snprintf(path, sizeof path, "%s/%s", dir, exe);
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) return 0;
    unsigned char magic[4] = {0};
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    ssize_t got = read(fd, magic, 4);
    close(fd);
    if (got != 4) return 0;
    /* Decrypted PS4 executable: ELF magic 7f 45 4c 46 */
    return magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
}

long long bbi_dump_free_space(void) {
    const char *home = getenv("HOME");
    if (!home) home = "/";
    struct statvfs st;
    if (statvfs(home, &st) == 0)
        return (long long)st.f_bavail * (long long)st.f_frsize;
    return -1;
}
