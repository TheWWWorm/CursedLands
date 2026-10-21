"""Input and observation checks for the quest_scheduler family (no game data)."""
import copy
import unittest
from pathlib import Path

import cases_ext_quest_scheduler as family
from cases import make_inputs
from compare import digest, first_difference, validate_trace


def state(**changes):
    row = {"trace": [], "globals": {}, "scripts": {}, "bodies": {}, "fatal": ""}
    row.update(changes)
    return row


class QuestSchedulerInputsTest(unittest.TestCase):
    def test_scenarios_are_deterministic_and_fuzz_sized(self):
        self.assertEqual(family.scenarios(7, 3), family.scenarios(7, 3))
        self.assertNotEqual(family.scenarios(7, 3), family.scenarios(8, 3))
        fuzz = lambda n: [r for r in family.scenarios(7, n) if "/fuzz_" in r["id"]]
        self.assertEqual(len(fuzz(0)), 0)
        self.assertEqual(len(fuzz(5)), 10)

    def test_inputs_reference_declared_names(self):
        rows = family.scenarios()
        self.assertEqual(len({r["id"] for r in rows}), len(rows))

        def walk(value, names, scripts):
            if isinstance(value, list):
                for item in value:
                    walk(item, names, scripts)
            elif isinstance(value, dict):
                if "global" in value:
                    self.assertIn(value["global"], names)
                if "set" in value:
                    self.assertIn(value["set"], names)
                if "script" in value and isinstance(value["script"], str):
                    self.assertIn(value["script"], scripts)
                for item in value.values():
                    walk(item, names, scripts)

        for row in rows:
            inputs = row["inputs"]
            names = set(inputs["globals"])
            scripts = {s["name"] for s in inputs["scripts"]}
            self.assertEqual(len(scripts), len(inputs["scripts"]))
            for script in inputs["scripts"]:
                walk(script["blocks"], names, scripts)
            walk(inputs["world"], names, scripts)
            self.assertGreater(len(inputs["ticks"]), 0)
            for tick in inputs["ticks"]:
                self.assertLessEqual(set(tick), {"globals", "briefing"})
                self.assertLessEqual(set(tick.get("globals", {})), names)
                if "briefing" in tick:
                    self.assertIn(tick["briefing"]["script"], scripts)
                    self.assertIn(tick["briefing"]["flag"], names)

    def test_inputs_hold_no_expected_values(self):
        rows = family.scenarios(1, 0)
        self.assertTrue(any(s["name"] == "#OnBriefingComplete" for r in rows for s in r["inputs"]["scripts"]))
        for row in rows:
            self.assertEqual(set(row["inputs"]), {"globals", "scripts", "world", "ticks"})

    def test_contract_only_for_qualified_campaign(self):
        self.assertIn(family.KIND, family.contracts("original"))
        self.assertEqual(family.contracts("lost_in_astral"), {})
        stubs = family.contracts("original")[family.KIND]["stubs"]
        self.assertTrue(any("0x480080" in s for s in stubs))

    def test_remake_script_declares_kind(self):
        text = Path(__file__).with_name("remake_ext_quest_scheduler.gd").read_text()
        self.assertIn('"quest_scheduler"', text)
        self.assertIn("func capture(", text)
        self.assertIn("vm.tick(ScriptVM.SLEEP_UNIT)", text)

    def test_validator_rejects_malformed_states(self):
        inputs = make_inputs(pattern="quest_scheduler/blocks_without_kill")
        case = inputs["scenarios"][0]
        names = sorted(case["inputs"]["globals"])
        good = state(globals={n: 0 for n in names})
        bad = [
            dict(good, extra=1),
            state(globals={}),
            state(globals={n: -1 for n in names}),
            dict(good, fatal=None),
            dict(good, scripts={"Nope": 1}),
            dict(good, scripts={"#OnBriefingComplete": 0}),
            dict(good, bodies={"#OnBriefingComplete.9": 1}),
            dict(good, trace=["poll:World"]),
            dict(good, trace=["c:Nope.0.0"]),
        ]
        steps = len(case["inputs"]["ticks"])

        def trace(row):
            return {"schema": 1, "role": "remake", "input_sha256": digest(inputs),
                    "scenarios": [{"id": case["id"], "steps": [{"step": i, "state": row} for i in range(steps)]}]}

        validate_trace(trace(good), inputs, "remake")
        for row in bad:
            with self.subTest(state=row), self.assertRaises(ValueError):
                validate_trace(trace(row), inputs, "remake")

    def test_one_sided_mutation_is_reported(self):
        native = [state(trace=["c:S.0.0", "fire:S.0"], globals={"x": 1065353216}, scripts={"S": 1})]
        remake = copy.deepcopy(native)
        self.assertIsNone(first_difference(native, remake))
        remake[0]["trace"] = ["c:S.0.0", "fire:S.0", "c:S.1.0"]
        self.assertIsNotNone(first_difference(native, remake))
        remake = copy.deepcopy(native)
        remake[0]["fatal"] = "KillScript command not allowed here"
        self.assertIsNotNone(first_difference(native, remake))


if __name__ == "__main__":
    unittest.main()
