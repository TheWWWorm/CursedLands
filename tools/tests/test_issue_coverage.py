"""Every changelog issue has a registered regression test or a recorded reason."""
import json
from pathlib import Path
import sys
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import check_issue_coverage as coverage


class IssueCoverageTests(unittest.TestCase):
    def test_changelog_issues_have_registered_tests_or_reasons(self):
        missing, stale = coverage.uncovered()
        self.assertEqual(missing, {}, "link the issue in a registered case's `issues` list, or explain it in "
                                      "tools/issue_coverage_exceptions.json")
        self.assertEqual(stale, [], "remove issues that now have a registered test from the exceptions file")

    def test_exceptions_carry_reasons(self):
        data = json.loads(coverage.EXCEPTIONS.read_text(encoding="utf-8"))
        for key, reason in data.items():
            self.assertTrue(key.isdigit() and len(reason) > 20, key)

    def test_recurring_families_are_covered(self):
        """The reports that reopened under new numbers each have a registered test now."""
        covered = coverage.registered_issues()
        for family in ((109, 113, 118), (98, 116, 119), (95, 103, 112), (89, 105, 111)):
            for issue in family:
                self.assertIn(issue, covered, f"#{issue}")


if __name__ == "__main__":
    unittest.main()
