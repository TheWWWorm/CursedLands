"""Negative controls for campaign identities, authored inputs and observations."""
import copy
import struct
import unittest

from campaign_quests import Reader, normalize, script_bytes, samples, iterator_names
from cases import make_inputs, contracts_for
from compare import digest, validate_trace
from run import check_inputs


def trace(inputs, states):
    return {"schema": 1, "role": "remake", "input_sha256": digest(inputs),
            "scenarios": [{"id": inputs["scenarios"][0]["id"],
                           "steps": [{"step": i, "state": state} for i, state in enumerate(states)]}]}


class References(unittest.TestCase):
    def test_both_qualified_campaigns(self):
        for campaign in ["original", "lost_in_astral"]:
            check_inputs(make_inputs(campaign=campaign))

    def test_cross_campaign_addresses_rejected(self):
        inputs = make_inputs(campaign="lost_in_astral", pattern="quest_predicate/IsEqual_0")
        inputs["contracts"]["quest_predicate"] = contracts_for("original")["quest_predicate"]
        with self.assertRaisesRegex(ValueError, "contract"):
            check_inputs(inputs)

    def test_astral_cannot_claim_unqualified_body_routine(self):
        inputs = make_inputs(campaign="lost_in_astral")
        base = make_inputs(pattern="body_health/intact")
        inputs["scenarios"] += base["scenarios"]
        inputs["contracts"].update(base["contracts"])
        with self.assertRaisesRegex(ValueError, "contract"):
            check_inputs(inputs)

    def test_unknown_binary_rejected(self):
        inputs = copy.deepcopy(make_inputs(campaign="lost_in_astral"))
        inputs["reference"]["executable_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "reference"):
            check_inputs(inputs)

    def test_supported_families_differ_by_campaign(self):
        self.assertNotIn("body_health", contracts_for("lost_in_astral"))
        self.assertIn("body_health", contracts_for("original"))


class AuthoredInputs(unittest.TestCase):
    def test_original_conditions_order_and_nested_calls_preserved(self):
        rows = Reader('''
            GlobalVars ( gate : unit )
            DeclareScript Watch ( this : unit )
            Script Watch (
                if ( IsAlive(this), IsLess(DistanceUnitPoint(this, 1, 2), 3) )
                then ( KillScript() )
                if ( IsEqual(GSGetVar(0, "q.test"), 2) ) then ( Next(this) )
            )
            WorldScript ( Watch(gate) )
        ''').blocks()
        self.assertEqual([(r[0], r[1]) for r in rows], [("Watch", 0), ("Watch", 1)])
        bindings = {}
        conditions = [normalize(c, bindings) for c in rows[0][2]]
        self.assertEqual(bindings, {"this": 0})
        self.assertEqual(conditions[1]["args"][0]["call"], "DistanceUnitPoint")
        self.assertEqual(conditions[0]["call"], "IsAlive")

    def test_unsupported_condition_rejected_whole(self):
        with self.assertRaisesRegex(ValueError, "GetSkill"):
            normalize({"call": "GetSkill", "args": [{"symbol": "hero"}, {"string": "stealth"}]}, {})

    def test_dynamic_actor_lookup_rejected(self):
        with self.assertRaisesRegex(ValueError, "dynamic actor"):
            normalize({"call": "IsAlive", "args": [{"call": "GetObject", "args": [1]}]}, {})

    def test_dynamic_string_rejected(self):
        with self.assertRaisesRegex(ValueError, "dynamic string"):
            normalize({"call": "GSGetVar", "args": [0, {"symbol": "key"}]}, {})

    def test_mob_reader_honors_root_boundary(self):
        text = b"WorldScript()"
        child = struct.pack("<II", 0xacceecca, 8 + len(text)) + text
        raw = struct.pack("<II", 0xa000, 8 + len(child)) + child + b"trailing editor payload"
        self.assertEqual(script_bytes(raw), text)

    def test_mob_reader_decrypts_native_cipher(self):
        text, key, encoded = b"WorldScript()", 123, bytearray()
        for value in text:
            key = (key * 214013 + 2531011) & 0xffffffff
            encoded.append(value ^ ((key >> 16) & 255))
        child = struct.pack("<III", 0xacceeccb, 12 + len(encoded), 123) + encoded
        self.assertEqual(script_bytes(struct.pack("<II", 0xa000, 8 + len(child)) + child), text)

    def test_mob_reader_rejects_ambiguous_scripts(self):
        child = struct.pack("<II", 0xacceecca, 9) + b"x"
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            script_bytes(struct.pack("<II", 0xa000, 26) + child + child)

    def test_unit_pair_samples_include_separation(self):
        conditions = [{"call": "IsLess", "args": [
            {"call": "DistanceUnitUnit", "args": [{"unit": 0}, {"unit": 1}]}, 5]}]
        rows = samples(conditions, 2)
        self.assertTrue(any(r["units"][0] and r["units"][0]["pos"] != r["units"][1]["pos"] for r in rows))
        self.assertEqual(rows[-1]["units"], [None, None])

    def test_group_iterator_binding_is_shared_with_following_condition(self):
        expressions = [
            {"call": "Any", "args": [{"symbol": "i"}, {"symbol": "guards"},
                                      {"call": "IsDead", "args": [{"symbol": "i"}]}]},
            {"call": "IsAlive", "args": [{"symbol": "i"}]},
        ]
        bindings, groups = {}, {}
        iterators = iterator_names(expressions)
        converted = [normalize(e, bindings, groups=groups, iterators=iterators) for e in expressions]
        self.assertEqual(bindings, {})
        self.assertEqual(groups, {"guards": 0})
        self.assertEqual(converted[0]["args"][0], {"iterator": "i"})
        self.assertEqual(converted[0]["args"][2]["args"][0], converted[1]["args"][0])

    def test_dynamic_group_lookup_not_replaced_with_empty_group(self):
        with self.assertRaisesRegex(ValueError, "dynamic group"):
            normalize({"call": "GroupSize", "args": [{"call": "GetUnits", "args": [0]}]}, {})

    def test_group_samples_keep_members_present_and_cover_empty_mixed_dead(self):
        rows = samples([], 0, {"guards": 0})
        for row in rows:
            self.assertTrue(all(row["units"][i] is not None for i in row["groups"]["guards"]))
        self.assertTrue(any(not r["groups"]["guards"] for r in rows))
        self.assertTrue(any(r["groups"]["guards"] and
                            all(r["units"][i]["dead"] for i in r["groups"]["guards"]) for r in rows))
        self.assertTrue(any(0 < sum(r["units"][i]["dead"] for i in r["groups"]["guards"])
                            < len(r["groups"]["guards"]) for r in rows))

    def test_dynamic_area_id_rejected(self):
        with self.assertRaisesRegex(ValueError, "dynamic area"):
            normalize({"call": "IsInArea", "args": [{"call": "Add", "args": [1, 1]}, 0, 0]}, {})

    def test_area_samples_do_not_claim_map_initialization(self):
        rows = samples([{"call": "IsInArea", "args": [7, 0, 0]}], 1)
        self.assertEqual(rows[0]["areas"][0]["id"], 7)
        self.assertEqual(rows[-1]["areas"], [])

    def test_clock_gate_without_actor_samples_both_sides_of_authored_boundary(self):
        condition = normalize({"call": "IsGreater", "args": [
            {"call": "GetWorldTime", "args": []}, 17.5]}, {})
        rows = samples([condition], 0)
        times = {r["world_time"] for r in rows if "world_time" in r}
        self.assertTrue({17.49999, 17.5, 17.50001} <= times)
        self.assertTrue(all(r["units"] == [] for r in rows))

    def test_money_gate_samples_authored_threshold_and_neighbors(self):
        rows = samples([{"call": "IsGreater", "args": [
            {"call": "GetMoney", "args": [0]}, 2500]}], 0)
        self.assertTrue({2499, 2500, 2501} <= {r["money"] for r in rows if "money" in r})

    def test_item_gate_samples_absent_each_and_combined_inventory(self):
        rows = samples([{"call": "HaveItem", "args": [0, item]} for item in [2, 68]], 0)
        bags = {tuple(r["quest_items"]) for r in rows if "quest_items" in r}
        self.assertEqual(bags, {(), (2,), (68,), (2, 68)})

    def test_loot_and_block_flags_sample_independently(self):
        rows = samples([{"call": name, "args": [{"unit": 0}]} for name in ["WasLooted", "IsUnitBlocked"]], 1)
        flags = {(u["looted"], u["blocked"]) for r in rows for u in r["units"] if u and "looted" in u}
        self.assertEqual(flags, {(False, False), (False, True), (True, False), (True, True)})

    def test_height_samples_include_both_object_types(self):
        rows = samples([{"call": "GetZ", "args": [{"unit": 0}]}], 1)
        paths = {u["map_object"] for r in rows for u in r["units"] if u and "map_object" in u}
        self.assertEqual(paths, {False, True})

    def test_environment_gate_includes_mixed_authored_prerequisites(self):
        conditions = [{"call": "IsGreater", "args": [{"call": "GetMoney", "args": [0]}, 499]}]
        conditions += [{"call": "IsEqual", "args": [
            {"call": "GSGetVar", "args": [0, {"string": key}]}, value]}
            for key, value in [("q.previous", 2), ("q.active", 1), ("b.unused", 0)]]
        rows = samples(conditions, 0)
        self.assertTrue(any(row.get("money") == 500 and row["variables"] ==
                            {"q.previous": 2, "q.active": 1, "b.unused": 0} for row in rows))


class ProgramObservations(unittest.TestCase):
    def setUp(self):
        self.inputs = make_inputs(pattern="quest_program/zero_delays_do_not_split_body")
        case = self.inputs["scenarios"][0]["inputs"]
        self.states = [{"values": {name: 0 for name in case["globals"]},
                        "observed_bits": [0] * len(case["observe"]),
                        "finished": True, "killed": True} for _ in case["ticks"]]

    def test_complete_program_observations_accepted(self):
        validate_trace(trace(self.inputs, self.states), self.inputs, "remake")

    def test_program_requires_every_tick(self):
        for states in [self.states[:-1], self.states + self.states[:1]]:
            with self.subTest(length=len(states)), self.assertRaisesRegex(ValueError, "captured"):
                validate_trace(trace(self.inputs, states), self.inputs, "remake")

    def test_program_requires_all_global_values(self):
        del self.states[0]["values"]["phase"]
        with self.assertRaisesRegex(ValueError, "invalid"):
            validate_trace(trace(self.inputs, self.states), self.inputs, "remake")

    def test_program_requires_all_observed_expressions(self):
        self.states[0]["observed_bits"].pop()
        with self.assertRaisesRegex(ValueError, "invalid"):
            validate_trace(trace(self.inputs, self.states), self.inputs, "remake")

    def test_program_bits_cannot_be_boolean_float_or_out_of_range(self):
        for value in [True, 0.0, -1, 0x100000000]:
            self.states[0]["values"]["phase"] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "invalid"):
                validate_trace(trace(self.inputs, self.states), self.inputs, "remake")

    def test_program_completion_flags_must_be_boolean(self):
        for field in ["finished", "killed"]:
            states = copy.deepcopy(self.states)
            states[0][field] = 1
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "invalid"):
                validate_trace(trace(self.inputs, states), self.inputs, "remake")


