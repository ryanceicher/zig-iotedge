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
FROM base AS azure-sdk-build

WORKDIR /work

# Copy the azure-iot-sdk-c source tree into the container
COPY lib/azure-iot-sdk-c ./azure-iot-sdk-c

# Configure and build with Ninja. Disable unnecessary components to speed up build.
RUN cmake \
        -S azure-iot-sdk-c \
        -B build/azure-sdk \
        -G Ninja \
        -Duse_amqp=OFF \
        -Duse_http=OFF \
        -Duse_prov_client=OFF \
        -Dbuild_service_client=OFF \
        -Duse_edge_modules=ON \
        -Dskip_samples=ON \
        -Drun_unittests=OFF \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build/azure-sdk --config Release

# Stage to build Zig application
FROM azure-sdk-build AS zig-build

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
COPY build.zig build.zig
COPY build.zig.zon build.zig.zon
COPY src ./src

# Copy azure build output for linking
COPY --from=azure-sdk-build /work/build/azure-sdk ./azure-sdk-build-output
COPY --from=azure-sdk-build /work/azure-iot-sdk-c ./lib/azure-iot-sdk-c

# Build Zig project (target Linux as container environment)
RUN zig build \
        -Dazure-sdk-build-root=azure-sdk-build-output \
        -Dazure-sdk-source-root=lib/azure-iot-sdk-c \
        --summary all

# Final stage publishes both azure artifacts and zig build outputs
FROM scratch AS artifacts

COPY --from=azure-sdk-build /work/build/azure-sdk /azure-sdk
COPY --from=zig-build /work/zig-out /zig

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
