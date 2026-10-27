"""Texture-folder packaging; fixtures are generated and contain no game assets."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import package_mod

PNG = b"\x89PNG\r\n\x1a\n" + bytes(32)


def write(root: Path, name: str, data: bytes = PNG) -> None:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


class TextureFolders(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "mod"
        self.root.mkdir()
        self.manifest = {"api": 2, "id": "png.pack", "version": "1.0", "title": "PNG pack",
                         "campaigns": ["cursed_lands"]}

    def tearDown(self):
        self.temp.cleanup()

    def build(self):
        (self.root / "mod.json").write_text(json.dumps(self.manifest))
        out = Path(self.temp.name) / "out.eimod"
        package_mod.package(self.root, out)
        with zipfile.ZipFile(out) as archive:
            return json.loads(archive.read("mod.json")), sorted(archive.namelist())

    def test_folders_become_overrides_without_a_table(self):
        write(self.root, "redress.res/unhufeax_01.gr.0.png")
        write(self.root, "textures.res/sub/Grass00.PNG")
        write(self.root, "textures.res/stone.mmp", b"MMP\0" + bytes(80))
        write(self.root, "textures.res/readme.txt", b"ignored")
        manifest, names = self.build()
        self.assertEqual(manifest["overrides"], [
            {"archive": "textures.res", "entry": "stone.mmp", "file": "textures.res/stone.mmp"},
            {"archive": "textures.res", "entry": "sub/Grass00.mmp", "file": "textures.res/sub/Grass00.PNG"},
            {"archive": "redress.res", "entry": "unhufeax_01.gr.0.mmp", "file": "redress.res/unhufeax_01.gr.0.png"}])
        self.assertEqual(names, ["mod.json", "redress.res/unhufeax_01.gr.0.png", "textures.res/stone.mmp",
                                 "textures.res/sub/Grass00.PNG"])

    def test_explicit_table_is_kept_and_extended(self):
        write(self.root, "assets/skin.mmp", b"MMP\0" + bytes(80))
        write(self.root, "redress.res/weapon.png")
        self.manifest["overrides"] = [{"archive": "redress.res", "entry": "skin.mmp", "file": "assets/skin.mmp"}]
        manifest, _ = self.build()
        self.assertEqual([o["entry"] for o in manifest["overrides"]], ["skin.mmp", "weapon.mmp"])

    def test_without_folders_the_manifest_bytes_are_unchanged(self):
        write(self.root, "assets/skin.mmp", b"MMP\0" + bytes(80))
        self.manifest["overrides"] = [{"archive": "redress.res", "entry": "skin.mmp", "file": "assets/skin.mmp"}]
        text = json.dumps(self.manifest)
        (self.root / "mod.json").write_text(text)
        out = Path(self.temp.name) / "out.eimod"
        package_mod.package(self.root, out)
        with zipfile.ZipFile(out) as archive:
            self.assertEqual(archive.read("mod.json").decode(), text)

    def test_duplicate_and_conflicting_replacements_are_rejected(self):
        write(self.root, "textures.res/stone.png")
        write(self.root, "textures.res/stone.mmp", b"MMP\0" + bytes(80))
        with self.assertRaisesRegex(ValueError, "Two files replace"):
            self.build()
        (self.root / "textures.res/stone.mmp").unlink()
        self.manifest["overrides"] = [{"archive": "textures.res", "entry": "STONE.mmp", "file": "textures.res/stone.png"}]
        with self.assertRaisesRegex(ValueError, "already listed"):
            self.build()


if __name__ == "__main__":
    unittest.main()
