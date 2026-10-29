"""Static checks on the test registry and the test scripts themselves.

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


def catalog_entries():
    return json.loads((REPO / "tools/parity/gameplay_catalog.json").read_text(encoding="utf-8"))["tests"]


class RegistryTests(unittest.TestCase):
    def test_catalog_entries_name_existing_scripts_and_markers(self):
        ids = [row["id"] for row in catalog_entries()]
        self.assertEqual(len(ids), len(set(ids)), "duplicate catalog IDs")
        for row in catalog_entries():
            script = REPO / row["script"]
            self.assertTrue(script.is_file(), row["id"])
            self.assertGreaterEqual(row["min_checks"], 1, row["id"])
            self.assertIn(row.get("display", "headless"), ("headless", "rendered"), row["id"])
            texts = [item.read_text(encoding="utf-8") for item in closure(script)]
            self.assertTrue(any(row["marker"] in text for text in texts),
                            f'{row["id"]}: no script in the closure prints {row["marker"]}')

    def test_focused_ids_are_unique_short_names(self):
        """tools/check_regressions.py selects and reports catalog entries by
        their `focused` ID; it must name exactly one entry and never another
        entry's own name."""
        rows = catalog_entries()
        aliases = [row["focused"] for row in rows if "focused" in row]
        self.assertEqual(len(aliases), len(set(aliases)), "duplicate focused IDs")
        names = {row["id"].split("/")[1]: row["id"] for row in rows}
        for row in rows:
            if "focused" in row:
                self.assertRegex(row["focused"], r"^[a-z0-9_]+$", row["id"])
                self.assertEqual(names.get(row["focused"], row["id"]), row["id"],
                                 f'{row["id"]}: focused ID {row["focused"]} is another entry\'s name')
        self.assertGreaterEqual(len(aliases), 370, "the folded focused manifest must stay registered")

    def test_same_registration_appears_once(self):
        """One script with the same arguments, campaign, display and renderer
        is one entry (and so one `min_checks`); the folded manifest must not
        grow a second registration of a catalog test."""
        seen = {}
        for row in catalog_entries():
            key = (row["script"], tuple(row.get("args", [])), row["campaign"], row.get("display", "headless"),
                   row.get("rendering_method", "gl_compatibility"))
            seen.setdefault(key, []).append(row["id"])
        self.assertEqual([ids for ids in seen.values() if len(ids) > 1], [])

    def test_localized_archives_are_declared(self):
        """`{texts_xx}` arguments name archives the entry lists in `texts`."""
        for row in catalog_entries():
            used = {language for arg in row.get("args", []) for language in re.findall(r"\{texts_(\w+)\}", arg)}
            self.assertEqual(used, set(row.get("texts", [])), row["id"])


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
