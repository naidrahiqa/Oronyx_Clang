# Oronyx Clang

Oronyx Clang is an optimized LLVM/Clang toolchain for Android kernel compilation. Built with PGO, ThinLTO, and BOLT for maximum performance.

## Host Compatibility

This toolchain is built on Ubuntu using the default `glibc` version. Compatibility with older distributions is not guaranteed. Other `libc` implementations (such as `musl`) are currently not supported.

## Installation

To install Oronyx Clang, run the following command:

```shell
bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/get_clang.sh)
```

Ensure the toolchain is included in your PATH:

```shell
export PATH="$HOME/toolchains/oronyx/bin:$PATH"
```

## LLVM Version

Oronyx Clang is built from the upstream [llvm/llvm-project](https://github.com/llvm/llvm-project) stable releases. Each release is tagged with the LLVM version and build date, e.g. `oronyx-22.1.8-20260716`.

To check exactly which build you have after installation:

```shell
clang --version
```

## Building Linux

For an AArch64 cross-compilation setup, the following variables must be set. While some can be defined as environment variables, it is **highly recommended** to pass all of them directly to `make` to avoid unexpected behavior:

* `CC=clang` (must be passed directly to `make`)
* `CROSS_COMPILE=aarch64-linux-gnu-`
* For 32-bit vDSO: `CROSS_COMPILE_ARM32=arm-linux-gnueabi-`

> **Note:** On sufficiently recent mainline kernel trees, `CROSS_COMPILE` can technically be omitted when using only LLVM tools, since the `--target=` triple is inferred from `ARCH`. This inference is not present on older Android kernel trees (e.g. 4.19, 5.4, 5.10), so explicitly passing `CROSS_COMPILE` as shown above remains the safe, portable default.

Optionally, you may use LLVM-based tools to minimize reliance on GNU binutils:

* `LD=ld.lld`
* `AR=llvm-ar`
* `NM=llvm-nm`
* `OBJCOPY=llvm-objcopy`
* `OBJDUMP=llvm-objdump`
* `STRIP=llvm-strip`
* `READELF=llvm-readelf`

To leverage Clang's integrated assembler and LLVM's linker (`lld`), you can enable the following build options:

* `LLVM=1` (Use Clang and LLVM tools e.g., `clang`, `lld` instead of GNU tools.)
* `LLVM_IAS=1` (Use Clang's built-in assembler instead of GNU `as`.)

> **Note on LLVM_IAS defaults:** Since Linux v5.15, the kernel build system enables the integrated assembler **by default** — on these trees `LLVM_IAS=0` is what you'd pass to fall back to GNU `as`. On older kernel trees (anything prior to 5.15, which includes most current Android `common` branches such as 4.19/5.4/5.10), the integrated assembler is still **off by default**, so `LLVM_IAS=1` must be passed explicitly as shown above. When in doubt, pass `LLVM_IAS=1` explicitly — it's a no-op on trees where it's already the default.

> **Note:** Some older kernel versions or architectures may not be fully compatible with the integrated assembler. Disable `LLVM_IAS` or apply necessary patches if build errors occur.

Older Android kernels (pre-4.14) require specific patches to be built with any Clang-based toolchain. Refer to [android-kernel-clang](https://github.com/nathanchance/android-kernel-clang) for guidance.

For Android kernels 4.19 and newer, use the upstream variable `CROSS_COMPILE_COMPAT` in place of `CROSS_COMPILE_ARM32`.

## Differences from Other Toolchains

Oronyx Clang is designed to be easier to use compared to toolchains like AOSP Clang. Key improvements include:

* `CLANG_TRIPLE` does not need to be set because we don't use AOSP binutils.
* `LD_LIBRARY_PATH` does not need to be set because we set library load paths in the toolchain.

## Features

| Feature | Details |
|---|---|
| **PGO** | 2-stage IR-based Profile-Guided Optimization |
| **ThinLTO** | Applied to the toolchain itself for faster, leaner binaries |
| **BOLT** | Binary Optimization and Layout Tool for 5-15% additional speedup |
| **Polly** | Loop vectorization optimizer, usable via `-mllvm -polly` |
| **Memory-aware jobs** | Auto-detects RAM and scales parallel jobs |
| **LTO modes** | Thin (default), Full, or Off — configurable via `LTO_MODE` |
| **Targets** | AArch64, ARM (32-bit), X86 (host tools) |
| **Kernel support** | 4.14 through 6.x (GKI + legacy trees) |

## Unified Kernel Build Script

```bash
# Auto-detect kernel version and apply correct flags
bash scripts/kernel-build.sh <kernel-dir> --defconfig=<name> --lto=auto

# Examples
bash scripts/kernel-build.sh ~/kernel/msm-4.19 --lto=off
bash scripts/kernel-build.sh ~/kernel/msm-5.15 --defconfig=vendor/sdm845_defconfig
bash scripts/kernel-build.sh ~/kernel/android-mainline --lto=thin
```

## Building from Source

```bash
git clone https://github.com/naidrahiqa/Oronyx_Clang
cd Oronyx_Clang
make build  # or: bash scripts/build.sh
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `LLVM_BRANCH` | `llvmorg-22.1.8` | LLVM branch or tag to build (supports 14+) |
| `ENABLE_PGO` | `true` | Enable 2-stage PGO build |
| `ENABLE_BOLT` | `true` | Enable BOLT post-build optimization |
| `PGO_WORKLOAD` | `sqlite` | PGO workload: `sqlite` (fast) or `kernel` (accurate) |
| `LTO_MODE` | `Thin` | LTO mode: `Thin`, `Full`, or `Off` |
| `JOBS` | auto | Parallel build jobs (auto-detected from RAM) |
| `LLVM_SOURCE` | `upstream` | LLVM repo source: `upstream` (GitHub) or `android` (AOSP fork) |

## FAQ

**Q: LTO causes kernel build failure?**
A: Use `--lto=off` for kernels < 5.10 or `--lto=thin` for newer kernels.

**Q: How to verify installation?**
A: Run `clang --version` — should show `Oronyx Clang` vendor string.

**Q: Can I build for older kernels (4.14)?**
A: Yes. Use `--lto=off` and the kernel presets in `config/kernels/`.

**Q: Which LLVM version should I use?**
A: For best compatibility, use LLVM 15+. For latest features, use LLVM 18+.

## Contributing

1. Fork the repo
2. Create feature branch
3. Run `make lint` before commit
4. Open PR

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
