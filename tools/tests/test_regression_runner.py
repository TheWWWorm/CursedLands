"""Make sure the release guard itself cannot turn missing/failed checks green."""
import importlib.util
import os
import sys
import time
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner", Path(__file__).parents[1] / "check_regressions.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def catalog_entry(name, description, min_checks=1, **extra):
    """A catalog entry registered for the focused runner as `name`."""
    return {"id": "focused/" + name, "category": "focused", "script": f"tools/tests/{name}.gd",
            "marker": name.upper(), "min_checks": min_checks, "quick": False, "description": description,
            "kind": "remake_regression", "timeout": 60, "args": [], "campaign": "cursed_lands",
            "required_files": [], "display": "headless", "focused": name, **extra}


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
        cases = {case["id"]: case for case in runner.focused_cases(runner.CATALOG)}
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
            manifest = repo / "tools/parity/gameplay_catalog.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"schema": 1, "tests": [catalog_entry(
                "probe", "staged dependencies", min_checks=3)]}))
            engine = root / "game.x86_64"
            engine.write_bytes(b"engine")
            engine.with_suffix(".pck").write_bytes(b"pack")

            def run(command, log, env, timeout, *extra, **options):
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
                Path(log).write_text("GAMEPLAY_SUITE_START " + json.dumps(expected) +
                                     "\nPROBE 3 checks 0 failures\n")
                return 0, None

            args = ["check_regressions.py", "--packaged", "--engine", str(engine),
                    "--base-data", str(root), "--output", str(root / "results")]
            with patch.object(runner, "REPO", repo), patch.object(runner, "CATALOG", manifest), \
                    patch.object(runner.sys, "argv", args), \
                    patch.object(runner.shutil, "which", side_effect=lambda value: value), \
                    patch.object(runner.subprocess, "check_output", return_value="source\n"), \
                    patch.object(runner, "run_program", side_effect=run):
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
            manifest = repo / "tools/parity/gameplay_catalog.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"schema": 1, "tests": [catalog_entry(
                "probe", "staged base class", min_checks=1)]}))
            engine = root / "godot"
            engine.write_bytes(b"engine")
            seen = {}

            def run(command, log, env, timeout, *extra, **options):
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
                Path(log).write_text("GAMEPLAY_SUITE_START " + json.dumps(expected) +
                                     "\nPROBE 1 checks 0 failures\n")
                return 0, None

            args = ["check_regressions.py", "--engine", str(engine),
                    "--base-data", str(root), "--output", str(root / "results")]
            with patch.object(runner, "REPO", repo), patch.object(runner, "CATALOG", manifest), \
                    patch.object(runner.sys, "argv", args), \
                    patch.object(runner.shutil, "which", side_effect=lambda value: value), \
                    patch.object(runner.subprocess, "check_output", return_value="source\n"), \
                    patch.object(runner, "run_program", side_effect=run):
                self.assertEqual(runner.main(), 0)
            self.assertIn("script", seen, "the engine was never started")
            result = json.loads((root / "results/results.json").read_text())
            self.assertTrue(result["passed"])
            self.assertEqual(result["cases"][0]["script"], "tools/tests/probe.gd",
                             "results keep the repository path, not the staged copy")


if __name__ == "__main__":
    unittest.main()


