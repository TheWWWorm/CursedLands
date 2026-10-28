"""Make sure the release guard itself cannot turn missing/failed checks green."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner", Path(__file__).parents[1] / "check_regressions.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class VerdictTests(unittest.TestCase):
    case = {"summary": "PROBE", "min_checks": 3, "mode": "headless"}

    def test_exported_runtime_and_required_renderer(self):
        case = {"mode": "rendered", "rendering_method": "forward_plus"}
        command = runner.engine_arguments("/qualified/game", case, packaged=True)
        self.assertNotIn("--path", command)
        self.assertEqual(command[command.index("--rendering-method") + 1], "forward_plus")
        self.assertEqual(command[command.index("--display-driver") + 1], "x11")
        self.assertEqual(command[command.index("--audio-driver") + 1], "Dummy")
        self.assertIn("--path", runner.engine_arguments("godot", self.case))

    def test_profile_isolation_covers_windows_user_data(self):
        # Windows Godot ignores XDG; without APPDATA a case used the player's profile.
        profile = Path("/evidence/case")
        env = runner.isolation_environment(profile)
        for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
            self.assertTrue(Path(env[key]).is_relative_to(profile), key)
        windows_settings = Path(env["APPDATA"]) / "Godot/app_userdata/Cursed Lands/settings.cfg"
        self.assertEqual(str(windows_settings).lower(), str(runner.profile_settings(profile)).lower())

    def test_staging_preserves_utf8_scripts(self):
        with tempfile.TemporaryDirectory() as directory:
            staged = runner.stage_tests(Path(directory))
            for script in staged.rglob("*.gd"):
                text = script.read_text(encoding="utf-8")
                self.assertNotIn("res://tools/", text, script.name)

    def test_headless_uses_production_worker_render_thread_mode(self):
        command = runner.engine_arguments("/qualified/game", self.case, packaged=True)
        self.assertIn("--headless", command)
        self.assertIn("--render-thread", command)
        self.assertEqual(command[command.index("--render-thread") + 1], "safe")
        rendered = runner.engine_arguments("/qualified/game", {"mode": "rendered"}, packaged=True)
        self.assertNotIn("--render-thread", rendered)

    def test_registered_pt_water_executes_with_hardware_ray_tracing(self):
        cases = {case["id"]: case for case in json.loads(runner.MANIFEST.read_text())["cases"]}
        for name in ("path_trace_water", "path_trace_water_live"):
            with self.subTest(case=name):
                command = runner.engine_arguments("/qualified/game", cases[name], packaged=True)
                self.assertEqual(command[command.index("--rendering-method") + 1], "forward_plus",
                                 "PT water transport requires the hardware ray-tracing renderer")

    def verdict(self, text, code=0, **overrides):
        return runner.verdict(text, {**self.case, **overrides}, code)

    def test_success_formats(self):
        for line in ['PROBE 3 checks 0 failures', 'PROBE {"checks":3,"failures":[]}',
                     'PROBE checks=3 failures=0']:
            self.assertTrue(self.verdict(line)["passed"])

    def test_success_exit_without_assertions_fails(self):
        for line in ["", "OTHER 50 checks 0 failures", "PROBE 0 checks 0 failures"]:
            self.assertFalse(self.verdict(line)["passed"])

    def test_reported_failures_fail(self):
        for line in ['PROBE 3 checks 1 failures', 'PROBE {"checks":3,"failures":["bad"]}']:
            self.assertFalse(self.verdict(line)["passed"])

    def test_duplicate_result_cannot_hide_failure(self):
        self.assertFalse(self.verdict("PROBE 3 checks 1 failures\nPROBE 3 checks 0 failures")["passed"])

    def test_wrong_campaign_and_missing_start_cannot_pass(self):
        expected = {"campaign": "cursed_lands", "display": "headless"}
        success = "PROBE 3 checks 0 failures"
        self.assertFalse(self.verdict(success, expected_start=expected)["passed"])
        for campaign in ("cursed_lands", "lost_in_astral"):
            start = "GAMEPLAY_SUITE_START " + json.dumps({**expected, "campaign": campaign})
            self.assertEqual(self.verdict(start + "\n" + success, expected_start=expected)["passed"],
                             campaign == "cursed_lands")

    def test_exit_and_late_errors_fail(self):
        success = "PROBE 3 checks 0 failures"
        self.assertFalse(self.verdict(success, 1)["passed"])
        for error in ["SCRIPT ERROR: invalid instance", "ERROR: descriptor allocation", "FAIL target position"]:
            self.assertFalse(self.verdict(success + "\n" + error)["passed"])

    def test_virtual_monitor_exception_is_narrow_and_retained(self):
        message = 'ERROR: Parameter "monitors" is null.\n   at: screen_get_refresh_rate (platform/linuxbsd/x11/display_server_x11.cpp:1858)'
        result = self.verdict(message + "\nPROBE 3 checks 0 failures", mode="rendered")
        self.assertTrue(result["passed"])
        self.assertEqual(len(result["infrastructure_diagnostics"]), 1)
        self.assertFalse(self.verdict(message + "\nPROBE 3 checks 0 failures")["passed"])
        self.assertFalse(self.verdict(message.replace("screen_get_refresh_rate", "anything_else") +
                                      "\nPROBE 3 checks 0 failures", mode="rendered")["passed"])


class PackagedFixtureTests(unittest.TestCase):
    def test_packaged_run_keeps_relative_helpers_and_fixture_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            scripts = repo / "tools/tests"
            benchmarks = repo / "tools/benchmarks"
            (scripts / "fixtures").mkdir(parents=True)
            benchmarks.mkdir()
            (repo / "game").mkdir()
            (repo / "game/project.godot").write_text('[application]\nconfig/version="1.0.0"\n')
            (scripts / "probe.gd").write_text('extends "../benchmarks/base.gd"\n')
            (benchmarks / "base.gd").write_text(
                'extends Node\nconst Helper = preload("res://tools/tests/helper.gd")\n')
            (scripts / "helper.gd").write_text('extends "res://src/game/session.gd"\n')
            payload = b'{"cases":[1,2,3]}\n'
            (scripts / "fixtures/original.json").write_bytes(payload)
            manifest = repo / "tools/regressions.json"
            manifest.write_text(json.dumps({"cases": [{
                "id": "probe", "mode": "headless", "data": "base",
                "script": "tools/tests/probe.gd", "summary": "PROBE",
                "min_checks": 3, "contract": "staged dependencies",
            }]}))
            engine = root / "game.x86_64"
            engine.write_bytes(b"engine")
            engine.with_suffix(".pck").write_bytes(b"pack")

            def run(command, **kwargs):
                script = Path(next(arg.split("=", 1)[1] for arg in command
                                   if arg.startswith("--suite-script=")))
                base = script.parent / "../benchmarks/base.gd"
                self.assertTrue(base.is_file(), "relative benchmark superclass was not staged")
                self.assertIn((script.parent / "helper.gd").as_posix(), base.read_text())
                self.assertNotIn("\\", base.read_text(), "GDScript imports must not contain Windows escape sequences")
                self.assertNotIn("res://tools/", base.read_text())
                self.assertEqual((script.parent / "fixtures/original.json").read_bytes(), payload)
                self.assertIn("res://src/game/session.gd", (script.parent / "helper.gd").read_text())
                expected = {"campaign": "cursed_lands", "display": "headless",
                            "script": str(script), "profile": {
                                "confine_mouse": 0, "show_fps": 1, "volume_sfx": 0,
                                "volume_stream": 0, "volume_voice": 0}}
                kwargs["stdout"].write("GAMEPLAY_SUITE_START " + json.dumps(expected) +
                                       "\nPROBE 3 checks 0 failures\n")
                return subprocess.CompletedProcess(command, 0)

            args = ["check_regressions.py", "--packaged", "--engine", str(engine),
                    "--base-data", str(root), "--output", str(root / "results")]
            with patch.object(runner, "REPO", repo), patch.object(runner, "MANIFEST", manifest), \
                    patch.object(runner.sys, "argv", args), \
                    patch.object(runner.shutil, "which", side_effect=lambda value: value), \
                    patch.object(runner.subprocess, "check_output", return_value="source\n"), \
                    patch.object(runner.subprocess, "run", side_effect=run):
                self.assertEqual(runner.main(), 0)
            result = json.loads((root / "results/results.json").read_text())
            self.assertTrue(result["passed"])


class SourceFixtureTests(unittest.TestCase):
    def test_source_run_stages_res_tools_imports(self):
        """Without --packaged the engine runs from game/, where res://tools/ does
        not exist; the suite script must still be a staged copy whose imports resolve."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            scripts = repo / "tools/tests"
            (repo / "tools/benchmarks").mkdir(parents=True)
            scripts.mkdir()
            (repo / "game").mkdir()
            (repo / "game/project.godot").write_text('[application]\nconfig/version="1.0.0"\n')
            (scripts / "probe.gd").write_text('extends "res://tools/tests/base.gd"\n')
            (scripts / "base.gd").write_text('extends Node\n')
            manifest = repo / "tools/regressions.json"
            manifest.write_text(json.dumps({"cases": [{
                "id": "probe", "mode": "headless", "data": "base",
                "script": "tools/tests/probe.gd", "summary": "PROBE",
                "min_checks": 1, "contract": "staged base class",
            }]}))
            engine = root / "godot"
            engine.write_bytes(b"engine")
            seen = {}

            def run(command, **kwargs):
                script = Path(next(arg.split("=", 1)[1] for arg in command
                                   if arg.startswith("--suite-script=")))
                suite_root = Path(next(arg.split("=", 1)[1] for arg in command
                                       if arg.startswith("--suite-script-root=")))
                seen["script"], seen["root"] = script, suite_root
                self.assertEqual(script.parent, suite_root)
                self.assertNotEqual(script, repo / "tools/tests/probe.gd", "source run must not use the repo copy")
                self.assertTrue((root / "results").resolve() in script.resolve().parents)
                text = script.read_text()
                self.assertNotIn("res://tools/", text)
                self.assertIn((suite_root / "base.gd").as_posix(), text)
                self.assertTrue((suite_root / "base.gd").is_file())
                self.assertIn("--path", command)
                expected = {"campaign": "cursed_lands", "display": "headless",
                            "script": str(script), "profile": {
                                "confine_mouse": 0, "show_fps": 1, "volume_sfx": 0,
                                "volume_stream": 0, "volume_voice": 0}}
                kwargs["stdout"].write("GAMEPLAY_SUITE_START " + json.dumps(expected) +
                                       "\nPROBE 1 checks 0 failures\n")
                return subprocess.CompletedProcess(command, 0)

            args = ["check_regressions.py", "--engine", str(engine),
                    "--base-data", str(root), "--output", str(root / "results")]
            with patch.object(runner, "REPO", repo), patch.object(runner, "MANIFEST", manifest), \
                    patch.object(runner.sys, "argv", args), \
                    patch.object(runner.shutil, "which", side_effect=lambda value: value), \
                    patch.object(runner.subprocess, "check_output", return_value="source\n"), \
                    patch.object(runner.subprocess, "run", side_effect=run):
                self.assertEqual(runner.main(), 0)
            self.assertIn("script", seen, "the engine was never started")
            result = json.loads((root / "results/results.json").read_text())
            self.assertTrue(result["passed"])
            self.assertEqual(result["cases"][0]["script"], "tools/tests/probe.gd",
                             "results keep the repository path, not the staged copy")


if __name__ == "__main__":
    unittest.main()
