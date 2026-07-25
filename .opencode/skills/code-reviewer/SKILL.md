# Code Reviewer - Oronyx Clang

## Overview
Reviews all code contributions to Oronyx Clang: LLVM/Clang patches, build scripts (`scripts/`), CMake configuration (`config/`), Dockerfile, and Python utility scripts. Enforces LLVM coding standards, build reproducibility, and no regression in optimization flags.

## Core Responsibilities
- Review LLVM/Clang patches: verify `Signed-off-by`, commit message format per LLVM conventions
- Review build scripts (`scripts/`): ensure POSIX shell, error handling, `ORONYX_CLANG_DIR` path safety
- Review CMake config: verify `config/build.conf` flags don't break Android kernel target compilation
- Review Dockerfile: ensure multi-stage build, cache efficiency, no hardcoded secrets
- Enforce: Oronyx Clang must NEVER be added to `GITHUB_PATH` — use `ORONYX_CLANG_DIR` only
- Verify no regression in `config/baseline.json` optimization metrics

## When This Skill Activates
| Trigger | Event | Condition |
|---|---|---|
| PR | `opened` or `synchronize` | Any path change |
| Manual | `workflow_dispatch` | `review_scope: llvm|scripts|cmake|docker|all` |

## Tech Stack
- **Review targets**: LLVM patches, `scripts/*.sh`, `config/build.conf`, `Dockerfile`, `*.cmake`, `*.py`
- **Tools**: `git-clang-format`, `shellcheck`, `cmake-format`, `hadolint` (Dockerfile lint)
- **Standards**: LLVM coding style (`clang-format`); POSIX shell; Docker best practices; CMake conventions
- **Key constraints**: `GITHUB_PATH` forbidden for Oronyx; `ORONYX_CLANG_DIR` must be used

## Automated Checks
```yaml
checks:
  - id: "CRC-001"
    name: "LLVM Coding Style"
    command: |
      [ -f .clang-format ] && git clang-format --diff HEAD~1 2>&1 | grep -c "diff" || echo "STYLE_CHECK_OK"
    severity: "medium"
  - id: "CRC-002"
    name: "Shell Script Lint"
    command: |
      shellcheck scripts/*.sh 2>&1 | grep -c "error" || echo "SCRIPTS_OK"
    severity: "high"
  - id: "CRC-003"
    name: "Hadolint Dockerfile"
    command: |
      hadolint Dockerfile 2>&1 | grep -c "error" || echo "DOCKERFILE_OK"
    severity: "medium"
  - id: "CRC-004"
    name: "No GITHUB_PATH Violation"
    command: |
      ! grep -r "GITHUB_PATH" scripts/ config/ Dockerfile 2>/dev/null && echo "NO_GITHUB_PATH_OK"
    severity: "critical"
```

## Input/Output Schema
```json
{
  "inputs": [
    {"name": "review_scope", "type": "string", "enum": ["llvm", "scripts", "cmake", "docker", "all"]},
    {"name": "diff_ref", "type": "string", "default": "origin/main"}
  ],
  "outputs": {
    "shell_errors": "integer",
    "dockerfile_errors": "integer",
    "format_violations": "integer",
    "github_path_references": "integer",
    "review_status": "pass|fail"
  }
}
```

## Error Recovery
- **LLVM style violation**: Run `git clang-format HEAD~1` to auto-fix formatting before merge
- **GITHUB_PATH found**: Replace with `ORONYX_CLANG_DIR` environment variable; update all scripts referencing Oronyx
- **Hadolint warnings**: Fix Dockerfile best practices (pin base image version, use multi-stage, avoid `latest` tag)
- **ShellCheck errors**: Fix unquoted variables, missing `set -e`, or unsafe `eval` usage in `scripts/`
