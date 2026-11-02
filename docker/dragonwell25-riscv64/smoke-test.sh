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

# Optional: run the resulting RISC-V JDK under qemu-user on an x86_64 host.
set -euo pipefail
jdk=$(cd "${1:?usage: smoke-test.sh JDK_DIRECTORY SYSROOT_DIRECTORY}" && pwd)
sysroot=$(cd "${2:?missing sysroot}" && pwd)
qemu=${QEMU_RISCV64:-qemu-riscv64}
cpu=${QEMU_CPU_MODEL:-max}
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cat > "$temp/Smoke.java" <<'JAVA'
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.zip.Deflater;
import java.util.zip.Inflater;

public class Smoke {
    static long sum(int n) {
        long s = 0;
        for (int i = 1; i <= n; i++) s += i;
        return s;
    }
    public static void main(String[] args) throws Exception {
        if (!System.getProperty("os.arch").equals("riscv64")) throw new AssertionError("architecture");
        for (int i = 0; i < 3000; i++) if (sum(1000) != 500500) throw new AssertionError("sum");
        byte[] input = "Dragonwell 25 Anolis 23.5 RVA23".repeat(100).getBytes(java.nio.charset.StandardCharsets.UTF_8);
        byte[] compressed = new byte[input.length + 100];
        Deflater deflater = new Deflater();
        deflater.setInput(input);
        deflater.finish();
        int count = deflater.deflate(compressed);
        if (!deflater.finished()) throw new AssertionError("deflate");
        deflater.end();
        Inflater inflater = new Inflater();
        inflater.setInput(compressed, 0, count);
        byte[] restored = new byte[input.length];
        if (inflater.inflate(restored) != input.length || !Arrays.equals(input, restored)) throw new AssertionError("inflate");
        inflater.end();
        String sha = java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(new byte[]{97, 98, 99}));
        if (!sha.equals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")) throw new AssertionError("SHA-256");
        var file = Files.createTempFile("dragonwell25-rv23", ".txt");
        try {
            Files.write(file, input);
            if (!Arrays.equals(Files.readAllBytes(file), input)) throw new AssertionError("file IO");
        } finally { Files.delete(file); }
        System.out.println("PASS: " + System.getProperty("java.runtime.version") + " " + System.getProperty("os.arch")
            + " (sum, zlib, SHA-256, file IO)");
    }
}
JAVA
timeout 120 "$qemu" -cpu "$cpu" -L "$sysroot" "$jdk/bin/java" -version
timeout 180 "$qemu" -cpu "$cpu" -L "$sysroot" "$jdk/bin/javac" -d "$temp" "$temp/Smoke.java"
timeout 120 "$qemu" -cpu "$cpu" -L "$sysroot" "$jdk/bin/java" -Xint -cp "$temp" Smoke
timeout 180 "$qemu" -cpu "$cpu" -L "$sysroot" "$jdk/bin/java" -Xbatch -XX:CompileThreshold=100 -cp "$temp" Smoke
