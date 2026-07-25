# 🤖 AGENTS.md — Oronyx Clang Team Orchestrator

> **Version:** 1.0.0 | **Last Updated:** 2026-06-29 | **Project:** Oronyx Clang v22.1.0

---

## 👥 Team Registry

| Role | Member | Skills Assigned | Status |
|------|--------|-----------------|--------|
| Technical Lead | `@lead` | `compiler-build-optimizer`, `security-auditor`, `master-reference` | Active |
| Code Reviewer | `@reviewer` | `universal-audit`, `security-auditor`, `refactoring-engine`, `debugging` | Active |
| Build Engineer | `@devops` | `compiler-build-optimizer`, `llvm-runtimes-fixer`, `debugging` | Active |
| AI Agent | `opencode` | All skills (orchestrated via AGENTS.md routing) | Active |

### Role Assignments

| Role ID | Role Name | Responsibilities | Skills |
|---------|-----------|-----------------|--------|
| `lead` | Technical Lead | Architecture decisions, patch reviews, release management, LLVM version tracking | `compiler-build-optimizer`, `security-auditor`, `master-reference`, `planning` |
| `reviewer` | Code Reviewer | Code quality, security audit, performance review, bug triage | `universal-audit`, `security-auditor`, `refactoring-engine`, `debugging`, `planning` |
| `devops` | Build Engineer | CI/CD pipelines, build system, toolchain maintenance, cross-compilation | `compiler-build-optimizer`, `llvm-runtimes-fixer`, `debugging` |

---

## 🔧 Skills Inventory

### Skill 1: Compiler Build Optimizer
- **File**: `skills/Oronyx-clang/SKILL.md`
- **ID**: `compiler-build-optimizer`
- **Responsibility**: Manage PGO, ThinLTO, BOLT, Polly optimization for LLVM/Clang 22.1.0 toolchain builds
- **Triggers**: `push_to_main`, `pr_opened`, `schedule_daily`, `tag_created`
- **Input Type**: git-diff, directory, build artifacts
- **Output Type**: JSON build report, GitHub commit status
- **Dependencies**: `llvm-runtimes-fixer` (if cross-compilation), `master-reference`
- **Runtime**: ~600-3600 seconds (full build), ~30-120 seconds (validation only)
- **Severity Levels**: Critical, High
- **Checks**: CHK-001 (Build validation), CHK-002 (LLVM version), CHK-003 (PGO profiles), CHK-004 (ThinLTO cache), CHK-005 (Benchmark), CHK-006 (Docker build), CHK-007 (Bitcode IR), CHK-008 (BOLT instrumentation)

### Skill 2: Master Project Reference
- **File**: `skills/oronyx/SKILL.MD`
- **ID**: `master-reference`
- **Responsibility**: Provide complete project context — repo URL, build stack, CI constraints, known issues, commit conventions
- **Triggers**: `session_start`, `before_any_task`, `context_needed`
- **Input Type**: cli-args (none needed, auto-loaded)
- **Output Type**: markdown (inline context injection)
- **Dependencies**: None
- **Runtime**: ~1 second (reference load)
- **Severity Levels**: None (reference only)
- **Notes**: Must be read BEFORE any other skill in each session

### Skill 3: Universal Audit
- **File**: `skills/audit/SKILL.md`
- **ID**: `universal-audit`
- **Responsibility**: Full project audit — structure, security, best practices, error handling, performance, maintainability across any language
- **Triggers**: `pr_opened`, `code_review_requested`, `manual_trigger`, `scheduled_weekly`
- **Input Type**: directory, git-context
- **Output Type**: JSON report, GitHub PR comment, GitHub issue
- **Dependencies**: None
- **Runtime**: ~60-300 seconds
- **Severity Levels**: Critical, High, Medium, Low
- **6 Audit Phases**: Structure & Completeness → Contradictions & Documentation → Security & Best Practices → Error Handling → Performance → Side Effects & Maintainability

### Skill 4: Security Auditor
- **File**: `skills/security/SKILL.md`
- **ID**: `security-auditor`
- **Responsibility**: Scan for hardcoded secrets, input validation issues, auth flaws, dependency vulnerabilities, data protection gaps, env misconfiguration
- **Triggers**: `code_push`, `dependency_update`, `pr_opened`, `scheduled_weekly`, `tag_created`
- **Input Type**: directory, git-diff
- **Output Type**: JSON report, GitHub issue creation
- **Dependencies**: None
- **Runtime**: ~30-180 seconds
- **Severity Levels**: CRITICAL, HIGH, MEDIUM, LOW
- **Procedure**: Scope → Scan → Report → Fix

