# Toolchain Builder (LLVM/Clang) - Oronyx Clang

## Overview
Builds the custom Oronyx Clang toolchain (LLVM/Clang 18.x) from source, optimized for Android kernel compilation. Manages the full build pipeline: CMake configuration, stage1/stage2 bootstrap, LLVM runtimes, and Docker-based reproducible builds. Produces the compiler artifact at `build/stage2/bin/clang`.

## Core Responsibilities
- Run `bash scripts/build.sh` with config from `config/build.conf`
- Manage CMake build: stage1 (host gcc bootstrap) → stage2 (self-hosted clang)
- Build LLVM runtimes: `compiler-rt`, `libunwind`, `libcxx`, `libcxxabi`
- Configure `LLVM_TARGETS_TO_BUILD` for AArch64, ARM, X86 (Android kernel targets)
- Build Docker image: `docker build -t oronyx-clang .`
- Verify output: `build/stage1/bin/clang --version` reports `Oronyx-Clang 18.x`

## When This Skill Activates
| Trigger | Event | Condition |
|---|---|---|
| Push | `refs/heads/main` or `release/*` | Changes to `scripts/`, `Makefile`, `config/`, `Dockerfile` |
| Manual | `workflow_dispatch` | `build_action: build|docker|rebuild` |
| Schedule | Weekly Sunday 02:00 UTC | Scheduled rebuild for LLVM upstream updates |

## Tech Stack
- **Language**: C++ (LLVM source), Shell (build scripts), Python (config)
- **Build**: CMake 3.25+, Ninja, GNU Make, Docker, `ccache`
- **Targets**: AArch64, ARM, X86 (LLVM_TARGETS_TO_BUILD)
- **Key files**: `scripts/build.sh`, `config/build.conf`, `Dockerfile`, `Makefile`
- **Constraints**: Oronyx Clang must NOT be added to GITHUB_PATH; use `ORONYX_CLANG_DIR` instead

## Automated Checks
```yaml
checks:
  - id: "TCB-001"
    name: "LLVM Source Integrity"
    command: |
      [ -f llvm-project/llvm/CMakeLists.txt ] || git submodule update --init --recursive
      echo "LLVM_SOURCE_OK"
    severity: "critical"
  - id: "TCB-002"
    name: "CMake Configuration Success"
    command: |
      cmake -G Ninja -S llvm-project/llvm -B build/stage1 \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86" 2>&1 | tail -5
      [ -f build/stage1/build.ninja ] && echo "CMAKE_OK"
    severity: "critical"
  - id: "TCB-003"
    name: "Stage1 Compilation"
    command: |
      ninja -C build/stage1 clang lld 2>&1 | tail -5
      [ -f build/stage1/bin/clang ] && echo "STAGE1_CLANG_OK"
    severity: "critical"
  - id: "TCB-004"
    name: "Docker Build"
    command: |
      docker build -t oronyx-clang:latest . 2>&1 | tail -3
      docker run --rm oronyx-clang:latest clang --version | grep -q "Oronyx-Clang 18" && echo "DOCKER_OK"
    severity: "critical"
```

## Input/Output Schema
```json
{
  "inputs": [
    {"name": "build_action", "type": "string", "enum": ["build", "docker", "rebuild"]},
    {"name": "targets", "type": "string", "default": "AArch64;ARM;X86"},
    {"name": "jobs", "type": "integer", "default": 4}
  ],
  "outputs": {
    "version": "string",
    "stage1_clang": "string (path)",
    "stage2_clang": "string (path)",
    "docker_image": "string",
    "build_log": "string (path)"
  }
}
```

## Error Recovery
- **CMake config fails**: Check `llvm-project/` submodule existence; verify CMake 3.25+ version; check `config/build.conf` syntax
- **Stage1 build OOM**: Reduce jobs with `-j2`; ensure 8GB+ RAM available; use `ccache` to reduce rebuild time
- **Docker build fails**: Check `Dockerfile` for LLVM source copy; increase Docker memory to 16GB; prune build cache
- **Clang version mismatch**: Verify `LLVM_VERSION` in `config/build.conf` matches expected 18.x tag
