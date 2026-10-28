#!/usr/bin/env python3
"""Convert supported legacy Evil Islands data changes into an API 1 .eimod.

Python 3.10+, standard library only. Inputs are read-only. Any unrepresented
content blocks package creation; the output directory always contains a report.
Binary layouts follow game/src/ei/{reg_file,res_archive,database}.gd.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import tempfile
from pathlib import Path

from package_mod import package

MAX_PACKAGE = 128 * 1024 * 1024
# menus.res: only the signpost MMP textures; its models and menus.reg still block.
ASSETS = {"textures.res": ".mmp", "redress.res": ".mmp", "menus.res": ".mmp", "sfx.res": ".wav", "speech.res": ".mp3"}
# Database entry -> (one-based section ID, table name, field ID -> name/type).
# Everything outside these fields is compared too, and blocks if changed.
DB_FIELDS = {
    "units.udb": (3, "monster_prototypes", {
        9: ("hp", "f"), 10: ("mana", "f"), 19: ("damage_min", "f"),
        20: ("damage_max", "f"), 43: ("experience", "f"),
    }),
    "spells.sdb": (1, "spell_prototypes", {
        3: ("price", "f"), 5: ("mana", "f"), 8: ("range", "f"),
        10: ("effect", "f"), 13: ("duration", "i"),
    }),
    "perks.pdb": (2, "perks", {18: ("cost", "i")}),
}
NATIVE_SUFFIXES = {".dll", ".exe", ".asi", ".so", ".dylib", ".bat", ".cmd"}


def safe_path(value: str) -> str:
    """Normalize legacy Windows separators; enforce the runtime's path rules."""
    if not isinstance(value, str) or not value or len(value) > 240:
        raise ValueError("Empty or oversized path")
    value = value.replace("\\", "/")
    for part in value.split("/"):
        if part in ("", ".", "..") or part.endswith((".", " ")):
            raise ValueError(f"Unsafe path: {value!r}")
        if any(ord(c) < 32 or c in ':<>\"|?*' for c in part):
            raise ValueError(f"Unsafe path: {value!r}")
        if re.fullmatch(r"con|prn|aux|nul|com[1-9]|lpt[1-9]", part.split(".")[0], re.I):
            raise ValueError(f"Reserved path: {value!r}")
    return value.lower()


def identifier(value: str) -> str:
    if not re.fullmatch(r"[a-z0-9_-][a-z0-9._-]{0,79}", value) or ".." in value:
        raise ValueError("IDs and versions need 1–80 lowercase letters, digits, '.', '_' or '-'; no leading dot or '..'")
    return value


def ansi(data: bytes, encoding: str) -> str:
    # EIText retains undefined ANSI bytes as C1 controls.
    return "".join(bytes([b]).decode(encoding) if b not in UNDEFINED[encoding] else chr(b)
                   for b in data.split(b"\0", 1)[0])


UNDEFINED = {"cp1251": {0x98}, "cp1252": {0x81, 0x8D, 0x8F, 0x90, 0x9D}}


class Binary:
    def __init__(self, data: bytes):
        self.data = data

    def read(self, offset: int, size: int) -> bytes:
        if offset < 0 or size < 0 or offset + size > len(self.data):
            raise ValueError("Truncated binary data or invalid offset")
        return self.data[offset:offset + size]

    def number(self, fmt: str, offset: int):
        return struct.unpack("<" + fmt, self.read(offset, struct.calcsize("<" + fmt)))[0]

    def string(self, offset: int, encoding: str) -> tuple[str, int]:
        size = self.number("H", offset)
        return ansi(self.read(offset + 2, size), encoding), offset + 2 + size


