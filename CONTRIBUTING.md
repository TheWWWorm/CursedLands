# Contributing to Cursed Lands

Cursed Lands is a Godot 4.7 engine that plays the files of Evil Islands and
Lost in Astral. This page says how to build it, which checks run without the
game, which need owned game data, and what every change must include.

## Layout

| Path | Contents |
| --- | --- |
| `game/` | The Godot project: scripts under `game/src`, the single scene, fonts, icons and export presets |
| `game/src/native/` | GDExtension sources, prebuilt binaries and their notices ([build guide](game/src/native/source/README.md)) |
| `engine_patches/` | Patches for the Windows, Linux and Android export templates ([catalogue](engine_patches/godot-4.7/README.md)) |
| `tools/` | Python tools, the two Godot test runners, `tools/tests/` (Godot and Python tests), `tools/parity/` (original-engine comparison) |
| `docs/` | Guides and design notes, release notes under `docs/releases/`, validation records under `docs/validation/` ([index](docs/README.md)) |
| `web/`, `public/`, `worker.js` | The hosted browser version and its Cloudflare worker |

## Building

Open `game/` in Godot 4.7 and export with the included presets, as described in
[Building from source](README.md#building-from-source). The stock editor runs
the game from source; release packages use the patched templates.

## Checks that need no game data

Run these before every commit. They need Python 3.11+ and, for the parse pass,
a Godot 4.7 binary (the stock headless build is enough).

```sh
python3 -B -m unittest discover -s tools/tests -p 'test_*.py'
python3 -B -m unittest discover -s tools/parity -p 'test_*.py'
python3 tools/check_translations.py
python3 tools/check_issue_coverage.py
python3 tools/check_test_scripts.py --engine /path/to/godot --import-first
```

- The `tools/tests` modules test the Python tools and the regression runner,
  and `tools/tests/test_registries.py` lints both test registries: every
  registered script exists, prints its completion marker, resolves its
  `res://tools/` imports, avoids the `var x := weakref(...)` form that
  Godot 4.7 refuses to load, and is registered once per script, arguments,
  campaign, display and renderer (`tools/raise_min_checks.py` raises
  `min_checks` from green runs).
- The `tools/parity` modules test the original-engine comparison tooling. The
  families that emulate the original executable are skipped when the `unicorn`
  package is not installed.
- `check_translations.py` checks that every player-visible string has Russian
  and German text, including dynamically chosen keys and error messages.
- `check_issue_coverage.py` checks that every issue the changelog links has a
  registered regression test (`issues` in `tools/parity/gameplay_catalog.json`)
  or a reason in
  `tools/issue_coverage_exceptions.json`. A fix entry that links an issue must
  therefore register its test in the same change; the exceptions file lists the
  issues fixed before the registries recorded links, and an entry must be
  removed once a test covers it.
- `check_test_scripts.py` loads all test and benchmark scripts in one headless
  engine process, so parse and analysis errors surface in under a minute.

The same commands run in GitHub Actions (`.github/workflows/ci.yml`).

## Checks that need the game

Gameplay, interface and rendering regressions read the original game files, so
they run only on a machine with an owned copy of the GOG base game (and Lost in
Astral for the expansion cases). One registry,
`tools/parity/gameplay_catalog.json`, serves two runners:

- [`tools/check_regressions.py`](docs/regression-checks.md): the catalog
  entries that carry a `focused` ID, selected and reported by that short ID,
  with isolated profiles and retained evidence per case. Headless cases need
  only the engine; rendered cases need a display and are submitted to the GPU
  queue on the maintainer's workstation.
- [`tools/parity/gameplay.py`](docs/gameplay-testing.md): the full catalog,
  run in parallel with retained logs and reproduction inputs.

Both runners stage `tools/tests` next to the game so that `extends
"res://tools/tests/..."` resolves; never run a test script directly from the
source tree.

## What a change must include

- **A regression test in the same change.** For a bug fix, the test exercises
  the reported failure and fails on the unfixed code; register it in the
  gameplay catalog (with a `focused` ID when the focused runner should offer
  it) with the issue number in its `issues` list (`tools/check_issue_coverage.py` fails on a changelog
  issue without one) and run the related cases. When a report repeats an
  earlier one (posture transitions, game speed, corpse targeting, menu
  frames), add its trigger to that family's matrix test instead of a new
  single-cell test.
- **Shared interface conventions.** Screens take their scale from a `UiScale`
  rule and cancel/confirm from `UiInput` (the `remake_cancel` /
  `remake_confirm` InputMap actions), not from a private `size / 600.0` ratio
  or a `KEY_ESCAPE` comparison; `tools/tests/test_ui_conventions.py` enforces
  this.
- **Original-game evidence for behaviour fixes.** Compare with the original
  code or a run of the original game and record what was confirmed and what
  was inferred ([original parity](docs/original-parity.md)).
- **All three languages.** Every player-visible string, option label, help
  text and generated description needs English, Russian and German entries in
  `game/src/ei/remake_text.gd`, added in the same change.
- **Readable on high-resolution displays.** Interface changes are checked at
  1280×720, 2560×1440 and 3840×2160 in all three languages, with text
  rasterised at its displayed size.
- **A changelog line** under *Unreleased* in `CHANGELOG.md` and, for a
  release, notes under `docs/releases/`.

Versioning follows [docs/versioning.md](docs/versioning.md). Commits carry no
generated attribution lines.

## Reporting bugs

Open a GitHub issue with the package name and version shown in the main menu,
the platform, what you did, what happened, and a save or recording when you
have one. Issues in Russian are welcome.
