# Mechanisms, prison geometry and Autochess follow-up

This continues the [issue review](../issues-109-112-2026-10-24/issue-review.md),
[attack-path audit](../attack-path-snow-ui-2026-10-25/README.md) and
[reload/stutter investigation](../fps-stutter-2026-10-25/README.md).
It records bounded reproductions, original-code evidence and balance fixtures.
It does not certify every campaign, player save, driver or possible army.

## Moving mechanisms and overload recovery

Each lift position previously removed and added its navigation footprint,
rebuilt full connected-component labels for every cached movement class, and
walked all native topology blocks and cached label windows. Movement now replaces
the footprint atomically, refreshes the overlapping region once, and invalidates
only intersecting native windows. Legacy comparison labels rebuild when queried.
Packed-array edits also persist for movement classes first requested later.
Distant scripted teleports update two small regions rather than the rectangle
between them. Authored heights and door states remain authoritative.

| Authored mechanism | Previous median / maximum update | Changed median / maximum update |
|---|---:|---:|
| Portal `Lift#11`, eight prepared movement classes | 583.452 / 663.775 ms | 23.099 / 38.781 ms |
| Repeated door states, `gz1d2` | 4.678 / 10.999 ms | 1.866 / 2.972 ms |

These are mechanism-update costs from `tools/benchmarks/mechanism_pacing.gd`,
one script tick per rendered frame with unrelated world simulation held.
They are not full-game FPS or real-time lift journey measurements. The door
capture predates the final additional native-window optimization. Raw rows and
scope are retained in the four mechanism JSON files. Linux Vulkan jobs used
GPU Lab; native libraries also built for Windows and Android, without a new
runtime test of those two binaries.

Both worker and inline worlds now cap elapsed wall time before applying the
chosen game speed. A long stall cannot turn into seconds of NPC fast-forward.
Interrupted work inside a bounded callback still retains its fractional/debt
accounting. The overload test covers severe stalls, recovery, pause and both speeds.

Regression coverage includes authored lift/door routes, fresh movement classes,
disjoint teleports, local invalidation against a fresh graph, scalar/native
deferred labels, worker timing and existing dynamic topology tests. The old
native library fails 16 bounded-work assertions in the new 120-check test.

## Prison walls

The Aliya-rescue prison is `gz3d1` / `zone3dun1`. Its tall `stwa10` and low
`stbuho48` masonry overlap on the same plane. Static wall rendering now assigns
overlapping coplanar strips to the first face and clips the duplicate triangles,
interpolating normals and UVs. Original part metadata and collision boxes remain
the script/navigation authority; lever geometry is excluded.

The authored-map regression checks coverage independently with polygon
intersection and tests metadata and unrelated geometry. It passes 293 checks;
the old renderer fails the duplicate-surface check. Measured duplicate area falls
from 80.068321 to 0.001053 square metres (floating-point tolerance). Three camera
captures were inspected; [the retained view](prison-after.png) includes tall and
low walls.

## Autochess interface and networking

The multiplayer host/join rows repeatedly validated both installations during
drawing and hit testing. Validation now happens on menu entry. Reopening refreshes
availability. The 56-check test covers host/join, locked states, removed/restored
installations and EN/RU/DE. Twelve assertions fail on the prior implementation.
The local benchmark did not reproduce 6 FPS: host/join were about 40/52 FPS and
about 504/519 FPS after removing the repeated scans. These isolated uncapped menu
figures are diagnostic, not a promised frame rate on another system.

Reserves support click-to-move, swaps and dragging, including a full bench,
save/load, undo and online authority. Ordering reserves remains available during
battle; deployed actors cannot be withdrawn during battle. Existing item drops
and keyboard navigation remain covered.

Reward buttons lost their press when tiny pointer motion cleared GUI focus.
Focus is now released only when leaving keyboard/controller navigation. The
rendered test presses each of the three rewards, moves one pixel while held and
releases; all three fail before the fix and pass afterward. An ENet test checks
that a single choice grants exactly one item. Help and changed values have
English, Russian and German translations.

## Dead Deer original comparison

The LiA executable SHA-256 is
`f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff`.
Inspection of `0x4b5fd0` and `0x4aeac0` shows a legacy weapon attachment lookup,
then the unit's stored geometry centre for an unarmed nonhuman rig. This deer
has no `baserh3` attachment. There is no deer-specific mouth-origin branch in
that routine. `0x49f3f0` constructs the stored geometry union from pose origins
and FIG bounds; the separate world-transformed bounds routine is not substituted.

