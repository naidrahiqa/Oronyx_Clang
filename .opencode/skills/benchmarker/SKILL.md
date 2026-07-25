# Benchmarker - Oronyx Clang

## Overview
Benchmarks the Oronyx Clang toolchain performance against stored baselines in `config/baseline.json`. Measures build time, binary size, compile speed (kernel builds), and code generation quality. Generates comparison reports with regression detection (>5% delta triggers warning).

## Core Responsibilities
- Run `bash scripts/benchmark.sh` to measure compiler performance
- Record metrics: build time (stage1, stage2), clang binary size, kernel compilation throughput
- Compare against `config/baseline.json` stored reference values
- Detect regression >5% in any metric and flag for investigation
- Generate `build/optimizer-report.json` with full benchmark results
- Run kernel compilation benchmark: compile a reference 4.19 kernel defconfig

## When This Skill Activates
| Trigger | Event | Condition |
|---|---|---|
| Push | `refs/heads/main` or `release/*` | After toolchain build completes |
| Manual | `workflow_dispatch` | `bench_action: quick|full|compare` |
| Schedule | Weekly Sunday 02:00 UTC | Automated benchmark regression check |

## Tech Stack
- **Benchmark tools**: `time`, `perf stat`, `scripts/benchmark.sh`, `scripts/kernel_bench.sh`
- **Metrics**: wall time (s), binary size (bytes), kernel compile time (s), object size (bytes)
- **Storage**: `config/baseline.json` (reference), `build/optimizer-report.json` (current)
- **Target**: Compile reference kernel (4.19 defconfig) under benchmark

## Automated Checks
```yaml
checks:
  - id: "BNC-001"
    name: "Baseline Config Exists"
    command: |
      [ -f config/baseline.json ] && echo "BASELINE_EXISTS" || echo "NO_BASELINE"
    severity: "high"
  - id: "BNC-002"
    name: "Quick Benchmark Run"
    command: |
      bash scripts/benchmark.sh --quick 2>&1 | tee build/bench_quick.log
      echo "QUICK_BENCH_DONE"
    severity: "medium"
  - id: "BNC-003"
    name: "Regression Detection"
    command: |
      [ -f build/optimizer-report.json ] && [ -f config/baseline.json ] && python3 -c "
import json
with open('config/baseline.json') as f: base = json.load(f)
with open('build/optimizer-report.json') as f: cur = json.load(f)
delta = (cur['artifact_size_bytes'] - base['artifact_size_bytes']) / base['artifact_size_bytes'] * 100
print(f'Delta: {delta:.2f}%')
if abs(delta) > 5: print('REGRESSION_DETECTED')
else: print('DELTA_OK')
"
    severity: "high"
  - id: "BNC-004"
    name: "Kernel Compile Benchmark"
    command: |
      [ -f scripts/kernel_bench.sh ] && bash scripts/kernel_bench.sh --defconfig=gki_defconfig 2>&1 | tee kernel_bench.log
      echo "KERNEL_BENCH_DONE"
    severity: "medium"
```

## Input/Output Schema
```json
{
  "inputs": [
    {"name": "bench_action", "type": "string", "enum": ["quick", "full", "compare"]},
    {"name": "baseline_ref", "type": "string", "default": "HEAD~1"}
  ],
  "outputs": {
    "build_time_s": "integer",
    "artifact_size_bytes": "integer",
    "kernel_compile_time_s": "float",
    "delta_percent": "float",
    "regression": "boolean",
    "report_path": "string"
  }
}
```

## Error Recovery
- **Benchmark script not found**: Verify `scripts/benchmark.sh` exists and is executable
- **Baseline JSON parse error**: Validate `config/baseline.json` syntax with `python3 -c "import json; json.load(open('config/baseline.json'))"`
- **>5% regression**: Run `git bisect` to find culprit; compare `config/build.conf` flags with baseline commit
- **Kernel benchmark fails**: Ensure reference kernel source is available (download via `scripts/fetch_kernel.sh`)
