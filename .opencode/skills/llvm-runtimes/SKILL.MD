# LLVM Runtimes Cross-Compilation — Known Issues & Fixes

> Baca skill ini saat build gagal di runtimes configure step, terutama error seperti `cmake_path undefined`, `LIBCXXABI_USE_LLVM_UNWINDER`, atau `Compiler doesn't support generation of unwind tables`.

---

## Root Cause

**Runtimes (libunwind, libcxx, libcxxabi) tidak bisa dibangun sebagai bagian dari LLVM build saat compiler hasil build adalah cross-compiler.**

Alur error:

```
main build (targeting AArch64)
  └── just-built clang (default target = aarch64-linux-android)
       └── runtimes sub-build (runs on x86_64 host)
            └── CMake compiler detection: compile test program
                 └── clang defaults to AArch64 → can't compile for x86_64
                      └── ALL compiler tests fail (ABI info, -fPIC, -funwind-tables, etc.)
                           └── libunwind: cmake_path undefined (variable not set due to failed detection)
                           └── libcxxabi: LIBCXXABI_USE_LLVM_UNWINDER auto-detected ON without libunwind
```

---

## Error Signatures

### 1. `cmake_path undefined variable for input path`
- **Lokasi**: `libunwind/CMakeLists.txt:148`
- **Cause**: Cross-compilation context — variabel path tidak di-set karena compiler detection gagal
- **Fix**: Jangan build runtimes di cross-compilation context

