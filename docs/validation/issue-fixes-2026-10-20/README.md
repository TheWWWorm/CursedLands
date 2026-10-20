# Audit and GitHub issue follow-up — 2026-10-20

Local changes on `test/original-parity-20261020`, based on
`6a1c015963814557b220018eac2eeff7c6c14564`. No release, push, issue comment or
issue closure was made. The version remains 1.19.0.

The four causes identified by the earlier player-encounter audit have fixes.
The bounded original-executable comparison now has **594 matches and zero
differences**, including all five previously differing attack-probability
cases. This does not establish complete original-game equivalence.

The latest matching gameplay captures contain **131 configurations: 128 pass,
three fail, zero runtime errors**, with 184,759 assertions and 1,384 failed
assertions. All three failing programs concern ordinary campaign footprints
in the OpenGL compatibility renderer. See the [failure list](failures.md),
[per-configuration results](results.md), and [machine-readable evidence](report.json).
The catalog now contains 281 configurations, up from 259; this follow-up
does **not** claim a fresh run of all 281.

## Changes

- Loading-screen removal disconnects its viewport callback before releasing
  the rendering handles.
- Fresh co-op origin validation rejects non-boolean values without performing
  an invalid typed comparison.
- Solo Arena retains in-flight worker updates while paused and applies them
  after resume, preserving the order of boards, effects and results.
- Attack rolls and displayed hit probability retain the original distance,
  target-radius and action-rate adjustments, float stores and rounding.
