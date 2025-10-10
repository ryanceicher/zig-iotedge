# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libcurl4-openssl-dev \
        libssl-dev \
        ninja-build \
        pkg-config \
        python3 \
        python3-pip \
        python3-setuptools \
        uuid-dev \
        wget \
        xz-utils \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Stage to build azure-iot-sdk-c static libraries
FROM base AS zig-build

WORKDIR /work

# Install Zig (using official tarball)
ARG ZIG_VERSION=0.15.1
ARG ZIG_ARCHIVE=zig-x86_64-linux-${ZIG_VERSION}.tar.xz
RUN wget -q https://ziglang.org/download/${ZIG_VERSION}/${ZIG_ARCHIVE} && \
    tar -xf ${ZIG_ARCHIVE} && \
    ZIG_DIR=$(tar -tf ${ZIG_ARCHIVE} | head -1 | cut -d/ -f1) && \
    mv ${ZIG_DIR} /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm ${ZIG_ARCHIVE}

# Copy project sources
COPY . .

ENV ZIG_GLOBAL_CACHE_DIR=/work/.zig-global-cache \
    ZIG_LOCAL_CACHE_DIR=/work/.zig-cache

# Fetch dependencies and build Zig project (target Linux as container environment)
RUN zig build --fetch && \
    zig build -Doptimize=ReleaseSafe

FROM ubuntu:24.04 AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libcurl4 \
        libssl3 \
        libuuid1 \
        zlib1g && \
    rm -rf /var/lib/apt/lists/*

COPY --from=zig-build /work/zig-out/bin/zig_iotedge /usr/local/bin/zig_iotedge

ENTRYPOINT ["/usr/local/bin/zig_iotedge"]
