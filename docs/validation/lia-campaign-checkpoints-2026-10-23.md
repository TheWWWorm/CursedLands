# LiA campaign quest and travel checkpoints — 2026-10-23

**Follow-up:** the two inventory differences recorded below are resolved by the
[2026-10-24 party-inventory correction](lia-party-inventory-2026-10-24.md).
The original results below remain the historical qualification record.

This extends the [earlier prologue, fragment and Кель qualification](lia-kel-checkpoints-2026-10-23.md)
across Suslanger, Gipat, Ingos and Jigran through the campaign-ending trigger.
The focus is quest acceptance, objective transitions, required items, NPC
handoffs, route gates, usable map points and continuing after save/load.

**Result: 20 new programs pass with 6,600 checks. Together with the 14 existing
programs selected by the LiA command, 34 programs pass with 7,761 checks.** All
35 native references repeat consistently twice; 33 match completely and two
retain the inventory differences described below. Every captured quest-state
delta and destination matches. The native runner still returns failure for
those differences. See the [machine-readable results](lia-campaign-checkpoints-2026-10-23/results.json).

The final integrated run exposed an intermittent test setup problem before
Ingos's laboratory conversation: ticking Kel alone left his dialogue-return
controller frozen. The checkpoint now advances ordinary world simulation
until that return finishes, while asserting unchanged rewards and unaccepted
quest state. The repaired program passed all 240 checks in two fresh profiles.
The initial failed report is retained; it is not counted as passing evidence.

Five surrounding travel/side-quest programs also passed 650 checks, including
all 28 installed base side-quest archives. Untouched pending battle saves
created with the earlier remake passed a separate 103-check replay. The Python
runner/comparator suite passed 168 tests with one documented skip. Final
production-source and test-source hashes are retained with the reports.

## Rerun

