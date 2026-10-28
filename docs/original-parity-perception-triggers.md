# Perception-driven quest triggers (`perception_triggers`)

Extension family of the [original-engine comparison suite](original-parity.md).
Files: `tools/parity/cases_ext_perception_triggers.py`,
`native_ext_perception_triggers.py`, `remake_ext_perception_triggers.gd`,
`test_ext_perception_triggers.py`.

Authored base-campaign triggers decide "an NPC notices the heroes" with these
condition shapes (79 condition lists in this installation's MOBs; counts are
conditions):

| Count | Shape |
|---|---|
| 33 | `GroupHas(PlayerSee(0), x)` |
| 13 | `GroupSize(GroupCross(UnitSee(npc), Heroes))` |
| 13 | `GroupSize(GroupCross(PlayerSee(0), g))` |
| 11 | `GroupSize(GroupCross(GroupSee(g), Heroes))` |
| 6 | `GroupSize(GroupCross(GroupSee(Heroes), g))` |
| 2 | `GroupHas(GroupSee(Heroes), x)` |
| 1 | `GroupSize(GroupCross(Heroes, GroupSee(g)))` |

`IsUnitVisible` (0xe5) is what level-editor `QObjSeeUnit` objectives compile
to (14 base uses).

## How the original decides

* `UnitSee` (0x5d) / `GroupSee` (0x5e), group evaluator **0x4b5b00**: for each
  watcher (any actor of type 0x50 with a logic record at +0x240 — *no death
  test*) every node of its AI **noticed list** (logic +0xa94, nodes
  `[next, prev, actor]`) is inserted with **0x4b2ef0** into a temporary group
  from the context pool (+0x1b0). Groups are sorted pointer sets; insertion
  removes duplicates.
* `PlayerSee` (0xa5): copy of the player's extra-visible group
  (`player+0x20 → +0x50f8`, filled by Clairvoyance 0x682610), then every
  unit in the player's unit map (`player+0x40`) and its noticed list. Corpse
  lists are **not** read.
