import copy
import json
import unittest

import cases_ext_quest_commands as cases
from compare import first_difference


def state(**changes):
    base = {"gs": {"capacity": 193, "count": 1, "chains": [[5, [["k1", 0x3fc00000]]]]}, "bag": [17],
            "money": 0, "levers": [], "groups": {}, "journal": {"recording": "", "compiled": []},
            "globals": {}, "observed_bits": [], "finished": True, "killed": False}
    base.update(changes)
    return base


class QuestCommandCases(unittest.TestCase):
    def setUp(self):
        self.rows = cases.scenarios(20261020, 3)

    def test_ids_kinds_and_contracts(self):
        ids = [r["id"] for r in self.rows]
        self.assertEqual(len(ids), len(set(ids)))
        contracts = cases.contracts("original")
        self.assertEqual(set(contracts), set(cases.KINDS))
        self.assertEqual(cases.contracts("lost_in_astral"), {})
        for row in self.rows:
            self.assertIn(row["kind"], contracts)
            self.assertTrue(row["id"].startswith(row["kind"] + "/"))
        for contract in contracts.values():
            self.assertTrue(contract["stubs"] and contract["entry"] and contract["tolerances"] == {})

    def test_inputs_are_json_without_expectations(self):
        for row in self.rows:
            text = json.dumps(row["inputs"], allow_nan=False)
            for forbidden in ("expected", "result", "answer"):
                self.assertNotIn(forbidden, text)
            self.assertTrue(row["inputs"]["ticks"])
            self.assertEqual(cases.STEP_COUNTS[row["kind"]], "ticks")

    def test_fuzz_is_seeded_and_sized(self):
        self.assertEqual(cases.scenarios(7, 4), cases.scenarios(7, 4))
        self.assertNotEqual(cases.scenarios(7, 4), cases.scenarios(8, 4))
        small = sum("/fuzz_" in r["id"] for r in cases.scenarios(1, 2))
        large = sum("/fuzz_" in r["id"] for r in cases.scenarios(1, 5))
        self.assertEqual((small, large), (8, 20))

    def test_collision_keys_share_an_initial_bucket(self):
        def native_hash(text):
            value = 0
            for byte in text.encode("latin-1"):
                value = (value * 5 + (byte - 256 if byte >= 128 else byte)) & 0xffffffff
            return value % 193
        self.assertEqual(len({native_hash(k) for k in cases.COLLIDE}), 1)

    def test_validator_accepts_and_rejects(self):
        row = {"id": "quest_cmd_gsvar/x", "kind": "quest_cmd_gsvar",
               "inputs": {"units": [], "groups": [], "globals": {}, "observe": []}}
        cases.validate(row, [{"state": state()}], "original")
        bad = [state(gs={"capacity": 193, "count": 1, "chains": [[200, [["k", 1]]]]}),
               state(gs={"capacity": 193, "count": 1, "chains": [[5, [["k", -1]]]]}),
               state(bag=["sackofgold"]), state(money=1.5), state(levers=[{"state": 0, "enabled": True}]),
               state(groups={"G": []}), state(journal={"recording": "", "compiled": [{"quest": "a"}]}),
               state(observed_bits=[1]), state(finished=1)]
        extra = state()
        extra["unexpected"] = 1
        bad.append(extra)
        for candidate in bad:
            with self.assertRaises(ValueError):
                cases.validate(row, [{"state": candidate}], "remake")

    def test_comparator_reports_single_field_mutation(self):
        native = state()
        for path, mutate in [("$.bag[0]", lambda s: s["bag"].__setitem__(0, 16)),
                             ("$.gs.chains[0][1][0][1]", lambda s: s["gs"]["chains"][0][1][0].__setitem__(1, 0x3fc00001)),
                             ("$.gs.count", lambda s: s["gs"].__setitem__("count", 2))]:
            remake = copy.deepcopy(native)
            mutate(remake)
            self.assertEqual(first_difference(native, remake)["field"], path)


if __name__ == "__main__":
    unittest.main()