- Equipment and attribute refreshes preserve the current animation, phase,
  transition state, dialogue state and seeded animation generator.
  Dialogue cleanup follows the unit's current figure.
  [#51](https://github.com/TheWWWorm/CursedLands/issues/51),
  [#56](https://github.com/TheWWWorm/CursedLands/issues/56).
- The journal includes accepted multiplayer contracts and their completed
  states. Base exits read the multiplayer destination variable with its
  required case.
  [#52](https://github.com/TheWWWorm/CursedLands/issues/52),
  [#54](https://github.com/TheWWWorm/CursedLands/issues/54).
- Cursor size supports automatic sizing and fixed 32/48/64 screen pixels.
  The player-status overlay can be hidden.
  [#55](https://github.com/TheWWWorm/CursedLands/issues/55),
  [#59](https://github.com/TheWWWorm/CursedLands/issues/59).
- Fitted item previews shrink large models without enlarging small models.
  Character creation heads use the fit option and a fixed camera covering
  their turning range.
  [#53](https://github.com/TheWWWorm/CursedLands/issues/53),
  [#60](https://github.com/TheWWWorm/CursedLands/issues/60).
- Camp and character lists share wheel, Shift-to-end and accelerating
  held-arrow controls. Camp selection outlines fade in and out. Duplicate
  bare prices are removed from item tooltips.
  [#57](https://github.com/TheWWWorm/CursedLands/issues/57),
  [#58](https://github.com/TheWWWorm/CursedLands/issues/58),
  [#60](https://github.com/TheWWWorm/CursedLands/issues/60).
- Arena fonts use distance-field rendering when the interface is scaled.
  [#43](https://github.com/TheWWWorm/CursedLands/issues/43).

New option labels, every choice and help text have English, Russian and
German translations. The existing default cursor scaling and visible status
overlay remain the normal player defaults.

## Validation

| Check | Result and scope |
|---|---|
| Original executable replay | 594/594 matching scenarios, 1,288 original observations, two repeat captures per implementation |
| Broad regression batch | 105 programs, 178,946 assertions, no failures; its intermediate source snapshot is retained |
| Earlier audit failures, final source | Both fresh-origin guards (76/75), loading-cover lifetime (6), and three-round Arena pause/lifecycle (569) pass |
| Equipment continuity | 56 assertions; original axe/armour, idle, movement, attacks, hit, cast, dialogue, complexion and frozen corpse poses |
| UI controls and journal lifecycle | 198 assertions, including the 28 installed optional-quest archives |
| Actual localized options, heads and rotating items | 1,055 assertions in each of EN/RU/DE; all available creation heads, six turns per head, four original item previews |
| Localization matrix | 14,640 assertions; runtime choice lookup included |
| Live original multiplayer | 35 assertions each for Gipat and Ingos; menu, separate worker, moving dialogue poses, figure refresh, quest acceptance, journal, exit state, travel and return to menu |
| Separate-worker animation response | 13 assertions; movement starts after 95 ms at both 1× and accelerated speed in this run; 38 moving preview samples and 33 shadow samples |
| Original Ingos mine | 39 assertions; paused commands and sustained simulation clock through a separate worker |
| Rabbit and other creature alerts | 20 assertions; original `HareF0` witnesses a nonfatal assault and its hostility reaches the compressed client snapshot |
| Stamina wait and acknowledgement | 47 local assertions and 14 network assertions |
| Presentation timing and network clock | 33 and 145 assertions; frog cast startup, delayed clips, stop transitions and accelerated time |
| Existing pause-menu checks | 21 clock assertions and 28 presented-frame assertions |
| Scaled Arena text | 32 assertions in each language; captured menus visually inspected |
| Python test harness | 55 tests pass |

Rows overlap the consolidated 131 configurations and must not be added
together. Selection retains the newest matching test/helper capture
regardless of whether it passes. Runtime errors and insufficient assertion
counts are rejected. Each retained log is re-assessed against the current
catalog minimum, and its hash, engine hash and declared original assets are
verified.

Production snapshots differ across capture batches. Their exact manifests
and differences from the final source are recorded in `report.json` and
`captures/`; the broad batch predates the final animation-RNG, scrolling,
portrait and option-localization refinements. Focused checks exercise those
later changes. Older audit reports and raw attempts remain unchanged.

The mine fixture loads the original `gz14k` location through `map.txt`
(`zone14.mpr` / `zone14.mob`), retaining its authored inhabitants. Its
8.01-second measurement intervals advance simulation by 7.975 seconds at
normal speed and 16.280 seconds at the original accelerated rate, 55/27.
Paused gait commands return in 25–47 ms. The first resumed clock update
takes 385 ms at normal speed and 16 ms at accelerated speed. These are
diagnostics, not a promise of zero command latency or hardware FPS.

### Original-code evidence

The native reference is the local executable with SHA-256
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
Attack analysis covers caller `0x553df0` and roll `0x555bd0`. The attack
corpus grew to 199 cases: the original 35 plus 164 distance, height,
use-radius, action-rate, aim and zero-spread boundary cases. The remainder
of the 594-case suite is retained.

The [native report](native/report.md) states each subsystem's supplied
boundaries and tolerances. Exact inputs and both pairs of raw traces are
retained as compressed JSON. The final combat source hash matches the
native capture. The REA analysis snapshot remains in the local raw capture
directory; no original executable or game assets are distributed here.

### Captures

- New settings: [English](images/options-en.png),
  [Russian](images/options-ru.png), [German](images/options-de.png).
- [Fitted creation heads](images/creation-fit.png) and
  [item preview sizes](images/item-previews.png).
- Arena text: [English](images/arena-en.png),
  [Russian](images/arena-ru.png), [German](images/arena-de.png).
- [OpenGL footprint failure](images/footprint-compatibility-failure.png).

The settings captures use the installed English original text archive plus
the selected remake language. Existing archive-owned labels therefore
remain English in some rows. The new and changed remake rows are translated.

## Remaining work and limits

Read [failures.md](failures.md) for the unresolved renderer failure and the
status of every open issue. Smooth sliding of list rows, complete menu
transition polish, reduced loopback latency and full reproduction of the
reported mine slowdown are not delivered in this batch.

The rendered runs use Linux, Godot 4.7, a private Xvfb display and Mesa
llvmpipe OpenGL. They do not qualify Windows, Vulkan/Mobile, Android, browser
exports, WAN/NAT play or an uninterrupted campaign. State assertions and
selected screenshots do not prove original animation or pixel equivalence.
All profiles are isolated, with a free cursor, FPS shown and all audio
muted. Player saves and normal preferences are not modified.

Several initial attempts exposed fixture errors: invalid example item IDs,
incorrect map filenames, missing scene-tree setup, a stale control method
name, premature loading-cover assertions, and the mine fixture toggling an
already-paused save back on. These attempts remain in the raw capture
directory and are not presented as product regressions. The current
footprint failures are retained as failures.

## Reproduction

Set `BASE_GAME`, `ASTRAL_GAME`, `GODOT`, `RENDER_DISPLAY` and optionally
`PYTHON`, then run `./reproduce.sh NEW_OUTPUT_DIRECTORY`. It replays the
selected 131 configurations against current source. A fresh output directory
is required. The three compatibility-footprint failures currently make
this selection return status 1.

For original-code comparisons, install `tools/parity/requirements.txt`,
set `BASE_GAME` and `GODOT`, and run
`./native/reproduce.sh NEW_OUTPUT_DIRECTORY`. This replays the retained
594 inputs twice per implementation.
