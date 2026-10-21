"""Extension families register without editing the shared runner."""
import unittest

import extensions
from cases import contracts_for, make_inputs
from native import CAPTURES


class ExtensionRegistryTest(unittest.TestCase):
    def test_every_extension_kind_has_contract_capture_and_scenarios(self):
        declared = extensions.contracts("original")
        self.assertTrue(declared)
        for kind in declared:
            with self.subTest(kind=kind):
                self.assertIn(kind, contracts_for("original"))
                self.assertIn(kind, CAPTURES)
                rows = make_inputs(pattern=kind + "/")["scenarios"]
                self.assertTrue(rows and all(r["kind"] == kind for r in rows))

    def test_extension_contracts_are_campaign_scoped(self):
        astral = contracts_for("lost_in_astral")
        for kind in extensions.contracts("original"):
            if kind not in extensions.contracts("lost_in_astral"):
                self.assertNotIn(kind, astral)

    def test_remake_scripts_declare_capture_entry_points(self):
        for script in extensions.remake_scripts():
            text = script.read_text()
            with self.subTest(script=script.name):
                self.assertIn("func kinds()", text)
                self.assertIn("func capture(", text)


if __name__ == "__main__":
    unittest.main()
