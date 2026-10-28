"""MMP-to-PNG export; fixtures are generated and contain no game assets.

Full-data parity with game/src/ei/mmp_texture.gd is recorded in
docs/validation/texture-export-2026-10-28.json.
"""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "tests"))
import export_textures
import package_mod
from test_legacy_mod_converter import archive

RED, BLUE = 0xF800, 0x001F
MASKS_4444 = ((0xF000, 12, 4), (0x0F00, 8, 4), (0x00F0, 4, 4), (0x000F, 0, 4))
MASKS_8888 = ((0xFF000000, 24, 8), (0xFF0000, 16, 8), (0xFF00, 8, 8), (0xFF, 0, 8))


def mmp(w, h, tag, payload, size=0, bits=0, masks=((0, 0, 0),) * 4):
    head = struct.pack("<IIII4sI", 0x00504D4D, w, h, size, tag, bits)
    head += b"".join(struct.pack("<III", *m) for m in masks)
    return head.ljust(export_textures.DATA_OFFSET, b"\0") + payload


def read_png(data):
    """(w, h, RGBA) of the filter-0 RGBA PNGs the exporter writes."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        assert struct.unpack_from(">I", data, pos + 8 + length)[0] == zlib.crc32(kind + body)
        if kind == b"IHDR":
            w, h, depth, color = struct.unpack_from(">IIBB", body)
            assert (depth, color) == (8, 6)
        idat += body if kind == b"IDAT" else b""
        pos += 12 + length
    raw = zlib.decompress(idat)
    rows = [raw[y * (w * 4 + 1):(y + 1) * (w * 4 + 1)] for y in range(h)]
    assert all(row[0] == 0 for row in rows)
    return w, h, b"".join(row[1:] for row in rows)


def pixel(rgba, w, x, y):
    return tuple(rgba[(y * w + x) * 4:(y * w + x) * 4 + 4])


class Decoding(unittest.TestCase):
    def test_dxt1_uses_godot_palette_and_transparent_index(self):
        indices = 0b11100100  # pixels 0..3 use palette entries 0..3
        opaque = struct.pack("<HHI", RED, BLUE, indices)
        w, h, px = export_textures.decode(mmp(4, 4, b"DXT1", opaque))
        self.assertEqual([pixel(px, w, x, 0) for x in range(4)],
                         [(255, 0, 0, 255), (0, 0, 255, 255), (170, 0, 85, 255), (85, 0, 170, 255)])
        punch = struct.pack("<HHI", BLUE, RED, indices)
        w, h, px = export_textures.decode(mmp(4, 4, b"DXT1", punch))
        self.assertEqual([pixel(px, w, x, 0) for x in (2, 3)], [(128, 0, 128, 255), (0, 0, 0, 0)])

    def test_dxt3_keeps_explicit_alpha_and_four_colour_mode(self):
        alpha = sum(n << (i * 4) for i, n in enumerate(range(16)))
        block = struct.pack("<Q", alpha) + struct.pack("<HHI", BLUE, RED, 0b11100100)
        w, h, px = export_textures.decode(mmp(4, 4, b"DXT3", block))
        self.assertEqual(pixel(px, w, 3, 0), (170, 0, 85, 51))
        self.assertEqual([pixel(px, w, x, 3)[3] for x in range(4)], [204, 221, 238, 255])

    def test_pnt3_run_length(self):
        payload = bytes((10, 20, 30, 255)) + struct.pack("<I", 8) + bytes((1, 2, 3, 4))
        w, h, px = export_textures.decode(mmp(2, 2, b"PNT3", payload, size=len(payload)))
        self.assertEqual([pixel(px, w, x, y) for y in range(2) for x in range(2)],
                         [(30, 20, 10, 255), (0, 0, 0, 0), (0, 0, 0, 0), (3, 2, 1, 4)])

    def test_raw_masks_and_bottom_up_8888(self):
        w, h, px = export_textures.decode(mmp(1, 1, b"\x44\x44\0\0", struct.pack("<H", 0x8F40), bits=16, masks=MASKS_4444))
        self.assertEqual(pixel(px, w, 0, 0), (255, 68, 0, 136))
        rows = struct.pack("<II", 0xFF102030, 0x80405060)
        w, h, px = export_textures.decode(mmp(1, 2, b"\x88\x88\0\0", rows, bits=32, masks=MASKS_8888))
        self.assertEqual([pixel(px, w, 0, y) for y in range(2)], [(64, 80, 96, 128), (16, 32, 48, 255)])

    def test_damaged_textures_are_rejected(self):
        for data in (b"PNG", mmp(0, 4, b"DXT1", b""), mmp(8, 8, b"DXT1", bytes(8)), mmp(4, 4, b"\x44\x44\0\0", b"", bits=16)):
            with self.assertRaises(ValueError):
                export_textures.decode(data)

    def test_png_is_lossless_rgba(self):
        rgba = bytes(range(64))
        self.assertEqual(read_png(export_textures.png(4, 4, rgba)), (4, 4, rgba))


class Export(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        res = self.root / "game/Res"
        res.mkdir(parents=True)
        dxt = mmp(4, 4, b"DXT1", struct.pack("<HHI", RED, BLUE, 0))
        (res / "Textures.res").write_bytes(archive({"Stone.mmp": dxt, "sub/grass.mmp": dxt, "readme.txt": b"x"}))
        (res / "menus.res").write_bytes(archive({"mainmenu00.mmp": dxt, "unmoco2.mod": b"model"}))
        (res / "redress.res").write_bytes(archive({"broken.mmp": b"MMP\0"}))
        self.out = self.root / "out"
        self.log = []

    def tearDown(self):
        self.temp.cleanup()

    def export(self, **options):
        return export_textures.export(self.root / "game", self.out, log=self.log.append, **options)

    def files(self):
        return sorted(p.relative_to(self.out).as_posix() for p in self.out.rglob("*") if p.is_file())

    def test_game_folder_exports_the_package_layout(self):
        counts = self.export()
        self.assertEqual(counts, {"written": 3, "unchanged": 0, "kept": 0, "failed": 1})
        self.assertEqual(self.files(), ["menus.res/mainmenu00.png", "textures.res/stone.png", "textures.res/sub/grass.png"])
        self.assertEqual(read_png((self.out / "textures.res/stone.png").read_bytes())[2][:4], bytes((255, 0, 0, 255)))
        self.assertTrue(any("broken.mmp" in line for line in self.log))

    def test_archive_and_name_filters(self):
        self.export(archives=["textures.res"], patterns=["sub/*"])
        self.assertEqual(self.files(), ["textures.res/sub/grass.png"])

    def test_edited_images_are_kept_unless_overwrite(self):
        self.export(archives=["textures.res"])
        edited = self.out / "textures.res/stone.png"
        edited.write_bytes(b"edited")
        self.assertEqual(self.export(archives=["textures.res"])["kept"], 1)
        self.assertEqual(edited.read_bytes(), b"edited")
        self.assertEqual(self.export(archives=["textures.res"], overwrite=True)["written"], 1)
        self.assertEqual(self.export(archives=["textures.res"])["unchanged"], 2)

    def test_single_archive_from_a_legacy_mod(self):
        export_textures.export(self.root / "game/Res/Textures.res", self.out, patterns=["stone.mmp"], name="textures.res")
        self.assertEqual(self.files(), ["textures.res/stone.png"])

    def test_exported_images_package_as_overrides(self):
        self.export(archives=["textures.res", "menus.res"], patterns=["stone*", "mainmenu*"])
        (self.out / "mod.json").write_text(json.dumps({"api": 2, "id": "png.pack", "version": "1.0",
                                                       "title": "PNG pack", "campaigns": ["cursed_lands"]}))
        package_mod.package(self.out, self.root / "pack.eimod")
        with zipfile.ZipFile(self.root / "pack.eimod") as pack:
            overrides = json.loads(pack.read("mod.json"))["overrides"]
        self.assertEqual(sorted((o["archive"], o["entry"]) for o in overrides),
                         [("menus.res", "mainmenu00.mmp"), ("textures.res", "stone.mmp")])

    def test_command_line(self):
        code = export_textures.main([str(self.root / "game"), str(self.out), "--archive", "menus.res", "--match", "mainmenu00"])
        self.assertEqual((code, self.files()), (0, ["menus.res/mainmenu00.png"]))
        self.assertEqual(export_textures.main([str(self.root / "missing"), str(self.out)]), 1)


if __name__ == "__main__":
    unittest.main()
