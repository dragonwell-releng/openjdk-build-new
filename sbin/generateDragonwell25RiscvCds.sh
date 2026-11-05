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

image=$(cd "${1:?usage: generateDragonwell25RiscvCds.sh JDK_IMAGE OUTPUT_DIRECTORY}" && pwd)
mkdir -p "${2:?missing output directory}"
output=$(cd "$2" && pwd)
sysroot=${RISCV_SYSROOT:-/opt/anolis23.5/sysroot}
qemu=${QEMU_RISCV64:-/usr/local/bin/qemu-riscv64}
qemu_cpu=${QEMU_CPU_MODEL:-rva23u64,zifencei=true}
timeout_seconds=${QEMU_CDS_TIMEOUT:-900}
server="$image/lib/server"

[[ -x "$image/bin/java" ]] || { echo "Target java is missing from $image" >&2; exit 1; }
[[ -d "$sysroot" ]] || { echo "RISCV_SYSROOT=$sysroot does not exist" >&2; exit 1; }
[[ -x "$qemu" ]] || { echo "QEMU_RISCV64=$qemu is not executable" >&2; exit 1; }
mkdir -p "$server"
temp=$(mktemp -d "$server/.cds.XXXXXX")
trap 'rm -rf "$temp"' EXIT

runTargetJava() {
  # The binfmt QEMU binary expects the guest argv[0] explicitly when invoked
  # as a normal command rather than through binfmt_misc.
  timeout "$timeout_seconds" "$qemu" -cpu "$qemu_cpu" -L "$sysroot" \
    "$image/bin/java" "$image/bin/java" "$@"
}

generateArchive() {
  local name=$1
  shift
  runTargetJava -Xshare:dump -XX:SharedArchiveFile="$temp/$name" \
    -server "$@" -Xmx128M -Xms128M -XX:+UseG1GC -Xlog:cds=info
}

verifyArchive() {
  local name=$1
  shift
  runTargetJava -Xshare:on -XX:SharedArchiveFile="$temp/$name" \
    -server "$@" -Xlog:cds=info -version
}

{
  "$qemu" --version
  echo "Generating Dragonwell 25 RISC-V CDS archives with QEMU CPU $qemu_cpu"
  generateArchive classes.jsa \
    -XX:+UnlockExperimentalVMOptions -XX:-UseCompactObjectHeaders
  generateArchive classes_nocoops.jsa \
    -XX:-UseCompressedOops -XX:+UnlockExperimentalVMOptions -XX:-UseCompactObjectHeaders
  generateArchive classes_coh.jsa \
    -XX:+UnlockExperimentalVMOptions -XX:+UseCompactObjectHeaders
  generateArchive classes_nocoops_coh.jsa \
    -XX:-UseCompressedOops -XX:+UnlockExperimentalVMOptions -XX:+UseCompactObjectHeaders

  verifyArchive classes.jsa \
    -XX:+UnlockExperimentalVMOptions -XX:-UseCompactObjectHeaders
  verifyArchive classes_nocoops.jsa \
    -XX:-UseCompressedOops -XX:+UnlockExperimentalVMOptions -XX:-UseCompactObjectHeaders
  verifyArchive classes_coh.jsa \
    -XX:+UnlockExperimentalVMOptions -XX:+UseCompactObjectHeaders
  verifyArchive classes_nocoops_coh.jsa \
    -XX:-UseCompressedOops -XX:+UnlockExperimentalVMOptions -XX:+UseCompactObjectHeaders

  for name in classes.jsa classes_nocoops.jsa classes_coh.jsa classes_nocoops_coh.jsa; do
    mv "$temp/$name" "$server/$name"
  done

  # Verify the normal JVM lookup finds the installed default archive.
  runTargetJava -Xshare:on -server \
    -XX:+UnlockExperimentalVMOptions -XX:-UseCompactObjectHeaders -version
} 2>&1 | tee "$output/cds.log"

(
  cd "$server"
  sha256sum classes.jsa classes_nocoops.jsa classes_coh.jsa classes_nocoops_coh.jsa
) > "$output/cds-sha256.txt"
