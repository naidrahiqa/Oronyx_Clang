# Compiler Build Optimizer Skill

## 📋 Overview
Optimizes and validates the Oronyx Clang custom LLVM/Clang 18 toolchain build for Android kernel compilation. This skill drives PGO (Profile-Guided Optimization), ThinLTO (Thin Link-Time Optimization), BOLT (Binary Optimization and Layout Tool), and Polly loop optimizations. It verifies the correctness of build artifacts, benchmarks compiler performance against baseline, and ensures Docker-based reproducible builds succeed.

## 🎯 Core Responsibilities
- Run `make build` or `bash scripts/build.sh` and verify artifact generation
- Validate LLVM/Clang version matches expected 18.x release
- Confirm PGO profile data is available and non-corrupt before an optimized build
- Check ThinLTO cache directory exists and contains expected module files
- Execute `bash scripts/benchmark.sh` and compare results against stored baselines
- Run Docker build with `docker build -t oronyx-clang .`
- Inspect generated bitcode with `llvm-dis`, `opt`, and `llc` for correctness
- Verify BOLT instrumentation and optimization stages produce valid binaries

## 🚀 When This Skill Activates
| Trigger Type | Event | Condition |
|---|---|---|
| `git push` | Push to `main` or `release/*` | Changes in `scripts/`, `Makefile`, `config/`, `Dockerfile`, `*.cmake`, `*.py` |
| `schedule` | Weekly Sunday 02:00 | Benchmark regression check against stored baseline |
| `manual` | Workflow dispatch | User selects `build` / `benchmark` / `docker` / `validate` / `full` |

## 🛠 Tech Stack Required
```yaml
languages:
  - Shell (Bash 5+)
  - Python 3.10+
  - Makefile / CMake
compilers:
  - LLVM 18.x (clang, clang++, llvm-dis, opt, llc, llvm-ar, llvm-nm)
  - GCC (bootstrapping host compiler)
tools:
  - Docker (buildx, compose)
  - Ninja / GNU Make
  - perf / perf_event_open (for PGO)
  - cmake (3.25+)
  - git (2.30+)
optimization_passes:
  - PGO (Profile-Guided Optimization)
  - ThinLTO (ThinLTO)
  - BOLT (Binary Optimization & Layout Tool)
  - Polly (polyhedral loop optimizations)
```

## 📊 Workflow & Process Pipeline

### Phase 1: DETECTION & ANALYSIS
- Detect changes to `scripts/*`, `Makefile`, `Dockerfile`, `config/build.conf`, or `*.cmake`
- Parse `config/build.conf` for `LLVM_VERSION`, `PGO_ENABLED`, `THINLTO_ENABLED`, `BOLT_ENABLED`, `POLLY_ENABLED`
- Check host system: `clang --version`, `cmake --version`, `python3 --version`
- Identify available physical CPUs and memory for parallel build tuning (`nproc`, `free -g`)

### Phase 2: DEEP DIVE INVESTIGATION
- Run full build with `bash scripts/build.sh` and capture build log to `build/build.log`
- If PGO enabled: verify `.profdata` files exist in `profiles/` and are non-corrupt with `llvm-profdata show`
- If ThinLTO enabled: check `build/thinlto-cache/` for index files and module summaries
- If BOLT enabled: confirm `.bolt` instrumented binary is generated before final optimization
- Run `bash scripts/benchmark.sh` — capture wall time, memory peak, and output binary size
- Compare benchmark results with `config/baseline.json`; flag regression >5%

### Phase 3: VALIDATION & VERIFICATION
- Run `llvm-dis < builtins.bc` to disassemble generated bitcode and verify structure
- Run `opt -passes='verify' < builtins.bc > /dev/null` to confirm IR validity
- Run `llc -O2 -filetype=obj builtins.bc -o builtins.o` to confirm object emission
- Check `build/stage1/bin/clang --version` reports `Oronyx-Clang 18.x`
- Verify Docker image builds and `docker run --rm oronyx-clang clang --version` succeeds

