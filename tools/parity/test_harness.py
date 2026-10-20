"""Negative controls for the comparator and runner; requires no original assets."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from cases import make_inputs
from compare import compare, digest, first_difference, validate_trace

HERE = Path(__file__).resolve().parent


def traces():
    inputs = make_inputs(fuzz=0, pattern="script_random/maximum_1.234567")
    steps = [{"step": i, "state": {"word": word, "value_bits": i + 100}}
             for i, word in enumerate(inputs["scenarios"][0]["inputs"]["words"])]
    original = {"schema": 1, "role": "original", "input_sha256": digest(inputs),
                "executable_sha256": inputs["reference"]["executable_sha256"],
                "scenarios": [{"id": inputs["scenarios"][0]["id"], "steps": steps}]}
    remake = copy.deepcopy(original)
    remake["role"] = "remake"
    remake.pop("executable_sha256")
    return inputs, original, remake


class ComparisonTests(unittest.TestCase):
    def test_matching_complete_captures(self):
        inputs, original, remake = traces()
        self.assertEqual(compare(inputs, original, remake)["counts"]["mismatches"], 0)

    def test_single_bit_error_reports_first_step_and_field(self):
        inputs, original, remake = traces()
        remake["scenarios"][0]["steps"][3]["state"]["value_bits"] ^= 1
        remake["scenarios"][0]["steps"][6]["state"]["value_bits"] ^= 8
        report = compare(inputs, original, remake)
        self.assertEqual(report["counts"]["mismatches"], 1)
        self.assertEqual(report["scenarios"][0]["first_divergence"]["field"], "$.steps[3].state.value_bits")

    def test_event_order_matters(self):
        inputs, original, remake = traces()
        steps = remake["scenarios"][0]["steps"]
        steps[0]["state"], steps[1]["state"] = steps[1]["state"], steps[0]["state"]
        self.assertEqual(compare(inputs, original, remake)["status"], "mismatch")

    def test_missing_case_is_error(self):
        inputs, original, remake = traces()
        remake["scenarios"].clear()
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)

    def test_duplicate_case_is_error(self):
        inputs, original, remake = traces()
        remake["scenarios"] *= 2
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)

    def test_both_truncated_captures_cannot_pass(self):
        inputs, original, remake = traces()
        original["scenarios"][0]["steps"].pop()
        remake["scenarios"][0]["steps"].pop()
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)

    def test_target_selection_requires_terminal_observation(self):
        inputs = make_inputs(fuzz=0, pattern="cast_rank/equal_distance_stable")
        trace = {"schema": 1, "role": "remake", "input_sha256": digest(inputs),
                 "scenarios": [{"id": inputs["scenarios"][0]["id"], "steps": [
                     {"step": 0, "state": {"selected": 2, "remaining": [0, 1]}}
                 ]}]}
        with self.assertRaisesRegex(ValueError, "truncated"):
            validate_trace(trace, inputs, "remake")

    def test_target_selection_cannot_continue_after_termination(self):
        inputs = make_inputs(fuzz=0, pattern="cast_rank/empty")
        trace = {"schema": 1, "role": "remake", "input_sha256": digest(inputs),
                 "scenarios": [{"id": inputs["scenarios"][0]["id"], "steps": [
                     {"step": i, "state": {"selected": -1, "remaining": []}}
                     for i in range(2)
                 ]}]}
        with self.assertRaisesRegex(ValueError, "overlong"):
            validate_trace(trace, inputs, "remake")

    def test_wrong_input_fingerprint_is_error(self):
        inputs, original, remake = traces()
        remake["input_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)

    def test_wrong_reference_binary_is_error(self):
        inputs, original, remake = traces()
        original["executable_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)

    def test_extra_state_field_is_not_ignored(self):
        inputs, original, remake = traces()
        remake["scenarios"][0]["steps"][0]["state"]["unreviewed"] = 1
        self.assertEqual(compare(inputs, original, remake)["status"], "mismatch")

    def test_boolean_is_not_integer(self):
        self.assertIsNotNone(first_difference({"alive": True}, {"alive": 1}))

    def test_integer_rng_bits_are_exact(self):
        self.assertIsNotNone(first_difference(0xfffffffe, 0xffffffff))

    def test_declared_float_tolerance_only(self):
        tolerance = {"fraction": {"abs": 1e-7}}
        self.assertIsNone(first_difference({"fraction": 0.5}, {"fraction": 0.50000005}, tolerance))
        self.assertIsNotNone(first_difference({"fraction": 0.5}, {"fraction": 0.50001}, tolerance))
        self.assertIsNotNone(first_difference({"hp": 0.5}, {"hp": 0.50000005}, tolerance))

    def test_nonfinite_observations_are_errors(self):
        inputs, original, remake = traces()
        remake["scenarios"][0]["steps"][0]["state"]["value_bits"] = float("nan")
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)

    def test_prefix_difference_precedes_length_difference(self):
        diff = first_difference([1, 2, 3], [1, 9])
        self.assertEqual(diff["field"], "$[1]")
        self.assertEqual(diff["reason"], "value")

    def test_seeded_inputs_reproduce_exactly(self):
        self.assertEqual(digest(make_inputs(30, 4)), digest(make_inputs(30, 4)))
        self.assertNotEqual(digest(make_inputs(30, 4)), digest(make_inputs(31, 4)))

    def test_generated_terrain_inputs_are_representable(self):
        from run import check_inputs
        check_inputs(make_inputs(20261020, 50))
        inputs = make_inputs(fuzz=0, pattern="cast_rank/height_matters")
        inputs["scenarios"][0]["inputs"]["units"][1]["pos"] = [1, 0, 999]
        with self.assertRaises(ValueError):
            check_inputs(inputs)

    def test_no_matching_scenarios_is_an_error(self):
        with self.assertRaises(ValueError):
            make_inputs(pattern="no-such-scenario")

    def test_bad_step_index_is_an_error(self):
        inputs, original, remake = traces()
        remake["scenarios"][0]["steps"][0]["step"] = True
        with self.assertRaises(ValueError):
            validate_trace(remake, inputs, "remake")


class RunnerTests(unittest.TestCase):
    def run_cli(self, *arguments):
        return subprocess.run([sys.executable, str(HERE / "run.py"), *map(str, arguments)],
                              capture_output=True, text=True, timeout=20)

    def test_list_does_not_require_emulator_or_game(self):
        result = self.run_cli("--list", "--fuzz", 0, "--case", "clock/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 5)

    def test_unsupported_binary_cannot_launch_engine(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root)
            game = folder / "original"
            game.mkdir()
            (game / "game.exe").write_bytes(b"not the qualified executable")
            out = folder / "result"
            result = self.run_cli("--game-dir", game, "--out", out, "--godot", "must-never-launch")
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(json.loads((out / "report.json").read_text())["status"], "error")
            self.assertFalse((out / "runtime").exists())

    def test_existing_results_are_immutable(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root)
            sentinel = folder / "report.json"
            sentinel.write_text("retained")
            result = self.run_cli("--game-dir", folder, "--out", folder, "--godot", "must-never-launch")
            self.assertEqual(result.returncode, 2)
            self.assertEqual(sentinel.read_text(), "retained")

    def test_output_inside_source_is_rejected_before_copy(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root)
            out = source / "recursive-results"
            result = self.run_cli("--game-dir", source, "--game-source", source,
                                  "--out", out, "--godot", "must-never-launch")
            self.assertEqual(result.returncode, 2)
            self.assertFalse(out.exists())

    def test_modified_tolerance_contract_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            inputs = make_inputs(fuzz=0, pattern="clock/")
            # Deep copy: avoid mutating the module's shared authored contract.
            inputs = copy.deepcopy(inputs)
            inputs["contracts"]["clock"]["tolerances"]["ticks"] = {"abs": 100}
            path = Path(root) / "inputs.json"
            path.write_text(json.dumps(inputs))
            result = self.run_cli("--replay-inputs", path, "--list")
            self.assertEqual(result.returncode, 2)

    def test_profile_never_reads_player_settings(self):
        from run import isolated_environment, PROFILE
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root)
            env = isolated_environment(folder / "isolated", "Cursed Lands", folder / "owned")
            settings = Path(env["XDG_DATA_HOME"]) / "godot/app_userdata/Cursed Lands/settings.cfg"
            text = settings.read_text()
            for key, value in PROFILE.items():
                self.assertIn(f"{key}={value}\n", text)
            self.assertEqual(env["XDG_CONFIG_HOME"], str(folder / "isolated/config"))


if __name__ == "__main__":
    unittest.main()
