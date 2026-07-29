FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LLVM_BRANCH=llvmorg-22.1.8
ENV ENABLE_PGO=false
ENV ENABLE_BOLT=false

RUN apt-get update && apt-get install -y \
    cmake ninja-build python3 git curl unzip \
    clang lld ccache \
    libxml2-dev libedit-dev libncurses-dev \
    libc++-dev libc++abi-dev \
    zstd build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash builder
WORKDIR /workspace

COPY --chown=builder:builder . .

RUN chmod +x scripts/*.sh get_clang.sh

USER builder

CMD ["make", "build"]