Use the [single LiA quest command](../original-checkpoints.md#run-the-lia-quest-checks):

```sh
BASE_GAME=/path/to/EvilIslands \
ASTRAL_GAME=/path/to/LostInAstral-with-1.01-then-1.02 \
GODOT=/path/to/godot-4 PYTHON=/path/to/parity-venv/bin/python \
  tools/parity/run_lia_quests.sh /path/to/NEW-results
```

It selects the old `lia_kel_` programs, new `lia_campaign_` programs, existing
arrival/Revenge/Slave Lists return/tomb regressions, the interaction callback
check, and every `lia_` native checkpoint. Original checkpoints run twice in
separate profiles. Individual reports retain their exact selection, source and
asset hashes, logs, saves and a `reproduce.sh` command. Failed assertions,
engine errors and native differences remain failures.

## What the checks establish

The loaded-map programs execute the shipped quest handlers. Conversations use
their normal topic/closing controls; quest objects use ordinary interaction
commands; corpse items are actually looted. Selected transfers use exit
availability, confirmation, map selection and real destination loads.
Save/reload checks cover both pending objectives and completed handoffs.

God mode, teleportation and explicit combat shortcuts shorten traversal and
fighting. Programs start at declared chapter checkpoints, and select the
relevant original quest threads after binding map objects. A later chapter may
prepare an offer, item or party already earned in another program. These are
bounded regression checkpoints, not a single uninterrupted playthrough or an
exhaustive exploration of concurrent side quests, stealth/combat choices,
co-op, graphics, sound, platforms or arbitrary legacy player saves.

Native comparisons are a separate evidence class. Their expected before/after
values come from actual saves made by the patched original executable, never
from the remake. They compare quest/route variables, declared observations,
destinations and repeatability. The broader loaded-map programs do not become
native-executable comparisons merely because they run original quest scripts.

## Route coverage

| Region | Quest segments and boundaries |
| --- | --- |
| Suslanger | Existing prison/escape, Slave Lists and disguise; orchard; supply approach and Sheriff offer; letter and ambush; Shaina's solo infiltration, return and party restoration; blackmailer; optional caravan/document/captive branch; prisoner dungeon and return; Revenge; guide, nugget, rescuer/spear and siege; bones/boss; report, ritual, harpy and sack; northern arrival, clearance and island departure. |
| Gipat | Arrival, corpse key/papers, mine basket and return, hiding place, courier, harpy rescue; orc rescue, shell, battle, Rick and village liberation; hunters, both letter branches, caravan, needle/crypt and healer; gift, Witch/flower/ritual, camp/Palantir, knife and Babur escort; city attack, book, Palantir repair, golem controls, Rick departure and playable Ingos arrival. |
| Ingos | Arrival and laboratory, paired ingredients and ritual scene; investigation and camp handoffs; mine keys, doors and documents; the remaining portal preparations and departure. Existing fortune/fragment checks remain included. |
| Jigran | Arrival and first six quests, duel and party reconstruction, materials/documents/ingredients/meal/battle, survey/map/commanders/amulet, convoy and failures, Кель belongings/death/rescue, crypt, final meetings, final battle, portal scene, four ordered controls, boss completion and ending trigger. |

Negative controls include missing keys/items, one surviving enemy, one missing
ingredient or hand-in, an absent party member, a dead required actor, an escort
that has not reached its own destination, wrong control order and repeated
completion signals. Required rewards and next offers must remain blocked until
the relevant condition is met.

The [coverage inventory](lia-campaign-checkpoints-2026-10-23/coverage.json) maps
the quest IDs to programs and records each prepared chapter seam. `q10h` and
`fq1` are unused database records; `q01h` is an unreachable legacy branch with
a surviving map marker. They are excluded from playable coverage after auditing
the 130 map scripts and briefing rewards. The live prison escape starts `q02h`. Tests
also distinguish authored failed objectives from declared failure handlers that
the original never starts; no invented handler call counts as a passing route.

## Map and entrance matrix

The matrix exercises **110 exits**, **89 reachable route choices**, **25 island
pieces**, **118 quest markers** and **12 settlement points** across all four
region maps. It checks unavailable/available/completed gates, ordinary map
picking, offered entrance arrows, objective selection, stale/unoffered choices,
party eligibility and once-only dispatch. This matrix prepares quest/gate state
and records the final load command; it is not evidence of earning those states
or loading every destination. Loaded quest/travel programs test those aspects
separately.

The dormant `gz21k_gz23dk` edge has no active incoming passage in the shipped
map and is explicitly excluded from reachable choices. The map fixture also
records the exact absent assets `mov1`, `cz3h`, `cz4h`, `gz17g`, `bz15g` rather
than pretending to load them. Static quest-marker inventory includes keys from
maps outside the selectable island surfaces; only the 118 exercised markers
are counted above.

## Compatibility fixes found by these checks

**Jigran entrance numbering.** The original map parser appends exit records in
file order and ignores the header's numeric label. `gz33j` repeats `#exit 2`.
The remake keyed exits by that label, overwriting the west route and losing
arrival 3 from the spy settlement. The parser now preserves all three records.
Native code evidence at LiA `0x43a1a0`, plus actual native travel from `bz32j`
through the third map arrow, establishes the expected numbering. The remake
test performs that return, saves/reloads, then travels west to `gz34j`.

**Final-battle shared groups.** `AddMob("zone35battle.mob")` fills the parent
zone's `ArEvil` and `Kanians` groups. The remake renamed colliding globals, so
the parent saw an empty enemy group and could declare victory prematurely.
AddMob scripts now share and preserve parent globals, including on load;
ordinary side-quest overlays retain their isolated names. Tests require all 39
enemies alive and then the last survivor to keep victory blocked, including
after saving/reloading. Only the actual last death unlocks the next objective.
Independent native saves cover those same three states.

Pending stock LiA battle saves made by the earlier remake also restore the
two old group aliases into their proper parent groups. The migration checks
the campaign, zone, exact shipped source hashes, addon record, pending quest
state and complete 39-enemy/34-ally actor sets. Both untouched pre-fix saves
(all alive and only the final enemy alive) were loaded through the normal save
loader; last-death completion and saving the repaired state were verified.
It does not rewind a save that already advanced past a wrongly completed
objective or attempt a general mod migration. No release version or published
artifact is changed.

## Original installation and terminal evidence

Official patch 1.01 followed by 1.02 is applied in the isolated owned original
installation. All 17 patched-file hashes were reverified in both the asset
installation and the native test runtime. Native executable SHA256:
`9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`.

The native boss-completion save was taken during the original script's brief
delay before ending. Resuming it replaced gameplay with a black presentation
under Wine/Xvfb; Escape returned to the 1.02 main menu. Timed screenshots and
the linkage to the completed save are retained. This establishes the observed
terminal transition, **not that credits/video rendered correctly**. The remake
separately checks its actual `EndOfGame` event, ending state, disabled world
processing, once-only behavior and completion after loading a pending save.

Two strict inventory differences remain visible and continue to fail the
native comparator. During Shaina's return, the original temporarily keeps the
meteorite samples in her named-party bag until her report gives them to the
restored party; the remake's shared quest inventory exposes them immediately.
Her quest completion, party restoration and reopened passages match. The
earlier spent-fragment difference also remains: the original
restores three fragments from an archived named-party bag after Кель's rescue,
while the remake consumes them from its shared quest inventory. Rescue,
reunion and subsequent progression are tested separately from that strict
inventory comparison.

Profiles are isolated, cursor confinement is off, FPS is shown and all three
audio volumes are zero. Godot also uses the Dummy audio driver. Raw proprietary
assets and saves remain in local evidence storage; committed references contain
only observations, operations and provenance hashes.