def read_registry(data: bytes, encoding: str) -> dict:
    b = Binary(data)
    if b.number("I", 0) != 0x45AB3EFB:
        raise ValueError("config.reg must be a Nival binary registry, not a Windows registry export")
    result = {}
    for i in range(b.number("H", 4)):
        start = b.number("I", 6 + i * 6 + 2)
        name, table = b.string(start + 2, encoding)
        section = {}
        for k in range(b.number("H", start)):
            pos = start + b.number("I", table + k * 6 + 2)
            kind = b.number("B", pos)
            key, pos = b.string(pos + 1, encoding)
            count = b.number("H", pos) if kind & 128 else 1
            if kind & 128:
                pos += 2
            values = []
            for _ in range(count):
                if kind & 127 == 2:
                    value, pos = b.string(pos, encoding)
                elif kind & 127 in (0, 1):
                    value = b.number("i" if kind & 127 == 0 else "f", pos)
                    pos += 4
                    if isinstance(value, float) and not math.isfinite(value):
                        raise ValueError("Nonfinite registry value")
                else:
                    raise ValueError(f"Unknown registry type: {kind}")
                values.append(value)
            if key.lower() in section:
                raise ValueError(f"Duplicate registry key: {name}/{key}")
            section[key.lower()] = values if kind & 128 else values[0]
        if name.lower() in result:
            raise ValueError(f"Duplicate registry section: {name}")
        result[name.lower()] = section
    return result


class Tree:
    """Case-insensitive lookup without following links or escaping the root."""
    def __init__(self, root: Path):
        self.root = root.resolve()
        if not self.root.is_dir():
            raise ValueError(f"Not a directory: {root}")
        self.files = {}
        seen = set()
        for path in sorted(self.root.rglob("*")):
            if len(seen) >= 100000:
                raise ValueError("Input directory contains more than 100,000 paths")
            name = safe_path(path.relative_to(self.root).as_posix())
            if path.is_symlink() or not (path.is_file() or path.is_dir()):
                raise ValueError(f"Input contains a link or special file: {name}")
            if name in seen:
                raise ValueError(f"Case-colliding input paths: {name}")
            seen.add(name)
            if path.is_file():
                self.files[name] = path

    def path(self, name: str) -> Path:
        name = safe_path(name)
        if name not in self.files:
            raise ValueError(f"Missing input: {name} in {self.root}")
        return self.files[name]


class Archive:
    def __init__(self, path: Path):
        self.path = path
        self.entries = {}
        size = path.stat().st_size
        with path.open("rb") as f:
            h = Binary(f.read(16))
            if h.number("I", 0) != 0x019CE23C:
                raise ValueError(f"Not an Evil Islands archive: {path.name}")
            count, offset, names_size = (h.number("I", i) for i in (4, 8, 12))
            table_size = count * 22
            if count > 1000000 or names_size > 16777216 or offset < 16 or offset + table_size + names_size > size:
                raise ValueError(f"Invalid archive index: {path.name}")
            f.seek(offset)
            table = Binary(f.read(table_size + names_size))
        for i in range(count):
            p = i * 22
            length, start = table.number("I", p + 4), table.number("I", p + 8)
            nl, no = table.number("H", p + 16), table.number("I", p + 18)
            if no + nl > names_size or start + length > size:
                raise ValueError(f"Invalid archive entry: {path.name}")
            # Match Godot's get_string_from_ascii(): a byte-to-codepoint
            # Latin-1 mapping, including names with bytes above 0x7f. The
            # config/database text encoding is not used for archive keys.
            name = safe_path(table.read(table_size + no, nl).decode("latin1"))
            if name in self.entries:
                raise ValueError(f"Duplicate archive entry: {path.name}/{name}")
            self.entries[name] = (start, length)

    def read(self, name: str) -> bytes:
        start, length = self.entries[name]
        if length > MAX_PACKAGE:
            raise ValueError(f"Archive entry exceeds 128 MiB: {self.path.name}/{name}")
        with self.path.open("rb") as f:
            f.seek(start)
            data = f.read(length)
        if len(data) != length:
            raise ValueError("Archive changed while being read")
        return data


def blocks(data: bytes) -> list[tuple[int, bytes]]:
    """Read length-delimited database fields, including their tags."""
    b, pos, result = Binary(data), 0, []
    while pos < len(data):
        tag, short = b.number("B", pos), b.number("B", pos + 1)
        width = 5 if short & 1 else 2
        size = (b.number("I", pos + 1) if short & 1 else short) // 2
        result.append((tag, b.read(pos + width, size)))
        pos += width + size
    return result


