#!/usr/bin/env python3
"""Package a data, texture or API 3 formula mod. The game validates the manifest."""
import argparse
import json
from pathlib import Path, PurePosixPath
import zipfile


# Texture folders: <archive>/<entry path>.mmp or .png in the mod source become
# overrides of <entry path>.mmp, so a texture pack needs no hand-written table.
# menus.res holds the menu signpost textures; only its MMP entries are replaceable.
TEXTURE_FOLDERS = ("textures.res", "redress.res", "menus.res")
TEXTURE_SUFFIXES = (".mmp", ".png")


def folder_overrides(source: Path, manifest: dict) -> list:
    declared = {(entry["archive"], entry["entry"].lower()) for entry in manifest.get("overrides", [])}
    found = {}
    for archive in TEXTURE_FOLDERS:
        root = source / archive
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Asset must be a regular file inside the mod: {path.relative_to(source)}")
            if not path.is_file() or path.suffix.lower() not in TEXTURE_SUFFIXES:
                continue
            relative = path.relative_to(root).as_posix()
            entry = relative[: -len(path.suffix)] + ".mmp"
            key = (archive, entry.lower())
            if key in found:
                raise ValueError(f"Two files replace {archive}/{entry}: {found[key]['file']} and {archive}/{relative}")
            if key in declared:
                raise ValueError(f"{archive}/{relative} replaces an entry already listed in mod.json: {entry}")
            found[key] = {"archive": archive, "entry": entry, "file": f"{archive}/{relative}"}
    return list(found.values())


def package(source: Path, output: Path) -> None:
    source = source.resolve()
    manifest_bytes = (source / "mod.json").read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    generated = folder_overrides(source, manifest)
    if generated:
        manifest["overrides"] = manifest.get("overrides", []) + generated
        manifest_bytes = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    names = {"mod.json", *(entry["file"] for entry in manifest.get("overrides", []))}
    names.update(manifest.get("attachments", []))
    modules = manifest.get("script", {}).get("modules", {})
    names.update(modules.values())
    payload = {}
    for name in sorted(names):
        parts = PurePosixPath(name).parts
        if not parts or name.startswith("/") or ".." in parts or "\\" in name or ":" in name:
            raise ValueError(f"Unsafe package path: {name}")
        path = source / name
        if not path.resolve().is_relative_to(source) or path.is_symlink():
            raise ValueError(f"Asset must be a regular file inside the mod: {name}")
        payload[name] = manifest_bytes if name == "mod.json" else path.read_bytes()
    if len(payload) > 4096 or sum(map(len, payload.values())) > 128 * 1024 * 1024:
        raise ValueError("Package exceeds the game's limits")
    if len(payload["mod.json"]) > 1024 * 1024:
        raise ValueError("Manifest exceeds 1 MiB")
    if any(len(payload[name]) > 1024 * 1024 for name in modules.values()) or sum(len(payload[name]) for name in modules.values()) > 4 * 1024 * 1024:
        raise ValueError("Formula sources exceed 1 MiB per module or 4 MiB total")
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
