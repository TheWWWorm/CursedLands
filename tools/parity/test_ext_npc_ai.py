"""npc_ai extension family: input shapes, validators and mismatch detection.

The optional native test runs only when PARITY_GAME_EXE names the pinned
original executable; everything else needs no original assets.
"""
import copy
import json
import math
import os
from pathlib import Path
import unittest

import cases_ext_npc_ai as cases
import extensions
from cases import make_inputs
from compare import compare, digest

KINDS = ("npc_ai_fear", "npc_ai_suspicion", "npc_ai_target_score", "npc_ai_motivation")
GOOD = {
    "npc_ai_fear": {"decision_priority": 166, "j_bits": 0x40400000, "kept_danger": False, "level": 998,
                 "delta": -2, "point_bits": [0x41400000, 0x41400000], "r_bits": 0x41200000},
    "npc_ai_suspicion": {"units": [{"level": 897, "delta": -3, "point_bits": [0x40400000, 0x40800000],
                                 "pending": [25]}]},
    "npc_ai_target_score": {"score_bits": 0xc1e8cccd},
    "npc_ai_motivation": {"motivation": "fear"},
}


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    if isinstance(value, list):
        return all(finite(v) for v in value)
    return True


class NpcAiInputTests(unittest.TestCase):
    def test_kinds_are_registered_with_contract_capture_and_remake(self):
        declared = cases.contracts("original")
        self.assertEqual(set(declared), set(KINDS))
        from native import CAPTURES
        remake = (Path(__file__).resolve().parent / "remake_ext_npc_ai.gd").read_text()
        for kind in KINDS:
            with self.subTest(kind=kind):
                self.assertIn(kind, CAPTURES)
                self.assertIn(f'"{kind}"', remake)
                self.assertIn(kind, extensions.step_counts())
                contract = declared[kind]
                self.assertTrue(contract["entry"] and contract["stubs"] and contract["limits"])
                self.assertEqual(contract["tolerances"], {})
        self.assertEqual(cases.contracts("lost_in_astral"), {})

    def test_ids_unique_and_inputs_finite_json(self):
        rows = cases.scenarios(20261020, 12)
        ids = [r["id"] for r in rows]
        self.assertEqual(len(ids), len(set(ids)))
        for row in rows:
            self.assertIn(row["kind"], KINDS)
            self.assertTrue(row["id"].startswith(row["kind"] + "/"))
            self.assertTrue(finite(row["inputs"]), row["id"])
            json.dumps(row["inputs"], allow_nan=False)

    def test_seeded_fuzz_is_reproducible_and_sized_by_fuzz(self):
        self.assertEqual(cases.scenarios(7, 3), cases.scenarios(7, 3))
        self.assertNotEqual(cases.scenarios(7, 3), cases.scenarios(8, 3))
        for fuzz in (0, 3):
            rows = cases.scenarios(20261020, fuzz)
            for kind in KINDS:
                seeded = [r for r in rows if r["kind"] == kind and "/seeded_" in r["id"]]
                self.assertEqual(len(seeded), fuzz, kind)

    def test_step_inputs_are_nonempty_and_indices_valid(self):
        counts = extensions.step_counts()
        for row in cases.scenarios(20261020, 12):
            data, kind = row["inputs"], row["kind"]
            steps = data[counts[kind]]
            self.assertTrue(steps, row["id"])
            n = len(data["units"])
            for step in steps:
                for event in step.get("events", []):
                    self.assertIn(event.get("when", "after"), ("before", "after"))
                    for key in ("unit", "by"):
                        if event.get(key) is not None:
                            self.assertLess(event[key], n, row["id"])
                for index in step.get("moves", {}):
                    self.assertLess(int(index), n, row["id"])
                if kind == "npc_ai_target_score":
                    for key in ("caster", "candidate"):
                        self.assertLess(step[key], n)
                    self.assertIn(step["candidate"], step["list"])
                    self.assertTrue(all(0 <= i < n for i in step["list"]))
                    self.assertIn(step["option"]["type"], range(8))
                    self.assertFalse("dur" in step["option"] and "effect" in step["option"])

    def test_grid_units_stay_inside_the_fixture_cell(self):
        # The help-call query 5c0bd0 (hits and help events) sees one 16 m
        # unit-grid cell.
        for row in cases.scenarios(20261020, 12):
            if row["kind"] == "npc_ai_target_score":
                continue
            events = [e for step in row["inputs"]["ticks"] for e in step.get("events", [])]
            if not any(e["kind"] in ("hit", "help") for e in events):
                continue
            positions = [u["pos"] for u in row["inputs"]["units"]]
            for step in row["inputs"]["ticks"]:
                positions += list(step.get("moves", {}).values())
            for pos in positions:
                self.assertTrue(0 <= pos[0] < 16 and 0 <= pos[1] < 16, row["id"])

    def test_seeded_noticed_units_are_alive(self):
        # The original perception scan drops dead units from the noticed
        # list; only authored cases put one there, for the dead test of the
        # noticed-hostile flag itself.
        for row in cases.scenarios(20261020, 12):
            if "/seeded_" not in row["id"]:
                continue
            for unit in row["inputs"]["units"]:
                self.assertFalse(unit.get("noticed") and unit.get("dead"), row["id"])

    def test_motivation_sets_cover_the_aggression_modes(self):
        import native_ext_npc_ai as native
        for row in cases.scenarios(20261020, 12):
            if row["kind"] == "npc_ai_motivation":
                self.assertIn(row["inputs"]["aggression"], native.MOTIVATION_SETS)


