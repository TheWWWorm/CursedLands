"""Packaged PT manifests must also validate after checkout on an LF host."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT / "game/src/game/fx/shaders"


def canonical_hash(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


class PortableManifestTests(unittest.TestCase):
    def test_path_trace_inputs_survive_cross_platform_checkout(self):
        manifest = json.loads((SHADERS / "path_trace_build.json").read_text())
        self.assertEqual(manifest["source_sha256"], canonical_hash(SHADERS / "path_trace.hlsl"))
        self.assertEqual(manifest["builder_sha256"], canonical_hash(ROOT / "tools/build_water_rt_shaders.py"))
        for name, digest in manifest["includes"].items():
            with self.subTest(source=name):
                self.assertEqual(digest, canonical_hash(SHADERS / name))

    def test_optional_shader_inputs_and_notices_survive_checkout(self):
        for feature in ["sharc", "rtxdi"]:
            manifest = json.loads((SHADERS / f"path_trace_{feature}_build.json").read_text())
            for name, digest in manifest["sources"].items():
                path = (ROOT / f"tools/build_path_{feature}.py" if name == "builder" else
                        ROOT / "engine_patches/rtxdi-sdk.json" if name == "sdk_pin" else SHADERS / name)
                with self.subTest(feature=feature, source=name):
                    self.assertEqual(digest, canonical_hash(path))
            with self.subTest(feature=feature, source="notice"):
                self.assertEqual(manifest["notice_sha256"], canonical_hash(SHADERS / f"{feature.upper()}_NOTICES.txt"))


if __name__ == "__main__":
    unittest.main()