class Observations(unittest.TestCase):
    def test_empty_predicate_state_cannot_pass(self):
        inputs = make_inputs(pattern="quest_predicate/IsEqual_0")
        with self.assertRaisesRegex(ValueError, "invalid"):
            validate_trace(trace(inputs, [{}]), inputs, "remake")

    def test_trigger_dispatch_requires_all_conditions_evaluated(self):
        inputs = make_inputs(pattern="quest_trigger/all_conditions_true")
        states = [{"fired": True, "dispatches": i+1, "evaluated": [0]} for i in range(2)]
        with self.assertRaisesRegex(ValueError, "invalid"):
            validate_trace(trace(inputs, states), inputs, "remake")

    def test_trigger_reordered_evaluations_cannot_pass(self):
        inputs = make_inputs(pattern="quest_trigger/all_conditions_true")
        states = [{"fired": True, "dispatches": i+1, "evaluated": [1, 0, 2]} for i in range(2)]
        with self.assertRaisesRegex(ValueError, "invalid"):
            validate_trace(trace(inputs, states), inputs, "remake")

    def test_trigger_truncation_cannot_pass(self):
        inputs = make_inputs(pattern="quest_trigger/empty_conditions")
        with self.assertRaisesRegex(ValueError, "captured"):
            validate_trace(trace(inputs, [{"fired": True, "dispatches": 1, "evaluated": []}]), inputs, "remake")

    def test_body_initial_and_each_operation_required(self):
        inputs = make_inputs(pattern="body_health/intact")
        with self.assertRaisesRegex(ValueError, "captured"):
            validate_trace(trace(inputs, [{"hp_bits": 0}]), inputs, "remake")

    def test_removed_effect_cannot_report_live_counter(self):
        inputs = make_inputs(pattern="effect_lifetime/counter0_deadFalse")
        with self.assertRaisesRegex(ValueError, "invalid"):
            validate_trace(trace(inputs, [{"alive": False, "ticks": 0}] * 5), inputs, "remake")


if __name__ == "__main__":
    unittest.main()