class SharedProcessTests(unittest.TestCase):
    """Both runners take their process rules from tools/parity/process.py."""

    def test_both_runners_share_process_control(self):
        import gameplay
        import process
        self.assertIs(runner.run_program, process.run_program)
        self.assertIs(gameplay.run_program, process.run_program)
        self.assertIs(runner.parse_summary, gameplay.parse_summary)
        self.assertIs(runner.DIAGNOSTIC, gameplay.DIAGNOSTIC)
        focused = runner.engine_arguments("/qualified/game", {"mode": "rendered"}, packaged=True)
        catalog = gameplay.engine_argv("/qualified/game", "/runtime", "rendered")
        self.assertEqual(focused[focused.index("--resolution") + 1], catalog[catalog.index("--resolution") + 1],
                         "the two runners must open the same rendered window")
        self.assertEqual(focused[focused.index("--resolution") + 1], process.RENDERED_RESOLUTION)

    def test_case_may_declare_its_own_resolution(self):
        command = runner.engine_arguments("/qualified/game", {"mode": "rendered", "resolution": "1920x1080"}, packaged=True)
        self.assertEqual(command[command.index("--resolution") + 1], "1920x1080")

    def test_script_error_stops_the_process_early(self):
        import process
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "run.log"
            script = "import sys,time\nprint('SCRIPT ERROR: boom', flush=True)\ntime.sleep(30)\n"
            started = time.monotonic()
            code, error = process.run_program([sys.executable, "-c", script], log, dict(os.environ), timeout=20)
            self.assertLess(time.monotonic() - started, 10, "a diagnostic must end the process at once")
            self.assertIn("Runtime/script error", error)
            self.assertNotEqual(code, 0)

    def test_tolerated_diagnostic_does_not_stop_the_process(self):
        """The virtual-monitor refresh-rate error ends no rendered test; the verdict judges it with its context."""
        import process
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "run.log"
            script = ("import sys,time\nprint('ERROR: Parameter \"monitors\" is null.', flush=True)\n"
                      "print('   at: screen_get_refresh_rate (platform/linuxbsd/x11/display_server_x11.cpp:1858)', flush=True)\n"
                      "time.sleep(1.5)\nprint('DONE 3 checks 0 failures')\n")
            code, error = process.run_program([sys.executable, "-c", script], log, dict(os.environ), timeout=20,
                                              tolerate=runner.INFRASTRUCTURE)
            self.assertIsNone(error)
            self.assertEqual(code, 0)
            self.assertIn("DONE 3 checks", log.read_text())
            # Without the tolerance the same line ends the process, as any diagnostic does.
            code, error = process.run_program([sys.executable, "-c", script.replace("1.5", "30")], log,
                                              dict(os.environ), timeout=20)
            self.assertIn("Runtime/script error", error)

    def test_only_complete_lines_are_judged(self):
        """A tolerated line written in two pieces must not be mistaken for a failure."""
        import process
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "run.log"
            script = ("import sys,time\nsys.stdout.write('ERROR: Parameter'); sys.stdout.flush()\ntime.sleep(0.6)\n"
                      "sys.stdout.write(' \"monitors\" is null.\\n'); sys.stdout.flush()\ntime.sleep(0.6)\n")
            code, error = process.run_program([sys.executable, "-c", script], log, dict(os.environ), timeout=20,
                                              tolerate=runner.INFRASTRUCTURE)
            self.assertIsNone(error)
            self.assertEqual(process.diagnostic_in('x\nSCRIPT ERROR: boom\n', runner.INFRASTRUCTURE), "SCRIPT ERROR: boom")
            self.assertIsNone(process.diagnostic_in('ERROR: Parameter "monitors" is null.\n', runner.INFRASTRUCTURE))

    def test_timeout_stops_the_process(self):
        import process
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "run.log"
            code, error = process.run_program([sys.executable, "-c", "import time; time.sleep(30)"], log,
                                              dict(os.environ), timeout=1)
            self.assertIn("exceeded 1 seconds", error)

    def test_mirror_file_is_scanned_for_diagnostics(self):
        import process
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "run.log"
            remote = Path(directory) / "stdout.log"
            script = ("import time,sys\nprint('GPU Lab job: abc', flush=True)\ntime.sleep(0.5)\n"
                      f"open({str(remote)!r},'w').write('ERROR: remote failure\\n')\ntime.sleep(30)\n")
            started = time.monotonic()
            code, error = process.run_program([sys.executable, "-c", script], log, dict(os.environ), timeout=20,
                                              mirror=lambda text: remote if "GPU Lab job: abc" in text else None)
            self.assertLess(time.monotonic() - started, 10)
            self.assertIn("Runtime/script error", error)

    def test_rendered_verdict_reports_runner_error(self):
        case = {"mode": "rendered", "summary": "PROBE", "min_checks": 1}
        result = runner.verdict("PROBE 2 checks 0 failures\n", case, 130, "Test exceeded 5 seconds")
        self.assertFalse(result["passed"])
        self.assertIn("Test exceeded 5 seconds", result["errors"])

    def test_focused_cases_come_from_the_catalog(self):
        """The folded registry: a catalog entry with `focused` is a case of
        this runner under that ID, with the catalog's marker, display,
        campaign, arguments and threshold; entries without it are not."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            path.write_text(json.dumps({"schema": 1, "tests": [
                catalog_entry("probe", "a focused case", min_checks=4, display="rendered",
                              rendering_method="forward_plus", args=["--texts={texts_ru}"], texts=["ru"],
                              campaign="lost_in_astral", issues=[7]),
                {**catalog_entry("other", "catalog only"), "id": "quests/other", "category": "quests"},
            ]}))
            for row in json.loads(path.read_text())["tests"]:
                row.pop("focused", None) if row["id"] == "quests/other" else None
            data = json.loads(path.read_text())
            data["tests"][1].pop("focused")
            path.write_text(json.dumps(data))
            cases = runner.focused_cases(path)
        self.assertEqual([case["id"] for case in cases], ["probe"])
        case = cases[0]
        self.assertEqual((case["catalog_id"], case["summary"], case["mode"], case["campaign"], case["data"]),
                         ("focused/probe", "PROBE", "rendered", "lost_in_astral", "astral"))
        self.assertEqual((case["min_checks"], case["rendering_method"], case["issues"], case["args"]),
                         (4, "forward_plus", [7], ["--texts={texts_ru}"]))
        self.assertEqual(sorted(case["needs"]), ["lost_in_astral", "texts_ru"])

    def test_focused_ids_must_not_collide_with_entry_names(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            path.write_text(json.dumps({"schema": 1, "tests": [
                {**catalog_entry("probe", "x"), "id": "quests/probe", "category": "quests", "focused": "shadow"},
                {**catalog_entry("shadow", "y"), "id": "quests/shadow", "category": "quests"},
            ]}))
            with self.assertRaises(ValueError):
                runner.focused_cases(path)

    def test_focused_runner_offers_parallel_jobs(self):
        self.assertEqual(runner.jobs_argument("auto"), "auto")
        self.assertEqual(runner.jobs_argument("3"), 3)
