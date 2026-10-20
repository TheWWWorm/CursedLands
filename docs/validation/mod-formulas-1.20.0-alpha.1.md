# Mod preview validation — 20 October 2026

Base: stable 1.19.0, source checkout `50fd5b06`. Feature branch:
`feat/mod-api-20261020`. This record covers the first desktop preview, not a
claim of full Jamais Vu compatibility or a completed campaign soak.

## Source runtime checks

All 11 selected runs passed: **478 assertions, zero failures or script errors**.
Detailed results are in [the JSON record](mod-formulas-1.20.0-alpha.1.json).

| Suite | Checks |
| --- | ---: |
| Formula packages, isolation, actual rewards/revival, source identity, saved options, failure containment, return to vanilla | 106 |
| Existing experience distribution and debt | 96 |
| Existing profile/save/API 1 boundaries | 87 |
| Existing API 2 texture packages | 43 |
| Authored-world damage, sandbox and original recovery mod | 12 |
| Actual separate simulation process with API 1 recovery mod | 25 |
| Actual separate simulation process with API 3 formula mod | 25 |
| ENet formula host, matching client and rejected client | 19 + 16 + 8 |
| Rendered mod/settings menus, EN/RU/DE, keyboard/controller and sizing | 41 |

A fresh vanilla process was checked before any native Lua library was loaded.
Ordinary rewards created no Lua VM; switching back from script mods retained
ordinary behavior and original save bytes. Script packages with invalid results,
NaN, out-of-range values, unbounded loops and large allocations were contained.
Missing functions and cyclic modules refused activation. Partial experience
chains did not commit and failed saves did not change existing files.

The real ENet test loaded the village on both peers, changed a host option,
awarded experience, saved the campaign, propagated a deliberate failure and
checked stopped simulation plus campaign/returned-progress save guards. The
client executed no gameplay callbacks. The worker tests authenticated an actual
child process and saved/reloaded effective settings.

Translation audit: 2,867 remake entries, 141 dynamic wiki keys, 179 dynamic arena
keys; no missing entries or placeholder errors. API 3 validates all example
titles, descriptions, labels and help in English, Russian and German. Rendered
menus were checked at 1280×720 and 540×960; representative captures:

- [English settings](mod-formulas-1.20.0-alpha.1/formula-en-options-1280.png)
- [Russian installed mods](mod-formulas-1.20.0-alpha.1/formula-ru-mods-1280.png)
- [German narrow settings](mod-formulas-1.20.0-alpha.1/formula-de-options-540.png)

All sessions used isolated profiles with cursor confinement disabled, FPS
enabled and all three game volume channels muted.

## Build and coverage limits

The Lua helper was built for Linux x86-64 and Windows x86-64 from the same
source and pinned godot-cpp revision. Desktop export results are recorded
separately after testing the exported executables.

Android, macOS and browser script execution are intentionally unavailable;
their existing non-script mod paths were not rebuilt in this preview. There is
no native Windows hardware qualification or long campaign soak in the source
checks above. Formula API 1 has no retained script state, arbitrary engine
hooks, original DLL compatibility or DLL conversion.

The first runtime test found that Godot dictionary keys may be `StringName`;
the plain-data boundary was corrected to accept them as strings. An additional
revival test initially inspected the active order before its simulation tick;
the assertion was corrected to inspect the queued order. Final selected runs
include both corrections.
