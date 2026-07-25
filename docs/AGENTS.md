# AGENTS.md — Oronyx Clang

Custom LLVM/Clang 18.x toolchain optimized for Android kernel compilation. PGO, ThinLTO, BOLT, Polly.

---

## Team Registry

| Role | ID | Core Skill |
|------|-----|------------|
| Toolchain Builder | `builder` | `compiler-build-optimizer` |
| Compiler Optimizer | `optimizer` | `compiler-build-optimizer` |
| Benchmark Runner | `benchmarker` | `compiler-build-optimizer` |
| Code Reviewer | `reviewer` | `compiler-build-optimizer` |

## Core Skill

### Compiler Build Optimizer Skill
- **ID**: `compiler-build-optimizer`
- **File**: `SKILL.md`
- **Responsibility**: Build LLVM/Clang from source, validate PGO/ThinLTO/BOLT/Polly, Docker build, benchmark against baselines, generate charts
- **Triggers**: Push to main, schedule weekly, manual
- **Input Type**: git-context / build-artifacts
- **Output Type**: json / artifact
- **Runtime**: ~7200s (toolchain build)
- **Owner**: builder, optimizer, benchmarker

## Role Skills

| Role | Skill File | Responsibility |
|------|-----------|----------------|
| Toolchain Builder (LLVM/Clang) | `../../.opencode/skills/toolchain-builder/SKILL.md` | Build LLVM/Clang 18 from source; CMake/Ninja; stage1/stage2 bootstrap; Docker build |
| Compiler Optimizer (PGO/LTO/BOLT/Polly) | `../../.opencode/skills/compiler-optimizer/SKILL.md` | Configure/tune PGO/ThinLTO/BOLT/Polly; validate profile data; optimize stage2 |
| Benchmarker | `../../.opencode/skills/benchmarker/SKILL.md` | Run benchmarks; compare vs baseline; detect regression >5%; generate optimizer-report |
| Code Reviewer | `../../.opencode/skills/code-reviewer/SKILL.md` | Review LLVM patches/scripts/cmake/Dockerfile; enforce no GITHUB_PATH; lint checks |
| LLVM Runtimes | `../../.opencode/skills/llvm-runtimes/SKILL.md` | Fix libcxx/libcxxabi build issues; runtime linking; ABI compatibility |
| Debugger | `../../.opencode/skills/debugging/SKILL.md` | Debug build failures; analyze error logs; trace compiler crashes |
| Security Auditor | `../../.opencode/skills/security/SKILL.md` | Security review; vulnerability assessment; dependency audit |
| Universal Auditor | `../../.opencode/skills/audit/SKILL.md` | Project-wide audit; code quality; structure validation |
| Refactoring | `../../.opencode/skills/refactoring/SKILL.md` | Code cleanup; tech debt reduction; optimization |
| Planning | `../../.opencode/skills/planning/SKILL.md` | Architecture planning; workflow design; task breakdown |
| Professional | `../../.opencode/skills/profesional/SKILL.md` | Code quality standards; best practices enforcement |
| DOM Debug | `../../.opencode/skills/DOM/SKILL.MD` | Browser automation; DOM debugging; web page inspection |

## Workflow Definitions

### Workflow: Toolchain Build
**ID**: `toolchain-build`
**Trigger**: Push to main, scheduled

**Steps:**
1. **Build** → `compiler-build-optimizer` → on failure: halt, retry: 1
2. **Benchmark** → `compiler-build-optimizer` → on failure: notify_only (depends: step 1)
3. **Optimize** → `compiler-build-optimizer` → on failure: notify_only (depends: step 1)

**Output Actions**: GitHub release with packaged toolchain + benchmark report
**Est. Duration**: ~9000 seconds

### Workflow: Optimization Tuning
**ID**: `optimization`
**Trigger**: Manual request

**Steps:**
1. **Tune Flags** → `compiler-build-optimizer` → on failure: halt
2. **Build** → `compiler-build-optimizer` → on failure: halt
3. **Benchmark** → `compiler-build-optimizer` → on failure: notify_only

## Notifications

| Channel | Trigger | Recipients |
|---------|---------|------------|
| GitHub Release | Build complete | builder, optimizer |
| GitHub Commit Status | Build failure | builder |

## Project Context

```json
{
  "project_name": "Oronyx Clang",
  "project_type": "compiler",
  "primary_languages": ["C++", "Shell", "Python"],
  "ci_cd_platform": "github-actions",
  "stage": "development"
}
```
