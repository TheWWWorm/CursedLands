"""Registered by unittest discovery in the Linux/Windows CI matrix."""
import os
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/parity"))
import process
from run import isolated_environment


class WindowsDevelopmentTests(unittest.TestCase):
    def test_qualification_reports_import_without_unix_locking_module(self):
        spec = importlib.util.spec_from_file_location("portable_qualification", ROOT / "tools/tests/run_path_trace_qualification.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"fcntl": None}):
            spec.loader.exec_module(module)
        self.assertTrue(callable(module.validate_reports))

    def test_render_driver_follows_host_without_changing_linux(self):
        for host, driver in [("win32", "windows"), ("linux", "x11")]:
            with patch.object(process.sys, "platform", host):
                args = process.rendered_arguments()
            self.assertEqual(args[args.index("--display-driver") + 1], driver)

    def test_catalog_profile_isolates_windows_player_directories(self):
        with tempfile.TemporaryDirectory(prefix="CL profile ") as directory:
            root = Path(directory)
            with patch.dict(os.environ, {"APPDATA": "PLAYER_PROFILE", "LOCALAPPDATA": "PLAYER_CACHE"}):
                env = isolated_environment(root, "Cursed Lands", root / "owned data")
            self.assertEqual(Path(env["APPDATA"]), root / "data")
            self.assertEqual(Path(env["LOCALAPPDATA"]), root / "local")
            settings = (root / "data/godot/app_userdata/Cursed Lands/settings.cfg").read_text()
            for value in ("confine_mouse=0", "show_fps=1", "volume_sfx=0", "volume_stream=0", "volume_voice=0"):
                self.assertIn(value, settings)

    @unittest.skipUnless(sys.platform == "win32", "native Windows process ownership test")
    def test_error_kills_child_and_preserves_unrelated_process(self):
        with tempfile.TemporaryDirectory(prefix="CL children ") as directory:
            root = Path(directory)
            child = "import time,pathlib;time.sleep(3);pathlib.Path(%r).write_text('escaped')" % str(root / "escaped.txt")
            parent = ("import subprocess,sys,time;subprocess.Popen([sys.executable,'-c',%r]);"
                      "time.sleep(.3);print('SCRIPT ERROR: stop',flush=True);time.sleep(30)") % child
            unrelated = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(30)"])
            try:
                _, error = process.run_program([sys.executable, "-c", parent], root / "run.log", dict(os.environ), 15)
                self.assertIn("Runtime/script error", error)
                time.sleep(3.2)
                self.assertFalse((root / "escaped.txt").exists(), "test descendant survived cancellation")
                self.assertIsNone(unrelated.poll(), "unrelated process was terminated")
            finally:
                unrelated.terminate()
                unrelated.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
