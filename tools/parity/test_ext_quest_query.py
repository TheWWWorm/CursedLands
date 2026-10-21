"""Input and observation checks for the quest_query family (no game data)."""
import unittest

import cases_ext_quest_query as family
from cases import make_inputs
from compare import validate_trace, digest


class QuestQueryInputsTest(unittest.TestCase):
    def test_object_calls_are_the_only_arguments_of_their_parent(self):
        from native_ext_quest_query import OBJECT_CALLS

        def walk(expression):
            args = expression.get("args", [])
            if any(isinstance(a, dict) and a.get("call") in OBJECT_CALLS for a in args):
                self.assertTrue(all(isinstance(a, dict) and a.get("call") in OBJECT_CALLS for a in args))
            for arg in args:
                if isinstance(arg, dict) and "call" in arg:
                    walk(arg)

        for row in family.scenarios():
            walk(row["inputs"]["expression"])

    def test_party_records_reference_supplied_actors(self):
        for row in family.scenarios():
            for record in row["inputs"].get("party", []):
                self.assertLess(record["unit"], len(row["inputs"]["units"]))

    def test_validator_rejects_malformed_states(self):
        inputs = make_inputs(pattern="quest_query/in_square_5_5")
        case = inputs["scenarios"][0]
        for state in [{"value_bits": -1, "truth": True}, {"value_bits": 0, "truth": 1}, {"value_bits": 0}]:
            trace = {"schema": 1, "role": "remake", "input_sha256": digest(inputs),
                     "scenarios": [{"id": case["id"], "steps": [{"step": 0, "state": state}]}]}
            with self.subTest(state=state), self.assertRaises(ValueError):
                validate_trace(trace, inputs, "remake")


if __name__ == "__main__":
    unittest.main()
