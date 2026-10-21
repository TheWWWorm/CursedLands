"""Harness tests for the dialogue-trigger family (no game data needed)."""
import unittest

import cases_ext_dialogue as cases
import extensions

KINDS = {"dialogue_topics", "dialogue_zone", "dialogue_merc", "dialogue_complete"}


class DialogueInputsTest(unittest.TestCase):
    def setUp(self):
        self.rows = cases.scenarios(20261020, 12)

    def test_kinds_and_contracts(self):
        contracts = cases.contracts("original")
        self.assertEqual(set(contracts), KINDS)
        self.assertEqual(cases.contracts("lost_in_astral"), {})
        for kind, contract in contracts.items():
            with self.subTest(kind=kind):
                self.assertTrue(contract["entry"] and contract["stubs"] and contract["limits"])
                self.assertEqual(contract["tolerances"], {})
        self.assertEqual({r["kind"] for r in self.rows}, KINDS)

    def test_ids_unique_and_deterministic(self):
        ids = [r["id"] for r in self.rows]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(self.rows, cases.scenarios(20261020, 12))
        self.assertNotEqual(self.rows, cases.scenarios(1, 12))
        self.assertGreater(len(cases.scenarios(20261020, 30)), len(self.rows))

    def test_inputs_are_ordered_gs_writes_without_answers(self):
        forbidden = {"expected", "topics", "titles", "started", "briefing", "completion", "experience_out"}
        for row in self.rows:
            with self.subTest(row=row["id"]):
                inputs = row["inputs"]
                self.assertFalse(forbidden & set(inputs))
                for key, value in inputs["variables"]:
                    self.assertIsInstance(key, str)
                    key.encode("ascii")
                    self.assertIsInstance(value, (int, float))
                if row["kind"] == "dialogue_topics":
                    self.assertIn("name", inputs["npc"])
                if row["kind"] in ("dialogue_merc", "dialogue_complete"):
                    self.assertTrue(all("name" in m for m in inputs["party"]))

    def test_registered_through_extensions(self):
        self.assertTrue(KINDS <= set(extensions.contracts("original")))
        self.assertTrue(any(p.name == "remake_ext_dialogue.gd" for p in extensions.remake_scripts()))


class DialogueValidatorTest(unittest.TestCase):
    def check(self, kind, state, valid=True):
        case = {"id": kind + "/x", "kind": kind}
        steps = [{"step": 0, "state": state}]
        if valid:
            cases.validate(case, steps, "original")
        else:
            with self.assertRaises(ValueError):
                cases.validate(case, steps, "remake")

    def test_topics(self):
        self.check("dialogue_topics", {"open": True, "topics": ["a"], "titles": [""]})
        self.check("dialogue_topics", {"open": False, "topics": [], "titles": []})
        self.check("dialogue_topics", {"open": True, "topics": [], "titles": []}, False)
        self.check("dialogue_topics", {"open": True, "topics": ["a"], "titles": []}, False)
        self.check("dialogue_topics", {"open": 1, "topics": ["a"], "titles": [""]}, False)
        self.check("dialogue_topics", {"open": True, "topics": ["a"], "titles": [""], "x": 1}, False)

    def test_zone(self):
        self.check("dialogue_zone", {"started": True, "briefing": "intro"})
        self.check("dialogue_zone", {"started": False, "briefing": ""})
        self.check("dialogue_zone", {"started": False, "briefing": "intro"}, False)
        self.check("dialogue_zone", {"started": "yes", "briefing": ""}, False)

    def test_merc(self):
        self.check("dialogue_merc", {"variables": {"amerc_1": 1.0, "b.merc1.n1_1": 1.0}})
        self.check("dialogue_merc", {"variables": {"q.x": 1.0}}, False)
        self.check("dialogue_merc", {"variables": {"amerc_1": 0.0}}, False)

    def test_complete(self):
        good = {"completion": [0, "b.a.b", 2.0, 0, "b.a.b"], "money": 1, "experience": [],
                "merc_events": [], "variables": {}}
        self.check("dialogue_complete", good)
        self.check("dialogue_complete", dict(good, money=1.5), False)
        self.check("dialogue_complete", dict(good, completion=[]), False)


class CompletionScriptTest(unittest.TestCase):
    def test_world_script_format(self):
        try:
            import native_ext_dialogue as native
        except ImportError:  # Unicorn is optional for harness-only checks.
            self.skipTest("unicorn not installed")
        match = native.COMPLETION.match('WorldScript( GSSetVar( 0,"b.smith.t1",2 ) #OnBriefingComplete( 0, "b.smith.t1" ) )')
        self.assertEqual(match.groups(), ("0", "b.smith.t1", "0", "b.smith.t1"))
        self.assertIsNone(native.COMPLETION.match('WorldScript( GSSetVar( 0,"b",1 ) )'))


if __name__ == "__main__":
    unittest.main()
