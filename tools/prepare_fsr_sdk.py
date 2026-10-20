#!/usr/bin/env python3
"""Fetch and verify the official AMD FSR SDK; optionally install its headers."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "engine_patches/godot-4.7/fsr-sdk.json"
VERSION = "2.3.0"
DLLS = ("amd_fidelityfx_loader_dx12.dll", "amd_fidelityfx_upscaler_dx12.dll",
        "amd_fidelityfx_framegeneration_dx12.dll")
AGILITY_CORE_SHA256 = "560f9574372a52ab66ad95ee1222f1eb4c9f6161d8f6b7b025d89f684b07246c"
AGILITY_VERSION = "1.618.5"
AGILITY_SHA256 = "0027fc24f947c48dbded13ada7d280be221eb651644e23a8a476f0f1f0a079dd"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare(output: Path, engine: Path | None = None):
    manifest = json.loads(MANIFEST.read_text())
    for name, expected in manifest["files"].items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            temporary = path.with_name(path.name + ".download")
            with urllib.request.urlopen(manifest["base_url"] + name, timeout=120) as src, temporary.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            if digest(temporary) != expected:
                raise ValueError(f"AMD SDK checksum mismatch: {name}")
            temporary.replace(path)
        if digest(path) != expected:
            raise ValueError(f"AMD SDK checksum mismatch: {name}")
        if engine and name.endswith(".h"):
            target = engine / "thirdparty/amd-fsr-sdk" / name.removeprefix("Kits/FidelityFX/")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    if engine:
        header = engine / "thirdparty/amd-fsr-sdk/api/include/dx12/ffx_api_dx12.h"
        text = header.read_text()
        original = "D3D12_RESOURCE_DESC desc = pRes->GetDesc();"
        if text.count(original) != 1:
            raise ValueError("Unexpected SDK resource helper; review the MinGW compatibility fix")
        header.write_text(text.replace(original,
            "#ifdef __MINGW32__\n"
            "    D3D12_RESOURCE_DESC desc;\n"
            "    pRes->GetDesc(&desc);\n"
            "#else\n"
            "    D3D12_RESOURCE_DESC desc = pRes->GetDesc();\n"
            "#endif"))
    print(f"Verified AMD FSR SDK {manifest['version']}: {output}")


def prepare_agility(output: Path, archive: Path):
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        temporary = archive.with_name(archive.name + ".download")
        url = f"https://www.nuget.org/api/v2/package/Microsoft.Direct3D.D3D12/{AGILITY_VERSION}"
        with urllib.request.urlopen(url, timeout=120) as src, temporary.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        if digest(temporary) != AGILITY_SHA256:
            raise ValueError("DirectX Agility SDK checksum mismatch")
        temporary.replace(archive)
    if digest(archive) != AGILITY_SHA256:
        raise ValueError("DirectX Agility SDK checksum mismatch")
    with zipfile.ZipFile(archive) as package:
        for source, target in (
            ("build/native/bin/x64/D3D12Core.dll", "x86_64/D3D12Core.dll"),
            ("LICENSE.txt", "licenses/Microsoft-DirectX/LICENSE.txt"),
            ("LICENSE-CODE.txt", "licenses/Microsoft-DirectX/LICENSE-CODE.txt"),
        ):
            destination = output / "agility" / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(package.read(source))
    print(f"Verified DirectX Agility SDK {AGILITY_VERSION}: {output / 'agility'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--agility-archive", type=Path)
    args = parser.parse_args()
    prepare(args.output.resolve(), args.engine.resolve() if args.engine else None)
    prepare_agility(args.output.resolve(), args.agility_archive.resolve() if args.agility_archive else
                    args.output.resolve() / f"Microsoft.Direct3D.D3D12.{AGILITY_VERSION}.nupkg")