### Phase 4: REPORT GENERATION
- Generate `build/optimizer-report.json` with: build status, LLVM version, PGO/ThinLTO/BOLT/Polly flags, benchmark delta, artifact sizes
- Append benchmark delta from baseline to report
- Post report as GitHub Actions artifact or CLI stdout

## ✅ AUTOMATED CHECKS (EXECUTABLE COMMANDS)
```yaml
quality_checks:
  - check_id: "CHK-001"
    name: "LLVM Version Validation"
    command: |
      "$PROJECT_DIR/build/stage1/bin/clang" --version 2>&1 | Select-String -Pattern "Oronyx-Clang 18\."
    expected_output: "Oronyx-Clang 18."
    failure_indicator: "not found"
    severity: "critical"

  - check_id: "CHK-002"
    name: "PGO Profile Data Integrity"
    command: |
      if (Test-Path "$PROJECT_DIR/profiles/") {
        $files = Get-ChildItem -Path "$PROJECT_DIR/profiles/" -Filter "*.profdata"
        if ($files.Count -eq 0) { Write-Error "No .profdata files found"; exit 1 }
        foreach ($f in $files) {
          & "llvm-profdata" show $f.FullName 2>&1 | Select-Object -First 3
          if ($LASTEXITCODE -ne 0) { Write-Error "Corrupt profile: $($f.Name)"; exit 1 }
        }
        Write-Output "PGO profiles OK ($($files.Count) files)"
      } else {
        Write-Output "PGO disabled (no profiles/ directory)"
      }
    expected_output: "PGO profiles OK"
    failure_indicator: "Corrupt profile|No .profdata files found"
    severity: "high"

  - check_id: "CHK-003"
    name: "ThinLTO Cache Validation"
    command: |
      $cache = "$PROJECT_DIR/build/thinlto-cache"
      if (Test-Path $cache) {
        $modules = Get-ChildItem -Path $cache -Filter "*.o" -Recurse
        $indexes = Get-ChildItem -Path $cache -Filter "*.thinlto.*" -Recurse
        if ($modules.Count -eq 0 -and $indexes.Count -eq 0) {
          Write-Error "ThinLTO cache empty"; exit 1
        }
        Write-Output "ThinLTO cache: $($modules.Count) modules, $($indexes.Count) indexes"
      } else {
        if ((Get-Content "$PROJECT_DIR/config/build.conf" | Select-String "THINLTO_ENABLED=true")) {
          Write-Error "ThinLTO enabled but cache missing"; exit 1
        }
        Write-Output "ThinLTO disabled"
      }
    expected_output: "ThinLTO cache:"
    failure_indicator: "ThinLTO enabled but cache missing"
    severity: "high"

  - check_id: "CHK-004"
    name: "Benchmark vs Baseline Comparison"
    command: |
      $report = "$PROJECT_DIR/build/optimizer-report.json"
      if (Test-Path $report) {
        $json = Get-Content $report | ConvertFrom-Json
        $baseline = "$PROJECT_DIR/config/baseline.json"
        if (Test-Path $baseline) {
          $base = Get-Content $baseline | ConvertFrom-Json
          $delta = [math]::Round(($json.artifact_size_bytes - $base.artifact_size_bytes) / $base.artifact_size_bytes * 100, 2)
          Write-Output "Baseline: $($base.artifact_size_bytes) bytes | Current: $($json.artifact_size_bytes) bytes | Delta: $delta%"
          if ([math]::Abs($delta) -gt 5.0) { Write-Warning "Regression detected: $delta%" }
        } else { Write-Output "No baseline file found" }
      } else { Write-Error "No optimizer report found at $report"; exit 1 }
    expected_output: "Baseline:"
    failure_indicator: "No optimizer report found"
    severity: "medium"

  - check_id: "CHK-005"
    name: "Docker Build & Version Check"
    command: |
      cd "$PROJECT_DIR"
      docker build -t oronyx-clang:latest . 2>&1 | Select-Object -Last 3
      if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed"; exit 1 }
      $version = docker run --rm oronyx-clang:latest clang --version 2>&1 | Select-String "Oronyx-Clang 18\."
      if (-not $version) { Write-Error "Docker image has wrong clang version"; exit 1 }
      Write-Output "Docker build OK — $($version.ToString().Trim())"
    expected_output: "Docker build OK — Oronyx-Clang 18."
    failure_indicator: "Docker build failed|wrong clang version"
    severity: "critical"

  - check_id: "CHK-006"
    name: "Bitcode IR Verification with opt"
    command: |
      $builtinsBc = "$PROJECT_DIR/build/lib/clang/18.0.0/lib/windows/libclang_rt.builtins-x86_64.bc"
      if (Test-Path $builtinsBc) {
        & opt -passes='verify' $builtinsBc -o /dev/null 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Error "IR verification failed"; exit 1 }
        $size = (Get-Item $builtinsBc).Length
        Write-Output "IR verified OK — $size bytes"
      } else {
        $anyBc = Get-ChildItem -Path "$PROJECT_DIR/build/" -Recurse -Filter "*.bc" | Select-Object -First 1
        if (-not $anyBc) { Write-Warning "No bitcode files found to verify"; return }
        & opt -passes='verify' $anyBc.FullName -o /dev/null 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Error "IR verification failed for $($anyBc.Name)"; exit 1 }
        Write-Output "IR verified OK — $($anyBc.Name)"
      }
    expected_output: "IR verified OK"
    failure_indicator: "IR verification failed"
    severity: "high"

  - check_id: "CHK-007"
    name: "BOLT Instrumentation Verification"
    command: |
      $conf = "$PROJECT_DIR/config/build.conf"
      if (Test-Path $conf) {
        $boltEnabled = Select-String -Path $conf -Pattern "BOLT_ENABLED=true"
        if ($boltEnabled) {
          $instrumented = Get-ChildItem -Path "$PROJECT_DIR/build/" -Recurse -Filter "*.bolt" | Select-Object -First 1
          if (-not $instrumented) {
            $stage2Bin = Get-ChildItem -Path "$PROJECT_DIR/build/stage2/bin/" -Filter "clang.exe" -Recurse | Select-Object -First 1
            if ($stage2Bin) { Write-Output "BOLT enabled — stage2 available, check perf data" }
            else { Write-Error "BOLT enabled but no instrumented binary found"; exit 1 }
          } else { Write-Output "BOLT instrumented binary: $($instrumented.Name) ($($instrumented.Length) bytes)" }
        } else { Write-Output "BOLT disabled" }
      } else { Write-Warning "No build.conf found" }
    expected_output: "BOLT enabled"
    failure_indicator: "BOLT enabled but no instrumented binary found"
    severity: "medium"

  - check_id: "CHK-008"
    name: "Polly Loop Optimization Detection"
    command: |
      $conf = "$PROJECT_DIR/config/build.conf"
      if (Test-Path $conf) {
        $pollyEnabled = Select-String -Path $conf -Pattern "POLLY_ENABLED=true"
        if ($pollyEnabled) {
          $pollyPass = & opt -passes='print<polly-ast>' -disable-output "$PROJECT_DIR/build/lib/clang/18.0.0/lib/windows/libclang_rt.builtins-x86_64.bc" 2>&1
          if ($LASTEXITCODE -eq 0) { Write-Output "Polly passes recognized — OK" }
          else { Write-Warning "Polly enabled but passes may not be applied" }
        } else { Write-Output "Polly disabled" }
      } else { Write-Output "No build.conf — check skipped" }
    expected_output: "Polly"
    failure_indicator: "Polly enabled but passes may not be applied"
    severity: "low"
```

