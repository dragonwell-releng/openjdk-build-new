#!/usr/bin/env python3
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

"""Extract target headers/libraries only from the checksum-pinned GA DVD."""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

iso, destination = sys.argv[1:]
root = pathlib.Path(destination).resolve()
root.mkdir(parents=True, exist_ok=True)
listing = subprocess.check_output([
    "xorriso", "-indev", iso, "-find", "/os/Packages", "-name", "*.rpm", "-exec", "lsdl"
], universal_newlines=True)
packages = re.findall(r"'(/os/Packages/[^']+\.rpm)'", listing)
families = ("glibc", "kernel-headers", "libgcc", "libstdc++", "libatomic", "alsa-lib", "cups-libs",
            "cups-devel", "fontconfig", "freetype", "libX", "libxcb", "libICE", "libSM",
            "libpng", "libjpeg-turbo", "zlib", "libxcrypt", "xorg-x11-proto", "xorg-x11-util",
            "expat", "bzip2-libs", "brotli", "harfbuzz", "libuuid", "libbsd", "libmd",
            "anolis-release", "filesystem", "setup", "tzdata")
selected = sorted(p for p in packages if pathlib.PurePosixPath(p).name.startswith(families)
                  and not any(s in p for s in ("-debuginfo-", "-debugsource-", "-docs-", "-doc-",
                                               "-benchtests-", "-locale-source-", "-all-langpacks-")))
assert any("gcc-14.3.0-5.an23_rva23" in p for p in selected), "Unexpected DVD GCC"
assert any("glibc-devel-" in p for p in selected), "Missing glibc headers"
with tempfile.TemporaryDirectory() as temp:
    # One xorriso invocation avoids repeatedly reading the ISO directory tree.
    command = ["xorriso", "-osirrox", "on", "-indev", iso]
    for package in selected:
        command += ["-extract", package, str(pathlib.Path(temp) / pathlib.PurePosixPath(package).name)]
    subprocess.run(command, check=True)
    for package in selected:
        rpm = pathlib.Path(temp) / pathlib.PurePosixPath(package).name
        with subprocess.Popen(["rpm2cpio", str(rpm)], stdout=subprocess.PIPE) as proc:
            subprocess.run(["cpio", "-idm", "--quiet", "--no-absolute-filenames"],
                           cwd=root, stdin=proc.stdout, check=True)
            proc.stdout.close()
            if proc.wait():
                raise SystemExit(f"rpm2cpio failed: {rpm}")
# Keep absolute target links from escaping into host libraries during configure.
for base, dirs, files in os.walk(root):
    for name in dirs + files:
        link = pathlib.Path(base) / name
        if link.is_symlink():
            target = os.readlink(link)
            if target.startswith("/"):
                link.unlink()
                link.symlink_to(os.path.relpath(root / target.lstrip("/"), link.parent))
provenance = root.parent / "provenance"
provenance.mkdir(exist_ok=True)
(provenance / "sysroot-packages.txt").write_text("\n".join(selected) + "\n")
print(f"Extracted {len(selected)} Anolis GA RPMs to {root}")
