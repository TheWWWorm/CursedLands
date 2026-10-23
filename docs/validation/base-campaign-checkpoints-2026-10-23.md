# Base Evil Islands campaign quest checkpoints — 2026-10-23

This applies the [LiA campaign qualification](lia-campaign-checkpoints-2026-10-23.md)
approach to the original Evil Islands / Cursed Lands campaign. The inventory
contains **92 named campaign quests**: 44 on Gipat, 23 on Ingos and 25 across
Suslanger and the ending. All **28 installed optional side-quest archives**
are included separately. The other 17 of the 109 database records are unnamed
spacers, not invented playable quests.

**Result: all 36 base configurations pass with 8,408 checks. Four surrounding
regressions pass another 3,825 checks: 40 configurations and 12,233 checks total,
with no failures or engine errors. All four original references match in both
fresh-profile replays, including all 192 replay assertions.**

The [results manifest](base-campaign-checkpoints-2026-10-23/results.json)
records each selected configuration, check count, retained report/log and
source hashes. The [coverage inventory](base-campaign-checkpoints-2026-10-23/coverage.json)
maps every named quest to its fixture, original completion site and prepared
boundary. Its inventory alone is not passing evidence.

Results are selected per completed configuration across retained runs. App
restarts interrupted some bundles; those reports remain marked incomplete.
The manifest identifies each selected passing case and audits source reuse,
including seven Gipat cases whose differences affect only unexecuted functions.
Other fixture content matches, apart from a recorded final blank-line cleanup.
The final optional-quest runs use
clean local-main production source plus the portal-control fix. Older story
and map runs have documented differences in unrelated rendering diagnostics
and the inactive side-overlay path; no identical-source claim is made for them.

## Rerun

Use the [base-game quest command](../original-checkpoints.md#run-the-base-game-quest-checks):

```sh
BASE_GAME=/path/to/EvilIslands \
GODOT=/path/to/godot-4 PYTHON=/path/to/parity-venv/bin/python \
  tools/parity/run_base_quests.sh /path/to/NEW-results
```

It runs 36 base-campaign configurations, two surrounding side-quest/lever-save
regressions and four independently captured original checkpoints, each twice.
Reports retain isolated profiles, source and asset hashes, selections, logs,
saves and a reproduction command. Missing results, engine errors, failed
assertions and original-state differences remain failures.

## What the checkpoints establish

The loaded-map tests execute authored quest handlers using actual actors and
objects. Conversations use their topic and closing controls; required items
come from ordinary corpse loot or interactable use. Tests check acceptance,
missing prerequisites, objective and journal changes, rewards, selected real
travel transitions and continued progress after saving and loading. The last
route kills the actual final boss, reaches `EndofGame` once, then repeats that
ending from an earned living-boss save.

| Region | Campaign quests | Selected configurations | Main coverage |
| --- | ---: | ---: | --- |
| Gipat | 44 | 18 | Opening and village, witch, investigation alternatives, mountains, three queen poison sources, daughter, both departure orders, return from Ingos and four companion farewells. |
| Ingos | 23 | 10 | Arrival, dryad rescue and escort, both labyrinth gratitude orders, mine/departure, six treasures, all three mine approaches and three companion farewells. |
| Suslanger and ending | 25 | 4 | Prison and canyon, night escape, town, necromancer, alarms, mines and portal, return to Gipat, transformation and actual final boss/ending. |
| Optional side archives | 28 | 3 | Every installed archive: 12 Gipat, 6 Ingos, 10 Suslanger; acceptance, actual objective chains, rewards and partial/completed/rewarded saves. |
| Travel-map matrix | — | 1 | Exit gates, entrance choices, map picking, quest markers and settlement points. |

Negative controls include one surviving required enemy, missing keys or
hand-in items, an escort short of its destination, incomplete control sequences,
pending travel gates and repeated reward signals. Gipat reward windows separate
combat experience from the exact authored quest experience. Side-quest rewards
check exact money, experience delivery and duplicate-close prevention.

Movement and fighting are accelerated with teleportation, god mode, actor
deaths and a high interaction-skill fixture. Tests select relevant original VM
threads and pause unrelated ambient story activity. Later checkpoints prepare
declared prior offers, items and companions; they never assign the measured
quest's completion. These are **bounded completion regressions**, not one
uninterrupted playthrough, proof of continuous pathfinding/combat balance, or
every simultaneous quest and incidental dialogue permutation.

## Save/load repair

The optional portal-invasion quest `z19q3` needs both portal panels switched
from on to off. Its original multiplayer-map overlay marks those controls as
cycling. The same controls in the campaign map have a different rule for the
main portal quest.

After a partial invasion save was loaded, the remaining panel inherited the
campaign rule and could no longer be switched off. Overlay loading now
reapplies its cycling metadata **before** saved lever permissions are restored.
It preserves the earned panel states and permissions, and does not rerun quest
initialization. No save-format change is needed.

The regression earns the key from the commander's corpse, switches off one
panel normally, saves/loads, and verifies that the spent panel remains disabled
while the second remains usable. It repeats the load with legacy three-field
lever rows derived from that earned save, then uses the remaining panel and
completes the quest normally. Piggy Fivepence, GoGo and Junophile escort saves
also preserve the original faction, follow behavior and restored hero target.

## Original executable comparisons

Four references were captured from actual before/after saves made by the owned
original executable under Wine on a GPU Lab virtual display. The executable
SHA256 is `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
Dedicated profiles keep the cursor free, show FPS and mute all game audio.

| Reference | Measured original outcome |
| --- | --- |
| Gipat pyramid | Defeated shaman plus pyramid control completes `q5dg` and opens the smith report. |
| Ingos elder release | Prison control consumes the authentic key, completes rescue and starts the escort. |
| First Suslanger portal control | First panel advances `PState` to 1 and its objectives without completing the quest. |
| Second Suslanger portal control | Second panel advances `PState` to 2 and its objectives; portal approach is still required. |

These captures use explicit native console control-state operations. Their
before-state reconstruction declares supplied prior quest flags, keys,
defeated actors, god mode and recalculated mercenary topics. They therefore
compare the watcher results, not native mouse interaction or an uninterrupted
route. Loaded-map tests independently exercise normal use, loot and travel.
The replay compares entry state, exact quest/route-variable changes, declared
item/control observations, money, destination and repeatability. Expected
values come from the original saves, never the remake.

## Map coverage and explicit limits

The prepared map matrix checks **76 exits, 114 route choices, 20 island pieces,
91 quest markers and 6 settlement points**. It records final load requests;
it does not prove those prepared quest states were earned or every destination
scene was loaded. Actual quest routes test selected real transfers separately.
The absent `gz21g` asset and three edges with no incoming passage are classified
explicitly. The final Jun chamber `gz20g` is reached by story transfer and is
not given an invented selectable route.

The inventory records original quirks rather than manufacturing extra quests:
Ingos treasure `qk11k` is completed in zone 13 despite its zone-12 database row;
`Tr52` is a briefing accepting `q53k`, not a missing `q52k`; Suslanger `qh6h`
omits its active root flag but still completes; and `qk17h` has an inconsistent
approach marker while its real chest reward works. Uncalled Gipat legacy timer
roots have no corresponding quest records and are excluded.

Opening tutorial presentation/subobjectives, the optional wolf boar-luring aid,
both equivalent totem-report orders, every informational conversation and all
final companion permutations are not independently replayed. Rendering,
cinematics, sound, co-op, other platforms and arbitrary player-save collections
are outside this qualification. The already documented nonlethal city-alarm
escape repair is checked as remake behavior, not claimed as original parity.