## 📥 INPUT SCHEMA
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["project_dir", "actions"],
  "properties": {
    "project_dir": {
      "type": "string",
      "description": "Absolute path to Oronyx-clang project root"
    },
    "actions": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": [
          "build", "benchmark", "docker", "validate_llvm", "validate_pgo",
          "validate_thinlto", "validate_bitcode", "validate_bolt", "validate_polly"
        ]
      },
      "description": "Build and validation actions to execute"
    },
    "config_overrides": {
      "type": "object",
      "properties": {
        "jobs":      { "type": "integer", "description": "Parallel build jobs" },
        "pgo":       { "type": "boolean" },
        "thinlto":   { "type": "boolean" },
        "bolt":      { "type": "boolean" },
        "polly":     { "type": "boolean" }
      },
      "description": "Override build configuration flags"
    }
  }
}
```

## 📤 OUTPUT SCHEMA
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["overall_status", "actions", "timestamp"],
  "properties": {
    "overall_status": {
      "type": "string",
      "enum": ["PASS", "FAIL", "WARN"]
    },
    "actions": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "action":      { "type": "string" },
          "status":      { "type": "string", "enum": ["PASS", "FAIL", "SKIP"] },
          "duration_ms": { "type": "integer" },
          "output":      { "type": "string" },
          "errors":      { "type": "array", "items": { "type": "string" } }
        }
      }
    },
    "timestamp": { "type": "string", "format": "date-time" },
    "build_config": {
      "type": "object",
      "properties": {
        "llvm_version": { "type": "string" },
        "pgo":          { "type": "boolean" },
        "thinlto":      { "type": "boolean" },
        "bolt":         { "type": "boolean" },
        "polly":        { "type": "boolean" }
      }
    },
    "benchmark": {
      "type": "object",
      "properties": {
        "artifact_size_bytes": { "type": "integer" },
        "build_time_ms":       { "type": "integer" },
        "delta_percent":       { "type": "number" }
      }
    }
  }
}
```

