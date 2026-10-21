"""Input and observation checks for the npc_commands family (no game data)."""
import unittest

import cases_ext_npc_commands as family
from cases import make_inputs
from compare import digest, first_difference, validate_trace

QUERY_NAMES = {"GetDiplomacy", "IsEnemy", "IsAlarm", "AlarmTime", "AlarmPosX", "AlarmPosY"}


def native_names():
    # native_ext imports Unicorn through native_quests; keep the name table
    # check usable without the emulator installed.
    try:
        from native_ext_npc_commands import COMMANDS, QUERIES
    except ImportError:
        return None, None
    return COMMANDS, QUERIES


def statements(row):
    inputs = row["inputs"]
    if row["kind"] == "npc_alarm":
        return [step["command"] for step in inputs["steps"] if "command" in step]
    return inputs["commands"]


class NpcCommandInputsTest(unittest.TestCase):
    def test_counts_and_kinds(self):
        rows = family.scenarios(fuzz=4)
        kinds = {row["kind"] for row in rows}
        self.assertEqual(kinds, {"npc_motivation", "npc_diplomacy", "npc_alarm"})
        self.assertEqual(len({row["id"] for row in rows}), len(rows))
        self.assertGreater(len(family.scenarios(fuzz=8)), len(rows))

    def test_commands_reference_supplied_actors_and_known_opcodes(self):
        commands, queries = native_names()
        for row in family.scenarios():
            units = row["inputs"].get("units", [])
            for statement in statements(row):
                with self.subTest(row=row["id"], call=statement["call"]):
                    if commands is not None:
                        self.assertIn(statement["call"], commands)
                    for arg in statement["args"]:
                        if isinstance(arg, dict):
                            self.assertEqual(set(arg), {"unit"})
                            self.assertLess(arg["unit"], len(units))
            for index in row["inputs"].get("observe", []):
                self.assertLess(index, len(units))
        if queries is not None:
            self.assertEqual(set(queries), QUERY_NAMES)

    def test_every_authored_command_is_covered(self):
        used = {s["call"] for row in family.scenarios() for s in statements(row)}
        for name in ["UMSentry", "Idle", "UMPlayer", "SetDiplomacy", "UMClear", "Guard", "InvokeAlarm",
                     "UMStandard", "UMGuard", "Sentry", "UMAggression", "UMFollow", "UMFear", "Follow",
                     "SetPlayer", "UMRevenge", "BlockUnit", "ResetTarget", "UMGuardEx", "UMPatrol",
                     "UMPatrolAddPoint", "UMPatrolAddPointLook", "UMPatrolClear", "UMSuspection",
                     "UMCorpseWatcher", "UMAg", "SetSpellAggression", "SetPlayerAggression", "SetEnemy"]:
            self.assertIn(name, used)

    def test_contracts_are_base_only(self):
        self.assertEqual(family.contracts("lost_in_astral"), {})
        for contract in family.contracts("original").values():
            self.assertTrue(contract["stubs"] and contract["entry"])
            self.assertEqual(contract["tolerances"], {})

    def test_config_sentinels_are_not_explicit_inputs(self):
        sentinels = set(family.CONFIG.values())
        for row in family.scenarios():
            for statement in statements(row):
                for arg in statement["args"]:
                    if not isinstance(arg, dict):
                        self.assertNotIn(arg, sentinels)


class NpcCommandValidatorTest(unittest.TestCase):
    def trace(self, pattern, state):
        inputs = make_inputs(pattern=pattern)
        case = inputs["scenarios"][0]
        count = len(case["inputs"][family.STEP_COUNTS[case["kind"]]])
        return inputs, {"schema": 1, "role": "remake", "input_sha256": digest(inputs), "scenarios": [
            {"id": case["id"], "steps": [{"step": i, "state": state} for i in range(count)]}]}

    def test_valid_motivation_state_passes(self):
        state = {"units": [{"present": True, "blocked": False, "side": 0, "ai_state": 0, "script_target": -1,
                            "motivations": [{"type": "guard", "point_bits": [0, 0, 0], "radius": "GuardRadius", "stay": 5}]},
                           {"present": False}]}
        inputs, trace = self.trace("npc_motivation/UMSentry_point_0", state)
        validate_trace(trace, inputs, "remake")

    def test_validator_rejects_malformed_states(self):
        good = {"present": True, "blocked": False, "side": 0, "ai_state": 0, "script_target": -1, "motivations": []}
        bad = [
            {"units": [dict(good)]},  # wrong unit count
            {"units": [dict(good, blocked=1), {"present": False}]},
            {"units": [dict(good, motivations=[{"type": "guard", "point_bits": [0, 0], "radius": 0, "stay": 0}]), {"present": False}]},
            {"units": [dict(good, motivations=[{"type": "fear", "flag": 1}]), {"present": False}]},
            {"units": [dict(good, motivations=[{"type": "guard", "point_bits": [0, 0, 0], "radius": "x", "stay": 0}]), {"present": False}]},
        ]
        for state in bad:
            inputs, trace = self.trace("npc_motivation/UMSentry_point_0", state)
            with self.subTest(state=state), self.assertRaises(ValueError):
                validate_trace(trace, inputs, "remake")
        for pattern, state in [("npc_alarm/InvokeAlarm_0", {"alarms": [], "countdowns": []}),
                               ("npc_alarm/InvokeAlarm_0", {"alarms": [{"on_bits": -1, "time_bits": 0, "x_bits": 0, "y_bits": 0}] * 5, "countdowns": []}),
                               ("npc_diplomacy/SetEnemy_bit", {"relation_bits": [0], "units": []})]:
            inputs, trace = self.trace(pattern, state)
            with self.subTest(pattern=pattern), self.assertRaises(ValueError):
                validate_trace(trace, inputs, "remake")

    def test_one_changed_field_is_reported(self):
        one = {"motivations": [{"type": "sentry", "point_bits": [1, 2, 0]}], "ai_state": 0}
        two = {"motivations": [{"type": "sentry", "point_bits": [1, 3, 0]}], "ai_state": 0}
        self.assertEqual(first_difference(one, two)["field"], "$.motivations[0].point_bits[1]")


if __name__ == "__main__":
    unittest.main()
