# Compiler Optimizer (PGO/LTO/BOLT/Polly) - Oronyx Clang

## Overview
Optimizes the Oronyx Clang toolchain using PGO (Profile-Guided Optimization), ThinLTO (Thin Link-Time Optimization), BOLT (Binary Optimization & Layout Tool), and Polly polyhedral loop optimizations. Configures via `config/build.conf`, validates profile data integrity, and generates optimized stage2 binaries.

## Core Responsibilities
- Enable and configure PGO: verify `profiles/*.profdata` exist and non-corrupt via `llvm-profdata show`
- Enable ThinLTO: verify `build/thinlto-cache/` contains module files post-build
- Enable BOLT: confirm `.bolt` instrumented binary generated before final optimization pass
- Enable Polly: verify `opt -passes='print<polly-ast>'` recognizes Polly passes
- Tune `config/build.conf` flags: `PGO_ENABLED`, `THINLTO_ENABLED`, `BOLT_ENABLED`, `POLLY_ENABLED`
- Compare optimized vs baseline binary size and build time

## When This Skill Activates
| Trigger | Event | Condition |
|---|---|---|
| Push | `refs/heads/main` | Changes to `config/build.conf`, `scripts/build.sh` |
| Manual | `workflow_dispatch` | `opt_config: pgo|thinlto|bolt|polly|all` |
| Schedule | Weekly Saturday 02:00 UTC | Full optimization validation |

## Tech Stack
- **Optimizations**: PGO (profiles/*.profdata), ThinLTO (thinlto-cache/), BOLT (.bolt binary), Polly (polyhedral)
- **Tools**: `llvm-profdata`, `llvm-cov`, `opt`, `llc`, `perf`
- **Config**: `config/build.conf` (LLVM_ENABLE_* flags), `config/baseline.json` (benchmark reference)
- **Constraints**: PGO needs representative workload; BOLT needs perf data; ThinLTO needs sufficient RAM

## Automated Checks
```yaml
checks:
  - id: "COP-001"
    name: "PGO Profile Integrity"
    command: |
      [ -d profiles ] && for f in profiles/*.profdata; do
        llvm-profdata show "$f" | head -1
      done; echo "PGO_PROFILES_OK"
    severity: "high"
  - id: "COP-002"
    name: "ThinLTO Cache Existence"
    command: |
      [ -d build/thinlto-cache ] && MODS=$(find build/thinlto-cache -name '*.thinlto.*' | wc -l)
      [ "$MODS" -ge 1 ] && echo "THINLTO_CACHE_OK ($MODS modules)" || echo "THINLTO_CACHE_MISSING"
    severity: "high"
  - id: "COP-003"
    name: "BOLT Instrumentation"
    command: |
      BOLT_BIN=$(find build/stage2/bin -name "*.bolt" 2>/dev/null | head -1)
      [ -n "$BOLT_BIN" ] && echo "BOLT_INSTRUMENTED" || echo "BOLT_CHECK_SKIPPED"
    severity: "medium"
  - id: "COP-004"
    name: "Polly Pass Recognition"
    command: |
      echo "int main(){}" | clang -O3 -mllvm -polly -x c - -o /dev/null 2>&1 || true
      echo "POLLY_CHECK_DONE"
    severity: "medium"
```

## Input/Output Schema
```json
{
  "inputs": [
    {"name": "opt_config", "type": "string", "enum": ["pgo", "thinlto", "bolt", "polly", "all"]},
    {"name": "profile_data", "type": "string", "default": "./profiles"}
  ],
  "outputs": {
    "pgo_profiles_valid": "integer",
    "thinlto_modules": "integer",
    "bolt_instrumented": "boolean",
    "polly_available": "boolean",
    "opt_status": "pass|fail"
  }
}
```

## Error Recovery
- **PGO profile corrupt**: Regenerate profiles: `bash scripts/generate-pgo-profiles.sh` → `llvm-profdata merge -output=profiles/merged.profdata profiles/*.profraw`
- **ThinLTO module count zero**: Ensure `LLVM_ENABLE_LTO=Thin` in cmake config; increase `vm.mmap_min_addr`
- **BOLT not producing optimized binary**: Check `perf` data format; verify BOLT version matches LLVM version
- **Polly passes not recognized**: Rebuild LLVM with `LLVM_ENABLE_PROJECTS="clang;lld;polly"` in cmake