## 🔌 INTEGRATION IMPLEMENTATIONS

### GitHub Actions
```yaml
name: Compiler Build Optimizer
on:
  push:
    branches: [main, release/*]
    paths: ['scripts/**', 'Makefile', 'Dockerfile', 'config/**', '*.cmake', '*.py']
  schedule:
    - cron: '0 2 * * 0'
  workflow_dispatch:
    inputs:
      actions:
        description: 'Comma-separated: build,benchmark,docker,validate_llvm,validate_pgo,validate_thinlto,validate_bitcode,validate_bolt,validate_polly'
        required: false
        default: 'build,validate_llvm,validate_pgo,validate_thinlto,validate_bitcode'

jobs:
  build-optimize:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - name: Install Dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y cmake ninja-build python3-pip llvm-18-tools
          pip3 install --upgrade pip
      - name: Run Full Build
        id: build
        run: |
          bash scripts/build.sh 2>&1 | tee build/build.log
          echo "status=$?" >> $GITHUB_OUTPUT
      - name: Validate LLVM Version
        if: always()
        run: |
          build/stage1/bin/clang --version | grep "Oronyx-Clang 18\."
      - name: Validate PGO Profiles
        if: always()
        run: |
          if [ -d profiles ]; then
            for f in profiles/*.profdata; do
              llvm-profdata show "$f" | head -3
            done
            echo "PGO profiles OK"
          else
            echo "PGO disabled"
          fi
      - name: Validate ThinLTO Cache
        if: always()
        run: |
          if [ -d build/thinlto-cache ]; then
            echo "ThinLTO cache: $(find build/thinlto-cache -name '*.o' | wc -l) modules"
          else
            echo "ThinLTO cache not found (may be disabled)"
          fi
      - name: Run Benchmark
        id: benchmark
        if: always()
        run: |
          bash scripts/benchmark.sh 2>&1 | tee build/benchmark.log
      - name: Compare with Baseline
        if: always()
        run: |
          if [ -f config/baseline.json ] && [ -f build/optimizer-report.json ]; then
            python3 -c "
              import json
              with open('config/baseline.json') as f: base = json.load(f)
              with open('build/optimizer-report.json') as f: cur = json.load(f)
              delta = (cur['artifact_size_bytes'] - base['artifact_size_bytes']) / base['artifact_size_bytes'] * 100
              print(f'Baseline: {base[\"artifact_size_bytes\"]} bytes | Current: {cur[\"artifact_size_bytes\"]} bytes | Delta: {delta:.2f}%')
              if abs(delta) > 5: exit(1)
            "
          else:
            echo "Baseline comparison skipped (files missing)"
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: build-artifacts
          path: |
            build/
            config/
```