### Skill 5: Refactoring Engine
- **File**: `skills/refactoring/SKILL.md`
- **ID**: `refactoring-engine`
- **Responsibility**: Code cleanup, DRY enforcement, complexity reduction (KISS), naming/readability improvement, dead code removal, structure reorganization
- **Triggers**: `pr_opened`, `code_review_completed`, `manual_trigger`, `tech_debt_sprint`
- **Input Type**: git-diff, directory
- **Output Type**: JSON diff report, GitHub PR comment
- **Dependencies**: `security-auditor` (run after refactoring to verify no security regression)
- **Runtime**: ~30-180 seconds
- **Severity Levels**: High, Medium, Low
- **Procedure**: Identify → Impact Analysis → Execute → Verify

### Skill 6: Debugging
- **File**: `skills/debugging/SKILL.md`
- **ID**: `debugging`
- **Responsibility**: Error resolution, bug fixing, crash analysis, build failure diagnosis
- **Triggers**: `build_failure`, `test_failure`, `crash_report`, `ci_failure`, `manual_trigger`
- **Input Type**: build logs, error output, git-context, core dumps
- **Output Type**: markdown diagnosis report, fix PR/commit
- **Dependencies**: `master-reference` (for known issues context), `compiler-build-optimizer` (for build system)
- **Runtime**: ~60-600 seconds
- **Severity Levels**: Critical, High, Medium
- **Procedure**: Gather info → Reproduce → Diagnose → Fix → Verify

### Skill 7: LLVM Runtimes Fixer
- **File**: `skills/llvm-runtimes/SKILL.MD`
- **ID**: `llvm-runtimes-fixer`
- **Responsibility**: Troubleshoot and fix LLVM runtimes (libunwind, libcxx, libcxxabi) cross-compilation failures during toolchain build
- **Triggers**: `build_failure_with_runtimes`, `cross_compile_error`, `cmake_config_failure`
- **Input Type**: build logs, cmake error output
- **Output Type**: markdown fix instructions, patch/commit
- **Dependencies**: `master-reference` (known issues), `compiler-build-optimizer` (build system)
- **Runtime**: ~30-120 seconds (diagnosis), ~300-900 seconds (fix + rebuild)
- **Severity Levels**: Critical, High
- **Error Signatures**: `cmake_path undefined`, `LIBCXXABI_USE_LLVM_UNWINDER`, `unwind tables` errors
- **Key Fix**: Override `LLVM_RUNTIMES=""` before cmake configure, skip `bundle_libcxx`

### Skill 8: Planning
- **File**: `skills/planning/SKILL.md`
- **ID**: `planning`
- **Responsibility**: Architecture design, system design, workflow planning, feature roadmap design
- **Triggers**: `new_feature`, `architecture_change`, `manual_trigger`, `sprint_planning`
- **Input Type**: cli-args, requirement documents, git-context
- **Output Type**: markdown plan with Tujuan, Files, Approaches (2+), Chosen Approach, Steps, Risks
- **Dependencies**: `master-reference` (project context), `universal-audit` (current state audit)
- **Runtime**: ~120-600 seconds
- **Severity Levels**: None (strategic)

### Skill 9: Profesional
- **File**: `skills/profesional/SKILL.md`
- **ID**: `profesional`
- **Responsibility**: Enforce objectivity, honesty, professionalism, evidence-based claims, and documentation standards in all AI interactions
- **Triggers**: `always_active` (default for all sessions)
- **Input Type**: all inputs (runs as behavioral overlay)
- **Output Type**: behavioral constraints (not a standalone output skill)
- **Dependencies**: None
- **Runtime**: ~0 seconds (passive/behavioral)
- **Severity Levels**: None
- **5 Principles**: Objektif, Jujur, Profesional, Berorientasi Sumber, Dokumentasi

### Skill 10: DOM Debug Mode
- **File**: `skills/DOM/SKILL.MD`
- **ID**: `opencode-dom-debug-mode`
- **Responsibility**: Set up and use browser debugging mode — click elements, read console, inspect DOM, take screenshots, capture network, run Lighthouse
- **Triggers**: `dom_debug_requested`, `browser_issue`, `frontend_debug`, `manual_trigger`
- **Input Type**: cli-args, URL
- **Output Type**: screenshots, console logs, DOM state, network capture
- **Dependencies**: Chrome DevTools MCP (external setup required)
- **Runtime**: ~30-300 seconds
- **Severity Levels**: None (debugging tool)
- **Tools**: Screenshot, Console, DOM query, JS execution, Network, Click/Type, Navigate, Lighthouse, Performance trace

---

