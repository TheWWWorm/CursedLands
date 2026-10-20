# Remaining failures and issue status

## Current automated failures

| Configuration | Checks | Failed checks | Finding |
|---|---:|---:|---|
| `effects/footprint_surface` | 688 | 686 | No visible footprint pixels on original village soil at any of the 14 tested camera angles in OpenGL |
| `effects/footprint_surface_enhanced` | 688 | 686 | Same absence with enhanced terrain/ground options |
| `effects/running_footprints` | 15 | 12 | Native footfalls generate marks, but no visible trail is found in the 12 image comparisons at 1×/2× |

These are three programs exposing one renderer limitation, not 1,384
independent bugs. Campaign `GroundMarks` uses `Decal` nodes, which the
compatibility renderer does not draw. Arena has a separate texture-composite
fallback in `ArenaWinterTerrain`; ordinary campaign terrain does not.
The rendered image and failure logs confirm the missing marks.

This is a broader OpenGL absence than
[#29](https://github.com/TheWWWorm/CursedLands/issues/29)'s reported clipping
while running. It does not establish the cause of that recording on another
renderer. No footprint production change or closure is claimed. A campaign
fallback needs terrain and walkable-object receivers, fading, blood/scorch
marks, soft ground and scene cleanup to be qualified together. The older
[Vulkan investigation](../campaign-issues-28-29-20261018.md) remains separate
evidence and is not substituted for this failed run.

## Earlier audit failures

| Earlier failure | Current status |
|---|---|
| Resizing after the loading cover is freed | Callback lifetime fixed; rendered lifetime test passes |
| Malformed fresh co-op origin in both campaigns | Strict boolean validation fixed; both campaign tests pass |
| Arena board updates advancing while paused at 2× | In-flight packets retained until resume; three-round worker test passes |
| Five original attack-probability differences | Distance/action/radius terms and original rounding restored; full 594-case comparison matches |

## GitHub issue inventory

The open issue list was read again on 20 October 2026. No comments, labels,
releases or issue states were changed.

| Issue | Status in this batch |
|---|---|
| [#60 — interface animation and consistent scrolling](https://github.com/TheWWWorm/CursedLands/issues/60) | Partial: selection fade, shared wheel/Shift/held-arrow controls and fitted creation heads implemented. Smooth row sliding and general transition polish remain. |
| [#59 — local ping and overlay](https://github.com/TheWWWorm/CursedLands/issues/59) | Partial: translated overlay option added. The measured response includes local process/frame scheduling; no synthetic zero-ping value or latency fix was introduced. |
| [#58 — duplicate tooltip price](https://github.com/TheWWWorm/CursedLands/issues/58) | Duplicate bare price removed. |
| [#57 — Shift-to-end and held scrolling](https://github.com/TheWWWorm/CursedLands/issues/57) | Shift-to-end and accelerated held repetition implemented and tested. Smooth row sliding remains. |
| [#56 — speech animation](https://github.com/TheWWWorm/CursedLands/issues/56) | Dialogue survives figure refresh and releases the current figure on close. Actual Gipat/Ingos conversation phases advance through worker snapshots. Full native gesture/video parity is not established. |
| [#55 — cursor size](https://github.com/TheWWWorm/CursedLands/issues/55) | Automatic and fixed 32/48/64-pixel choices implemented with EN/RU/DE labels, choices and help. |
| [#54 — closed base exit colour](https://github.com/TheWWWorm/CursedLands/issues/54) | Case-sensitive destination-variable lookup fixed. Gipat/Ingos are red before acceptance and open afterwards. |
| [#53 — item fitting](https://github.com/TheWWWorm/CursedLands/issues/53) | Fit mode no longer enlarges small previews; rotation bounds checked. Fit-off retains fixed scale and can overflow, now stated in help. Exact native fit-off framing is not certified. |
| [#52 — multiplayer journal](https://github.com/TheWWWorm/CursedLands/issues/52) | Optional quest lifecycle included; all 28 installed archives plus two real multiplayer flows pass. |
| [#51 — interrupted animations](https://github.com/TheWWWorm/CursedLands/issues/51) | Gear/stat refresh retains clip, phase, blends, dialogue state and animation RNG. 56 targeted assertions pass. |
| [#48 — animation, speed, stamina and rabbit follow-up](https://github.com/TheWWWorm/CursedLands/issues/48) | Existing timing, accelerated-clock, aimed-stance and stamina behaviour checked; explicit rabbit nonfatal-witness case added and passes. Full interactive reproduction of every sub-report remains. |
| [#47 — mine slowdown](https://github.com/TheWWWorm/CursedLands/issues/47) | Original mine clock runs near requested 1× and 55/27 rates in the new worker fixture. The severe movement slowdown is not reproduced; the reporter's affected save and hardware remain untested. |
| [#45 — frog spit discontinuity](https://github.com/TheWWWorm/CursedLands/issues/45) | Deferred-time/cast-start regression passes. The entire reported visual sequence has not been matched against the original. |
| [#43 — distorted Arena text](https://github.com/TheWWWorm/CursedLands/issues/43) | Distance-field fonts implemented; actual scaled EN/RU/DE menus pass and were visually inspected on Linux/OpenGL. Windows remains untested. |
| [#42 — command and combat timing](https://github.com/TheWWWorm/CursedLands/issues/42) | Simplified worker movement responds in 95 ms in both speed modes. The full-mine first resumed clock update takes 385 ms at 1×. No zero-latency or complete hit/death/video equivalence claim. |
| [#29 — footprints](https://github.com/TheWWWorm/CursedLands/issues/29) | Unresolved. Current OpenGL tests expose missing campaign footprints; the running-only clipping report is not reproduced on its original platform/renderer. |
| [#20 — pause-menu animation frame](https://github.com/TheWWWorm/CursedLands/issues/20) | Existing clock and presented-opening-frame regressions pass. No new production change or verification of every nested menu transition in this batch. |

The remaining automated failure count is deliberately nonzero. The
local fixes are reviewable, but this is not an all-issues-resolved release.