### CLI Interface
```bash
# Full optimization pipeline
export PROJECT_DIR=/path/to/Oronyx-clang
cd $PROJECT_DIR && bash scripts/build.sh && bash scripts/benchmark.sh

# Validate LLVM version
build/stage1/bin/clang --version | grep "Oronyx-Clang 18"

# Validate PGO profiles
llvm-profdata show profiles/*.profdata

# Inspect ThinLTO cache
ls -la build/thinlto-cache/

# Verify bitcode IR
opt -passes='verify' build/lib/clang/18.0.0/lib/windows/libclang_rt.builtins-x86_64.bc -o /dev/null

# Docker build + smoke test
docker build -t oronyx-clang:latest . && docker run --rm oronyx-clang:latest clang --version

# Benchmark comparison
powershell -Command "
  \$cur = Get-Content build/optimizer-report.json | ConvertFrom-Json;
  \$base = Get-Content config/baseline.json | ConvertFrom-Json;
  \$delta = [math]::Round((\$cur.artifact_size_bytes - \$base.artifact_size_bytes) / \$base.artifact_size_bytes * 100, 2);
  Write-Output \"Delta: \$delta%\";
  if ([math]::Abs(\$delta) -gt 5) { Write-Warning 'Regression!' }
"
```

## 📝 ERROR HANDLING & RECOVERY
```yaml
errors:
  - error: "Build failure at stage1 or stage2"
    cause: "Missing LLVM source submodules, cmake configuration mismatch, or insufficient memory"
    recovery: |
      run: |
        cd "$PROJECT_DIR"
        git submodule update --init --recursive
        rm -rf build/stage1 build/stage2
        bash scripts/build.sh --clean 2>&1 | tee build/build.log
    escalation: "Review cmake/Modules/ and config/build.conf for LLVM_TARGETS_TO_BUILD"

  - error: "PGO profile corruption"
    cause: "Interrupted profiling run or incompatible LLVM version"
    recovery: |
      run: |
        cd "$PROJECT_DIR"
        rm -rf profiles/
        bash scripts/generate-pgo-profiles.sh
        llvm-profdata merge -output=profiles/merged.profdata profiles/*.profraw
    escalation: "Check profiling workload in scripts/generate-pgo-profiles.sh"

  - error: "ThinLTO cache stale or missing"
    cause: "Incremental build with changed flags, or cache cleaned"
    recovery: |
      run: |
        cd "$PROJECT_DIR"
        rm -rf build/thinlto-cache
        bash scripts/build.sh --thinlto-only
    escalation: "Verify -flto=thin flag in cmake/options.cmake"

  - error: "Benchmark regression >5%"
    cause: "Code change in LLVM passes, different PGO data, or host variance"
    recovery: |
      run: |
        cd "$PROJECT_DIR"
        git bisect start
        git bisect bad HEAD
        git bisect good HEAD~10
        # Use scripts/bisect-build.sh to automate
    escalation: "Compare config/build.conf with baseline commit; pin PGO data version"

  - error: "Docker build OOM"
    cause: "Insufficient memory allocation for Docker Desktop"
    recovery: |
      run: |
        docker system prune -a --volumes -f
        docker build --memory=8g --memory-swap=16g -t oronyx-clang:latest .
    escalation: "Increase Docker memory limit in settings to 16 GB minimum"
```

