#!/usr/bin/env python3
"""Fetch/check the pinned Streamline dependency for the Windows experiment."""
import argparse
import hashlib
from pathlib import Path
import shutil
import urllib.request
import zipfile

VERSION = "2.14.16"
SHA256 = "32041e51db0cab709a271b72a352281b690c2abbd669a827809401a5dd23956b"
URL = f"https://github.com/NVIDIA-RTX/Streamline/releases/download/v{VERSION}/streamline-sdk-v{VERSION}.zip"
DLLS = ("sl.interposer.dll", "sl.common.dll", "sl.dlss.dll", "sl.dlss_g.dll",
        "sl.reflex.dll", "sl.pcl.dll", "nvngx_dlss.dll", "nvngx_dlssg.dll")
NOTICES = ("license.txt", "3rd-party-licenses.md", "external/ngx-sdk/license.txt",
           "bin/x64/nvngx_dlss.license.txt", "bin/x64/reflex.license.txt")


def prepare(archive: Path, output: Path, engine: Path | None = None):
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        temporary = archive.with_suffix(".download")
        with urllib.request.urlopen(URL) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target)
        temporary.replace(archive)
    if hashlib.file_digest(archive.open("rb"), "sha256").hexdigest() != SHA256:
        raise ValueError("Streamline SDK checksum mismatch")
    with zipfile.ZipFile(archive) as sdk:
        names = [name for name in sdk.namelist() if name.startswith("include/") and not name.endswith("/")]
        names += ["bin/x64/" + name for name in DLLS] + list(NOTICES)
        for name in names:
            if ".." in Path(name).parts:
                raise ValueError("Unsafe SDK member")
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(sdk.read(name))
    if engine:
        shutil.copytree(output / "include", engine / "thirdparty/streamline/include", dirs_exist_ok=True)
    print(f"Verified Streamline {VERSION}: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--engine", type=Path)
    args = parser.parse_args()
    prepare(args.archive.resolve(), args.output.resolve(), args.engine.resolve() if args.engine else None)
