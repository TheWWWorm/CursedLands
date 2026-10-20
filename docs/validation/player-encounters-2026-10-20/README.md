# Player-encounter audit — 2026-10-20

**259 configurations: 255 passed, one assertion failure, three runtime errors.**
They report 223,855 completed checks, including three failed assertions. The
separate original comparison records 425 matches and five differences out of
430 scenarios. The collection is complete; its overall result is **error**.

Read the [failure list](failures.md) for the two confirmed runtime defects,
the unresolved Arena pause-timing failure, and the original hit-probability
differences. [report.md](report.md) contains every configuration and
[features.md](features.md) maps checked player functions and remaining gaps.

## Coverage added

The catalog grew from 101 to **259 configurations across 19 areas**, using
205 scripts. Of the 158 additions, 150 register existing standalone programs
and their campaign/language variants. Five new scripts supply eight more
configurations:

- Theft: actual approach/use completion, quest pockets, cancellation, death,
  target removal, ownership, hostility and persistence in both campaigns.
- Optional quests: eligibility, acceptance, completion, exact rewards,
  repeated callbacks and disk persistence for all 28 installed base archives.
- Camp actions: nine recipe/material combinations per campaign, construction,
  dismantling, fees, stale/missing inputs, weapon/spell capacities and saves.
- Travel: authority dispatch, confirm/cancel, stale selections, death, owner
  permissions, once-only time charges and deferred destination arguments in
  both campaigns. Separate network fixtures perform actual world transfers.
- Localization: 14,538 checks covering remake option labels, help, choices,
  nonempty EN/RU/DE translations and format argument compatibility.

The feature inventory covers 35 groups and accounts for all 48 verbs in the
campaign authority dispatchers. That is **not exhaustive function, path,
platform or original-game coverage**. The report states gaps explicitly.
There are 232 headless and 27 rendered configurations. Rendered tests use a
private Xvfb display with real OpenGL/Mesa llvmpipe, never the user's desktop.

| Area | Configurations | Pass | Fail | Error | Reported checks |
|---|---:|---:|---:|---:|---:|
| animation | 9 | 9 | 0 | 0 | 2,694 |
| arena | 21 | 20 | 1 | 0 | 8,338 |
| combat | 4 | 4 | 0 | 0 | 9,052 |
| commands | 14 | 14 | 0 | 0 | 2,764 |
| coop | 48 | 46 | 0 | 2 | 1,667 |
| creatures | 12 | 12 | 0 | 0 | 25,192 |
| dialogue | 11 | 11 | 0 | 0 | 290 |
| effects | 11 | 11 | 0 | 0 | 73,698 |
| interface | 9 | 8 | 0 | 1 | 3,724 |
| inventory | 26 | 26 | 0 | 0 | 4,323 |
| network | 3 | 3 | 0 | 0 | 251 |
| party | 3 | 3 | 0 | 0 | 57 |
| pathing | 14 | 14 | 0 | 0 | 43,249 |
| persistence | 12 | 12 | 0 | 0 | 195 |
| progression | 5 | 5 | 0 | 0 | 345 |
| quests | 27 | 27 | 0 | 0 | 1,438 |
| settings | 14 | 14 | 0 | 0 | 15,564 |
| spells | 8 | 8 | 0 | 0 | 27,898 |
| stealth | 8 | 8 | 0 | 0 | 3,116 |

## Evidence and reproduction

This is a consolidation of **161 freshly captured configurations and 98
retained configurations**, not one fresh run of all 259. Retained results are
accepted only after matching test/helper hashes, campaign, arguments and
execution mode. Every selected raw log is reassessed against the current
minimum check threshold. Selection uses the latest matching capture,
regardless of whether it passes. Original raw reports remain unchanged.

All 1,074 production files, the engine binary, and 113 declared required
assets were rechecked. Production digest:
`d7cf76efc45d6d78c8335f449d3ab7bd65b758dd9d938192989579f59f8ce652`.
The native replay also matches every production file; its 199 additional
files are engine-generated `.import` metadata from staging the imported
snapshot. No production gameplay code was changed.

The machine-readable records are [report.json](report.json),
[validation.json](validation.json), [selection.json](selection.json), and
[junit.xml](junit.xml). Runtime failure logs are retained in [logs/](logs/).
Every result includes its capture path, log hash and selected dependencies.
Local `qualify_encounters.py` verifies and consolidates these inputs.

[reproduce.sh](reproduce.sh) reruns this selection against current source.
Set `BASE_GAME`, `ASTRAL_GAME`, `GODOT`, `RENDER_DISPLAY`, and optionally
`PYTHON`, then supply a new output directory. The native comparison requires
the dependencies in `tools/parity/requirements.txt`. See the
[runner guide](../../gameplay-testing.md) for filtering, private X server
setup and expected exit statuses. Current full runs return 2 because runtime
errors remain; the original comparison alone returns 1 for mismatches.

## Verification of the tests

All **55 Python harness tests pass**, including rejection of wrong display,
wrong campaign, missing summaries, incomplete captures and runtime errors.
The final cross-check also caught and repaired a reporting bug: feature-level
counters had overwritten the JUnit suite totals. The retained raw captures'
JSON and individual JUnit cases still contain their failures, but the early
JUnit header totals should not be used. This consolidated JUnit has been
checked against JSON: 259 cases, one failure and three errors.
Two faults deliberately injected into a separate source copy produced the
expected failures in an isolated negative-control run:

| Injected fault | Checks failing |
|---|---:|
| Disable the active-briefing guard, allowing repeated reward completion | 56 |
| Change a Russian numeric format argument from `%d` to `%s` | 1 |

The initial reward oracle checked only money and missed zero-money quests.
It was strengthened to check XP dispatch and dialogue-close events; the
rerun catches duplicate completion. The unmodified-source versions pass.
No injected production changes were applied to the working tree.

## Limits

All runs use isolated profiles with a free cursor, FPS enabled and muted
Dummy audio. They do not overwrite player saves or preferences. Network
checks use loopback peers; they do not establish WAN/NAT/browser behavior.

Animation/effect state tests do not prove original rendered pixels. Selected
localized option captures were visually inspected, but this is not a review
of every screen; original labels still use the installed English archive.
Mod distribution and other operating systems have no configurations here.
No uninterrupted whole-campaign playthrough or exhaustive quest graph is
claimed. The bounded native replay executes original x86 instructions with
its declared supplied boundaries, not the complete original game.
