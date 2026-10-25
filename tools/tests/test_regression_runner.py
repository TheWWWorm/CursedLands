"""Make sure the release guard itself cannot turn missing/failed checks green."""
import importlib.util
import json
from pathlib import Path
import unittest

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


if __name__ == "__main__":
    unittest.main()
