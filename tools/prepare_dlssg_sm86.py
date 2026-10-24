#!/usr/bin/env python3
"""Make a separate, opt-in local DLSS-G SM86 package from a Windows preview.

Requires the exact upstream archive; never downloads or modifies an installed
game, player profile, operating-system DLL or the base package.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

VERSION = "0.4.0"
URL = "https://github.com/sdli1995/dlssg_for_sm86/releases/download/0.4.0/dlssg-release-0.4.0-x64.zip"
ARCHIVE_SHA256 = "5865360c3295038f0ff979d303bb7eb9437eec09fbc08686967d3b5d41d9c019"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare(base, archive, output):
    base, archive, output = base.resolve(), archive.resolve(), output.resolve()
    if output.exists() or base == output or base in output.parents:
        raise ValueError("Output must be a new directory outside the base package")
    if sha(archive) != ARCHIVE_SHA256:
        raise ValueError("Archive SHA-256 does not match pinned dlssg_for_sm86 0.4.0")
    metadata = json.loads((base / "BUILD-INFO.json").read_text())
    if metadata.get("platform") != "windows-x86_64" or not metadata.get("dlss"):
        raise ValueError("Base must be an exported Windows preview with native NVIDIA DLSS")
    if any((base / name).exists() for name in ("winmm.dll", "version.dll", "dlssg_sm86", "dlssg_sm86.ini")):
        raise ValueError("Base already contains a proxy/mod; use a clean preview")
    with zipfile.ZipFile(archive) as package:
        names = package.namelist()
        required = ["alternatives/winmm.dll", "dlssg_sm86.ini", "LICENSE.md", "THIRD_PARTY_NOTICES.txt",
                    "dlssg_sm86/runtime/nvngx_dlssg.dll", "dlssg_sm86/backend/sm86_backend.dll"]
        if any(name not in names for name in required):
            raise ValueError("Upstream archive layout has changed")
        entries = {"winmm.dll": "alternatives/winmm.dll", "dlssg_sm86.ini": "dlssg_sm86.ini"}
        for name in names:
            if name.endswith("/"):
                continue
            if name.startswith("dlssg_sm86/"):
                entries[name] = name
            elif name in ("LICENSE.md", "THIRD_PARTY_NOTICES.txt", "manifest.json", "validation.json") or name.startswith("docs/"):
                entries["licenses/dlssg_for_sm86/" + name] = name
        for destination in entries:
            if Path(destination).is_absolute() or ".." in Path(destination).parts:
                raise ValueError("Unsafe archive path")
        ini = package.read("dlssg_sm86.ini").decode("utf-8-sig")
        for old, new in (("MaxGeneratedFrames=3", "MaxGeneratedFrames=1"), ("Optimized=2", "Optimized=1")):
            if ini.count(old) != 1:
                raise ValueError("Unexpected upstream configuration")
            ini = ini.replace(old, new)
        shutil.copytree(base, output)
        for destination, source in entries.items():
            target = output / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(package.read(source))
        (output / "dlssg_sm86.ini").write_text(ini)
    readme = Path(__file__).resolve().parents[1] / "docs/integrations/dlssg-sm86-player.txt"
    shutil.copy2(readme, output / "README-RTX30.txt")
    metadata["base_package_build_info_sha256"] = sha(base / "BUILD-INFO.json")
    metadata["build_type"] = "local unpublished DLSS-G SM86 experiment"
    metadata["dlssg_sm86"] = {
        "version": VERSION, "archive_sha256": ARCHIVE_SHA256, "source": URL,
        "proxy": "winmm.dll", "engine": "DLSS", "generated_frames": 1,
        "consistency_tier": 1, "super_resolution_patch": False,
        "native_windows_qualified": False,
    }
    (output / "SHA256SUMS.txt").unlink(missing_ok=True)
    metadata["files"] = {str(p.relative_to(output)): sha(p) for p in sorted(output.rglob("*"))
                         if p.is_file() and p.name != "BUILD-INFO.json"}
    (output / "BUILD-INFO.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-package", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True, help=URL)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.base_package, args.archive, args.output)
