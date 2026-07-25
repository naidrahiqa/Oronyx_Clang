# Docker Build Environment

Reproducible build environment for OronyxClang.

## Quick Start

```bash
# Build the Docker image
make docker-build

# Run build inside Docker
make docker-run

# Or manually
docker build -t oronyx-clang .
docker run --rm -v $(pwd):/workspace -w /workspace oronyx-clang make build
```

## Custom Build Options

```bash
# Build with PGO enabled
docker run --rm -v $(pwd):/workspace -w /workspace \
  -e ENABLE_PGO=true \
  oronyx-clang make build

# Build specific LLVM branch
docker run --rm -v $(pwd):/workspace -w /workspace \
  -e LLVM_BRANCH=llvmorg-22.1.0 \
  oronyx-clang make build
```

## Notes

- Build artifacts are mounted from host, so they persist after container exits
- First build will be slow (downloading + compiling LLVM)
- Subsequent builds use ccache for faster rebuilds
