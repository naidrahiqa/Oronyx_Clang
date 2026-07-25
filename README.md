# Oronyx Clang

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/naidrahiqa/Oronyx_Clang)](https://github.com/naidrahiqa/Oronyx_Clang/releases)
[![Build Status](https://github.com/naidrahiqa/Oronyx_Clang/actions/workflows/build.yml/badge.svg)](https://github.com/naidrahiqa/Oronyx_Clang/actions/workflows/build.yml)
[![LLVM Version](https://img.shields.io/badge/LLVM-22.1.8-orange.svg)](https://github.com/llvm/llvm-project)
[![Build Time](https://img.shields.io/badge/Build%20Time-%3E4h%2030m-blue.svg)](https://github.com/naidrahiqa/Oronyx_Clang/actions/workflows/build.yml)

A prebuilt LLVM/Clang toolchain optimized for Android kernel compilation. Supports LLVM 14 through 22+.

## What is This?

Oronyx Clang is a **ready-to-use** Clang toolchain for building Android kernels. Download, extract, and compile — no need to build LLVM yourself.

**Key optimizations:**
- PGO (Profile-Guided Optimization) for faster compilation
- ThinLTO for leaner, faster binaries
- BOLT for 5-15% additional speedup
- Auto-detects RAM to scale build parallelism

## Who Is This For?

- **Kernel developers** — Need a fast, optimized Clang for building kernels
- **ROM developers** — Want a reliable toolchain for custom Android ROMs
- **Anyone** — Who needs a prebuilt Clang with Android kernel support

## Need Help?

- **Found a bug?** — [Open an issue](https://github.com/naidrahiqa/Oronyx_Clang/issues)
- **Want to fix something?** — [Open a PR](https://github.com/naidrahiqa/Oronyx_Clang/pulls)
- **Want to build your own?** — [Fork the repo](https://github.com/naidrahiqa/Oronyx_Clang/fork)

## Why Oronyx Clang?

| Feature | Stock Clang | Oronyx Clang |
|---------|:-----------:|:------------:|
| PGO | - | 2-stage IR-based |
| ThinLTO | - | Applied to toolchain |
| BOLT | - | 5-15% additional speedup |
| Auto-detect RAM | - | Scales parallel jobs |
| Kernel presets | - | 4.14 - 6.x |
| LTO modes | - | Thin / Full / Off |
| Benchmark | - | Auto-generated charts |
| Telegram notify | - | Build status push |

## Features

| Feature | Details |
|---|---|
| **PGO** | 2-stage IR-based Profile-Guided Optimization |
| **ThinLTO** | Applied to the toolchain itself for faster, leaner binaries |
| **BOLT** | Binary Optimization and Layout Tool for 5-15% additional speedup |
| **Polly** | Loop vectorization optimizer, usable via `-mllvm -polly` |
| **Memory-aware jobs** | Auto-detects RAM and scales parallel jobs |
| **LTO modes** | Thin (default), Full, or Off — configurable via `LTO_MODE` |
| **Ccache aggressive** | Compression + sloppiness for faster rebuilds |
| **Build profiling** | Per-stage timing in `build_metadata.json` |
| **Targets** | AArch64, ARM (32-bit), X86 (host tools) |
| **Kernel support** | 4.14 through 6.x (GKI + legacy trees) |
| **LLVM versions** | Supports building from LLVM 14+ (stable and main) |
| **Distribution** | GitHub Releases + `clang-version.txt` + `clang_notes.txt` manifests |
| **Telegram notify** | Build status pushed to Telegram channel |

## Benchmark

Performance comparison of Oronyx Clang against stock Clang, measuring real-world kernel compilation workloads.

### What's Measured

| Metric | Description | Why It Matters |
|--------|-------------|----------------|
| **Compile Time** | Time to compile a full kernel (e.g., msm-5.15) | Faster builds = quicker iteration |
| **Binary Size** | Size of the compiled kernel image | Smaller = faster boot, less storage |
| **Peak Memory** | Maximum RAM usage during compilation | Determines if you can build on your machine |

### Oronyx Clang vs Stock Clang

Benchmark runs automatically on every release using `scripts/benchmark.sh`:

![Oronyx Clang Benchmark](benchmark/chart.svg)

<details>
<summary>Understanding the Charts</summary>

- **Compile Time (ms)** — Lower is better. Oronyx Clang with PGO+BOLT typically shows 10-20% faster compilation.
- **Binary Size** — Lower is better. LTO optimizes dead code elimination.
- **Peak Memory (GB)** — Lower is better. Memory-aware job scaling helps here.

</details>

<details>
<summary>Raw Results (JSON)</summary>

```json
benchmark/results.json
```

</details>

### Run Benchmark Locally

```bash
# Quick benchmark (1 iteration)
make bench-quick

# Standard benchmark (3 iterations)
make bench

# Full benchmark (5 iterations, more accurate)
RUNS=5 bash scripts/benchmark.sh

# Output:
# - benchmark/results.json   (raw data)
# - benchmark/chart.svg      (visualization)
```

## Quick Start

### One-liner install (recommended)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/get_clang.sh)
```

### Manual install

```bash
# Get the latest manifest
wget https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/clang-version.txt

# Download the toolchain
DOWNLOAD_URL=$(grep DOWNLOAD_URL clang-version.txt | cut -d= -f2)
wget "$DOWNLOAD_URL"

# Extract
mkdir -p $HOME/toolchains
tar -I zstd -xf oronyx-clang-*.tar.zst -C $HOME/toolchains/

# Fix ld symlink (if needed)
cd $HOME/toolchains/oronyx/bin
ln -sf $(which ld.lld) ld
```

## Kernel Integration

```bash
export PATH="$HOME/toolchains/oronyx/bin:$PATH"

make -j$(nproc) \
  O=out \
  ARCH=arm64 \
  CC=clang \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu-
```

### Unified Kernel Build Script

```bash
# Auto-detect kernel version and apply correct flags
bash scripts/kernel-build.sh <kernel-dir> --defconfig=<name> --lto=auto

# Examples
bash scripts/kernel-build.sh ~/kernel/msm-4.19 --lto=off
bash scripts/kernel-build.sh ~/kernel/msm-5.15 --defconfig=vendor/sdm845_defconfig
bash scripts/kernel-build.sh ~/kernel/android-mainline --lto=thin
```

### Kernel LTO Integration

```bash
source scripts/kernel-lto.sh [kernel-source-dir]
make -j$(nproc) O=out ARCH=arm64 ...
```

## Repository Structure

```
Oronyx_Clang/
├── .github/
│   ├── workflows/
│   │   ├── build.yml           # CI/CD pipeline
│   │   ├── check-llvm-update.yml  # Auto-check new LLVM releases
│   │   ├── lint.yml            # ShellCheck linting
│   │   └── sync-patches.yml    # Auto-sync from LLVM stable
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── config/
│   ├── build.conf              # Default build configuration
│   └── kernels/
│       ├── 4.x.conf            # Kernel 4.x settings
│       ├── 5.x.conf            # Kernel 5.x settings
│       └── 6.x.conf            # Kernel 6.x settings
├── contrib/                    # Community contributions
├── docker/                     # Docker build environment
├── docs/
│   ├── CHANGELOG.md
│   ├── CONTRIBUTING.md
│   ├── SKILL.md
│   └── TROUBLESHOOT.md
├── patches/                    # Custom LLVM patches
├── scripts/
│   ├── benchmark.sh            # Benchmark runner (compile time, binary size, memory)
│   ├── build.sh                # Main build script
│   ├── check-compat.sh         # Compatibility validator
│   ├── generate-chart.py       # SVG chart generator for benchmark results
│   ├── install.sh              # Legacy installer
│   ├── kernel-build.sh         # Unified kernel build (4.x-6.x)
│   ├── kernel-lto.sh           # Kernel ThinLTO helper
│   ├── notify.sh               # Telegram notifications
│   ├── package.sh              # Package + manifest generator
│   ├── patch.sh                # Patch application
│   └── sync-patches.sh         # LLVM stable sync
├── tests/
│   └── test-build.sh           # Build tests
├── .editorconfig
├── .gitignore
├── Dockerfile
├── LICENSE                     # Apache-2.0
├── Makefile                    # Common tasks
├── README.md
├── VERSION                     # Version tracking
└── get_clang.sh                # One-liner installer
```

## Building from Source

```bash
git clone https://github.com/naidrahiqa/Oronyx_Clang
cd oronyx_clang
make build  # or: bash scripts/build.sh
```

### Make Commands

| Command | Description |
|---|---|
| `make build` | Full build with PGO + BOLT |
| `make build-simple` | Quick build without PGO |
| `make lint` | Run ShellCheck on scripts |
| `make test` | Run build tests |
| `make bench` | Run benchmark (compile time, binary size, memory) |
| `make bench-quick` | Run benchmark with 1 iteration |
| `make bench-full` | Run benchmark with 5 iterations |
| `make docker-build` | Build in Docker |
| `make clean` | Remove build artifacts |

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `LLVM_BRANCH` | `llvmorg-22.1.8` | LLVM branch or tag to build (supports 14+) |
| `ENABLE_PGO` | `true` | Enable 2-stage PGO build |
| `ENABLE_BOLT` | `true` | Enable BOLT post-build optimization |
| `PGO_WORKLOAD` | `sqlite` | PGO workload: `sqlite` (fast) or `kernel` (accurate) |
| `LTO_MODE` | `Thin` | LTO mode: `Thin`, `Full`, or `Off` |
| `ZSTD_LEVEL` | `19` | Zstd compression level (1-22) |
| `JOBS` | auto | Parallel build jobs (auto-detected from RAM) |
| `CLANG_VENDOR` | `Oronyx Clang` | Vendor string in clang version output |
| `INSTALL_DIR` | `~/toolchains/oronyx` | Where to install the toolchain |
| `LLVM_SOURCE` | `upstream` | LLVM repo source: `upstream` (GitHub) or `android` (AOSP fork) |

### Benchmark Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ORONYX_DIR` | `~/toolchains/oronyx` | Path to installed Oronyx Clang toolchain |
| `KERNEL_SOURCE` | auto-clone | Kernel source directory for benchmark |
| `RUNS` | `3` | Number of iterations per configuration |
| `ARCH` | `arm64` | Target architecture |

## Building Older LLVM Versions

Oronyx Clang supports building LLVM 14 and newer:

```bash
# Build LLVM 15
LLVM_BRANCH=llvmorg-15.0.7 make build

# Build LLVM 16
LLVM_BRANCH=llvmorg-16.0.6 make build

# Build LLVM 17 (latest 17.x)
LLVM_BRANCH=llvmorg-17.0.6 make build

# Build LLVM 18
LLVM_BRANCH=llvmorg-18.1.8 make build

# Build LLVM 19 (latest stable)
LLVM_BRANCH=llvmorg-19.1.0 make build

# Build LLVM 22 (latest release)
LLVM_BRANCH=llvmorg-22.1.8 make build
```

**Note:** Older LLVM versions (< 15) may not support all features (PGO, BOLT). Use `make build-simple` for those versions.

## Docker Build

```bash
# Build in Docker container
make docker-build

# Run build inside Docker
make docker-run
```

## Adding Custom Patches

1. Generate a patch from your LLVM working tree:
   ```bash
   git -C llvm-project format-patch -1 HEAD
   ```
2. Move it to `patches/` with a descriptive name:
   ```
   patches/0001-fix-arm64-inline-asm.patch
   ```
3. Push — the workflow auto-triggers on changes to `patches/`.

## Compatibility Check

```bash
# Check toolchain only
make test-compat

# Or directly
bash scripts/check-compat.sh ~/kernel/msm-5.15
```

## FAQ

**Q: LTO causes kernel build failure?**
A: Use `--lto=off` for kernels < 5.10 or `--lto=thin` for newer kernels.

**Q: How to verify installation?**
A: Run `clang --version` — should show `Oronyx Clang` vendor string.

**Q: Can I build for older kernels (4.14)?**
A: Yes. Use `--lto=off` and the kernel presets in `config/kernels/`.

**Q: Which LLVM version should I use?**
A: For best compatibility, use LLVM 15+. For latest features, use LLVM 18+.

**Q: How to enable Telegram notifications?**
A: Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in repository secrets.

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md).

Quick start:
1. Fork the repo
2. Create feature branch
3. Run `make lint` before commit
4. Open PR

## Documentation

- [Changelog](docs/CHANGELOG.md) — Version history
- [Contributing](docs/CONTRIBUTING.md) — How to contribute
- [Troubleshooting](docs/TROUBLESHOOT.md) — Common issues and fixes

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