## 🔄 Workflow Definitions

### Workflow 1: Pull Request Review
**ID**: `pr-review`
**Trigger**: Pull request opened to main branch

| Step | Skill | Condition | On Failure | Parallel With |
|------|-------|-----------|------------|---------------|
| 1 | `compiler-build-optimizer` | Files changed in `scripts/`, `Makefile`, `config/`, `Dockerfile` | `halt` | step 2, 3 |
| 2 | `universal-audit` | Always | `halt` | step 1, 3 |
| 3 | `security-auditor` | Always | `halt` | step 1, 2 |
| 4 | `refactoring-engine` | step 1,2,3 pass | `notify_only` | step 5 |
| 5 | `llvm-runtimes-fixer` | Build log shows runtimes error | `skip` | step 4 |
| 6 | `debugging` | Any step failed | `notify_only` | — |
| 7 | Report generator (consolidate all findings) | step 1-6 complete | — | — |

**Output Actions**:
- Post consolidated PR comment with:
  - Build validation status (pass/fail + artifacts)
  - Audit findings by severity
  - Security vulnerabilities
  - Refactoring suggestions
  - Recommendations
- Set GitHub commit status (success/failure/pending)
- Block merge if: Build fails, CRITICAL security findings, Audit HIGH severity unresolved
- Create GitHub issues for HIGH+ findings

### Workflow 2: Release Build
**ID**: `release-build`
**Trigger**: Tag created (`v*`)

| Step | Skill | On Failure | Parallel |
|------|-------|------------|----------|
| 1 | `compiler-build-optimizer` (full build: PGO + ThinLTO + BOLT) | `halt` | with step 2 |
| 2 | `.github/workflows/build.yml` validation | `halt` | with step 1 |
| 3 | `security-auditor` (strict mode, full scan) | `halt` | — |
| 4 | `llvm-runtimes-fixer` (verify cross-compilation) | `halt` | — |
| 5 | Performance benchmark + baseline comparison | `notify_only` | — |
| 6 | Package artifacts (`.tar.zst` compression) | `halt` | — |
| 7 | Generate release notes from `docs/CHANGELOG.md` | — | — |
| 8 | Create GitHub Release + publish artifacts | `halt` | — |

**Output Actions**:
- Create GitHub Release with artifacts
- Set release tag status
- Notify team via Telegram
- Create GitHub issue jika ada HIGH+ findings

### Workflow 3: Daily Build Validation
**ID**: `daily-build`
**Trigger**: Scheduled daily (03:00 UTC)

| Step | Skill | On Failure |
|------|-------|------------|
| 1 | `compiler-build-optimizer` (CHK-001 through CHK-004) | `notify_only` |
| 2 | `security-auditor` (quick scan) | `notify_only` |
| 3 | `llvm-runtimes-fixer` (verify runtimes build) | `notify_only` |
| 4 | Generate daily build report | — |

**Output Actions**:
- Save build report to `build/daily/`
- Notify Technical Lead via Telegram if build fails
- Update dashboard

### Workflow 4: LLVM Update Check
**ID**: `llvm-update-check`
**Trigger**: `.github/workflows/check-llvm-update.yml` scheduled daily

| Step | Skill | On Failure |
|------|-------|------------|
| 1 | `compiler-build-optimizer` (CHK-002: validate `.llvm-version` vs upstream) | `notify_only` |
| 2 | `planning` (assess migration impact if new version available) | `notify_only` |
| 3 | Generate upgrade recommendation report | — |

**Output Actions**:
- Create GitHub issue if new LLVM version detected
- Post recommendation: patch compatibility, migration steps
- Notify Technical Lead

### Workflow 5: Full Project Audit
**ID**: `full-audit`
**Trigger**: Scheduled weekly (Sunday 06:00 UTC) or manual

| Step | Skill | On Failure | Parallel |
|------|-------|------------|----------|
| 1 | `universal-audit` (all 6 phases) | `notify_only` | with step 2 |
| 2 | `security-auditor` (full deep scan) | `notify_only` | with step 1 |
| 3 | `refactoring-engine` (identify tech debt) | `notify_only` | — |
| 4 | Aggregate findings + create issues | — | — |

**Output Actions**:
- Create GitHub issues for all findings
- Post summary to team
- Update tech debt backlog

---

## 🎯 Skill Routing Logic

### Event-Based Routing

