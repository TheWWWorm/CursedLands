"""Input and observation checks for the perception_triggers family.

The optional native tests run only when the user's original executable is
present; they prove the native observation reacts to the supplied lists.
"""
import copy
import os
from pathlib import Path
import unittest

import cases_ext_perception_triggers as family
from cases import make_inputs
from compare import digest, validate_trace

GAME = Path(os.environ.get("EI_GAME_DIR", "/home/llm2x/Documents/EI/inspection/extracted/app"))


class PerceptionInputsTest(unittest.TestCase):
    def test_references_stay_inside_the_fixture(self):
        for row in family.scenarios():
            data = row["inputs"]
            count = len(data["units"])
            for unit in data["units"]:
                for i in unit.get("noticed", []) + unit.get("corpses", []):
                    self.assertTrue(0 <= i < count, row["id"])
            for members in data["groups"].values():
                self.assertTrue(all(0 <= i < count for i in members), row["id"])
            self.assertTrue(all(0 <= i < count for i in data["player_units"]), row["id"])

    def test_no_actor_notices_itself(self):
        for row in family.scenarios():
            for i, unit in enumerate(row["inputs"]["units"]):
                self.assertNotIn(i, unit.get("noticed", []) + unit.get("corpses", []), row["id"])

    def test_tick_inputs_are_well_formed(self):
        for row in family.scenarios(fuzz=30):
            if row["kind"] != "perception_ticks":
                continue
            data = row["inputs"]
            self.assertEqual(data["watcher"], 0)
            self.assertFalse(data["units"][0]["party"])
            for tick in data["ticks"]:
                self.assertTrue(set(tick) <= {"positions", "rays", "dead"})
                for key in list(tick.get("positions", {})) + list(tick.get("rays", {})):
                    self.assertTrue(0 < int(key) < len(data["units"]))

    def test_layer_one_variants_cover_dead_duplicates_and_corpses(self):
        ids = {row["id"].split("/")[1] for row in family.scenarios() if row["kind"] == "perception_group"}
        for name in ["npc_duplicate_entry", "npc_list_holds_corpse", "dead_npc_retained_list", "hero_corpse_list"]:
            self.assertIn(name, ids)

    def _trace(self, inputs, state):
        case = inputs["scenarios"][0]
        return {"schema": 1, "role": "remake", "input_sha256": digest(inputs),
                "scenarios": [{"id": case["id"], "steps": [{"step": i, "state": copy.deepcopy(state)}
                                                           for i in range(len(case["inputs"].get("ticks", [0])))]}]}

    def test_validator_rejects_malformed_states(self):
        group = make_inputs(pattern="perception_group/empty/unitsee_missing")
        number = make_inputs(pattern="perception_group/empty/size_unitsee")
        ticks = make_inputs(pattern="perception_ticks/exact_thresholds")
        validate_trace(self._trace(group, {"count": 0, "members": []}), group, "remake")
        validate_trace(self._trace(number, {"truth": False, "value_bits": 0}), number, "remake")
        validate_trace(self._trace(ticks, {"count_bits": 0, "fired": False, "noticed": []}), ticks, "remake")
        for inputs, state in [
            (group, {"count": 0, "members": [-1]}), (group, {"count": 2, "members": [3, 1]}),
            (group, {"truth": False, "value_bits": 0}), (number, {"count": 0, "members": []}),
            (number, {"truth": 0, "value_bits": 0}), (ticks, {"count_bits": 0, "fired": False, "noticed": [0]}),
            (ticks, {"count_bits": 0, "fired": False, "noticed": [1, 1]}), (ticks, {"count_bits": 0, "fired": False}),
        ]:
            with self.subTest(state=state), self.assertRaises(ValueError):
                validate_trace(self._trace(inputs, state), inputs, "remake")


@unittest.skipUnless((GAME / "game.exe").exists(), "original executable not available")
class PerceptionNativeSensitivityTest(unittest.TestCase):
    """Mutating one supplied input must change the native observation."""

    def capture(self, kind, data):
        from native import Original
        import native_ext_perception_triggers as native
        o = Original((GAME / "game.exe").read_bytes())
        try:
            return native.CAPTURES[kind](o, data)
        finally:
            o.close()

    def test_noticed_list_drives_unitsee(self):
        data = copy.deepcopy(family.VARIANTS["npc_sees_hero"])
        data["expression"] = family.expressions()["size_cross_unitsee_heroes"]
        self.assertTrue(self.capture("perception_group", data)[0]["truth"])
        data["units"][0]["noticed"] = []
        self.assertFalse(self.capture("perception_group", data)[0]["truth"])

    def test_retention_drives_ticks(self):
        row = next(r for r in family.scenarios() if r["id"] == "perception_ticks/approach_retreat_hostile1_cross")
        hostile = [s["fired"] for s in self.capture("perception_ticks", copy.deepcopy(row["inputs"]))]
        data = copy.deepcopy(row["inputs"])
        data["observer"]["hostile_sides"] = []
        neutral = [s["fired"] for s in self.capture("perception_ticks", data)]
        self.assertNotEqual(hostile, neutral)


if __name__ == "__main__":
    unittest.main()
