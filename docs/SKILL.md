# OronyxClang Toolchain — Quick Reference

**Current**: Clang 22.1.0 | Build #54 | `llvmorg-22.1.0` | 672M compressed

## Struktur

```
```
oronyx-clang/
├── .github/workflows/
│   ├── build.yml              # Main build pipeline (build + package + release)
│   ├── build-multi.yml        # Multi-version build (manual dispatch, matrix)
│   ├── check-llvm-update.yml  # Cek LLVM release baru otomatis
│   ├── lint.yml               # ShellCheck lint
│   └── sync-patches.yml       # Auto-sync LLVM patches
├── scripts/
│   ├── build.sh               # Core 2-stage PGO+ThinLTO build
│   ├── patch.sh               # Apply patches with fallback
│   ├── package.sh             # Compress + generate manifest
│   ├── notify.sh              # Telegram notifications (started/success/failure/release/changelog)
│   ├── sync-patches.sh        # Auto-find LLVM stable commits
│   ├── kernel-lto.sh          # Kernel ThinLTO env setup
│   └── check-compat.sh        # Toolchain compatibility check
├── patches/
│   └── 0001-*.patch           # Applied to LLVM before build
├── docs/
│   ├── feature-general.md     # Feature dev template
│   └── feature-specific.md    # Feature prompts
└── README.md
```

## Build Flags

| Flag | Default | Deskripsi |
|------|---------|-----------|
| `PRESET` | `kernel` | Build preset: `kernel` (PGO+BOLT), `full`, `slim` (tanpa PGO/BOLT) |
| `LLVM_BRANCH` | `llvmorg-22.1.0` | LLVM branch/tag |
| `ENABLE_PGO` | `true` | 2-stage PGO build |
| `ENABLE_BOLT` | `true` | BOLT post-build optimization |
| `PGO_WORKLOAD` | `sqlite` | PGO workload (`sqlite`/`kernel`) |
| `LLVM_TARGETS` | `AArch64` | Target architectures |
| `LTO_MODE` | `Thin` | LTO mode (`Thin`/`Full`/`Off`) |
| `JOBS` | `$(nproc)` | Parallel jobs (auto from RAM) |
| `ZSTD_LEVEL` | `19` | Zstd compression level (1-22) |

## Android 16 Kernel Compatibility

Android 16 uses kernel **6.12** (GKI 2.0). Key requirements:
- **Clang >= 18** recommended for kernel 6.x features
- **ThinLTO** for kernel build: `KCFLAGS="-flto=thin"`
- **CFI** (Control Flow Integrity) support for security
- **16 KB page size** alignment for memory optimization

OronyxClang 22.1.0 fully supports all Android 16 kernel build requirements.

## Patch Workflow

1. Taruh `.patch` di `patches/`
2. Push ke `main` → build trigger otomatis
3. `patch.sh` apply via `git apply` → `--3way` → `sed` fallback

## Secrets (GitHub Actions)

- `TELEGRAM_BOT_TOKEN` — Bot token
- `TELEGRAM_CHAT_ID` — Channel notif build
- `ERROR_DUMP_CHAT_ID` — Channel error dump

## Kontribusi

- Commit style: `type: description` (e.g. `fix:`, `feat:`, `chore:`)
- Branch: `main` untuk semua
- Patch: format `NNNN-description.patch`
