"""Static checks on both test registries and the test scripts themselves.

These run without game data or an engine. They catch the registration
mistakes that otherwise surface only after a long run: scripts that do not
exist, completion markers that no script prints, duplicate case IDs, base
scripts that `extends "res://tools/..."` cannot find, and the `var x := weakref(...)`
form that Godot 4.7 rejects as an inference-from-Variant error.
"""
import json
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[2]
TESTS = REPO / "tools/tests"
BENCHMARKS = REPO / "tools/benchmarks"
VARIANT_INFERENCE = re.compile(
    r'\bvar\s+\w+\s*:=\s*(?:weakref|JSON\.parse_string|str_to_var|bytes_to_var)\([^\n]*')


def scripts():
    return sorted(list(TESTS.glob("*.gd")) + list(BENCHMARKS.glob("*.gd")))


def dependencies(script):
    """Scripts this one pulls in through res://tools/, relative or sibling paths."""
    text = script.read_text(encoding="utf-8")
    found = []
    for match in re.finditer(r'(?:extends|preload\()\s*"([^"]+\.gd)"', text):
        target = match.group(1)
        if target.startswith("user://"):
            continue
        if target.startswith("res://tools/"):
            found.append(REPO / "tools" / target.removeprefix("res://tools/"))
        elif target.startswith("res://"):
            found.append(REPO / "game" / target.removeprefix("res://"))
        else:
            found.append((script.parent / target).resolve())
    return found


def closure(script):
    seen, queue = [], [script]
    while queue:
        item = queue.pop()
        if item in seen or not item.is_file():
            continue
        seen.append(item)
        queue.extend(dependencies(item))
    return seen


def focused_cases():
    return json.loads((REPO / "tools/regressions.json").read_text(encoding="utf-8"))["cases"]


def catalog_entries():
    return json.loads((REPO / "tools/parity/gameplay_catalog.json").read_text(encoding="utf-8"))["tests"]


class RegistryTests(unittest.TestCase):
    def test_focused_cases_name_existing_scripts_and_markers(self):
        ids = [case["id"] for case in focused_cases()]
        self.assertEqual(len(ids), len(set(ids)), "duplicate focused case IDs")
        for case in focused_cases():
            script = REPO / case["script"]
            self.assertTrue(script.is_file(), case["id"])
            self.assertGreaterEqual(case["min_checks"], 1, case["id"])
            self.assertIn(case["mode"], ("headless", "rendered"), case["id"])
            texts = [item.read_text(encoding="utf-8") for item in closure(script)]
            self.assertTrue(any(case["summary"] in text for text in texts),
                            f'{case["id"]}: no script in the closure prints {case["summary"]}')

    def test_catalog_entries_name_existing_scripts_and_markers(self):
        ids = [row["id"] for row in catalog_entries()]
        self.assertEqual(len(ids), len(set(ids)), "duplicate catalog IDs")
        for row in catalog_entries():
            script = REPO / row["script"]
            self.assertTrue(script.is_file(), row["id"])
            texts = [item.read_text(encoding="utf-8") for item in closure(script)]
            self.assertTrue(any(row["marker"] in text for text in texts),
                            f'{row["id"]}: no script in the closure prints {row["marker"]}')


class ScriptSourceTests(unittest.TestCase):
    def test_imports_resolve(self):
        missing = []
        for script in scripts():
            for target in dependencies(script):
                if not target.is_file():
                    missing.append(f"{script.relative_to(REPO)} -> {target}")
        self.assertEqual(missing, [])

    def test_no_variant_inference_from_untyped_builtins(self):
        """`var x := weakref(y)` infers Variant; Godot 4.7 refuses to load the script."""
        offending = []
        for script in scripts():
            for number, line in enumerate(script.read_text(encoding="utf-8").splitlines(), 1):
                match = VARIANT_INFERENCE.search(line)
                if match and " as " not in match.group(0):
                    offending.append(f"{script.relative_to(REPO)}:{number}: {line.strip()}")
        self.assertEqual(offending, [])


if __name__ == "__main__":
    unittest.main()
