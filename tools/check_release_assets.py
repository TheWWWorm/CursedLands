#!/usr/bin/env python3
"""Reject the permanently withdrawn RTX 30 mod in staged release artifacts.

Checks package directories, ZIP/APK archives and tar archives without extraction.
This checks the withdrawal policy, not general license compliance.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import tarfile
import zipfile


WITHDRAWN = "RTX 30 / dlssg_for_sm86 was permanently withdrawn; do not publish it"
PAYLOAD_NAMES = {
    "dlssg_sm86", "dlssg_for_sm86", "dlssg_sm86.ini", "fg_kernels.dll",
    "sr_kernels.dll", "sm86_backend.dll",
}
ASSET_NAME = re.compile(r"(?:^|[-_])(?:rtx[-_]?30|dlssg[-_](?:for[-_])?sm86)(?:[-_.]|$)", re.I)
ARCHIVE_SUFFIXES = (".zip", ".apk", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tar.xz")


def check_name(name):
    parts = PurePosixPath(str(name).replace("\\", "/").lower()).parts
    if any(part in PAYLOAD_NAMES for part in parts) or any(
        part.endswith(ARCHIVE_SUFFIXES) and ASSET_NAME.search(part) for part in parts
    ):
        raise ValueError(f"{WITHDRAWN}: {name}")


def check_metadata(data, name):
    metadata = json.loads(data)
    if not isinstance(metadata, dict):
        raise ValueError(f"Invalid build metadata: {name}")
    if metadata.get("dlssg_sm86") or metadata.get("dlssg_for_sm86"):
        raise ValueError(f"{WITHDRAWN}: {name}")


def check_artifact(path):
    path = Path(path)
    if not path.exists():
        raise ValueError(f"Release artifact does not exist: {path}")
    if ASSET_NAME.search(path.name) and (path.is_dir() or path.name.lower().endswith(ARCHIVE_SUFFIXES)):
        raise ValueError(f"{WITHDRAWN}: {path.name}")
    check_name(path.name)
    if path.is_dir():
        for entry in sorted(path.rglob("*")):
            check_name(entry.relative_to(path))
            if entry.is_file():
                check_artifact(entry)
    elif zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                check_name(entry.filename)
                if PurePosixPath(entry.filename).name.lower() == "build-info.json":
                    check_metadata(archive.read(entry), entry.filename)
    elif path.name.lower().endswith((".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tar.xz")):
        with tarfile.open(path, "r:*") as archive:
            for entry in archive:
                check_name(entry.name)
                if entry.isfile() and PurePosixPath(entry.name).name.lower() == "build-info.json":
                    with archive.extractfile(entry) as stream:
                        check_metadata(stream.read(), entry.name)
    elif path.name.lower() == "build-info.json":
        check_metadata(path.read_bytes(), path.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, nargs="+")
    args = parser.parse_args()
    try:
        for asset in args.assets:
            check_artifact(asset)
            print(f"Withdrawal policy passed: {asset.name}")
    except (ValueError, OSError, tarfile.TarError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release blocked: {error}\n")
