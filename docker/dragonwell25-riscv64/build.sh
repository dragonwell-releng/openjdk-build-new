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

# Run the same build-farm entry point as Jenkins, using the Anolis cross image.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=${WORK_DIR:-$repo/workspace/dragonwell25-riscv64}
mkdir -p "$work"
work=$(cd "$work" && pwd)
export WORK_DIR="$work"
image=${IMAGE:-alibabadragonwelljdk/dragonwell25-riscv64-build:anolis23.5-rva23-v1}
export IMAGE="$image"
if [[ "${SKIP_IMAGE_BUILD:-false}" != true ]]; then
    bash "$here/build-image.sh"
fi
engine=${CONTAINER_ENGINE:-docker}
runtime=("$engine")
if [[ "$engine" == podman ]]; then
    runtime+=(--root "${PODMAN_ROOT:-$work/container-storage}" --runroot "${PODMAN_RUNROOT:-$work/runroot}")
fi
source_cache_args=()
if [[ -n "${SOURCE_GIT_CACHE:-}" ]]; then
    source_cache=$(cd "$SOURCE_GIT_CACHE" && pwd)
    [[ $(git --git-dir="$source_cache" rev-parse --is-bare-repository) == true ]]
    # Rewrite transport only; origin and SBOM provenance keep the official URL.
    source_cache_args=(-v "$source_cache:/source-git-cache:ro"
        -e GIT_CONFIG_COUNT=1
        -e GIT_CONFIG_KEY_0=url.file:///source-git-cache.insteadOf
        -e GIT_CONFIG_VALUE_0=https://github.com/dragonwell-project/dragonwell25.git)
fi
mkdir -p "$work/jdk-workspace" "$work/ccache" "$work/logs"
exec 9>"$work/jdk-build.lock"
flock -n 9 || { echo "Another JDK build is using $work" >&2; exit 1; }
# Clear any ISA default baked into older images; linux.sh owns the build default.
"${runtime[@]}" run --rm --network=host --security-opt label=disable \
    --entrypoint /bin/bash -w /openjdk-build \
    -e ARCHITECTURE=riscv64 -e TARGET_OS=linux -e VARIANT=dragonwell -e JAVA_TO_BUILD=jdk25u \
    -e "BUILD_ARGS=${BUILD_ARGS:---create-sbom --cross-compile}" \
    -e "CONFIGURE_ARGS=${CONFIGURE_ARGS:-}" -e "NUM_PROCESSORS=${JOBS:-32}" \
    -e "RISCV_MARCH=${RISCV_MARCH:-}" -e CCACHE_DIR=/ccache \
    -e "FILENAME=${FILENAME:-OpenJDK25U-jdk_riscv64_linux_dragonwell_anolis23.5-rva23.tar.gz}" \
    -v "$repo:/openjdk-build" -v "$work/jdk-workspace:/openjdk-build/workspace" \
    -v "$work/ccache:/ccache" \
    "${source_cache_args[@]}" "$image" build-farm/make-adopt-build-farm.sh "$@" 2>&1 | tee "$work/logs/jdk-build.log"
printf '\nArtifacts: %s/jdk-workspace/target\n' "$work"
