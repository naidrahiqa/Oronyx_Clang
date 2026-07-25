# Contributing to OronyxClang

Thank you for your interest in contributing! This guide will help you get started.

## Development Setup

```bash
git clone https://github.com/naidrahiqa/Oronyx_Clang
cd Oronyx_Clang
chmod +x scripts/*.sh
```

## Making Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run lint: `make lint`
5. Test locally: `make build-simple`
6. Commit with descriptive message
7. Push and create a Pull Request

## Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation
- `ci:` CI/CD changes
- `chore:` maintenance

Examples:
```
feat: add ARM 32-bit target support
fix: handle disk space check on macOS
docs: update kernel integration guide
```

## Code Style

- Use 2-space indentation for shell scripts
- Follow ShellCheck recommendations
- Use `shellcheck --severity=warning` to check scripts

## Testing Changes

```bash
# Quick build (no PGO, fast)
make build-simple

# Full build with PGO
make build

# Lint check
make lint

# Test kernel build
make test-compat
```

## Reporting Issues

Use GitHub Issues with the provided templates:
- Bug Report: build failures, unexpected behavior
- Feature Request: new functionality suggestions

## Pull Request Checklist

- [ ] Code follows project style
- [ ] ShellCheck passes
- [ ] Self-review completed
- [ ] Documentation updated (if needed)
- [ ] No new warnings introduced

## Questions?

Open a GitHub Issue or start a Discussion.
