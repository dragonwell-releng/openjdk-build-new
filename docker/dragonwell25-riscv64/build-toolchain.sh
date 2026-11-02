#!/usr/bin/env bash
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

set -euo pipefail
prefix=/opt/anolis23.5/cross
sysroot=/opt/anolis23.5/sysroot
target=riscv64-unknown-linux-gnu
jobs=${JOBS:-32}
mkdir -p /build/binutils /build/gcc "$prefix"
python3 /scripts/prepare-sources.py binutils /inputs/binutils-2.42-4.an23_rva23.src.rpm /build/binutils-src
python3 /scripts/prepare-sources.py gcc /inputs/gcc-14.3.0-5.an23_rva23.src.rpm /build/gcc-src
cd /build/binutils
"$(cat /build/binutils-src/source-dir)/configure" --target="$target" --prefix="$prefix" \
    --with-sysroot="$sysroot" --disable-multilib --disable-nls --disable-werror \
    --disable-gprofng --disable-gdb --enable-plugins
make -j"$jobs" MAKEINFO=true
make install MAKEINFO=true
export PATH="$prefix/bin:$PATH"
cd /build/gcc
"$(cat /build/gcc-src/source-dir)/configure" --target="$target" --prefix="$prefix" \
    --with-sysroot="$sysroot" --with-native-system-header-dir=/usr/include \
    --with-arch=rv64gc --with-abi=lp64d --enable-languages=c,c++ \
    --disable-bootstrap --disable-multilib --disable-nls --enable-shared --enable-threads=posix \
    --disable-libsanitizer --disable-libquadmath --disable-libssp --disable-libvtv \
    --disable-libgomp --disable-libitm --disable-libcc1 --with-system-zlib \
    --with-pkgversion='Anolis 23.5 gcc-14.3.0-5.an23_rva23 cross'
make -j"$jobs" all-gcc all-target-libgcc all-target-libstdc++-v3
make install-gcc install-target-libgcc install-target-libstdc++-v3
"$target-gcc" --version
printf 'int main() { return 0; }\n' | "$target-gcc" -march=rva23u64 -mabi=lp64d -x c - -o /build/probe
"$target-readelf" -A /build/probe
mkdir -p /opt/anolis23.5/provenance
cp /inputs/SHA256SUMS /opt/anolis23.5/provenance/
cp /build/{gcc,binutils}-src/*.spec /opt/anolis23.5/provenance/
rm -rf /build
