"""Exercise the withdrawal gate with packages that could be uploaded by mistake."""
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_release_assets import check_artifact


class ReleaseAssetPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def make_zip(self, name, files):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as archive:
            for member, data in files.items():
                archive.writestr(member, data)
        return path

    def test_standard_dlss_and_historical_documents_are_allowed(self):
        path = self.make_zip("windows.zip", {
            "game/nvngx_dlss.dll": b"standard runtime",
            "game/docs/integrations/dlssg-sm86.md": b"withdrawal record",
            "game/BUILD-INFO.json": json.dumps({"dlss": True}),
        })
        check_artifact(path)
        with zipfile.ZipFile(path) as archive:
            archive.extractall(self.root / "normal")
        check_artifact(self.root / "normal")

    def test_withdrawn_asset_name_is_rejected(self):
        path = self.make_zip("CursedLands-windows-x86_64-rtx30.zip", {})
        with self.assertRaisesRegex(ValueError, "permanently withdrawn"):
            check_artifact(path)

    def test_renamed_zip_with_mod_payload_is_rejected(self):
        path = self.make_zip("windows.zip", {"game/DLSSG_SM86/kernels/FG_KERNELS.DLL": b"kernel"})
        with self.assertRaisesRegex(ValueError, "permanently withdrawn"):
            check_artifact(path)

    def test_unpacked_mod_is_rejected(self):
        (self.root / "dlssg_sm86.ini").write_text("mod config")
        with self.assertRaisesRegex(ValueError, "permanently withdrawn"):
            check_artifact(self.root)

    def test_tar_build_metadata_cannot_relabel_mod_as_normal(self):
        path = self.root / "windows.tar.gz"
        data = json.dumps({"dlssg_sm86": {"version": "0.4.0"}}).encode()
        with tarfile.open(path, "w:gz") as archive:
            info = tarfile.TarInfo("game/BUILD-INFO.json")
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
        with self.assertRaisesRegex(ValueError, "permanently withdrawn"):
            check_artifact(path)

    def test_retired_packager_fails_without_creating_output(self):
        tool = Path(__file__).resolve().parents[1] / "prepare_dlssg_sm86.py"
        result = subprocess.run([sys.executable, str(tool), "--output", str(self.root / "output")],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("permanently withdrawn", result.stderr)
        self.assertFalse((self.root / "output").exists())


if __name__ == "__main__":
    unittest.main()
