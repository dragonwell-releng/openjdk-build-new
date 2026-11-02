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

# Build the cached x86_64 cross-build image. Run build.sh for the repository JDK flow.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=${WORK_DIR:-$PWD/workspace/dragonwell25-riscv64}
mkdir -p "$work"
work=$(cd "$work" && pwd)
mkdir -p "$work/tmp"
export TMPDIR="$work/tmp"
exec 9>"$work/image-build.lock"
flock -n 9 || { echo "Another build is using $work" >&2; exit 1; }
engine=${CONTAINER_ENGINE:-docker}
if [[ "$engine" == docker ]]; then
    export DOCKER_BUILDKIT=1
fi
runtime=("$engine")
cache_args=()
if [[ "$engine" == podman ]]; then
    runtime+=(--root "${PODMAN_ROOT:-$work/container-storage}" --runroot "${PODMAN_RUNROOT:-$work/runroot}")
    cache_args+=(--layers)
fi
image=${IMAGE:-alibabadragonwelljdk/dragonwell25-riscv64-build:anolis23.5-rva23-v1}
jobs=${JOBS:-32}
mkdir -p "$work/downloads" "$work/context/inputs" "$work/output" "$work/ccache" "$work/logs"
fetch() {
    local url=$1 name=$2 expected=$3
    if [[ -f "$work/downloads/$name" ]] && (cd "$work/downloads" && printf '%s  %s\n' "$expected" "$name" | sha256sum -c -); then
        return
    fi
    curl -fL --retry 4 --connect-timeout 30 --continue-at - -o "$work/downloads/$name.part" "$url"
    printf '%s  %s\n' "$expected" "$work/downloads/$name.part" | sha256sum -c -
    mv "$work/downloads/$name.part" "$work/downloads/$name"
}
iso_base=https://mirrors.openanolis.cn/anolis/23.5/isos/GA/riscv64
srpm_base=https://mirrors.openanolis.cn/anolis/23.5/os/source/Packages
while read -r checksum name; do
    case "$name" in
        *.iso) url="$iso_base/$name" ;;
        *.rpm) url="$srpm_base/$name" ;;
        bootjdk.tar.gz) url=https://download.java.net/java/GA/jdk25.0.2/b1e0dfa218384cb9959bdcb897162d4e/10/GPL/openjdk-25.0.2_linux-x64_bin.tar.gz ;;
        *) exit 1 ;;
    esac
    fetch "$url" "$name" "$checksum"
    if [[ ! "$work/downloads/$name" -ef "$work/context/inputs/$name" ]]; then
        rm -f "$work/context/inputs/$name"
        ln "$work/downloads/$name" "$work/context/inputs/$name" || cp "$work/downloads/$name" "$work/context/inputs/$name"
    fi
done < "$here/inputs.sha256"
cp "$here/inputs.sha256" "$work/context/inputs/SHA256SUMS"
cp "$here/"{Dockerfile,prepare-sources.py,prepare-sysroot.py,build-toolchain.sh} "$work/context/"
"${runtime[@]}" build "${cache_args[@]}" --network=host \
    --build-arg "BASE_IMAGE=${BASE_IMAGE:-ubuntu:24.04}" \
    --build-arg "APT_MIRROR=${APT_MIRROR:-http://archive.ubuntu.com/ubuntu}" \
    --build-arg "JOBS=$jobs" -t "$image" "$work/context" 2>&1 | tee "$work/logs/image-build.log"
"${runtime[@]}" image inspect "$image" > "$work/output/builder-image.json"
printf '\nBuilder image: %s\n' "$image"
