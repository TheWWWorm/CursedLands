"""Interface conventions that one shared helper now carries.

Scale: a screen names a `UiScale` rule instead of restating `size / 600.0`
(seven variants of the same ratio used to live in eleven files). Input: a
panel asks `UiInput.is_cancel` / `UiInput.is_confirm` instead of comparing
`keycode == KEY_ESCAPE`, so the binding lives in the InputMap. These checks
need no engine and run with the other tools/tests modules.
"""
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[2]
UI = REPO / "game/src/ui"
GAME = REPO / "game/src/game"
SCALE_HELPER = UI / "ui_scale.gd"
INPUT_HELPER = UI / "ui_input.gd"
# Files that translate gamepad buttons into key events, and the per-panel key
# tables they read (`pad_keys()` returns the keycodes to synthesize).
KEYCODE_ALLOWED = re.compile(r'"(menu|cancel)":\s*KEY_ESCAPE|PadUI\.key\(|_key_for\(')
PRIVATE_SCALE = re.compile(r"\b(?:var|return)\b[^\n#]*(?:/\s*(?:600|800)\.0)")


def scripts(*roots):
    for root in roots:
        yield from sorted(root.glob("*.gd"))


class InputConventionTests(unittest.TestCase):
    def test_panels_use_the_cancel_action_not_the_escape_keycode(self):
        offending = []
        for script in scripts(UI, GAME):
            if script == INPUT_HELPER:
                continue
            for number, line in enumerate(script.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("#", 1)[0]
                if "KEY_ESCAPE" in code and not KEYCODE_ALLOWED.search(code):
                    offending.append(f"{script.relative_to(REPO)}:{number}: {line.strip()}")
        self.assertEqual(offending, [], "compare with UiInput.is_cancel(event) instead")

    def test_project_declares_both_actions_with_their_default_keys(self):
        settings = (REPO / "game/project.godot").read_text(encoding="utf-8")
        section = settings.split("[input]", 1)[1].split("\n[", 1)[0]
        cancel = section.split("remake_cancel=", 1)[1].split("remake_confirm=", 1)[0]
        confirm = section.split("remake_confirm=", 1)[1]
        self.assertEqual(re.findall(r'"keycode":(\d+)', cancel), ["4194305"], "cancel is Escape")
        self.assertEqual(re.findall(r'"keycode":(\d+)', confirm), ["4194309", "4194310"], "confirm is Enter and keypad Enter")


class ScaleConventionTests(unittest.TestCase):
    def test_scale_helpers_delegate_to_ui_scale(self):
        offending = []
        for script in scripts(UI, GAME):
            if script == SCALE_HELPER:
                continue
            lines = script.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if re.match(r"\s*func (_k|font_px)\(", line):
                    body = " ".join(item.strip() for item in lines[number + 1:number + 4] if item.strip())
                    if "UiScale." not in body:
                        offending.append(f"{script.relative_to(REPO)}:{number + 1}: {body.strip()}")
        self.assertEqual(offending, [], "a screen's _k()/font_px() must name a UiScale rule")

    def test_no_private_scale_ratio(self):
        """`var k := size.y / 600.0` and friends belong in UiScale."""
        offending = []
        for script in scripts(UI, GAME):
            if script == SCALE_HELPER:
                continue
            for number, line in enumerate(script.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("#", 1)[0]
                if re.search(r"\b(var|return)\s+(k|scale|ui_scale|_ui_scale|glyph_scale|factor)\b\s*:?=", code) and PRIVATE_SCALE.search(code):
                    offending.append(f"{script.relative_to(REPO)}:{number}: {line.strip()}")
                elif re.search(r"FONT_EM\[\d\]", code) and "UiScale" not in code and script.name != "interface800.gd":
                    offending.append(f"{script.relative_to(REPO)}:{number}: {line.strip()}")
        self.assertEqual(offending, [])

    def test_ui_scale_rules_are_the_only_definitions(self):
        text = SCALE_HELPER.read_text(encoding="utf-8")
        for name in ("fit", "by_height", "by_width", "by_min_side", "by_height_within", "canvas_height",
                     "font_px", "font_px_for_width", "dialog", "reading"):
            self.assertIn(f"static func {name}(", text)


if __name__ == "__main__":
    unittest.main()
