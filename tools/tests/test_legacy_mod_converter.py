"""Behavioral tests; all fixtures are generated and contain no game assets."""
import contextlib
import io
import json
import math
from pathlib import Path
import re
import struct
import sys
import tempfile
import unittest
from unittest import mock
import wave
import zipfile

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import convert_legacy_mod as convert


def archive(entries):
    data = bytearray(16)
    rows, names = bytearray(), bytearray()
    for name, payload in entries.items():
        encoded = name.encode("latin1")
        rows += struct.pack("<IIIIHI", 0, len(payload), len(data), 0, len(encoded), len(names))
        names += encoded
        data += payload
    struct.pack_into("<IIII", data, 0, 0x019CE23C, len(entries), len(data), len(names))
    return bytes(data + rows + names)


def registry(sections):
    def string(value):
        b = value.encode("cp1251")
        return struct.pack("<H", len(b)) + b
    data = bytearray(struct.pack("<IH", 0x45AB3EFB, len(sections)) + b"\0" * (len(sections) * 6))
    for i, (name, values) in enumerate(sections.items()):
        start = len(data)
        struct.pack_into("<I", data, 6 + i * 6 + 2, start)
        data += struct.pack("<H", len(values)) + string(name)
        table = len(data)
        data += b"\0" * (len(values) * 6)
        for j, (key, value) in enumerate(values.items()):
            struct.pack_into("<I", data, table + j * 6 + 2, len(data) - start)
            values_list = value if isinstance(value, list) else [value]
            kind = 2 if isinstance(values_list[0], str) else 0
            data += bytes([kind | (128 if isinstance(value, list) else 0)]) + string(key)
            if isinstance(value, list):
                data += struct.pack("<H", len(value))
            for v in values_list:
                data += string(v) if kind == 2 else struct.pack("<i", v)
    return bytes(data)


def field(tag, payload):
    length = struct.pack("<I", len(payload) * 2 + 1) if len(payload) > 127 else bytes([len(payload) * 2])
    return bytes([tag]) + length + payload


def database(hp=100.0, damage=7.0, experience=20.0, other=b"Human\0", extra_row=False,
             record=b"Human Hero\0", omit_hp=False):
    values = {0: record, 1: other, 9: struct.pack("<f", hp),
              19: struct.pack("<f", damage), 43: struct.pack("<f", experience)}
    if omit_hp:
        del values[9]
    row = field(1, b"".join(field(k, v) for k, v in values.items()))
    if extra_row:
        row += field(1, field(0, b"New Monster\0") + field(9, struct.pack("<f", 100)))
    return field(1, field(1, b"") + field(2, b"") + field(3, row)) + b"\0\0\2\14\2\10\1\0\0\0"