class NpcAiValidatorTests(unittest.TestCase):
    def case(self, kind):
        return {"id": kind + "/x", "kind": kind}

    def test_good_states_validate(self):
        for kind, state in GOOD.items():
            cases.validate(self.case(kind), [{"step": 0, "state": state}], "original")

    def assert_rejected(self, kind, state):
        with self.assertRaises(ValueError):
            cases.validate(self.case(kind), [{"step": 0, "state": state}], "remake")

    def test_malformed_states_are_rejected(self):
        for kind, good in GOOD.items():
            with self.subTest(kind=kind):
                extra = dict(good, extra=1)
                self.assert_rejected(kind, extra)
                for key in good:
                    missing = {k: v for k, v in good.items() if k != key}
                    self.assert_rejected(kind, missing)
        self.assert_rejected("npc_ai_fear", dict(GOOD["npc_ai_fear"], kept_danger=0))
        self.assert_rejected("npc_ai_fear", dict(GOOD["npc_ai_fear"], decision_priority=True))
        self.assert_rejected("npc_ai_fear", dict(GOOD["npc_ai_fear"], level=998.0))
        self.assert_rejected("npc_ai_fear", dict(GOOD["npc_ai_fear"], point_bits=[1]))
        self.assert_rejected("npc_ai_fear", dict(GOOD["npc_ai_fear"], r_bits=-1))
        self.assert_rejected("npc_ai_fear", dict(GOOD["npc_ai_fear"], j_bits=1 << 32))
        unit = GOOD["npc_ai_suspicion"]["units"][0]
        self.assert_rejected("npc_ai_suspicion", {"units": [dict(unit, pending=None)]})
        self.assert_rejected("npc_ai_suspicion", {"units": [dict(unit, pending=[25.0])]})
        self.assert_rejected("npc_ai_suspicion", {"units": [dict(unit, level=True)]})
        self.assert_rejected("npc_ai_suspicion", {"units": [{k: v for k, v in unit.items() if k != "delta"}]})
        self.assert_rejected("npc_ai_suspicion", {"units": "none"})
        self.assert_rejected("npc_ai_target_score", {"score_bits": -1.5})
        self.assert_rejected("npc_ai_target_score", {"score_bits": 1 << 32})
        self.assert_rejected("npc_ai_motivation", {"motivation": "Fear"})
        self.assert_rejected("npc_ai_motivation", {"motivation": 7})

    def test_unknown_kind_is_rejected(self):
        self.assert_rejected("npc_unknown", {"motivation": "fear"})


