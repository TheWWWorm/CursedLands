"""Negative controls for gameplay collection; no game assets required."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import xml.etree.ElementTree as ET

from gameplay import assess, catalog, parse_summary, run_program, save_report
from run import HERE, PROFILE, REPO


SPEC = {
    "id": "quests/example", "category": "quests", "script": "tools/tests/example.gd",
    "campaign": "cursed_lands", "marker": "EXAMPLE", "min_checks": 3,
}


def capture(summary="EXAMPLE 3 checks 0 failures", **changes):
    start = dict(script="res://" + SPEC["script"], profile=PROFILE,
                 campaign="cursed_lands", seed=20261020)
    start.update(changes)
    return "GAMEPLAY_SUITE_START " + json.dumps(start) + "\n" + summary + "\n"


class GameplayResults(unittest.TestCase):
    def test_supported_summary_formats(self):
        for tail in ("3 checks 0 failures", "3 checks 0 failures; fast_us=12",
                     "3 checks 0 failures { \"route\": [] }",
                     "3 checks; failures=0", "checks=3 failures=0",
                     '{"checks":3,"failures":[]}', '{"checks":3,"failures":0}'):
            self.assertEqual(parse_summary("EXAMPLE " + tail, "EXAMPLE", 3),
                             {"checks": 3, "failures": 0})

    def test_success_requires_profile_and_completion(self):
        self.assertEqual(assess(capture(), SPEC, 0)["status"], "passed")
        self.assertEqual(assess("EXAMPLE 3 checks 0 failures", SPEC, 0)["status"], "error")
        self.assertEqual(assess(capture(""), SPEC, 0)["status"], "error")

    def test_wrong_campaign_cannot_pass(self):
        self.assertEqual(assess(capture(campaign="lost_in_astral"), SPEC, 0)["status"], "error")

    def test_unmuted_profile_cannot_pass(self):
        profile = dict(PROFILE, volume_voice=50)
        self.assertEqual(assess(capture(profile=profile), SPEC, 0)["status"], "error")

    def test_wrong_script_cannot_pass(self):
        self.assertEqual(assess(capture(script="res://tools/tests/other.gd"), SPEC, 0)["status"], "error")

    def test_duplicate_completion_is_error(self):
        self.assertEqual(assess(capture() + "EXAMPLE 3 checks 0 failures\n", SPEC, 0)["status"], "error")

    def test_undercoverage_and_zero_counts_are_errors(self):
        for tail in ("0 checks 0 failures", "2 checks 0 failures"):
            self.assertEqual(assess(capture("EXAMPLE " + tail), SPEC, 0)["status"], "error")

    def test_invalid_counts_are_errors(self):
        for tail in ('{"checks":true,"failures":0}', '{"checks":3,"failures":-1}',
                     '{"checks":3,"failures":4}', '{"checks":3,"failures":false}'):
            self.assertEqual(assess(capture("EXAMPLE " + tail), SPEC, 0)["status"], "error")

    def test_nonterminal_text_cannot_impersonate_summary(self):
        self.assertEqual(assess(capture("EXAMPLE 3 checks 0 still running"), SPEC, 0)["status"], "error")
        self.assertEqual(assess(capture("EXAMPLE checks=3 failures=0unfinished"), SPEC, 0)["status"], "error")

    def test_unrelated_helper_summary_does_not_replace_selected_one(self):
        self.assertEqual(assess(capture("HELPER 300 checks 0 failures"), SPEC, 0)["status"], "error")
        self.assertEqual(assess(capture() + "HELPER 300 checks 0 failures\n", SPEC, 0)["status"], "passed")

    def test_failures_report_even_on_zero_exit(self):
        for code in (0, 1):
            result = assess(capture("EXAMPLE 3 checks 1 failures\nFAIL boundary changed"), SPEC, code)
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["failure_messages"], ["FAIL boundary changed"])

    def test_runtime_errors_override_assertion_results(self):
        for summary in ("EXAMPLE 3 checks 0 failures", "EXAMPLE 3 checks 1 failures"):
            result = assess(capture(summary) + "SCRIPT ERROR: stale fixture\n", SPEC, 0)
            self.assertEqual(result["status"], "error")

    def test_timeout_or_crash_after_summary_cannot_pass(self):
        self.assertEqual(assess(capture(), SPEC, -9)["status"], "error")
        self.assertEqual(assess(capture(), SPEC, 0, "timeout")["status"], "error")
        self.assertEqual(assess(capture("EXAMPLE 3 checks 1 failures"), SPEC, -9, "timeout")["status"], "error")

    def test_nonzero_exit_without_failed_checks_is_error(self):
        self.assertEqual(assess(capture(), SPEC, 1)["status"], "error")

    def test_partial_report_and_junit_cannot_pass(self):
        row = dict(SPEC, **assess(capture(), SPEC, 0), log="example.log")
        report = {"tests": [row], "selected": [SPEC["id"], "quests/not_run"], "complete": False}
        with tempfile.TemporaryDirectory() as folder:
            save_report(report, Path(folder))
            self.assertEqual(report["status"], "incomplete")
            self.assertEqual(ET.parse(Path(folder) / "junit.xml").getroot().get("errors"), "1")

    def test_original_mismatch_is_visible_in_aggregate_junit(self):
        row = dict(SPEC, **assess(capture(), SPEC, 0), log="example.log")
        report = {"tests": [row], "selected": [SPEC["id"]], "complete": True,
                  "original": {"status": "mismatch", "counts": {"mismatches": 5}}}
        with tempfile.TemporaryDirectory() as folder:
            save_report(report, Path(folder))
            self.assertEqual(report["status"], "failed")
            self.assertEqual(ET.parse(Path(folder) / "junit.xml").getroot().get("failures"), "1")


class GameplayExecution(unittest.TestCase):
    def test_runtime_error_aborts_hung_program(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "run.log"
            start = time.monotonic()
            code, error = run_program(
                [sys.executable, "-u", "-c",
                 "import time; print('SCRIPT ERROR: injected broken script'); time.sleep(30)"],
                log, os.environ.copy(), 10)
            self.assertNotEqual(code, 0)
            self.assertIn("Runtime/script", error)
            self.assertLess(time.monotonic() - start, 5)
            self.assertIn("injected broken script", log.read_text())

    def test_timeout_terminates_owned_program(self):
        with tempfile.TemporaryDirectory() as folder:
            code, error = run_program([sys.executable, "-c", "import time; time.sleep(30)"],
                                      Path(folder) / "run.log", os.environ.copy(), 0.2)
            self.assertNotEqual(code, 0)
            self.assertIn("exceeded", error)

    def test_all_catalog_programs_and_markers_exist(self):
        rows = catalog()
        self.assertEqual({row["category"] for row in rows},
                         {"quests", "creatures", "animation", "effects", "stealth", "commands", "pathing"})
        for row in rows:
            script = REPO / row["script"]
            self.assertTrue(script.is_file(), row["id"])
            self.assertIn(row["marker"], script.read_text(), row["id"])

    def test_frozen_selection_replays_without_catalog_changes(self):
        rows = catalog()[:2]
        with tempfile.TemporaryDirectory() as folder:
            selection = Path(folder) / "selection.json"
            selection.write_text(json.dumps(rows))
            self.assertEqual(catalog(selection), rows)

    def test_output_and_asset_paths_cannot_escape_selection(self):
        for key, value in (("id", "../../outside"), ("script", "tools/tests/../../outside.gd"),
                           ("required_files", ["../../player.save"])):
            rows = copy.deepcopy(catalog()[:1])
            rows[0][key] = value
            with tempfile.TemporaryDirectory() as folder:
                selection = Path(folder) / "selection.json"
                selection.write_text(json.dumps(rows))
                with self.assertRaises(ValueError):
                    catalog(selection)

    def test_listing_requires_no_game_or_engine(self):
        result = subprocess.run([sys.executable, str(HERE / "gameplay.py"), "--list", "--category", "quests"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(line.startswith("quests/") for line in result.stdout.splitlines()))

    def test_existing_result_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            sentinel = Path(folder) / "report.json"
            sentinel.write_text("retained")
            result = subprocess.run([sys.executable, str(HERE / "gameplay.py"), "--out", folder,
                                     "--game-dir", folder, "--godot", "must-not-launch"],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(sentinel.read_text(), "retained")

    def test_output_inside_copied_test_tree_is_rejected_before_staging(self):
        with tempfile.TemporaryDirectory(dir=REPO / "tools/tests") as folder:
            out = Path(folder) / "must-not-exist"
            result = subprocess.run([sys.executable, str(HERE / "gameplay.py"), "--out", str(out),
                                     "--game-dir", folder, "--godot", "must-not-launch"],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertIn("source folders", result.stderr)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