`tools/tests/replay_dead_deer_cast_source.py` executes the original x86 geometry
and source routines in Unicorn. It supplies only graphics mode and the absent
attachment lookup. All three authored deer at three headings and two cast poses
match, both as campaign figures and fitted Autochess figures: 36 assertions per
replay, zero differences. The Godot tests also check live acid-missile creation
and an offset arena board. No production cast-origin change was justified.
The oracle inputs and results are retained here; this is a bounded routine
comparison, not a full original-game replay.

## Autochess combat and balance

The design target is useful choices within a price tier, preserving different
roles and counters. Combat decisions now consider targets already within attack
range, allow a finishable enemy to outweigh a small current-target preference,
and reject spells when casting is blocked. Area casters respect Autochess's
existing ally-damage protection instead of refusing protected melee clusters.
Campaign scoring and friendly-fire precautions remain covered separately.

The exploding hare's single-use fire burst changes from 30/55/120 to 60/125/300.
Its 0.6-second fuse, 2.5-metre radius, three-target cap, low health and one-blast
limit remain. The regression uses actual damage against same-star armored
frontlines, tests survival, distant kills, ally safety, and repeated death/tick
notifications. The old implementation fails six of 29 checks.

The roster audit compares all 37 installed families at equal price in actual
combat, mirrored sides and two fixed seeds. Duels measure independence; `line`
adds two melee allies; `screen` adds two ranged/caster allies. Formations and
role asymmetry matter, so a poor duel result alone does not trigger a buff.
The retained compressed JSON files include every outcome, damage, duration and
survivor. They are controlled diagnostics, not player win-rate estimates.

The complete final matrix contains 4,428 fights across all three stars. The
last wolf adjustment replays its 252 affected fights; `balance-summary.json`
replaces only those pairings. Other pairings use only unchanged base-family
supporters, so their results remain applicable. Before/after experiments total
9,600 fights, excluding additional regression and integration fixtures.

| Recruit | Autochess tuning | Observed reason |
|---|---|---|
| Goblins | Damage factor 0.94 → 1.10 | Weak even behind a frontline; protected opening points improve from 37.5% to 44.6% after the AI-only comparison. |
| Elementals | Health factor 1.20 → 1.40 | A costly tank needs time to protect its back line; opening `screen` points improve from 31.2% to 41.7%. |
| Jigran wolves | Health 0.96 → 1.08; damage 1.18 → 1.32 | Health alone did not improve opening team results; damage raises `line` points from 14.3% to 28.6%. |
| Jun lizards | Health factor 1.28 → 1.45 | The guardian was too short-lived in its intended formation; opening `screen` points improve from 10.4% to 45.8%. |

Percentages count a draw as half a point in the stated small, mirrored fixture.
They do not express online win rates. The opening viability regression uses
every same-price opponent and both seeds, requiring useful protected goblin
output and a conservative floor across both team formations for the three
melee families. It deliberately permits losing matchups. The all-star audit,
source-data immutability, promotion, armor limits and deterministic combat
checks provide separate coverage. Dragons and other contextual performers
retain their existing numerical budgets; the AI fixes themselves help area
casters and support hybrids.

## Reproduction and regression policy

Final acceptance results:

| Group | Result |
|---|---:|
| Focused headless suite | 34 cases, 6,466 checks, zero failures |
| Additional registered opening-viability case | 186 checks, zero failures; four failures on the AI-only build before stat boosts |
| Rendered bench and first-click reward cases | 43 checks, zero failures |
| Existing equipment UI input case | 89 checks, zero failures |
| Eleven related gameplay/navigation suites | 31,146 checks, zero failures |
| Original deer routine replay | 72 checks, zero differences |
| Gameplay runner / focused runner Python tests | 33 / 7 tests, zero failures |
| Translation coverage | 3,523 entries, zero errors |

The related suite includes the final native navigation library. Its expansion
combat case was rerun successfully after the last wolf damage adjustment.
`final-source.json` records the final code. The focused runner's aggregate hash
records its start; the later wolf adjustment has its separate matrix, packaged
artifact hashes and registered opening-viability result. GPU captures and native
builds retain the platform limits described above.

Every fix or feature now requires a regression test in `AGENTS.md`, including
demonstration of the prior failure for fixes and related existing checks.
Cases are registered in both `tools/regressions.json` and the gameplay catalog.
The gameplay runner now declares, validates, hashes and passes companion LiA
data for base-game Autochess tests, and stages their benchmark dependencies.
Its Python checks cover absent installations, paths with spaces and invalid
asset paths. `gameplay-runner-results.json` records successful staged execution.

Run the commands in [regression-checks.md](../../regression-checks.md) with the
owned base and LiA installations. Use an editor-capable Godot executable for
the source runners; packaged game executables intentionally reject `--path`.
Rendered checks must run through GPU Lab. No player profile was changed.
