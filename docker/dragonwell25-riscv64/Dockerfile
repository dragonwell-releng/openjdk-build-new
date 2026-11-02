# ********************************************************************************
# Copyright (c) 2026 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE} AS host
ARG APT_MIRROR=http://archive.ubuntu.com/ubuntu
RUN sed -i "s|http://archive.ubuntu.com/ubuntu|${APT_MIRROR}|g; s|http://security.ubuntu.com/ubuntu|${APT_MIRROR}|g" /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       build-essential gcc-14 g++-14 autoconf automake bison flex texinfo patch \
       ca-certificates curl git file zip unzip xz-utils bzip2 cpio rpm xorriso \
       python3 pkg-config ccache libgmp-dev libmpfr-dev libmpc-dev libisl-dev \
       zlib1g-dev libzstd-dev libasound2-dev libcups2-dev libfontconfig1-dev \
       libfreetype-dev libx11-dev libxext-dev libxrender-dev libxrandr-dev libxtst-dev libxt-dev \
    && rm -rf /var/lib/apt/lists/*
ENV CC=gcc-14 CXX=g++-14

FROM host AS toolchain
ARG JOBS=32
COPY prepare-sysroot.py prepare-sources.py build-toolchain.sh /scripts/
RUN --mount=type=bind,source=inputs,target=/inputs cd /inputs && sha256sum -c SHA256SUMS
RUN --mount=type=bind,source=inputs,target=/inputs python3 /scripts/prepare-sysroot.py /inputs/AnolisOS-23.5-riscv64-dvd.iso /opt/anolis23.5/sysroot
RUN --mount=type=bind,source=inputs,target=/inputs JOBS=${JOBS} bash /scripts/build-toolchain.sh
RUN --mount=type=bind,source=inputs,target=/inputs mkdir -p /opt/bootjdk && tar -xf /inputs/bootjdk.tar.gz -C /opt/bootjdk --strip-components=1 \
    && /opt/bootjdk/bin/java -version

FROM host AS builder
COPY --from=toolchain /opt/ /opt/
# SBOM generation and the build-farm entry point need these host-side tools.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ant jq wget pigz \
    && rm -rf /var/lib/apt/lists/*
ENV PATH=/opt/anolis23.5/cross/bin:/opt/bootjdk/bin:$PATH \
    JAVA_HOME=/opt/bootjdk \
    RISCV64=/opt/anolis23.5/cross \
    RISCV_SYSROOT=/opt/anolis23.5/sysroot \
    JDK_BOOT_VERSION=25 \
    JDK25_BOOT_DIR=/opt/bootjdk \
    RISCV_BUILD_JDK=/opt/bootjdk
WORKDIR /openjdk-build
# Jenkins Docker Pipeline supplies its own command (cat); do not use ENTRYPOINT.
CMD ["bash"]