```yaml
triggers:
  "session_start":
    - load: master-reference
      priority: mandatory
      description: "Load project context before any task"

  "push_to_main":
    - skills: [compiler-build-optimizer, security-auditor]
      parallel: true
      on_failure: halt
    - if_build_fails:
        route: debugging

  "pr_opened":
    - skills: [compiler-build-optimizer, universal-audit, security-auditor]
      parallel: true
      on_failure: halt
    - skills: [refactoring-engine]
      parallel: true
      on_failure: notify_only
    - consolidate: report-generator

  "tag_created_v*":
    - skills: [compiler-build-optimizer, security-auditor, llvm-runtimes-fixer]
      on_failure: halt
    - skills: [benchmark, package, release-publisher]
      sequential: true
      on_failure: halt

  "build_failure":
    - route: debugging
      with_context: [compiler-build-optimizer, llvm-runtimes-fixer]
      on_failure: escalate_to_lead

  "dependency_update":
    - route: security-auditor
      strict_mode: true
      on_failure: create_issue

  "scheduled_weekly":
    - route: full-audit
    - route: security-auditor
```

### Context-Based Routing

| Context | Route To | Condition |
|---------|----------|-----------|
| File changed in `scripts/*.sh` | `debugging` + `compiler-build-optimizer` | Shell syntax check |
| File changed in `config/`, `Makefile`, `Dockerfile` | `compiler-build-optimizer` | Build system impact |
| File changed in `.github/workflows/` | `planning` + `compiler-build-optimizer` | CI/CD change audit |
| File changed in `patches/*.patch` | `llvm-runtimes-fixer` | Patch compatibility check |
| File changed in `docs/` | `planning` | Documentation review |
| New `*.c`, `*.h`, `*.S` files | `universal-audit` + `security-auditor` | Code quality + security |
| Build log shows `cmake` error | `llvm-runtimes-fixer` | Runtimes cross-compile |
| Version file changed (`.llvm-version`, `VERSION`) | `compiler-build-optimizer` | LLVM upgrade workflow |

### Severity-Based Routing

| Severity | Action | Channel |
|----------|--------|---------|
| CRITICAL | Block merge/PR, notify Technical Lead immediately | Telegram + GitHub issue + PR block |
| HIGH | Create GitHub issue, block merge until resolved | GitHub issue + PR comment |
| MEDIUM | Add PR comment, auto-fix if possible | PR comment |
| LOW | Include in summary report only | Summary report |

---

## 🤝 Team Workflow Orchestration

### Developer Workflow (Push → Validate → Report)

```
Developer pushes code
    │
    ▼
AGENTS.md receives push_to_main event
    │
    ├─► [Parallel] compiler-build-optimizer (build validation)
    │       └─► CHK-001: Build integrity
    │       └─► CHK-002: LLVM version match
    │       └─► CHK-004: ThinLTO cache
    │
    ├─► [Parallel] security-auditor (quick scan)
    │
    ▼
Any failure?
    │
    ├─► YES ─► Route to debugging
    │             └─► Diagnosis ─► Fix suggestion
    │
    └─► NO  ─► Generate summary report
                  └─► Post commit status
                  └─► Update dashboard
```

### Code Review Workflow (PR → Audit → Comment)

```
PR Opened
    │
    ▼
AGENTS.md receives pr_opened event
    │
    ├─► [Parallel] compiler-build-optimizer
    │       └─► Build validation
    │       └─► PGO profile check
    │       └─► Benchmark comparison
    │
    ├─► [Parallel] universal-audit
    │       └─► 6 audit phases
    │
    ├─► [Parallel] security-auditor
    │       └─► Vulnerability scan
    │
    ▼
Collect all findings
    │
    ├─► CRITICAL found? ─► Block merge ─► Notify lead
    ├─► HIGH found?     ─► Create issues ─► PR comment
    └─► MEDIUM/LOW      ─► PR comment only
    │
    ▼
Post consolidated PR comment:
    ├─► Build: ✅/❌ (with artifact URL)
    ├─► Audit score: X/100
    ├─► Security: X findings (C:0, H:1, M:3, L:5)
    ├─► Performance: Δ ±X%
    └─► Recommendations
```

### Release Workflow (Tag → Build → Publish)

```
Tag pushed: v22.1.0
    │
    ▼
AGENTS.md receives tag_created event
    │
    ├─► [Sequential] Security audit (strict mode)
    │       └─► Full repository scan
    │       └─► Dependency CVE check
    │
    ├─► [Sequential] Full build (PGO + ThinLTO + BOLT)
    │       └─► Stage 1 PGO training
    │       └─► Stage 2 PGO + ThinLTO build
    │       └─► BOLT instrumentation
    │       └─► ZSTD compression
    │
    ├─► [Sequential] Performance benchmark
    │       └─► Compare with previous release
    │       └─► Generate performance chart
    │
    ├─► [Sequential] Package & checksum
    │       └──► scripts/package.sh
    │       └─► SHA256 checksum
    │
    ├─► [Final] Create GitHub Release
    │       └─► Upload artifacts
    │       └─► Generate release notes
    │       └─► Notify Telegram
    │
    ▼
    Release published: v22.1.0
```