* `IsUnitVisible` (0xe5), evaluator **0x4b41e0**: membership in the player's
  visible group (`player+0x20 → +0x510c`), rebuilt by **0x66e0f0** from the
  extra-visible group, the player's units, their noticed lists **and their
  corpse lists** (logic +0xab0; 0x66e0f0 also replaces every party member's
  corpse list with the party's union).
* `GroupCross` 0x4b2b60 / `GroupAdd` 0x4b2620 / `GroupSub` 0x4b2920 are
  sorted-merge set operations on those groups.
* The noticed list is maintained per AI tick by **0x5caa00** (called from
  0x5cb700 with `ECX = 0x7b2788`, `param_1 = logic`, `param_2 = logic+0xa50`):
  a dead entry moves to the corpse list ("sees corpse of unit") and leaves the
  noticed list; a living entry is dropped ("lost from sight unit") only when
  it is not hostile-to-an-NPC (0x530150 masks +0x244/+0x248) or the watcher
  is a party unit (0x5301a0), it is not fighting the watcher, it is beyond
  both `vis·factor·detect·sight·f` and `lifeDetect·life·f` (f = 1.05 for
  NPCs, 3D distance), and it is not the Aggression target (0x5d5f20). Then
  **0x5ca5a0** scans candidates: an NPC considers living hostile/party units
  and dead others; sight needs 2D distance ≤ the sight product, the cone
  (`dot ≥ cos(half)·d`, facing from 0x5ca410) and `ray·sight > d`
  (0x5bc3e0); otherwise peripheral vision (`dot ≥ +0`, `d < +0x228`,
  **without a ray test**); otherwise life sense for living targets. New
  entries are pushed at the list head; dead ones go to the corpse lists.
* 0x552300 runs the AI (0x5d53b0 → 0x5cb700 → 0x5caa00) only while actor
  +0x274 (death flag, set by 0x546720 from 0x553ac0) is 0, so a dead watcher's
  list is not updated afterwards; no clearing of +0xa90 was found in the death
  path's direct callees (not exhaustively proven).

## How the remake decides

`ScriptVM` (`game/src/game/script/vm.gd`) never reads `UnitAI`'s noticed
list. `UnitSee`/`GroupSee` call `_sees` → `_noticed(w)`, which recomputes
perception from geometry on every call: every unit within `w.stats.sight`
(`_units_within`, living or dead) that `UnitAI.can_notice_with` accepts. Dead
watchers are skipped. `PlayerSee` and `IsUnitVisible` both use
`_player_visible()` = the human players' living units plus `_sees` of them.
`GroupHas(UnitSee/GroupSee(..), x)` and `GroupCross(g, UnitSee/GroupSee(..))`
take a fast path (`_sees_has`) with the same geometric answer.
`UnitAI.player_perceive` maintains the retained "noticed" meta (mirroring
0x5caa00) but scripts do not consult it.

## Kinds

### `perception_group` (layer 1: supplied lists)

Inputs: actors (position, death, side, party flag), per-actor `noticed` and
`corpses` index lists, script groups, the player's units, and one expression.

* Native: actors get logic records with exactly those lists; groups are built
  by native insertion 0x4b2ef0 (sorted sets, as `AddObject` makes them);
  0x66e0f0 runs once (server player update) and then the expression is
  evaluated by 0x4b5b00 (group-valued) or 0x4b41e0 (numeric).
* Remake: the same actors registered in a `GameWorld` (`adopt_prepared_unit`)
  with `UnitAI.can_notice_with` overridden to answer true exactly for the
  supplied `noticed ∪ corpses` pairs, every actor within the watchers' sight
  radius (so the geometric prefilter keeps all of them); party units have
  `controller = 0`; then `ScriptVM._eval`.
* Observation: numeric `{truth, value_bits}`; group `{count, members}` with
  members as sorted fixture indices. Native order is pointer order (equal to
  fixture order here) and is not compared; `count` exposes duplicates.

13 supplied-list variants (empty, one/both heroes, reversed order, duplicate
entry, corpse still in a noticed list, bystander, dead NPC/guard/hero with a
retained list, guards split, heroes noticing NPCs, hero corpse list, hero
noticed list holding a corpse) × 32 expressions (the seven authored shapes,
group values, both remake fast paths, `Any`/`Every`, `PlayerSee(1)`,
`GroupHas(PlayerSee(0), x)` and `IsUnitVisible(x)` for five actors and a
missing one).

Authored conditions: `python cases_ext_perception_triggers.py --game-dir
<install> --output inputs.json` writes replay inputs with every perception
condition of the 79 authored condition lists (identifiers bound to fixture
actors/groups; no game text), each evaluated under four supplied snapshots
(nothing noticed, living mutual, corpses only, dead watchers retaining), and
`run.py --replay-inputs inputs.json` runs them (`--campaign lost_in_astral`
writes Astral inputs for layer 1). The module also exposes
`authored(game_dir, limit) -> (rows, summary)` for runners that support it.

### `perception_ticks` (layer 2: perception over time)

One NPC watcher (index 0) and one or two heroes. Per tick: positions, deaths
and terrain-ray factors are applied, then

* native: 0x5caa00 runs for the watcher (skipped once it is dead — declared
  assumption above), then the trigger is evaluated over the maintained list;
* remake: `UnitAI.player_perceive(watcher)` (production retention and
  acquisition), then `ScriptVM._eval` of the same trigger.

Observation per tick: `count_bits` (trigger value), `fired`, `noticed`
(sorted indices: native list vs remake "noticed" meta). Supplied senses use
dyadic values; the native cone receives `cos(half)` as float32, the remake
`race.vision_arc = 2·half` in degrees. Triggers: authored
`GroupSize(GroupCross(UnitSee(npc), Heroes))`, the fast-path order
`GroupCross(Heroes, UnitSee(npc))`, and `GroupHas(UnitSee(npc), hero)`.
Scenarios: approach/retreat (neutral and hostile), circling behind the
watcher, hero dying in view, life sense beyond the sight radius, peripheral
vision with a blocked ray, half ray, crawling hero, watcher dying, two heroes,
exact sight/retention thresholds, first notice from outside the cone, and a
seeded fuzz set (random senses, facing, hostility, walks, rays, deaths).

### `perception_candidates` (layer 3: the candidate list)

The same watcher and trigger as `perception_ticks`, but the candidate list
0x5ca1d0 is not stubbed. Native: the notice-cell table is built by 0x5bf8f0
(its CRT `qsort` 0x6e88bc is unstable, so cells of equal distance keep the
sort's order). Every actor is placed with 0x5c0df0 in the supplied
`arrivals` order into an empty 16 m unit-cell map (`grid_cells` × `grid_cells`
cells at map record +0x124). Per tick, `moves` run through 0x5c11d0 in their
listed order, the refresh countdown is reset, and 0x5caa00 runs (refresh,
then scan). Remake: a registered host `GameWorld` with coarse buckets. Every
unit passes a staging point in arrival order, moves set `pos` in the same
order, `ai_near_t` is cleared each tick, and production
`UnitAI.player_perceive` runs.

Observation per tick: `candidates` in native list order (head first; remake
`ai_near` meta), plus `count_bits`, `fired` and sorted `noticed` as in layer 2.
Scenarios: one actor in each of the 21 cells with D ≤ 1 (in two arrival
orders), several arrivals in one cell with moves out and back, the layout of
`tools/tests/notice_candidate_order.gd`, a watcher crossing cell boundaries
(including x = 112, a nearest-even boundary), small sight versus large life
sense, and 12 seeded crowds (shuffled arrivals, random moves of any actor
including the watcher, deaths, sight 6–40, life 0–30). Some seeded queries
reach x < 0, so the remake falls back to its exhaustive path there.

Original order: the refresh walks the cells in table order and each cell's
list from head to tail. Arrivals are appended to a cell's tail by placement,
and by a move only when the cell changes. Every unit is inserted at the
candidate list head (0x5ca37a–0x5ca3d0), so the list ends with the first
arrival in the watcher's own cell. See
[the validation record](validation/notice-candidate-order-2026-10-28.md).

## Supplied boundaries (stubs)

See each contract's `stubs` list: supplied noticed/corpse list contents;
script groups; player-zero lookup and unit map; actor type/death/release and
position accessors; CRT malloc/free and the CPlex allocator 0x6fe8af; the
debug log stream operators (0x6fc2dd, 0x6fc986, 0x6fc070, 0x434fe0,
0x6fc7ba); the spatial candidate list 0x5ca1d0 (every other actor, refreshed
every tick on both sides — the native 8..11-tick random refresh and the remake
`_notice_candidates` cache are both removed; `perception_candidates` runs it
natively and supplies only the AI-map occupancy stamp 0x5b6a80, `rand` and the
refresh countdown); the terrain ray 0x5bc3e0 /
`GameWorld.sight_ray`; flat ground and zero eye height; senses as listed.
Hostility, party test, Aggression target lookup (empty motivation list), list
node allocation/removal, corpse transfer, facing computation, distances and
all comparisons execute natively.

## Limits

No suspicion/alarm/call-for-help outcomes, hearing, combat stance ("fighting
the watcher") or Aggression target; one watcher per tick scenario; Clairvoyance
(extra-visible group) is empty; whether a dead hero stays in the player's unit
map is not established. For Lost in Astral only `perception_group` is
qualified (see below); its perception update 0x514d70 (acquisition scan
0x514a10, corpse transfer 0x514810) is identified but `perception_ticks` is
not qualified there.

## Can it fail?

* `test_ext_perception_triggers.py` changes one supplied input and asserts the
  native observation changes (noticed list → `UnitSee` truth; hostility →
  retention over ticks).
* Mutation run `results/perception-04-mutant` (scratch copy of `game/` via
  `--game-source`, never `game/` itself): `GroupCross` negated in `vm.gd` and
  the NPC retention factor 1.05 → 1.0 in `ai.gd`. 27 previously matching
  scenarios failed (e.g. `perception_group/npc_sees_hero/size_cross_unitsee_heroes`),
  and the per-tick noticed lists diverged (e.g.
  `approach_retreat_hostile0_cross` tick 4: native `[1]`, remake `[]`).
* The same mutant against Lost in Astral (`results/perception-08-astral-mutant`)
  turned 29 matching layer-1 scenarios into failures; an Astral sensitivity
  test clears the noticed lists and asserts `IsUnitVisible` flips.

## Results (2026-10-21)

`results/perception-03` (core family + 316 authored rows, replay inputs in
that directory): **768 scenarios, 670 match, 98 differ**, 1084 original
observations; both captures repeatable. After the per-campaign address
refactor, `results/perception-09` reproduced all 768 original and remake
trace hashes unchanged. Without authored rows: 452 scenarios,
393 match, 59 differ. Every divergence (original → remake):

### A. Scripts ignore the AI's retained noticed list (perception_ticks)

The remake's `UnitAI.player_perceive` list matched the native list on **every
tick of every scenario** except group D below — but the trigger is computed
from instantaneous geometry instead of that list:

* Retention: `approach_retreat_hostile0_{cross,cross_fastpath,has}` tick 4
  (hero at 10.25 m, sight 10, retained below 10.5) 1 → 0;
  `approach_retreat_hostile1_*` tick 4..9 (hostile hero retained at any
  distance) 1 → 0; `circle_behind_hostile{0,1}` tick 3 (hero behind the
  watcher, outside the cone, still noticed) 1 → 0; `ray_half_hostile{0,1}`
  tick 3; `crawling_hero_hostile{0,1}` tick 3; `two_heroes_hostile0` tick 3
  1 → 0; `two_heroes_hostile1` tick 2 count 2 → 1; seeded `seeded_003` tick
  11, `seeded_005` tick 2, `seeded_011` tick 2 1 → 0.
* Life sense beyond the script's sight-radius prefilter:
  `life_sense_beyond_sight_hostile{0,1}` tick 1 (hero 14 m behind, life
  sense 15, sight 10) 1 → 0 — the remake AI notices it, `_units_within(sight)`
  excludes it.
* Corpses: `hero_dies_in_view_hostile{0,1}` tick 2 0 → 1, `seeded_007` tick 8
  and `seeded_010` tick 6 0 → 1 — the original moves the dead hero to the
  corpse list, the remake's geometric `UnitSee` still returns the visible
  corpse, which `Heroes` contains.
* Dead watcher: `watcher_dies_hostile{0,1}` tick 1 1 → 0 — the original keeps
  reading the frozen list of a dead NPC; the remake skips dead watchers.

### B. Dead watchers with retained lists (perception_group)

`dead_npc_retained_list/{size_cross_unitsee_heroes, has_unitsee_hero,
size_unitsee, any_heroes_seen}` truth 1 → 0 and `{cross_unitsee_heroes,
cross_heroes_unitsee, unitsee}` count 1 → 0;
`dead_guard_retained_list/{size_cross_groupsee_heroes,
size_cross_heroes_groupsee}` 1 → 0, `groupsee_guards` count 2 → 1,
`cross_groupsee_heroes` 1 → 0; `dead_hero_retained_list/{size_cross_groupsee_heroes_guards,
has_groupsee_heroes_npc}` 1 → 0, `groupsee_heroes` count 2 → 0. Native
`UnitSee`/`GroupSee` have no death test.

### C. Corpse lists (perception_group)

`hero_corpse_list/{size_cross_playersee_guards, size_cross_groupsee_heroes_guards,
has_playersee_dead_guard}` 0 → 1, `groupsee_heroes` count 1 → 2, `playersee`
count 3 → 4: the original's `PlayerSee`/`GroupSee` read only noticed lists
(corpses are in the separate corpse list); the remake's geometric perception
includes visible corpses. `IsUnitVisible` (which reads corpse lists in the
original) matched.

### D. Peripheral vision through a blocked ray (perception_ticks)

`peripheral_blocked_ray_hostile{0,1}` tick 0: original noticed `[1]`, trigger
1; remake noticed `[]`, trigger 0. The original's peripheral test has no ray;
the remake requires `sight_ray > 0.0001` (deliberate comment in
`UnitAI.can_notice_with`). This is the only AI-list divergence.

### E. `PlayerSee(1)` in single player

All 13 `*/playersee_other_player` scenarios: original count 0 (no player
record 1), remake returns player 0's visible set (the argument is ignored).
Not used by authored base scripts.

### Fix status

Branch `fix/script-perception-20261021` makes `UnitSee`/`GroupSee`/`PlayerSee`
read the AI's retained noticed lists (refreshed by `UnitAI.player_perceive`
on demand; a dead watcher keeps its last list), `IsUnitVisible` and
QObjSeeUnit add the player's corpse lists, and `PlayerSee(n != 0)` is empty
in single player. Groups A, B, C and E match; the core family is
**450 match, 2 differ**, the two being group D, kept on purpose. The full
authored run changes only `perception_group` (+71) and `perception_ticks`
(+25). The layer-1 harness supplies the retained lists as the AI's state
for the tick (`noticed`, `seen_corpses`, `perceived`).

### F. Authored conditions (39 of 316 rows)

All in the `dead_watchers_retain` snapshot (B; 20 rows: `GroupSee(g)` /
`GroupSee(Heroes)` shapes in z18q1, z18q3, zone1, zone12, zone12-lmp,
zone12magess, zone16, zone17, zone19, zone3obr ×9, zone7letter, zone8) or the
`corpses_only` snapshot (C; 19 rows: `GroupSize(GroupCross(PlayerSee(0), g))`
×13 and `GroupSize(GroupCross(GroupSee(Heroes), g))` ×6 in zone1, zone15,
zone15night, zone16, zone17, zone18, zone3obr, zone4, zone6, zone7zasada),
truth 1 → 0 and 0 → 1 respectively. Nothing-noticed and living-mutual
snapshots matched for every authored condition.

### G. Candidate list order (perception_candidates, 2026-10-28)

Before the fix, all 19 scenarios differed. The remake returned the candidates
in registry order, and the original returns table order and arrival order,
reversed by head insertion. `GameWorld.notice_units_near` now uses the
original order: the 2026-10-28 run gives 19 match, 0 differ for this kind, and
`--case perception_` gives **469 match, 2 differ** (group D). The `noticed`
sets matched in every tick. The order of the noticed list itself (head
insertion of new entries in 0x5ca5a0) is still not compared.

### Lost in Astral (`perception_group` only)

Addresses were matched by structure in the Astral executable (sha256
f04a305b…): expression evaluator 0x46cca0 (`IsUnitVisible` 0xe5 reads player
zero +0x20 → +0x510c through the membership helper 0x466560), group
evaluator 0x46db40 (same opcodes 0x59/0x5a/0x5b/0x5d/0x5e/0xa5, temporary
groups from the context pool at +0x1b0 via 0x46b480), sorted insertion
0x4688b0, list merge 0x4689b0, union/difference/intersection 0x4684e0 /
0x468680 / 0x468790, group vtable 0x62789c, and the visible-group update
0x597590 (extra-visible ∪ units ∪ noticed lists, then ∪ the party's merged
corpse lists, which are written back to every member). Stubs: operator new /
free 0x5ffa7b / 0x5ecb7c (CPlex 0x5fed90 runs natively), player lookup
0x4e6c40 and the CRT locale, as in the Astral quest fixture.

`results/perception-07-astral` (core layer 1 + 8 authored rows from 20
Astral condition lists; replay inputs in `perception-07-astral-inputs`):
**424 scenarios, 390 match, 34 differ**, repeatable. The Astral native traces
of all 416 core layer-1 scenarios are byte-identical to the base executable's
(`perception-03`), so its 32 core divergences are exactly groups B, C and E
above. The two authored divergences are `dead_watchers_retain` rows (group B)
in zone1 and zone22. (`perception-06-astral` is the earlier core-only run with
the same 32 divergences; `perception-05-astral` is an aborted setup.)

### Matches worth noting

Duplicate list entries, list order, a corpse still inside a noticed list
(transient state between death and the next update), `UnitSee(NULL)`,
`IsUnitVisible` with corpse lists, `Any`/`Every` over `GroupSee`, and both
remake fast paths all matched. The remake AI's retention, corpse transfer,
cone, ray, life sense and first-notice timing matched the native 0x5caa00 on
every tick apart from D.
