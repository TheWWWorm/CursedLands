#!/usr/bin/env python3
"""Package an API 1 data mod. The game performs the authoritative validation."""
import argparse
import json
from pathlib import Path, PurePosixPath
import zipfile


def package(source: Path, output: Path) -> None:
    source = source.resolve()
    manifest = json.loads((source / "mod.json").read_text(encoding="utf-8"))
    names = {"mod.json", *(entry["file"] for entry in manifest.get("overrides", []))}
    payload = {}
    for name in sorted(names):
        parts = PurePosixPath(name).parts
        if not parts or name.startswith("/") or ".." in parts or "\\" in name or ":" in name:
            raise ValueError(f"Unsafe package path: {name}")
        path = source / name
        if not path.resolve().is_relative_to(source) or path.is_symlink():
            raise ValueError(f"Asset must be a regular file inside the mod: {name}")
        payload[name] = path.read_bytes()
    if len(payload) > 4096 or sum(map(len, payload.values())) > 128 * 1024 * 1024:
        raise ValueError("Package exceeds the game's limits")
    if len(payload["mod.json"]) > 1024 * 1024:
        raise ValueError("Manifest exceeds 1 MiB")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Stable timestamps and ordering make repeated package builds identical.
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in payload.items():
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.source, args.output)
    print(args.output)