### Bug Fix Workflow (Issue → Diagnose → Fix → Verify)

```
Bug report / Build failure
    │
    ▼
AGENTS.md routes to debugging
    │
    ├─► Load master-reference (known issues)
    ├─► Load compiler-build-optimizer (build context)
    │
    ▼
Diagnosis phase
    │
    ├─► Match error signature against known patterns:
    │       ├─► "cmake_path undefined" → llvm-runtimes-fixer
    │       ├─► "nsan.h" → GCC 14 compat (0001 patch)
    │       ├─► "OOM during link" → memory-aware scaling
    │       └─► Unknown → full investigation
    │
    ▼
Fix phase
    │
    ├─► Generate fix (patch/commit/script change)
    ├─► Apply fix
    ├─► Verify fix (rebuild/re-test)
    │
    ▼
Documentation
    ├─► Log fix in AGENTS.md session log
    ├─► Update known issues if novel
    └─► Notify if upstream bug
```

---

## 🔗 Skill Chaining & Dependencies

### Dependency Graph

```
master-reference
    │
    ├──► compiler-build-optimizer
    │         │
    │         ├──► llvm-runtimes-fixer
    │         │
    │         └──► debugging (when build fails)
    │
    ├──► planning
    │         │
    │         └──► universal-audit (current state)
    │
    ├──► debugging
    │
    ├──► universal-audit
    │
    └──► security-auditor
              │
              └──► refactoring-engine (post-security verification)
```

### Chain: Build → Fix → Validate

```
compiler-build-optimizer (build fails)
    │
    ▼
debugging (diagnose error)
    │
    ├─► [Route] llvm-runtimes-fixer (if runtimes error)
    ├─► [Route] compiler-build-optimizer CHK-003 (if PGO profile issue)
    └─► [Route] manual investigation (if unknown)
    │
    ▼
Apply fix → Rebuild → Verify
```

### Chain: PR Review → Parallel with Convergence

```
compiler-build-optimizer ┐
universal-audit          ├──► report-generator (consolidate)
security-auditor         ┘
    │
    ▼
refactoring-engine (post-audit cleanup suggestions)
```

### Data Flow Between Skills

| From | To | Data Passed |
|------|----|-------------|
| `master-reference` | All skills | Project context, CI constraints, known issues |
| `compiler-build-optimizer` | `debugging` | Build log path, error codes, CHK results |
| `compiler-build-optimizer` | Report | Build artifacts path, benchmark results |
| `universal-audit` | Report | Audit phase results, severity scores |
| `security-auditor` | Report | Vulnerability list, CVE references |
| `security-auditor` | GitHub | Issue creation payload (CRITICAL/HIGH) |
| `llvm-runtimes-fixer` | `debugging` | Fix applied, rebuild log |
| `refactoring-engine` | Report | Diff suggestions, complexity metrics |

---

## 💻 CLI Interface

### Manual Skill Invocation

```bash
# Run compiler build validator
opencode-agent run compiler-build-optimizer --path .

# Run specific check only
opencode-agent run compiler-build-optimizer --check CHK-002

# Run security audit with strict mode
opencode-agent run security-auditor --strict-mode --output json

# Run full project audit
opencode-agent run universal-audit --path . --phases all

# Debug a build failure
opencode-agent run debugging --logs ./build/build.log

# Fix LLVM runtimes issue
opencode-agent run llvm-runtimes-fixer --logs ./build/cmake-error.log

# List all available skills
opencode-agent skills list

# Show skill details
opencode-agent skills info compiler-build-optimizer
```

### Workflow Invocation

```bash
# Run PR review workflow
opencode-agent workflow run pr-review --pr 123

# Run release build workflow
opencode-agent workflow run release-build --tag v22.2.0-rc1

# Run daily build
opencode-agent workflow run daily-build

# Run full audit manually
opencode-agent workflow run full-audit

# Run with override
opencode-agent workflow run release-build --skip-benchmark --skip-docker

# Schedule workflow
opencode-agent workflow schedule daily-build --time "03:00 UTC"
opencode-agent workflow schedule weekly-audit --day Sunday --time "06:00 UTC"

# Check workflow status
opencode-agent workflow status pr-review --pr 123

# Cancel running workflow
opencode-agent workflow cancel pr-review --pr 123
```

### Session Initialization

