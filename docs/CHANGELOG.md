# Changelog

All notable changes to Oronyx Clang will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [22.1.0] - 2026-06-29

### Changed

- **Vendor string** — Renamed from "CyreneClang" to "Oronyx Clang" for better readability
- **CI/CD schedule** — Removed fixed weekly cron schedule; build now only triggers on:
  - Manual dispatch (`workflow_dispatch`)
  - Push to `patches/`, `scripts/`, or `.github/workflows/`
  - New LLVM release detection via `repository_dispatch`
- **Auto-update checker** — New `check-llvm-update.yml` workflow runs daily to check for new LLVM releases and triggers build automatically
- **Benchmark chart** — Upgraded from single-metric (compile time only) to 3-panel chart showing compile time, binary size, and peak memory

### Added

- **LLVM version tracking** — `.llvm-version` file tracks currently built LLVM version
- **Repository dispatch** — Build workflow accepts `new-llvm-release` event type for automated builds
- **Makefile benchmark targets** — `make bench`, `make bench-quick`, `make bench-full`

---

## [22.1.0] - 2026-06-23

### Fixed

- **Runtimes configure failure** — Replace `-DLLVM_USE_LINKER=lld` with standard CMake linker flags (`CMAKE_LINKER`, `CMAKE_*_LINKER_FLAGS`) to prevent the flag from propagating to the runtimes sub-build, which caused `Host compiler does not support '-fuse-ld=lld'` error
- **PATH for just-built tools** — Prepend `$build/bin` to PATH before `cmake --build` in `simple_build()` so the just-built Clang can find lld, llvm-ar, etc. during runtimes configure

---

## [22.1.0] - 2026-06-21

### Added

- **Memory-aware job scaling** — Auto-detects available RAM and adjusts `JOBS` accordingly
  - <4GB RAM: `RAM × 2` jobs
  - 4-8GB RAM: `RAM × 2` jobs
  - 8-16GB RAM: `nproc` jobs
  - \>16GB RAM: `nproc` jobs (capped at 8)
- **LTO mode selection** — New `LTO_MODE` env var (`Thin` | `Full` | `Off`)
  - `Thin` (default): Fast linking, good optimization
  - `Full`: Smaller binaries, slower linking
  - `Off`: No LTO, fastest build
- **Ccache aggressive mode** — When ccache is available, enables:
  - `sloppiness=file_stat_matches` — Skip stat for cached files
  - `compression=true` — Compress cache entries
  - `compression_level=9` — Maximum compression
- **Build time profiling** — Tracks duration of each build stage:
  - Clone, patches, stage1, pgo_collect, stage2, bolt, simple
  - Output to `build/build_metadata.json`
- **Zstd compression level tuning** — New `ZSTD_LEVEL` env var (1-22, default: 19)
  - Level 19 for releases (balanced size/speed)
  - Level 3 for CI testing (fast compression)

### Changed

- `JOBS` default now calculated from available RAM instead of raw `nproc`
- `LTO_MODE` exported to `clang-version.txt` and `clang_notes.txt`
- `package.sh` uses `LTO_MODE` from environment instead of hardcoded `"Thin"`
- Build metadata now includes `jobs`, `zstd_level`, and per-stage timings

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LTO_MODE` | `Thin` | LTO mode: `Thin`, `Full`, or `Off` |
| `ZSTD_LEVEL` | `19` | Zstd compression level (1-22) |
| `JOBS` | auto | Parallel build jobs (auto-detected from RAM) |

### Build Metadata

Build now generates `build/build_metadata.json` with:
```json
{
  "llvm_branch": "llvmorg-22.1.0",
  "llvm_commit": "abc1234",
  "clang_version": "22.1.0",
  "build_date": "2026-06-21",
  "pgo": true,
  "bolt": true,
  "lto": "Thin",
  "jobs": 8,
  "zstd_level": 19,
  "patches": 1,
  "duration": "1h 23m 45s",
  "stages": {
    "clone": 45,
    "patches": 2,
    "stage1": 1800,
    "pgo_collect": 120,
    "stage2": 3600,
    "bolt": 300
  }
}
```

---

## [21.0.0] - 2026-06-14

### Added

- Initial OronyxClang release
- 2-stage PGO build with SQLite/kernel workload
- ThinLTO for toolchain optimization
- BOLT post-build optimization
- Polly loop vectorizer support
- Auto-sync patches from LLVM stable
- Telegram build notifications
- Kernel LTO helper script
- Kernel 4.x build helper script
- Compatibility checker

### Targets

- AArch64 (ARM64)
- ARM (32-bit)
- X86 (host tools)

### Kernel Support

- 4.14+ (legacy)
- 5.12+ (ThinLTO)
- 6.0+ (GKI)