def unique_fields(data: bytes) -> dict[int, bytes]:
    entries = blocks(data)
    result = dict(entries)
    if len(result) != len(entries):
        raise ValueError("Duplicate database field")
    return result


class Converter:
    def __init__(self, source: Path, base: Path, mod_id: str, version: str,
                 campaign: str, encoding: str = "cp1251"):
        self.source, self.base = Tree(source), Tree(base)
        self.encoding = encoding
        self.assets: dict[str, bytes] = {}
        self.asset_bytes = 0
        self.used = set()
        self.report = {"converter_version": 1, "mod_api": 1, "status": "analyzing",
                       "source": str(self.source.root), "base_game": str(self.base.root),
                       "encoding": encoding, "blockers": [], "base_entries": [],
                       "ignored_documentation": [], "unchanged_entries": 0}
        self.manifest = {"api": 1, "id": identifier(mod_id), "version": identifier(version),
                         "title": mod_id, "campaigns": [campaign], "overrides": [], "patches": []}

    def block(self, code: str, location: str, message: str) -> None:
        self.report["blockers"].append({"code": code, "location": location, "message": message})

    def database(self, target: str, entry: str, old: bytes, new: bytes) -> None:
        location = target + "/" + entry
        if entry not in DB_FIELDS:
            self.block("unsupported_database", location, "This database entry is outside API 1.")
            return
        section_id, table_name, fields = DB_FIELDS[entry]
        a, b = blocks(old), blocks(new)
        # The first root is the DB; further roots hold editor metadata. Do not
        # discard changes there, or reinterpret a different database layout.
        if not a or not b or a[0][0] != 1 or b[0][0] != 1 or a[1:] != b[1:]:
            self.block("database_layout", location, "Database root or trailing metadata changed.")
            return
        left, right = blocks(a[0][1]), blocks(b[0][1])
        if [t for t, _ in left] != [t for t, _ in right] or len(dict(left)) != len(left):
            self.block("database_layout", location, "Database sections were added, removed, reordered or duplicated.")
            return
        for (tag, before), (_, after) in zip(left, right):
            if before == after:
                continue
            if tag != section_id:
                self.block("unsupported_table", f"{location}/section-{tag}", "This table cannot be patched by API 1.")
                continue
            rows_a, rows_b = blocks(before), blocks(after)
            if [t for t, _ in rows_a] != [t for t, _ in rows_b] or any(t != 1 for t, _ in rows_a):
                self.block("database_records", location, "Adding or removing database records needs a newer mod API.")
                continue
            seen = set()
            for (_, raw_a), (_, raw_b) in zip(rows_a, rows_b):
                fa, fb = unique_fields(raw_a), unique_fields(raw_b)
                name = ansi(fa.get(0, b""), self.encoding)
                if not name or name.lower() in seen or fa.get(0) != fb.get(0):
                    self.block("database_records", location, "Record names are missing, duplicated, renamed or reordered.")
                    continue
                seen.add(name.lower())
                for field in sorted(fa.keys() | fb.keys()):
                    if fa.get(field) == fb.get(field):
                        continue
                    at = f"{location}/{name}/field-{field}"
                    if field not in fields or field not in fa or field not in fb:
                        self.block("unsupported_field", at, "This field change cannot be represented by API 1.")
                        continue
                    field_name, fmt = fields[field]
                    if len(fa[field]) != 4 or len(fb[field]) != 4:
                        self.block("database_layout", at, "Numeric field is not four bytes.")
                        continue
                    value = struct.unpack("<" + fmt, fb[field])[0]
                    if not math.isfinite(value) or not 0 <= value <= 1000000 or len(name) > 160:
                        self.block("database_value", at, "Value or record name exceeds API 1 limits.")
                        continue
                    self.manifest["patches"].append({"database": "campaign" if target == "database.res" else "multiplayer",
                        "table": table_name, "record": name, "field": field_name, "value": value})

    def archive(self, target: str, paths: list[str]) -> None:
        base = Archive(self.base.path("res/" + target))
        providers = {}
        for name in paths:
            name = safe_path(name)
            archive = Archive(self.source.path(name))
            self.used.add(name)
            for entry in archive.entries:
                providers.setdefault(entry, []).append(archive)
        for entry, sources in sorted(providers.items()):
            at = target + "/" + entry
            new = sources[0].read(entry)
            if any(other.read(entry) != new for other in sources[1:]):
                self.block("archive_precedence", at, "Multiple archives provide different bytes; legacy precedence needs an explicit adapter.")
                continue
            if entry not in base.entries:
                self.block("new_archive_entry", at, "New entries and their references need a newer mod API.")
                continue
            old = base.read(entry)
            if new == old:
                self.report["unchanged_entries"] += 1
                continue
            self.report["base_entries"].append({"archive": target, "entry": entry,
                "sha256": hashlib.sha256(old).hexdigest()})
            if target in ASSETS and entry.endswith(ASSETS[target]) and new:
                path = "assets/" + target + "/" + entry
                safe_path(path)
                self.asset_bytes += len(new)
                # Keep scanning oversized packs so the report also identifies
                # unsupported content after the size limit is reached. Retain
                # payloads only while the package could still fit in API 1.
                if self.asset_bytes <= MAX_PACKAGE and len(self.assets) < 4095:
                    self.assets[path] = new
                self.manifest["overrides"].append({"archive": target, "entry": entry, "file": path})
            elif target in ("database.res", "databaselmp.res"):
                self.database(target, entry, old, new)
            else:
                self.block("unsupported_archive", at, "API 1 supports MMP textures, WAV sound, MP3 speech and selected numeric database fields.")

    def analyze(self) -> dict:
        config = {}
        if "config.reg" in self.source.files:
            path = self.source.path("config.reg")
            if path.stat().st_size > 1048576:
                raise ValueError("config.reg exceeds 1 MiB")
            config = read_registry(path.read_bytes(), self.encoding)
            self.used.add("config.reg")
        metadata = config.get("mod", {})
        self.report["legacy_metadata"] = metadata
        title = metadata.get("title", self.manifest["id"])
        if isinstance(title, str) and title and len(title) <= 100:
            self.manifest["title"] = title
        else:
            self.block("metadata", "MOD.Title", "Title must contain 1–100 characters.")
        modes = []
        for key, choices in (("single", ["single_player", "campaign_coop"]), ("multi", ["original_multiplayer"])):
            value = metadata.get(key, 1)
            if type(value) is not int or value not in (0, 1):
                self.block("metadata", "MOD." + key, "Expected a 0 or 1 mode flag.")
            elif value:
                modes.extend(choices)
        if not modes:
            self.block("metadata", "MOD", "No supported game mode enabled.")
        self.manifest["modes"] = modes
        for section, values in config.items():
            for key, value in values.items():
                if key.startswith((";", "#")):
                    continue
                if section == "res" or section == "mod" and key in {"title", "author", "authoremail", "url", "date_dmy", "version", "gamesaves", "single", "multi"}:
                    continue
                if section == "dev" and key == "plugin" and value in ("", []):
                    continue
                self.block("native_plugin" if section == "dev" and "plugin" in key else "unsupported_config",
                    section + "/" + key, f"Requires a compatibility adapter: {value!r}")
        mappings = {}
        for target, value in config.get("res", {}).items():
            if target.startswith((";", "#")):
                continue
            target = safe_path(target)
            if "/" in target or not target.endswith(".res"):
                raise ValueError(f"Unsupported archive target: {target}")
            paths = value if isinstance(value, list) else [value]
            if not paths or not all(isinstance(p, str) for p in paths):
                raise ValueError(f"Invalid resource mapping: {target}")
            mappings[target] = paths
        # A conventional res/<archive>.res also works for simple folder mods.
        # If config.reg explicitly remaps it, an unused file is still reported.
        declared = {safe_path(name) for paths in mappings.values() for name in paths}
        for name in self.source.files:
            if name not in declared and re.fullmatch(r"res/[^/]+\.res", name):
                mappings.setdefault(name.split("/")[1], [name])
        for target, paths in sorted(mappings.items()):
            try:
                self.archive(target, paths)
            except (ValueError, UnicodeError, OSError) as error:
                self.block("unreadable_archive", target, str(error))
        for name in sorted(self.source.files.keys() - self.used):
            suffix = Path(name).suffix
            if suffix in ("", ".txt", ".md", ".rst") and "/" not in name and re.fullmatch(r"(?:readme|license|licence|copying|changelog)(?:[._ -].*)?", name):
                self.report["ignored_documentation"].append(name)
            else:
                self.block("native_plugin" if suffix in NATIVE_SUFFIXES else "unsupported_file", name,
                    "Native code needs a manual feature port." if suffix in NATIVE_SUFFIXES else "File has no equivalent in the API 1 package.")
        if not self.manifest["overrides"] and not self.manifest["patches"]:
            self.block("no_changes", "mod", "No supported changes relative to this base installation.")
        manifest_bytes = json.dumps(self.manifest, ensure_ascii=False, allow_nan=False).encode("utf-8")
        if (len(self.manifest["overrides"]) + 1 > 4096 or len(self.manifest["patches"]) > 1024 or
                len(manifest_bytes) > 1048576 or self.asset_bytes + len(manifest_bytes) > MAX_PACKAGE):
            self.block("package_limits", "mod", "Converted content exceeds API 1 package limits.")
        self.report["candidate_overrides"] = self.manifest["overrides"]
        self.report["candidate_patches"] = self.manifest["patches"]
        self.report["candidate_asset_bytes"] = self.asset_bytes
        self.report["status"] = "blocked" if self.report["blockers"] else "ready"
        self.report["runtime_validation"] = "Not performed. Test a converted package in a new mod profile."
        return self.report

    def write_package(self, output: Path) -> Path:
        if self.report["status"] != "ready":
            raise ValueError("Cannot package an incomplete conversion")
        destination = output / (self.manifest["id"] + ".eimod")
        with tempfile.TemporaryDirectory(prefix=".conversion-", dir=output) as scratch:
            stage = Path(scratch)
            (stage / "mod.json").write_text(json.dumps(self.manifest, ensure_ascii=False, allow_nan=False), encoding="utf-8")
            for name, data in self.assets.items():
                path = stage / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            temporary = stage / "package.eimod"
            package(stage, temporary)
            if temporary.stat().st_size > MAX_PACKAGE:
                raise ValueError("Compressed package exceeds 128 MiB")
            temporary.replace(destination)
        return destination


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Unpacked legacy mod folder")
    parser.add_argument("--base-game", required=True, type=Path, help="Clean matching game installation")
    parser.add_argument("--output", required=True, type=Path, help="New output directory, outside both inputs")
    parser.add_argument("--id", required=True, help="Stable lowercase mod ID")
    parser.add_argument("--version", required=True, help="Version of the converted package")
    parser.add_argument("--campaign", required=True, choices=["cursed_lands", "lost_in_astral"])
    parser.add_argument("--encoding", choices=["cp1251", "cp1252"], default="cp1251",
                        help="Russian: cp1251; English/German: cp1252")
    parser.add_argument("--report-only", action="store_true", help="Analyze without creating a package")
    args = parser.parse_args(argv)
    output = args.output.resolve()
    if any(output.is_relative_to(p.resolve()) for p in (args.source, args.base_game)):
        parser.error("Output must be outside the mod and base-game directories")
    if output.exists():
        parser.error("Output directory already exists; choose a new directory")
    output.mkdir(parents=True)
    converter = None
    try:
        converter = Converter(args.source, args.base_game, args.id, args.version, args.campaign, args.encoding)
        report = converter.analyze()
        if report["status"] == "ready" and not args.report_only:
            report["package"] = converter.write_package(output).name
            report["status"] = "converted"
    except (ValueError, UnicodeError, OSError) as error:
        report = converter.report if converter else {"converter_version": 1, "mod_api": 1, "blockers": []}
        report["status"] = "blocked"
        report["blockers"].append({"code": "input_error", "location": "conversion", "message": str(error)})
    report_path = output / "conversion-report.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    print(f"{report['status']}: {len(report['blockers'])} blocker(s); {report_path}")
    if "package" in report:
        print(output / report["package"])
    return 1 if report["status"] == "blocked" else 0


if __name__ == "__main__":
    raise SystemExit(main())