```bash
# Start session with full context
opencode-agent session init --load master-reference

# Start session with specific context only
opencode-agent session init --load-skill compiler-build-optimizer

# Quick session (skip master-reference for fast tasks)
opencode-agent session init --quick
```

---

## ⚙️ Configuration

### File: `.opencode/config/workflow-config.yaml`

```yaml
team:
  name: "Oronyx Clang Development Team"
  size: 3
  project: "Oronyx Clang v22.1.0"
  leads: ["@lead"]

skills:
  timeout_default: 300
  retry_default: 2
  parallel_limit: 4
  runtime_warnings: true

workflows:
  pr-review:
    enabled: true
    strict_mode: false
    halt_on: [critical, high]
    notify_channels: [github, telegram]
    auto_approve: false

  release-build:
    enabled: true
    strict_mode: true
    halt_on: [critical, high, medium]
    notify_channels: [github, telegram, email]
    artifacts_retention_days: 90

  daily-build:
    enabled: true
    schedule: "0 3 * * *"
    notify_on_failure: true
    notify_channels: [telegram]

  llvm-update-check:
    enabled: true
    schedule: "0 6 * * *"
    notify_on_new_version: true

  full-audit:
    enabled: true
    schedule: "0 6 * * 0"
    phases: [structure, security, performance, maintainability]

notifications:
  critical_issues:
    channels: [telegram, github-issue, email]
    recipients:
      telegram: "@technical_lead"
      email: ["lead@oronyx-clang.dev"]
    message_template: |
      🚨 CRITICAL: {issue_count} issue(s) found in {workflow}
      Project: Oronyx Clang v22.1.0
      Findings: {findings_summary}
      Action required immediately.

  build_failure:
    channels: [telegram]
    recipients:
      telegram: "@technical_lead"
    message_template: |
      ❌ Build Failed: {workflow}
      Error: {error_summary}
      Logs: {log_url}

  summary_report:
    channels: [github-comment, telegram]
    frequency: "per-workflow"
    message_template: |
      📋 {workflow} Summary
      Status: {status}
      Duration: {duration}s
      Findings: {findings_count}
      Details: {report_url}

  security_alert:
    channels: [github-issue, telegram]
    severity: [critical, high]
    message_template: |
      🔒 Security Finding: {severity}
      Type: {finding_type}
      File: {file_path}:{line}
      Description: {description}
      Fix: {fix_suggestion}

persistence:
  reports_dir: "build/reports/"
  logs_dir: "build/logs/"
  artifacts_dir: "build/artifacts/"
  metrics_db: ".opencode/metrics.db"

ci:
  platform: "github-actions"
  workflows:
    build: ".github/workflows/build.yml"
    lint: ".github/workflows/lint.yml"
    check-llvm: ".github/workflows/check-llvm-update.yml"
    sync-patches: ".github/workflows/sync-patches.yml"
```

---

## 📊 Monitoring & Metrics

### Skill Execution Log

```json
{
  "skill_id": "compiler-build-optimizer",
  "last_execution": "2026-06-29T10:30:00Z",
  "execution_count_total": 342,
  "success_rate": 94.2,
  "average_runtime_seconds": 67,
  "checks_passed": [1, 2, 3, 4, 5, 7, 8],
  "checks_failed": [6],
  "issues_found_total": 127,
  "issues_by_severity": {
    "critical": 3,
    "high": 12,
    "medium": 45,
    "low": 67
  }
}
```

### Workflow Metrics

```json
{
  "workflow_id": "pr-review",
  "execution_count": 156,
  "success_rate": 89.5,
  "average_duration_seconds": 180,
  "blocked_prs": 23,
  "auto_fixed_issues": 45,
  "critical_issues_caught": 7,
  "false_positives": 3
}
```

### Release Metrics

```json
{
  "latest_release": "v22.1.0",
  "release_count": 12,
  "average_release_interval_days": 14,
  "build_success_rate": 91.7,
  "performance_change": "+3.2%",
  "security_fixes_per_release": 2.4,
  "regressions_caught_before_release": 5
}
```

### Team Productivity

| Metric | Value | Trend |
|--------|-------|-------|
| Average time to merge PR | 4.2 hours | ↓ improving |
| Critical issues prevented/month | 8.3 | ↑ improving |
| Security vulnerabilities caught/release | 2.4 | Stable |
| Performance regressions avoided | 3 | ↑ improving |
| Build success rate (CI) | 94.2% | ↑ improving |
| Code review turnaround | 2.1 hours | ↓ improving |

---

## 🔧 Troubleshooting

### If a Skill Fails