def traces(pattern, state_of):
    inputs = make_inputs(fuzz=0, pattern=pattern)
    counts = extensions.step_counts()
    scenarios = []
    for case in inputs["scenarios"]:
        steps = [{"step": i, "state": copy.deepcopy(state_of(case["kind"], i))}
                 for i in range(len(case["inputs"][counts[case["kind"]]]))]
        scenarios.append({"id": case["id"], "steps": steps})
    original = {"schema": 1, "role": "original", "input_sha256": digest(inputs),
                "executable_sha256": inputs["reference"]["executable_sha256"], "scenarios": scenarios}
    remake = copy.deepcopy(original)
    remake["role"] = "remake"
    remake.pop("executable_sha256")
    return inputs, original, remake


class NpcAiMismatchTests(unittest.TestCase):
    def test_identical_captures_match(self):
        inputs, original, remake = traces("npc_ai_", lambda kind, i: GOOD[kind])
        self.assertEqual(compare(inputs, original, remake)["counts"]["mismatches"], 0)

    def test_each_observed_field_mutation_is_detected(self):
        mutations = {
            "npc_ai_fear/flag1_party_noticed_d4.0": ("decision_priority", 165, "$.steps[1].state.decision_priority"),
            "npc_ai_suspicion/help_after_decision": (None, None, "$.steps[1].state.units[1].pending[0]"),
            "npc_ai_target_score/weapon_basic": ("score_bits", 0xc1e8ccce, "$.steps[1].state.score_bits"),
            "npc_ai_motivation/danger_mode3": ("motivation", "calm", "$.steps[1].state.motivation"),
        }
        for name, (key, value, field) in mutations.items():
            with self.subTest(case=name):
                def state(kind, i):
                    good = copy.deepcopy(GOOD[kind])
                    if kind == "npc_ai_suspicion":
                        good = {"units": [GOOD[kind]["units"][0]] * 2}
                    return good
                inputs, original, remake = traces(name, state)
                steps = remake["scenarios"][0]["steps"]
                if key is None:
                    steps[1]["state"]["units"][1] = dict(steps[1]["state"]["units"][1], pending=[26])
                else:
                    steps[1]["state"][key] = value
                report = compare(inputs, original, remake)
                self.assertEqual(report["counts"]["mismatches"], 1)
                self.assertEqual(report["scenarios"][0]["first_divergence"]["field"], field)

    def test_truncated_remake_capture_is_an_error(self):
        inputs, original, remake = traces("npc_ai_motivation/danger_mode3", lambda kind, i: GOOD[kind])
        remake["scenarios"][0]["steps"].pop()
        with self.assertRaises(ValueError):
            compare(inputs, original, remake)


@unittest.skipUnless(os.environ.get("PARITY_GAME_EXE"), "PARITY_GAME_EXE names the pinned original executable")
class NpcAiNativeTests(unittest.TestCase):
    def capture(self, ids):
        from native import Original, CAPTURES
        data = Path(os.environ["PARITY_GAME_EXE"]).read_bytes()
        rows = {r["id"]: r for r in cases.scenarios(20261020, 2)}
        out = {}
        for case_id in ids:
            o = Original(data)
            try:
                out[case_id] = CAPTURES[rows[case_id]["kind"]](o, rows[case_id]["inputs"])
            finally:
                o.close()
        return out

    def test_native_captures_are_deterministic_and_valid(self):
        ids = ["npc_ai_fear/seeded_000", "npc_ai_suspicion/help_twice_next_tick", "npc_ai_target_score/heal",
               "npc_ai_motivation/fear_hold_mode3_level1000"]
        first, second = self.capture(ids), self.capture(ids)
        self.assertEqual(first, second)
        rows = {r["id"]: r for r in cases.scenarios(20261020, 2)}
        for case_id, states in first.items():
            cases.validate(rows[case_id], [{"step": i, "state": s} for i, s in enumerate(states)], "original")


if __name__ == "__main__":
    unittest.main()