### 2. `LIBCXXABI_USE_LLVM_UNWINDER is set to ON, but libunwind is not specified in LLVM_ENABLE_RUNTIMES`
- **Lokasi**: `libcxxabi/CMakeLists.txt:57`
- **Cause**: LLVM auto-detect libunwind source ada → set `LIBCXXABI_USE_LLVM_UNWINDER=ON` → tapi libunwind tidak di-list
- **Fix**: Jangan build runtimes di cross-compilation context (atau set `-DLIBCXXABI_USE_LLVM_UNWINDER=OFF`)
- **Kasus 2026-08-02 (Build #86)**: preset `kernel`/`full` set `LLVM_RUNTIMES="libcxx;libcxxabi"` (tanpa `libunwind`) → propagasi ke **stage1** → runtimes sub-build stage1 gagal di configure. Fix: stage1 force `LLVM_RUNTIMES=""` (stage1 tidak butuh runtimes), preset ditambahkan `libunwind`.

### 3. `Compiler doesn't support generation of unwind tables if exception support is disabled`
- **Lokasi**: `libunwind/src/CMakeLists.txt:95`
- **Cause**: Cross-compiler targeting wrong architecture → `-funwind-tables` check gagal
- **Fix**: Jangan build runtimes di cross-compilation context

---

## Fix

### Untuk simple_build (non-PGO)

**Jangan build runtimes di simple_build.** Override `LLVM_RUNTIMES` ke empty sebelum cmake configure:

```bash
# simple_build() di build.sh
local saved_runtimes="$LLVM_RUNTIMES"
LLVM_RUNTIMES=""
cmake_configure "$LLVM_DIR" "$build" "$INSTALL_DIR" "$LLVM_PROJECTS" "" "${cmake_args[@]}"
LLVM_RUNTIMES="$saved_runtimes"
```

Dan skip `bundle_libcxx` call:

```bash
# HAPUS baris ini dari simple_build:
bundle_libcxx "$build"
```

### Mengapa ini aman

- **Kernel builds tidak butuh libc++**: Android kernel pakai Bionic, bukan glibc/libstdc++
- **compiler-rt builtins sudah cukup**: Builtins dibangun sebagai project, bukan runtime
- **PGO build tetap punya runtimes**: Stage1 build compiler host-targeting dulu → runtimes sub-build berhasil

### Untuk PGO build

Stage 1 TIDAK boleh build runtimes — hanya dipakai untuk PGO profile collection dan artefaknya dihapus (cleanup_stage1_artifacts). Sejak 2026-08-02, `stage1_build()` force `LLVM_RUNTIMES=""` sebelum cmake configure:

```bash
# stage1_build() di build.sh
local saved_runtimes="$LLVM_RUNTIMES"
LLVM_RUNTIMES=""
cmake_configure ... # tanpa runtimes
LLVM_RUNTIMES="$saved_runtimes"
```

Stage 2/3 (final toolchain) build runtimes **dengan libunwind**:

```bash
LLVM_RUNTIMES="libcxx;libcxxabi;libunwind"
```

Jika `LLVM_RUNTIMES` ditambahkan di preset (`config/presets/*.conf`), PASTIKAN selalu menyertakan `libunwind` — karena:
1. Preset value propagasi ke stage1 → libcxxabi configure gagal tanpa libunwind
2. Stage2/3 override nilainya sendiri, tapi preset harus tetap konsisten sebagai dokumentasi

---

## Pencegahan

Sebelum menambah/menghapus item dari `LLVM_RUNTIMES`, cek:

1. **Apakah build path-nya cross-compilation?**
   - Jika `CLANG_DEFAULT_TARGET_TRIPLE != host triple` → runtimes TIDAK BOLEH dibangun sebagai bagian dari main build
   - Kecuali ada stage1 (host compiler) yang dibangun dulu

2. **Apakah `LLVM_TARGETS_TO_BUILD` includes host target?**
   - Jika hanya `AArch64` → just-built Clang defaults ke AArch64 → runtimes gagal
   - Jika kosong (all targets) → X86 dibangun tapi default target tetap AArch64

3. **Apakah stage ini butuh runtimes?**
   - Stage1 (PGO profiling) → TIDAK. Force `LLVM_RUNTIMES=""`
   - Stage2/3 (final toolchain) → YA, sertakan `libunwind` (libcxxabi auto-enable `LIBCXXABI_USE_LLVM_UNWINDER` jika source libunwind ada)

4. **Preset consistency**: `LLVM_RUNTIMES` di `config/presets/*.conf` harus selalu menyertakan `libunwind` bila mencantumkan `libcxx;libcxxabi`

5. **Test mental**: Just-built Clang → compile test program untuk host → gagal? → runtimes juga gagal

---

## Related Files

| File | Relevansi |
|------|-----------|
| `scripts/build.sh:41` | `LLVM_RUNTIMES` variable definition |
| `scripts/build.sh:398-411` | stage1_build — force `LLVM_RUNTIMES=""` |
| `scripts/build.sh:727-728` | stage2_build runtime override (`libcxx;libcxxabi;libunwind`) |
| `scripts/build.sh:793-794` | stage3_build runtime override (`libcxx;libcxxabi;libunwind`) |
| `scripts/build.sh:98-128` | `bundle_libcxx()` — skip saat runtimes tidak dibangun |
| `config/presets/kernel.conf:12` | Preset kernel — `LLVM_RUNTIMES` harus include `libunwind` |
| `config/presets/full.conf:12` | Preset full — `LLVM_RUNTIMES` harus include `libunwind` |
| `.github/workflows/build.yml:35` | `ENABLE_PGO` default (false untuk push builds) |

---

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `llvm-runtimes-fixer` |
| **Triggers** | `build_failure_with_runtimes`, `cross_compile_error`, `cmake_config_failure` |
| **Dependencies** | `master-reference` (known issues context), `compiler-build-optimizer` (build system) |
| **Depended By** | `compiler-build-optimizer` (if cross-compilation detected) |
| **Workflows** | `pr-review` (step 5 — conditional), `release-build` (step 4), `daily-build` (step 3) |
| **Routing Rule** | Build log shows `cmake_path` / `LIBCXXABI_USE_LLVM_UNWINDER` / `unwind tables` → route to this skill |
| **Error Signatures** | `cmake_path: command not found`, `LIBCXXABI_USE_LLVM_UNWINDER`, `doesn't support generation of unwind tables` |

*Terjadi di: Build #65, #66 (2026-06-23), Build #86 (2026-08-02 — stage1 libunwind missing)*