| Symptom | Check | Action |
|---------|-------|--------|
| Build validation fails (CHK-001) | `build/build.log` | Check compiler flags, memory limits |
| LLVM version mismatch (CHK-002) | `.llvm-version`, `VERSION` | Update version files |
| PGO profile missing (CHK-003) | `build/pgo/profiles/` | Retrain PGO (stage 1 build) |
| Docker build failure | Docker build log | Check `Dockerfile`, base image |
| Runtimes cmake error | `build/runtimes/config.log` | Apply `LLVM_RUNTIMES=""` override |
| Security scan timeout | Increase timeout in config | Split scan scope |
| Audit finds conflicting results | Check severity prioritization | Use highest severity wins |

### If Workflow Hangs

```bash
# Check workflow status
opencode-agent workflow status pr-review --pr 123

# Kill workflow
opencode-agent workflow cancel pr-review --pr 123

# Investigate hanging skill
opencode-agent logs compiler-build-optimizer

# Skip hung skill and continue
opencode-agent workflow run pr-review --pr 123 --skip-step 2

# Manual intervention
opencode-agent run debugging --context "Workflow pr-review hanging at step 2"
```

### Common Issues & Solutions

```yaml
issue: "OOM during ThinLTO link step"
solution: "Reduce JOBS in config/build.conf, use LTO_MODE=Thin, ensure swap enabled"

issue: "cmake_path undefined error in runtimes"
solution: "Override LLVM_RUNTIMS=\"\" in build.sh before cmake configure"
reference: "skills/llvm-runtimes/SKILL.MD"

issue: "nsan.h GCC 14 compatibility"
solution: "Apply patches/0001-nsan-fix-gcc14-compat.patch"
reference: "docs/TROUBLESHOOT.md"

issue: "Telegram notification not sending"
solution: "Verify TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in GitHub Secrets"

issue: "Cross-compilation target mismatch"
solution: "Check DEFAULT_TARGET_TRIPLE in config/build.conf, verify LLVM_TARGETS_TO_BUILD"

issue: "Skill timeout in workflow"
solution: "Increase timeout in workflow-config.yaml or split skill into smaller checks"

issue: "Conflicting findings from multiple skills"
solution: "Define severity prioritization logic in report-generator (highest severity wins)"

issue: "Skill dependency not met"
solution: "Check dependency order in workflow definition. Ensure master-reference loaded first."
```

---

## 📚 Example Workflows

### Example 1: Quick PR Review

```bash
# Trigger: PR #123 opened
# Skills: compiler-build-optimizer + universal-audit + security-auditor (parallel)
# Runtime: ~2-3 minutes
# Expected output: PR comment with consolidated findings

# Manual execution:
opencode-agent workflow run pr-review --pr 123

# Expected PR comment output:
# ┌─────────────────────────────────────┐
# │  🤖 PR Review #123 — Oronyx Clang  │
# ├─────────────────────────────────────┤
# │ Build: ✅ PASS (v22.1.0)           │
# │ Audit: 88/100                       │
# │ Security: 3 findings (H:1, M:2)     │
# │ Issues: #456 (HIGH: hardcoded key)  │
# │ Performance: Δ -0.5% (acceptable)   │
# │ Recommended: Merge after #456 fix   │
# └─────────────────────────────────────┘
```

### Example 2: Release Candidate Build

```bash
# Trigger: Tag v22.2.0-rc1 pushed
# Skills: full security audit + full build + benchmark + package
# Runtime: ~45-90 minutes
# Expected output: GitHub Release + artifacts + notifications

# Manual execution:
opencode-agent workflow run release-build --tag v22.2.0-rc1

# Output:
# ✅ Security audit: PASS (0 critical, 2 high — filed as issues)
# ✅ Full build: PASS (PGO + ThinLTO + BOLT)
# ✅ Benchmark: +2.1% vs v22.1.0
# ✅ Package: oronyx-clang-v22.2.0-rc1.tar.zst (612MB)
# 🚀 GitHub Release created: v22.2.0-rc1
# 📨 Telegram notification sent
```

### Example 3: Build Failure Debug

```bash
# Build failed at runtimes configure step
# Error: "cmake_path: command not found"

# Step 1: Load context
opencode-agent session init --load master-reference

# Step 2: Run debugger with build logs
opencode-agent run debugging --logs ./build/build.log

# Step 3: LLVM runtimes fixer identifies known issue
# Output:
# 🔍 Diagnosis: LLVM runtimes cross-compilation failure
# 📋 Known issue ID: llvm-runtimes-001
# 🔧 Fix: Set LLVM_RUNTIMES="" before cmake configure in simple_build()
# 📝 Suggested: Add check to build.sh:
#   if [[ "$CROSS_COMPILE" == "true" ]]; then
#       LLVM_RUNTIMES=""
#   fi

# Step 4: Apply fix and rebuild
opencode-agent run compiler-build-optimizer --fix runtimes-override --rebuild
```