def wav(sample):
    out = io.BytesIO()
    with wave.open(out, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(22050)
        f.writeframes(struct.pack("<hhhh", sample, 0, -sample, 0))
    return out.getvalue()


class ConversionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.base = self.root / "mod", self.root / "base"
        self.source.mkdir()
        self.base.mkdir()

    def put(self, root, name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def db(self, **kwargs):
        self.put(self.base, "res/database.res", archive({"units.udb": database()}))
        self.put(self.source, "res/database.res", archive({"units.udb": database(**kwargs)}))

    def sound(self):
        self.put(self.base, "res/sfx.res", archive({"tools/gate.wav": wav(200), "same.wav": wav(100)}))
        self.put(self.source, "res/sfx.res", archive({"tools\\gate.wav": wav(400), "same.wav": wav(100)}))

    def converter(self, **kwargs):
        return convert.Converter(self.source, self.base, "test.legacy", "1.0", "cursed_lands", **kwargs)

    def codes(self, report):
        return {b["code"] for b in report["blockers"]}

    def run_cli(self, name="out", *extra):
        output = self.root / name
        with contextlib.redirect_stdout(io.StringIO()):
            result = convert.main([str(self.source), "--base-game", str(self.base), "--output", str(output),
                "--id", "test.legacy", "--version", "1.0", "--campaign", "cursed_lands", *extra])
        return result, output, json.loads((output / "conversion-report.json").read_text())

    def test_package_delta_and_inputs_unchanged(self):
        self.sound()
        self.db(hp=125.0, experience=33.5)
        before = {str(p): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        code, out, report = self.run_cli()
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "converted")
        self.assertEqual(report["unchanged_entries"], 1)
        with zipfile.ZipFile(out / "test.legacy.eimod") as z:
            self.assertEqual(set(z.namelist()), {"mod.json", "assets/sfx.res/tools/gate.wav"})
            manifest = json.loads(z.read("mod.json"))
            self.assertEqual(z.read("assets/sfx.res/tools/gate.wav"), wav(400))
            self.assertEqual({p["field"]: p["value"] for p in manifest["patches"]}, {"hp": 125.0, "experience": 33.5})
            self.assertEqual(manifest["patches"][0]["record"], "Human Hero")
        for p, b in before.items():
            self.assertEqual(Path(p).read_bytes(), b)
        _, second, _ = self.run_cli("second")
        self.assertEqual((out / "test.legacy.eimod").read_bytes(), (second / "test.legacy.eimod").read_bytes())

    def test_registry_remapping_and_modes(self):
        self.sound()
        (self.source / "res/sfx.res").rename(self.source / "res/custom.res")
        self.put(self.source, "config.reg", registry({"MOD": {"Title": "Example", "Single": 0, "Multi": 1},
            "RES": {"sfx.res": "RES\\CUSTOM.RES"}, "DEV": {"Plugin": ""}, "starter": {";PluginPath": "disabled.bat"}}))
        c = self.converter()
        self.assertEqual(c.analyze()["status"], "ready")
        self.assertEqual(c.manifest["title"], "Example")
        self.assertEqual(c.manifest["modes"], ["original_multiplayer"])

    def test_redress_delta_preserves_source_archives(self):
        entry = "unhufeax_01.gr.0.mmp"
        old = struct.pack("<5I", 0x504D4D, 1, 1, 4, 0x33544E50) + bytes(56) + bytes([0, 0, 255, 255])
        new = old[:-4] + bytes([255, 0, 0, 255])
        self.put(self.base, "res/redress.res", archive({entry: old, "same.mmp": old}))
        self.put(self.source, "res/redress.res", archive({entry: new, "same.mmp": old}))
        before = {p: p.read_bytes() for p in (self.base / "res/redress.res", self.source / "res/redress.res")}
        code, out, report = self.run_cli()
        self.assertEqual(code, 0)
        self.assertEqual(report["unchanged_entries"], 1)
        with zipfile.ZipFile(out / "test.legacy.eimod") as z:
            path = "assets/redress.res/" + entry
            m = json.loads(z.read("mod.json"))
            self.assertEqual(m["overrides"], [{"archive": "redress.res", "entry": entry, "file": path}])
            self.assertEqual(z.read(path), new)
        for path, data in before.items():
            self.assertEqual(path.read_bytes(), data)

    def test_menu_signpost_texture_converts_but_menu_models_block(self):
        entry = "escmenu00.mmp"
        old = struct.pack("<5I", 0x504D4D, 1, 1, 4, 0x33544E50) + bytes(56) + bytes([0, 0, 255, 255])
        new = old[:-4] + bytes([255, 0, 0, 255])
        self.put(self.base, "res/menus.res", archive({entry: old, "menus.reg": b"old", "unmoco1.mod": b"old"}))
        self.put(self.source, "res/menus.res", archive({entry: new, "menus.reg": b"old", "unmoco1.mod": b"old"}))
        code, out, report = self.run_cli()
        self.assertEqual(code, 0)
        self.assertEqual(report["unchanged_entries"], 2)
        with zipfile.ZipFile(out / "test.legacy.eimod") as z:
            path = "assets/menus.res/" + entry
            self.assertEqual(json.loads(z.read("mod.json"))["overrides"], [{"archive": "menus.res", "entry": entry, "file": path}])
            self.assertEqual(z.read(path), new)
        for changed in ("menus.reg", "unmoco1.mod"):
            entries = {entry: new, "menus.reg": b"old", "unmoco1.mod": b"old", changed: b"new"}
            self.put(self.source, "res/menus.res", archive(entries))
            report = self.converter().analyze()
            self.assertEqual(report["status"], "blocked")
            self.assertEqual({(b["code"], b["location"]) for b in report["blockers"]},
                             {("unsupported_archive", "menus.res/" + changed)})

    def test_multiple_distinct_archives_and_conflicting_precedence(self):
        self.sound()
        self.put(self.source, "res/second.res", archive({"same.wav": wav(100)}))
        self.put(self.source, "config.reg", registry({"RES": {"sfx.res": ["res/sfx.res", "res/second.res"]}}))
        self.assertEqual(self.converter().analyze()["status"], "ready")
        self.put(self.source, "res/second.res", archive({"same.wav": wav(101)}))
        self.assertIn("archive_precedence", self.codes(self.converter().analyze()))

    def test_disabled_legacy_settings_and_author_email(self):
        self.sound()
        self.put(self.source, "config.reg", registry({
            "MOD": {"AuthorEmail": "author@example.invalid", "#Single": 0},
            "DEV": {"#Plugin": "disabled.dll"},
            "RES": {"#gipath": "zone0", "#figures.res": "missing.res", "sfx.res": "res/sfx.res"},
        }))
        c = self.converter()
        self.assertEqual(c.analyze()["status"], "ready")
        self.assertIn("single_player", c.manifest["modes"])
        self.assertEqual(len(c.manifest["overrides"]), 1)

    def test_archive_names_match_runtime_byte_decoding(self):
        name = "sound\u00e9\u0097.wav"
        self.put(self.base, "res/sfx.res", archive({name: wav(100)}))
        self.put(self.source, "res/sfx.res", archive({name: wav(200)}))
        c = self.converter()
        self.assertEqual(c.analyze()["status"], "ready")
        self.assertEqual(c.manifest["overrides"][0]["entry"], name)

    def test_oversized_pack_still_reports_later_unsupported_content(self):
        old = {f"{i}.wav": wav(100) for i in range(4)}
        new = {f"{i}.wav": wav(200) for i in range(4)}
        old["z.ini"], new["z.ini"] = b"old", b"new"
        self.put(self.base, "res/sfx.res", archive(old))
        self.put(self.source, "res/sfx.res", archive(new))
        c = self.converter()
        with mock.patch.object(convert, "MAX_PACKAGE", 200):
            report = c.analyze()
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(self.codes(report), {"package_limits", "unsupported_archive"})
        self.assertEqual(len(report["candidate_overrides"]), 4)
        self.assertEqual(report["candidate_asset_bytes"], 4 * len(wav(200)))
        self.assertLessEqual(sum(map(len, c.assets.values())), 200)

    def test_dll_dependency_blocks_package_even_without_binary(self):
        self.sound()
        self.put(self.source, "config.reg", registry({"DEV": {"Plugin": "um.dll"}}))
        code, out, report = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("native_plugin", self.codes(report))
        self.assertEqual(list(out.glob("*.eimod")), [])
        self.assertEqual(len(report["candidate_overrides"]), 1)

    def test_native_file_cannot_hide_as_readme(self):
        self.sound()
        self.put(self.source, "readme.dll", b"MZ")
        self.assertIn("native_plugin", self.codes(self.converter().analyze()))

    def test_unsupported_edit_blocks_otherwise_supported_patch(self):
        self.db(hp=125, other=b"Orc\0")
        code, out, report = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("unsupported_field", self.codes(report))
        self.assertEqual(report["candidate_patches"][0]["field"], "hp")
        self.assertFalse(list(out.glob("*.eimod")))

    def test_add_remove_rename_records_and_missing_fields(self):
        for kwargs, expected in [({"extra_row": True}, "database_records"),
                ({"record": b"New Hero\0"}, "database_records"), ({"omit_hp": True}, "unsupported_field")]:
            with self.subTest(kwargs=kwargs):
                self.db(**kwargs)
                self.assertIn(expected, self.codes(self.converter().analyze()))

    def test_nonfinite_and_out_of_range_numeric_values(self):
        for value in [math.nan, math.inf, -1, 1000001]:
            with self.subTest(value=value):
                self.db(hp=value)
                self.assertIn("database_value", self.codes(self.converter().analyze()))

    def test_cp1252_record_names_and_multiplayer_target(self):
        name = "Héros".encode("cp1252") + b"\0"
        self.put(self.base, "res/databaselmp.res", archive({"units.udb": database(record=name)}))
        self.put(self.source, "res/databaselmp.res", archive({"units.udb": database(hp=123, record=name)}))
        c = self.converter(encoding="cp1252")
        self.assertEqual(c.analyze()["status"], "ready")
        self.assertEqual(c.manifest["patches"][0]["record"], "Héros")
        self.assertEqual(c.manifest["patches"][0]["database"], "multiplayer")

    def test_unsafe_registry_path(self):
        self.sound()
        self.put(self.source, "config.reg", registry({"RES": {"sfx.res": "..\\secret.res"}}))
        code, out, report = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("input_error", self.codes(report))
        self.assertFalse(list(out.glob("*.eimod")))

    def test_archive_traversal_case_collision_and_truncation(self):
        self.sound()
        for data in [archive({"../escape.wav": wav(300)}), archive({"A.wav": wav(100), "a.wav": wav(200)}), b"bad"]:
            with self.subTest(data=data[:16]):
                self.put(self.source, "res/sfx.res", data)
                self.assertIn("unreadable_archive", self.codes(self.converter().analyze()))

    def test_links_and_case_colliding_input_files(self):
        self.sound()
        link = self.source / "external"
        link.symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "link"):
            self.converter()
        link.unlink()
        self.put(self.source, "res/SFX.RES", b"duplicate")
        with self.assertRaisesRegex(ValueError, "Case-colliding"):
            self.converter()

    def test_maps_settings_and_new_assets_are_reported(self):
        self.sound()
        self.put(self.source, "SPELLADDON.INI", b"[Settings]")
        self.put(self.source, "maps/new.mob", b"map")
        self.put(self.source, "res/sfx.res", archive({"new.wav": wav(200)}))
        report = self.converter().analyze()
        self.assertTrue({"unsupported_file", "new_archive_entry"}.issubset(self.codes(report)))

    def test_documentation_and_report_only(self):
        self.sound()
        self.put(self.source, "README.txt", b"Documentation")
        code, out, report = self.run_cli("out", "--report-only")
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "ready")
        self.assertEqual(report["ignored_documentation"], ["readme.txt"])
        self.assertFalse(list(out.glob("*.eimod")))

    def test_existing_output_is_not_overwritten(self):
        self.sound()
        self.run_cli()
        sentinel = self.root / "out/keep.txt"
        sentinel.write_text("keep")
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.run_cli()
        self.assertEqual(sentinel.read_text(), "keep")

    def test_schema_matches_engine_contract(self):
        source = (TOOLS.parent / "game/src/ei/database.gd").read_text()
        schema = (TOOLS.parent / "game/src/game/mod_schema.gd").read_text()
        textures = set(re.findall(r'"([^"]+)"', re.search(r"RESOURCE_ARCHIVES := \[([^\]]+)\]", schema)[1]))
        self.assertEqual({name for name, suffix in convert.ASSETS.items() if suffix == ".mmp"}, textures)
        for _, (_, table, fields) in convert.DB_FIELDS.items():
            spec, names = re.search(r'\["' + table + r'",\s*"([^"]*)",\s*"([^"]*)"', source).groups()
            names = iter(names.split(","))
            actual = {i: (next(names), t) for i, t in enumerate(spec) if t != " "}
            allowed = set(re.findall(r'"([^"]+)"', re.search(r'"' + table + r'": \[([^\]]+)\]', schema)[1]))
            self.assertEqual({name for name, _ in fields.values()}, allowed)
            for i, (name, fmt) in fields.items():
                self.assertEqual(actual[i], (name, fmt.upper()))


if __name__ == "__main__":
    unittest.main()
