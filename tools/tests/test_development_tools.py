import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("development_tools", ROOT / "tools/development.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class DevelopmentTests(unittest.TestCase):
    def test_zip_traversal_is_rejected_before_any_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "unsafe.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("good.txt", "good")
                z.writestr("../outside.txt", "outside")
            with self.assertRaises(ValueError):
                dev.unpack_zip(archive, root / "extracted")
            self.assertFalse((root / "outside.txt").exists())
            self.assertFalse((root / "extracted/good.txt").exists())

    def test_repeated_bootstrap_reuses_verified_editor_and_removes_duplicate_archive(self):
        with tempfile.TemporaryDirectory(prefix="CL tool setup ") as directory:
            root = Path(directory)
            archive = root / "editor.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("editor.exe", "fixture editor")
            digest = hashlib.sha512(archive.read_bytes()).hexdigest()
            lock = root / "lock.json"
            lock.write_text(json.dumps({"godot": {"editors": {"windows": {
                "archive": archive.name, "executable": "editor.exe", "sha512": digest, "url": "unused"}}}}))
            with patch.object(dev, "LOCK", lock), patch.object(dev, "CACHE", root / "cache"), \
                    patch.object(dev.sys, "platform", "win32"), patch("platform.machine", return_value="AMD64"), \
                    patch.object(dev, "fetch", return_value=archive) as download, patch.object(dev, "execute"):
                first = dev.bootstrap()
                second = dev.bootstrap()
            self.assertEqual(first, second)
            self.assertEqual(download.call_count, 1)
            self.assertFalse(archive.exists())

    def test_profile_does_not_reuse_player_data(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory)
            with patch.dict(dev.os.environ, {"APPDATA": "PLAYER", "LOCALAPPDATA": "PLAYER"}):
                env = dev.profile_environment(profile)
            self.assertEqual(Path(env["APPDATA"]).resolve(), (profile / "data").resolve())
            self.assertEqual(Path(env["LOCALAPPDATA"]).resolve(), (profile / "local").resolve())
            self.assertIn("volume_voice=0", (profile / "data/godot/app_userdata/Cursed Lands/settings.cfg").read_text())

    def test_all_engine_profile_patches_and_pinned_editor_checksums_exist(self):
        lock = json.loads(dev.LOCK.read_text())
        self.assertEqual(len(lock["engine_profiles"]["windows"]), 24)
        self.assertEqual(len(lock["engine_profiles"]["linux"]), 17)
        for profile in lock["engine_profiles"].values():
            self.assertEqual(len(profile), len(set(profile)))
            for name in profile:
                self.assertTrue((ROOT / "engine_patches/godot-4.7" / name).is_file(), name)
        for item in lock["godot"]["editors"].values():
            self.assertRegex(item["sha512"], r"^[0-9a-f]{128}$")


if __name__ == "__main__":
    unittest.main()