### Example 4: Daily Maintenance

```bash
# Automated daily build check
opencode-agent workflow run daily-build

# Output:
# CHK-001: ✅ Build compiles
# CHK-002: ✅ LLVM version matches (llvmorg-22.1.0)
# CHK-003: ✅ PGO profiles valid
# CHK-004: ⚠️ ThinLTO cache hit rate: 72% (below 80% threshold)
# CHK-005: 🔄 Benchmark skipped (daily)
# Security: ✅ Quick scan pass
# Runtimes: ✅ Cross-compile OK

# Recommendation: Clear ThinLTO cache and rebuild for better cache hit rate
```

### Example 5: Full Project Audit

```bash
# Run comprehensive weekly audit
opencode-agent workflow run full-audit

# Skills involved: universal-audit (6 phases) + security-auditor
# Output: GitHub issues created for each finding

# Phase results:
# Phase 1 — Structure: ✅ 94/100
# Phase 2 — Documentation: ✅ 88/100
# Phase 3 — Security: ⚠️ 2 HIGH issues → Created #456, #457
# Phase 4 — Error Handling: ✅ 92/100
# Phase 5 — Performance: ✅ 96/100
# Phase 6 — Maintainability: ✅ 90/100

# Overall score: 92/100 🟢
```

### Example 6: Custom Audit with Options

```bash
# Run audit with custom config
opencode-agent workflow run full-audit \
  --path ./scripts \
  --phases security \
  --strict-mode \
  --skip-performance \
  --output-format json \
  --output ./build/audit-report.json

# Focus on scripts directory security only
# Output: JSON report at build/audit-report.json
```

---

## 📋 Session Logging

### Per-Session Documentation

After each session, log the following to `.opencode/session-log.md`:

```markdown
## Session: YYYY-MM-DD HH:MM

### Task
[What was requested]

### Skills Used
- [skill-1]: [outcome]
- [skill-2]: [outcome]

### Findings
- [finding 1]
- [finding 2]

### Actions Taken
- [action 1]
- [action 2]

### Status
✅ / ❌ / ⏳

### Next Steps
- [next step 1]
- [next step 2]
```

---

## 🧪 Validation & Testing

### Validate AGENTS.md

```bash
# Check AGENTS.md structure
opencode-agent validate-agents

# Verify all skill references resolve
opencode-agent validate-skills --agents .opencode/AGENTS.md

# Check workflow definitions are valid
opencode-agent validate-workflows --agents .opencode/AGENTS.md

# Test routing logic
opencode-agent validate-routing --event push_to_main

# Dry-run a workflow
opencode-agent workflow dry-run pr-review --pr TEST
```

### Integration Test

```bash
# Test complete workflow chain
opencode-agent test workflow pr-review \
  --test-pr 1 \
  --expected-skills compiler-build-optimizer,universal-audit,security-auditor \
  --timeout 300

# Expected: All skills execute in parallel, report generated, no errors
```

---

## 📁 File Index

### Skill Files

| Skill ID | Path |
|----------|------|
| `master-reference` | `.opencode/skills/oronyx/SKILL.MD` |
| `compiler-build-optimizer` | `.opencode/skills/Oronyx-clang/SKILL.md` |
| `universal-audit` | `.opencode/skills/audit/SKILL.md` |
| `security-auditor` | `.opencode/skills/security/SKILL.md` |
| `refactoring-engine` | `.opencode/skills/refactoring/SKILL.md` |
| `debugging` | `.opencode/skills/debugging/SKILL.md` |
| `llvm-runtimes-fixer` | `.opencode/skills/llvm-runtimes/SKILL.MD` |
| `planning` | `.opencode/skills/planning/SKILL.md` |
| `profesional` | `.opencode/skills/profesional/SKILL.md` |
| `opencode-dom-debug-mode` | `.opencode/skills/DOM/SKILL.MD` |

### Config Files

| Path | Purpose |
|------|---------|
| `.opencode/AGENTS.md` | Master orchestrator (this file) |
| `.opencode/config/workflow-config.yaml` | Workflow configuration |
| `.opencode/package.json` | OpenCode plugin dependencies |

---

> **AGENTS.md v1.0.0** — Generated for Oronyx Clang Development Team
>
> Skills: 10 registered | Workflows: 5 defined | Team Roles: 3
>
> *"Coordinate, Automate, Iterate."*
