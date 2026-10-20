# Quest progression comparisons — 20 October 2026

**All 4,373 original-versus-remake scenarios match**, with two identical
captures per side. This expansion adds **862 scenarios**, including **360
additional condition lists from the original campaign files**. Every one of
those 360 lists is observed both blocking and firing under the supplied inputs.

| Reference | Scenarios | Matching | Differing | Observations per capture | Authored lists | Maps represented |
|---|---:|---:|---:|---:|---:|---:|
| Base game | 2,581 | 2,581 | 0 | 15,761 | 1,092 | 70 |
| Lost in Astral | 1,792 | 1,792 | 0 | 16,209 | 989 | 123 |
| Total | 4,373 | 4,373 | 0 | 31,970 | 2,081 | — |

All 3,511 scenarios from the previous validation remain present with unchanged
original observation hashes. Quest observations compare exactly; the legacy
clock and hit-probability families retain their documented numerical tolerances.
No comparison tolerance was widened.

The [failure disposition](failures.md) lists all 84 newly detected and resolved
scenario/reference pairs. These repeat several causes in two executables; they
are not 84 distinct player bugs. [All scenario results](scenario-results.json)
retain observation hashes, and the [validation receipt](validation.json) records
source identities, contracts, repeated captures, coverage outcomes and local
reproduction paths.

## Additional quest coverage

- **Time and money gates:** native `GetWorldTime` and `GetMoney`, including
  dawn/night boundaries, exact purchase thresholds, absent players and float32
  conversion of large balances. Authored conditions retain their own thresholds.
- **Item requirements:** native `HaveItem` bag traversal with absent, present,
  duplicate and unrelated item IDs. Tests include acquire/consume/reacquire
  snapshots and attempts to query a missing player's inventory.
- **Object state:** `WasLooted`, `IsUnitBlocked` and `GetZ`, with live/dead/missing
  units, independent loot/block flags, supplied terrain and map-object offsets.
- **Persistent command bodies:** 61 scenarios per campaign execute native
  assignments, `Sleep`, `SleepUntil` and `KillScript` across consecutive logic
  ticks. They cover zero/negative/fractional delays, chained waits, changing a
  delay while asleep, initially true conditions, ordered global assignments,
  and commands after a script marks itself for removal.
- **Authored prerequisites:** environment samples include mixed flag values.
  A completed prerequisite, active quest and unused dialogue can require `2`,
  `1` and `0` simultaneously. The first sampling pass left 28 new gates always
  false; the final fixtures exercise both outcomes for all 360 additions.

The 360 new authored lists comprise 109 base-game and 251 Astral lists. They
include 245 time gates, 62 money gates, 51 item gates, one loot gate and one
height gate. Existing predicate, area, group, combat, path, body and effect
comparisons continue to pass.

## Causes fixed

**Script waits now follow the original command dispatcher.** `Sleep` rounds its
float32 argument to the nearest integer with ties to even, advances once per
delivered logic tick, and reevaluates its expression while waiting. Zero,
negative and rounded-to-zero delays continue in the current tick. This removes
extra pauses, fractional-delay differences and floating-point deadline drift.
An already-true `SleepUntil` also continues immediately.

**Missing-player item queries return false.** The script builtin checks that
the requested player exists before consulting the session inventory. It no
longer reads the local quest bag for an absent player.

**Missing-object loot queries match the original.** `WasLooted` returns true for
a null or removed reference. This remains separate from `IsDead`, which still
requires an actual dead unit. Tests cover null, freed, live and retained looted
actors.

Saved script instances retain the pending delay expression and elapsed run
count in optional `sc` and `st` fields. The previous remaining-seconds field
`w` remains available, and saves that contain only that field still load and
resume. A legacy save cannot recover the original delay expression or exact
run count that its format never stored.

## Verification

The rollback control restores only `game/src/game/script/vm.gd` from
`db43e9bc` in a private game copy. The new 251-scenario selection produces
**42 differences in each campaign**, verified with two captures per side.
All 502 original observation hashes are unchanged in the fixed captures;
all 84 differing cases now match.

The Python harness has **91 passing tests**. New negative controls reject
truncated command traces, missing globals or expression observations, invalid
float32 bit fields and non-boolean completion flags. Sampling tests verify
authored threshold neighbors, item combinations and mixed quest prerequisites.

The new parser/save regression performs **56 checks in each campaign**,
covering reload during a wait, changed delays after reload, immediate and
delayed conditions, completion after `KillScript`, and legacy save fields.
The broader selection finishes with **52 passing configurations and 2,018
checks**: 30 quest, 11 dialogue and 11 persistence configurations. The result
uses the latest completed run of each configuration; the initial fixture
failure and corrected rerun remain recorded separately in
[gameplay-results.json](gameplay-results.json). These are remake regressions,
distinct from original-executable parity.

The original story-effect fixture advanced the VM clock without delivering
the intervening cooldown ticks. Its acid-trap and shrine assertions failed
after waits began counting actual runs. The fixture now delivers all 25 and
40 ticks and adds checks against early resumption. The original outcome
assertions remain intact; the corrected fixture passes **169 checks**. Initial
results and the corrected rerun are retained in the gameplay receipt.

Earlier adapter-development errors remain diagnostics: the initial global
assignment fixture reversed two parameters, and two inventory/height captures
had incomplete session/navigation setup. None is counted as an original-game
behavioral mismatch or as passing evidence.

All development profiles are isolated, keep the cursor free, show FPS and mute
all audio. No player-visible strings or release metadata changed.

## Reproduction and limits

Use [the comparison runner setup](../../original-parity.md), then run both
campaigns with `--authored-quests --quest-limit 0 --repeat 2`. The qualified
captures are retained locally as `base-qualified` and `astral-qualified` under
the work directory recorded in `validation.json`; each has a `reproduce.sh`
that accepts a fresh output directory and an optional case filter.

The gameplay selection uses `tools/parity/gameplay.py` with both installation
paths and `--category quests --category dialogue --category persistence
--display headless --no-original`. The corrected fixture uses
`--case quests/story_coop_effects --display headless --no-original`.

Original executable SHA-256 identities remain:

- Base: `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`
- Astral: `f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff`

Native captures use Unicorn 2.1.4 with x87 control word `0x027f`. Static Ghidra
analysis is recorded separately from executed observations. Original binaries,
assets and decompiled source are not committed.

These comparisons exercise controlled states, not complete quest playthroughs.
Quest bags are supplied and owned-unit inventory is empty; native bag traversal
runs, but item transfers and carried-unit inventory are not qualified here.
Ground heights are supplied rather than queried from native terrain. Authored
condition trees remain unchanged, while actors, flags and environment values
are fixtures, not proof that each state is reachable in a real save.

Command comparisons start one already-running body. Native thread-list
scheduling, spawning, reward delivery, original save serialization, dynamic
actor/group construction and full campaign completion remain outside scope.
Unsupported authored condition lists remain visible in the source audit.
