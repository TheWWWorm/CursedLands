#!/usr/bin/env python3
"""Reject unrelated graphics integrations in an FSR-only source/package."""
import argparse
from pathlib import Path
import re
import subprocess

FORBIDDEN_PATH = re.compile(
    r"dlss|streamline|(?:^|/)rtx[^/]*|nvidia-geforce|splash-(?:nvidia|graphics)|"
    r"(?:^|/)(?:sl\.[^/]+|nvngx[^/]*|_nvngx[^/]*)\.dll$", re.I)
FORBIDDEN_BINARY = (
    b"Streamline", b"SCALING_3D_MODE_DLSS", b"sl.interposer.dll",
    b"nvngx_dlss.dll", b"--experimental-rtx",
)


def check_source(root, archived=False):
    names = [] if archived else subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                                    cwd=root, text=True).splitlines()
    if archived:
        names = [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()]
    rejected = sorted({n for n in names if FORBIDDEN_PATH.search(n)})
    # The checker itself names what it prohibits; it contains no integration.
    for name in names:
        if not name.startswith(("game/src/", "engine_patches/")) or not name.endswith((".gd", ".patch")):
            continue
        text = (root / name).read_text()
        if re.search(r"RtxGraphics|Streamline|SCALING_3D_MODE_DLSS|experimental-rtx", text):
            rejected.append(name)
    if rejected:
        raise ValueError("FSR-only source contains excluded integrations: " + ", ".join(rejected))
    return len(names)


def check_template(template):
    binary = template.read_bytes()
    for marker in FORBIDDEN_BINARY:
        if marker in binary or marker.decode().encode("utf-16le") in binary:
            raise ValueError(f"Template includes excluded integration: {marker.decode()}")
    if b"FSR_SDK" not in binary or b"FidelityFX" not in binary:
        raise ValueError("Template does not expose the FidelityFX integration")


def check_package(package):
    for path in package.rglob("*"):
        if path.is_file() and FORBIDDEN_PATH.search(str(path.relative_to(package))):
            raise ValueError(f"Excluded package file: {path.relative_to(package)}")
    check_template(package / "CursedLands.exe")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--template", type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    if args.source:
        print("Source paths verified:", check_source(args.source))
    if args.template:
        check_template(args.template)
    if args.package:
        check_package(args.package)
    print("FSR-only distribution checks passed")
