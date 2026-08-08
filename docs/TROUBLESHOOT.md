# Troubleshooting

Common issues and solutions when using OronyxClang.

## Build Issues

### "Not enough disk space"

**Cause:** GitHub Actions runner has limited disk (~25GB).

**Solution:**
- The build script automatically cleans up during build
- If still failing, try `ENABLE_PGO=false` for single-pass build
- Check `df -h /` to verify available space

### "Compiler doesn't support '-fuse-ld=lld'"

**Cause:** Runtimes sub-build fails with cross-compilation.

**Solution:**
- This is fixed in recent versions
- Ensure you're using the latest build.sh
- The fix uses `CMAKE_LINKER` instead of `-DLLVM_USE_LINKER=lld`

### "LIBCXXABI_USE_LLVM_UNWINDER is set to ON, but libunwind is not specified in LLVM_ENABLE_RUNTIMES"

**Cause:** A stage is configured with runtimes (`libcxx;libcxxabi`) but without `libunwind`. libcxxabi auto-detects the in-tree libunwind and requires it to be listed in `LLVM_ENABLE_RUNTIMES`.

**Solution:**
- Stage 1 never needs runtimes — it is only used for PGO profile collection and its artifacts are deleted afterwards. It forces `LLVM_RUNTIMES=""` in `scripts/build.sh`.
- Stage 2/3 build the final runtimes and must include `libunwind`: `LLVM_RUNTIMES="libcxx;libcxxabi;libunwind"` (see `config/presets/kernel.conf`, `config/presets/full.conf`).
- If adding a new preset, always keep the runtimes list in sync: Stage 2/3 require the `libunwind` entry.
- Alternatively pass `-DLIBCXXABI_USE_LLVM_UNWINDER=OFF`, but bundling libunwind is preferred since the toolchain is distributed without system libunwind guarantees.

### "git clone failed"

**Cause:** Network issues on CI runners.

**Solution:**
- Build script now retries 3 times automatically
- Manual retry usually succeeds
- Check if GitHub is accessible

### Stage 2 fails with "ld.lld not found"

**Cause:** PATH not set correctly for Stage 2.

**Solution:**
- Build script prepends Stage 1 bin to PATH
- Ensure Stage 1 completed successfully
- Check `ls build/stage1-install/bin/` for binaries

## Installation Issues

### "clang: not found"

**Cause:** PATH not configured.

**Solution:**
```bash
export PATH="$HOME/toolchains/oronyx/bin:$PATH"
# Add to ~/.bashrc for persistence
```

### "ld: not found"

**Cause:** Missing ld symlink.

**Solution:**
```bash
cd $HOME/toolchains/oronyx/bin
ln -sf $(which ld.lld) ld
```

### Wrong libc++ version

**Cause:** System libc++ conflicts with toolchain.

**Solution:**
- OronyxClang bundles its own libc++
- Set `LD_LIBRARY_PATH` to toolchain lib dir
- Or use `LD_PRELOAD` with toolchain's libc++.so

## Kernel Build Issues

### "Kernel < 5.0 does not support LTO"

**Cause:** LTO enabled for old kernel.

**Solution:**
```bash
bash scripts/kernel-build.sh <kernel-dir> --lto=off
```

### Many warnings with kernel 4.x

**Cause:** Modern Clang is stricter than older versions.

**Solution:**
- Use `kernel-build.sh` which auto-applies warning suppression
- Or manually add `-Wno-*` flags

### "undefined reference to __gnu_mcount_nc"

**Cause:** Kernel needs specific ARM configuration.

**Solution:**
- Ensure `CONFIG_HAVE_KPROBES=y` in defconfig
- Or disable CONFIG_FUNCTION_TRACER

## CI/CD Issues

### Build fails with "No space left on device" (free runner)

**Cause:** Free GitHub runner disk (14 GB) is exhausted by PGO+BOLT builds. `config/build.conf` used to force `PRESET="kernel"` (PGO+BOLT) which ignored workflow inputs — now overridable.

**Solution:**
- Use the `slim` preset for free runners (default in CI): no PGO/BOLT, fits in 14 GB
- `build.sh` prunes unused LLVM subprojects (mlir/flang/lldb/etc.) after clone — ~1-2 GB freed
- Use the `kernel`/`full` presets only on runners with large disk (self-hosted or GitHub large runner)
- Manual dispatch: set `preset` input to `slim`

### Build timeout

**Cause:** PGO build takes 3+ hours on GitHub Actions.

**Solution:**
- Build timeout is set to 6 hours
- Use `ENABLE_PGO=false` for faster testing
- Check if disk cleanup is working
- Use `slim` preset (skips PGO stage entirely)

### Release not publishing

**Cause:** Release tag or permissions issue.

**Solution:**
- Ensure `GITHUB_TOKEN` has write permissions
- Check if release tag format is correct
- Verify the tarball was created

## Getting Help

1. Check this troubleshooting guide
2. Search existing GitHub Issues
3. Open a new Issue with:
   - Build log (last 1000 chars)
   - Environment details
   - Steps to reproduce
