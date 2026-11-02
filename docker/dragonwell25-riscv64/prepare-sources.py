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

"""Apply the Anolis SRPM patch series, in spec order, for a cross build."""
import pathlib
import re
import subprocess
import sys
import tarfile

kind, rpm, output = sys.argv[1:]
out = pathlib.Path(output).resolve()
out.mkdir(parents=True, exist_ok=True)
with subprocess.Popen(["rpm2cpio", rpm], stdout=subprocess.PIPE) as proc:
    subprocess.run(["cpio", "-idm", "--quiet"], cwd=out, stdin=proc.stdout, check=True)
    proc.stdout.close()
    if proc.wait():
        raise SystemExit("rpm2cpio failed")
spec = (out / f"{kind}.spec").read_text()
archive = next(out.glob(f"{kind}-*.tar.xz"))
with tarfile.open(archive) as tf:
    root = out / tf.getmembers()[0].name.split("/")[0]
    tf.extractall(out)
patches = {int(n): name for n, name in re.findall(r"^Patch(\d+):\s*(\S+)", spec, re.M)}
prep = spec.split("\n%prep\n", 1)[1].split("\n%build\n", 1)[0]
if kind == "gcc":
    order = [int(n) for n in re.findall(r"^%patch(\d+)\s+-p\s*1", prep, re.M)]
else:
    assert "%autosetup -p1" in prep
    order = sorted(patches)
for number in order:
    with (out / patches[number]).open("rb") as patch:
        subprocess.run(["patch", "--batch", "-p1"], cwd=root, stdin=patch, check=True)
if kind == "gcc":
    (root / "gcc/DEV-PHASE").write_text("Anolis OS 14.3.0-5.an23_rva23 cross compiler\n")
    subprocess.run(["bash", "contrib/gcc_update", "--touch"], cwd=root, check=True)
print(root)
(out / "source-dir").write_text(str(root))