## 🎓 CLI USAGE EXAMPLES
```bash
# Full build and benchmark
cd D:\Dev\Project-Coding\2026\skills\Oronyx-clang
$env:PROJECT_DIR = (Get-Location).Path
bash scripts/build.sh
bash scripts/benchmark.sh

# Quick LLVM version check
.\build\stage1\bin\clang.exe --version

# PGO profile inspection
llvm-profdata show profiles/merged.profdata

# ThinLTO module listing
Get-ChildItem -Path build/thinlto-cache/ -Recurse -Filter "*.thinlto.*"

# Bitcode disassembly with llvm-dis
llvm-dis build/lib/clang/18.0.0/lib/windows/libclang_rt.builtins-x86_64.bc -o output.ll
Get-Content output.ll -Head 50

# Docker smoke test
docker build -t oronyx-clang . --no-cache
docker run --rm oronyx-clang clang --version
docker run --rm oronyx-clang llvm-dis --version

# BOLT optimization check
Get-ChildItem -Path build/ -Recurse -Filter "*.bolt" | ForEach-Object { Write-Output "$($_.Name) — $($_.Length) bytes" }

# Read current build configuration
Get-Content config/build.conf

# Generate optimizer report manually
powershell -Command "
  \$report = @{
    overall_status = 'PASS';
    actions = @();
    timestamp = (Get-Date -Format o);
    build_config = @{
      llvm_version = (Get-Content config/build.conf | Select-String 'LLVM_VERSION').ToString().Split('=')[1].Trim();
      pgo    = (Select-String -Path config/build.conf -Pattern 'PGO_ENABLED=true') -ne $null;
      thinlto= (Select-String -Path config/build.conf -Pattern 'THINLTO_ENABLED=true') -ne $null;
      bolt   = (Select-String -Path config/build.conf -Pattern 'BOLT_ENABLED=true') -ne $null;
      polly  = (Select-String -Path config/build.conf -Pattern 'POLLY_ENABLED=true') -ne $null;
    };
    benchmark = @{
      artifact_size_bytes = (Get-Item 'build/stage2/bin/clang.exe').Length;
      build_time_ms = 0;
      delta_percent = 0
    }
  };
  \$report | ConvertTo-Json -Depth 5 | Set-Content build/optimizer-report.json;
  Write-Output 'Report saved'
"
```

## 🔐 CONFIGURATION & SECURITY
```yaml
environment:
  LLVM_VERSION: "18.1.0"
  CC: "clang"
  CXX: "clang++"
  CMAKE_GENERATOR: "Ninja"
  PROJECT_DIR: "D:\\Dev\\Project-Coding\\2026\\skills\\Oronyx-clang"

config_files:
  - path: "config/build.conf"
    required: true
    description: "Core build flags: LLVM_TARGETS, PGO, ThinLTO, BOLT, Polly toggles"
  - path: "config/baseline.json"
    required: false
    description: "Stored benchmark results for regression detection"

security:
  - rule: "Never bake credentials into config/build.conf; use environment variables or .env files"
  - rule: "Pin LLVM source to signed commits/tags; verify with `git verify-tag`"
  - rule: "Do not run untrusted Docker images; build from Dockerfile only"
  - rule: "Use `cmake --build . --target install` rather than sudo make install to avoid system pollution"
  - rule: "Validate PGO profiles are generated from trusted workloads only (profiles/ should be gitignored)"
  - rule: "Set ulimit -n 65536 and vm.mmap_min_addr=65536 in Docker for large ThinLTO builds"
```

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `compiler-build-optimizer` |
| **Triggers** | `push_to_main`, `pr_opened`, `schedule_daily`, `tag_created` |
| **Dependencies** | `master-reference` (project context), `llvm-runtimes-fixer` (if cross-compile) |
| **Depended By** | `debugging` (build failure context) |
| **Workflows** | `pr-review` (step 1), `release-build` (step 2), `daily-build` (step 1), `llvm-update-check` (step 1) |
| **Routing Rule** | Files changed in `scripts/`, `config/`, `Makefile`, `Dockerfile` → route to this skill |
| **Data Flow** | Output (build logs, artifacts) → `debugging` on failure |
