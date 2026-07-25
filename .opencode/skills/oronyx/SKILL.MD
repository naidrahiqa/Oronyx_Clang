# OronyxClang — Master Project Reference

> Baca file ini **sebelum apapun** di setiap sesi yang berkaitan dengan OronyxClang.

---

## Gambaran Proyek

- **Repo**: `naidrahiqa/Oronyx_Clang`, branch `main`
- **Tujuan**: Custom LLVM/Clang toolchain untuk Android kernel compilation
- **Status**: Masih dalam development — belum diintegrasikan ke kernel production manapun

---

## Stack & Build

- LLVM/Clang dari branch `main` (bleeding edge)
- 2-stage PGO build (stage1: instrumented, stage2: optimized)
- ThinLTO pada toolchain itu sendiri — **bukan Full LTO**, akan OOM di runner
- Polly loop optimizer aktif
- Target triple: AArch64, ARM (32-bit), X86 (host tools)

### Constraint GitHub Actions Runner
- 4 core, 16GB RAM, ~25GB disk usable setelah cleanup
- **Full LTO = OOM** — jangan pernah aktifkan
- Selalu `--depth=1` saat clone llvm-project

---

## Struktur File Kritis

```
Oronyx_Clang/
├── .github/workflows/build.yml   # Pipeline CI — jangan hardcode flag di sini
├── scripts/
│   ├── build.sh                  # CMake configure + 2-stage PGO — semua flag di sini
│   ├── patch.sh                  # Apply patches — wajib pakai path absolut
│   ├── package.sh                # Compress output + buat clang-version.txt
│   ├── notify.sh                 # Telegram notification
│   └── kernel-lto.sh             # Helper ThinLTO untuk kernel
├── patches/                      # Format: NNNN-deskripsi.patch (git format-patch style)
└── docs/SKILL_ORONYX.md          # File ini
```

---

## Known Issues & Fixes

### Runtimes cross-compilation failure in simple_build
- **Root cause**: `simple_build()` builds Clang targeting AArch64, but runtimes sub-build runs on x86_64 host. All CMake compiler detection fails.
- **Errors**: `cmake_path undefined variable`, `LIBCXXABI_USE_LLVM_UNWINDER auto-detected ON`, `Compiler doesn't support generation of unwind tables`
- **Fix**: Override `LLVM_RUNTIMES=""` before `cmake_configure` in `simple_build()`, skip `bundle_libcxx`. Runtimes only needed for userspace, not kernel builds.
- **See**: `.opencode/skills/llvm-runtimes/SKILL.MD`

### nsan.h — SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD
- **Root cause**: Kombinasi GCC 14 + libstdc++ menarik `<bits/stl_pair.h>` dari `<math.h>` di C++ mode, konflik dengan definisi array di nsan.h saat Clang jadi host compiler
- **Fix**: Tambah flag `-include sanitizer_redefine_builtins.h -DSANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD` — approach yang sama dengan `build_symbolizer.sh` di LLVM upstream
- **Jangan**: Patch nsan.h langsung — tidak ada upstream fix untuk kasus ini
- **Patch file**: `patches/0001-fix-nsan-redefine-builtins-gcc14.patch`

### patch.sh — Path Absolut untuk git -C
- **Root cause**: `git -C` butuh path absolut, relative path gagal di beberapa environment
- **Fix**: Resolve di top script dengan `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`, lalu gunakan `git -C "$REPO_ROOT"`
- **Jangan**: Pakai `$(cd ... && pwd)` inline di dalam subshell nested

---

## Aturan Wajib

- Semua bash script: `set -euo pipefail` setelah shebang
- Semua build flag: edit di `scripts/build.sh`, **bukan** di workflow YAML
- Output patches: `git format-patch -1 HEAD` dari llvm-project working tree
- Compress artifact: gunakan `zstd`, bukan `gzip`
- Naming patch: `NNNN-deskripsi-singkat.patch`

---

## Secrets GitHub yang Dibutuhkan

| Secret | Keterangan |
|--------|------------|
| `TELEGRAM_BOT_TOKEN` | Notifikasi build |
| `TELEGRAM_CHAT_ID` | Target channel |
| `GH_TOKEN` | Upload release |

---

## Checklist Sebelum Push

- [ ] `set -euo pipefail` ada di semua script
- [ ] Flag build ada di `build.sh`, bukan `build.yml`
- [ ] Patch baru ada di `patches/` dengan naming benar
- [ ] `patch.sh` pakai path absolut

---

## Konvensi Commit

Format: `type(scope): deskripsi singkat`

| Type | Kapan |
|------|-------|
| `fix` | Bug/error fix |
| `feat` | Fitur baru |
| `ci` | Perubahan workflow |
| `chore` | Cleanup, update deps |
| `patch` | Tambah/update LLVM patch |

Contoh: `fix(nsan): apply SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD for GCC 14 compat`

---

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `master-reference` |
| **Triggers** | `session_start`, `before_any_task` |
| **Dependencies** | None (root skill — must be loaded first) |
| **Depended By** | `compiler-build-optimizer`, `debugging`, `llvm-runtimes-fixer`, `planning` |
| **Workflows** | All workflows load this first |
| **Routing Rule** | `session_start` → load `master-reference` (mandatory) |

*File ini harus dibaca SEBELUM skill lain di setiap sesi.*

*Last updated: 2026-06-29*