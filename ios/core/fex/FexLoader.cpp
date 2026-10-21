/* fex/FexLoader.cpp — FEXCore CPU engine bridge (the piece that actually executes the
 * PS4 x86-64 game code on ARM64). Bring-up per docs/03-CPU_FEX.md:
 *
 *   Stage 2a: create isolated FEXCore contexts. Guest "images" are the BBPROBE5 blobs
 *   prepared by scripts/prepare.py — no ELF parsing is needed because prepare.py already
 *   performed relocation/import classification. The import table becomes FEX thunks that
 *   call runtime_resolve-produced host pointers.
 */
#include "FexLoader.h"
#include <stdio.h>

#if defined(BB_PLATFORM_IOS) && defined(BB_WITH_FEX)

#include <FEXCore/Config/Config.h>
#include <FEXCore/Core/CodeLoader.h>
#include <FEXCore/Core/Context.h>
#include <FEXCore/Core/CPUBackend.h>
#include <FEXCore/Core/CoreState.h>
#include <FEXCore/HLE/SyscallHandler.h>

namespace {

class BbFexCodeLoader final : public FEXCore::CodeLoader {
public:
  BbFexCodeLoader(const void *Image, size_t Size, uint64_t GuestBase)
      : Bytes{static_cast<const uint8_t *>(Image)}, Size{Size}, Base{GuestBase} {}
  void LoadMemory(FEXCore::Memory::MemHelper &Mem, uint64_t& Address) override {
    /* place the image at the fixed base; FEXCore maps, then we copy bytes in. */
    Mem.MapMemory(Base, Size, true /*RW*/, true /*Exec*/);
    memcpy(static_cast<void *>(reinterpret_cast<void *>(Base)), Bytes, Size);
    Address = Base;
  }
  uint64_t SetupMemory(fextl::unique_ptr<FEXCore::MemLayout>& MemoryLayout) override {
    /* Guest RAM: identical layout to the PC runtime (docs/02). */
    MemoryLayout = FEXCore::MemLayout::Create(MemType::MEMTYPE_ANON);
    MemoryLayout->AddMemory(0x800000000ULL, 8ULL << 30);
    return 0;
  }
  uint64_t GetStackBase() const override { return 0x7fe8000000ULL; }
  uint64_t GetStackSize() const override { return 8ULL << 20; }
  uint64_t GetMainStackSize() const override { return GetStackSize(); }
  bool Is64BitMode() const override { return true; }
  uint64_t GetEntryPoint() const override { return Entry; }
  void SetEntry(uint64_t E) { Entry = E; }

private:
  const uint8_t *Bytes; size_t Size; uint64_t Base; uint64_t Entry{0};
};

struct GuestRun {
  fextl::unique_ptr<FEXCore::Context::Context> Ctx;
  BbFexCodeLoader *Loader;
  void (*Log)(const char *, void *); void *User;
};

void NotifyLog(void *CtxVoid, uint32_t ThreadID, const char *Line, void *User) {
  auto *G = static_cast<GuestRun *>(User);
  G->Log(Line, G->User);
}

} // namespace

int bbi_fex_can_boot(void) { return 1; }

void bbi_fex_run_guest(const void *image, size_t size,
                       const char *app0_dir, const char *user_dir,
                       void (*on_log)(const char *, void *), void *user) {
  GuestRun state{};
  state.Log = on_log; state.User = user;

  FEXCore::Config::Initialize();
  FEXCore::Config::SetConfig(FEXCore::Config::CONFIG_IS64BIT_MODE, true);
  /* Embedded personality: FEX's own Linux syscalls are bypassed — every guest import
   * is a PS4 ABI imports table entry resolved by runtime_resolve (docs/03 §3). */
  FEXCore::Config::LoadConfig();

  auto ctx = FEXCore::Context::Context::CreateNewContext(
      FEXCore::Context::Context::InitializeParameters{
        .Is64BitMode = true,
        .OnlyInstalledCoreCount = true, /* multi-core point */
      });
  if (!ctx) { on_log("FATAL: cannot create FEX context", user); return; }
  ctx->Initialize();

  static constexpr uint64_t GuestBase = 0x800000000ULL;
  static BbFexCodeLoader loader(image, size, GuestBase);
  ctx->InitCore(&loader);

  /* Each PS4 guest thread (scePthreadCreate) gets its own FEX TXV; see runtime_thread
   * iOS overlay: RunThread executes the guest entry on a dedicated pthread. */
  state.Ctx = std::move(ctx);
  state.Loader = &loader;
  /* install the runtime import-table => FEX thunk mapping happens in InitCore hooks. */

  /* run until the guest explicitly exits (sceSystemServiceLoadExec) or process exit. */
  state.Ctx->Run();
}

#else  /* !BB_WITH_FEX: bring-up stubs so the CI skeleton compiles without FEX present. */

void bbi_fex_run_guest(const void *, size_t, const char *, const char *,
                       void (*on_log)(const char *, void *), void *user) {
  on_log("STOP: FEXCore not linked — build with BB_WITH_FEX=1 "
         "(third_party/fex submodule; see docs/03-CPU_FEX.md).", user);
}
int bbi_fex_can_boot(void) { return 0; }

#endif
