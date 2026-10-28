# LiA Wormfaces' Riddle first-visit lock — 2026-10-28

The Lost in Astral quest “Wormfaces' Riddle” (`fq6`, Wormface caves `gz4h`)
could not be completed when the fortune-teller's last prediction
(`b.skelet.fq6 = 2`) was bought before the first visit to the caves. The three
riddle levers stayed disabled, so the first Rod of Life fragment (`kel1`) and
therefore Kel's revival were unreachable. A supplied 1.0.x save shows exactly
that state.

**Result: fixed as an intentional passability repair.** The original LiA 1.02
has the same lock (confirmed under Wine below); the remake now re-enables the
untouched riddle in that one state. Answered riddles, including a wrong answer,
are not reopened.

## Cause

`zone4.mob`'s WorldScript binds `Lever1..3` to objects 16426, 1047355 and
1088298 and starts `Start` before `VLever1#0#0`. Script triggers are polled
newest-first (see [the quest scheduler notes](../original-parity-quest-scheduler.md)),
so on the first visit, in one pass:

1. `VLever1#0#0` (`b.skelet.fq6 == 2 && q.gz4h.fq6 == 0`) enables the three
   levers, resets their states and sets `CaveLever = 0`, then kills itself.
2. `Start` (`q.gz4h.q19h.1 == 0`) sets `CaveLever = 0` and disables the three
   levers, then kills itself.

Both are one-shot, so nothing enables the levers again. Bought after the first
visit, the fortune is seen by `VLever1#0#0` on a later pass, after `Start` has
already finished, and the riddle works. The existing `lia_kel_suslanger` test
clears the startup threads after map entry, so it never ran this order.

## Original comparison (LiA 1.02 under Wine)

Bounded native suite `local/runtime/sessions/lia-riddle-20261028` (template
`original-lia-1.02`, Wine 11.20 WoW64 in GPU Lab, `game.exe` SHA-256
`9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`, muted,
FPS shown, free cursor). It starts from the retained 2026-10-23 native
checkpoint after `fortune_6` (`b.skelet.fq6 = 2`) and enters `gz4h` for the
first time. Values were read by setting `cp_*` variables through the debug
console, quick-saving and decoding with `tools/parity/original_save.py`.

| Probe | Observation |
| --- | --- |
| Hover over lever 3 (210, 49) | Plain arrow cursor, no use cursor. |
| Click lever 3, nonce 4101 | `GetLeverState` of all three levers = 0; `CaveLever` = 0. The click had no effect. |
| Console `EnableLever(…, 1)` for all three, hover | Use (hand) cursor. |
| Click lever 3, nonce 4102 | `cp_l3 = 1`, `CaveLever = 30` (`(0 + 3) × 10` from `VLever3#0#1`). |

Confirmed: the original disables the riddle permanently in this purchase order,
and the levers themselves work once enabled. The remake repair therefore
deliberately differs from the original only in this unwinnable state.

## Repair

`story_compat.gd` recognizes the shipped `zone4` scripts exactly (`Start`,
`VLever1#0#0`, `VLever{1,2,3}#0#1`, the three `GetObjectByID` bindings and
their WorldScript launches); modified maps are left alone. Each script tick it
re-enables the three levers only when all of these hold:

- campaign is Lost in Astral, `b.skelet.fq6 = 2`, `q.gz4h.fq6 = 0`,
  `CaveLever = 0`;
- all three levers are disabled and unpulled;
- `Start`, `VLever1#0#0` and the WorldScript are finished, and the three
  `VLever{1,2,3}#0#1` answer watchers are still waiting.

A wrong answer pulls the levers and kills their watchers, so it stays final as
in the original. Saves already stuck are released on the first tick after load.

## Rendered check with the supplied save

The fixed build was run rendered (Vulkan, GPU Lab, muted isolated profile) with
a copy of the supplied stuck save, loaded from the ordinary load screen. The
console reported `CaveLever = 0`, `q.gz4h.fq6 = 0` and Lever1 state 0; `god on`
and `teleport 207 52` only shortened the walk. Clicking the levers in the
order 3, 1, 2 pulled each one, revealed the chest, and opening it reported the
Rod of Life fragment, 100 coins and “Wormfaces' Riddle” completed.

## Other quests checked

- Static scan of every LiA map for a startup script that disables levers which
  an earlier-launched quest script enables: three candidates.
  - `zone4` — the reported lock.
  - `zone16` (Gipat `fq12`) — not a lock: the enabler sleeps 15 before enabling,
    and the other branch needs progress inside the map.
  - `zone3dun1` — not a lock: altar lever 2173451 is enabled by `Altar#0` only
    after lever 338779 is pulled inside the map, after `Start` has finished.
- The other two Rod fragments were exercised through their real startup
  threads in both purchase orders: Uyka's crypt key (`fq13`, `gz11d1`) and
  Khabburu's mine key (`fq19`, `gz24k`). Both pass without changes.

## Regression coverage

`quests/lia_fragment_first_entry` (`tools/tests/lia_fragment_first_entry.gd`,
114 checks) enters the fragment maps with their authored startup threads
running:

- fortune before the first `gz4h` visit: levers usable, save/reload, a
  synthesized stuck save released after one tick, correct 3-1-2 answer, chest at
  (202, 52), `kel1`;
- fortune after the first visit: riddle enabled on return and solved;
- wrong 1-2-3 answer: consumed, not reopened by the repair on revisit;
- crypt key bought before and after the first `gz11d1` visit: door, `kel2`;
- mine key granted before and after the first `gz24k` visit: three route doors,
  chest, `kel3` and the 70,000 reward once.

Against the unfixed source the program fails 10 of 52 checks before stopping.

`tools/tests/lia_riddle_user_save.gd` (not in the catalog, like
`suslanger_user_save.gd`) loads a copy of a supplied save with
`--supplied-save=PATH`. On the supplied stuck save it passes 19 checks with the
fix and fails 5 of 18 without it.

### Why the existing Kel tests missed it

The `lia_kel_*` and `lia_campaign_*` fixtures cleared every thread a map's
WorldScript started and spawned only the quest threads under test. That kept
each program focused, but no program ran a map's own startup scripts against an
already-accepted quest, which is exactly where this lock lives.

`lia_kel_support.gd` now has a `--map-startup` mode that keeps the startup
threads, as an ordinary visit does; named quest threads must then already be
running or finished. Every `lia_kel_` and `lia_campaign_` program has a
`<id>_startup` catalog variant, 27 in all, except `late_addmob` and
`map_points` (no loaded map: a parsed script and the map/entrance controls)
and `fortune_orders` (always keeps the startup threads). Each variant has
the same check count as its base program. Tests that cleared threads
themselves after a later passage now use the shared `threads()` helper, so the
variant also covers those passages.

`quests/lia_kel_fortune_orders` (`tools/tests/lia_kel_fortune_orders.gd`, 132
checks) covers every other fortune on the way to Kel's revival with the map's
startup threads running, bought before the first visit and after a first visit
in the fortune-teller's village: Suslanger `fq2`/`fq4` (Portal: cellar torch,
Raja, dead man, trader chest) and `fq3`/`fq5` (graveyard: midday basket, night
undead and chest), and Gipat `fq8` (mushrooms), `fq9` (clerk's key and cage),
`fq10`/`fq12` (captive's escort, giant's two meals) and `fq11` (the invalid).
Each chapter's starting map (Portal, Gipat arrival) can only be covered after a
first visit. God mode, teleport and kills shorten walking and fighting; quest
outcomes come from the maps' own scripts.

`tools/parity/run_lia_kel.sh` runs the 20 Kel-chain programs (base, startup,
fortune orders, fragments) remake-only. The runner now runs programs in
parallel (`--jobs`, default `auto`: one per three CPU threads, limited by free
memory, with each start held while free memory is short); programs that open
fixed network ports (found through their `extends`/`preload` bases) and
rendered programs still run one at a time. On this workstation the 20 programs
took 4.3 minutes with seven jobs (25 minutes of program time, 2,342 checks, all
passed), peaking at 22 GB in total. An independent review found that the first
parallel version kept running queued programs after Ctrl-C or a worker error;
both now stop every program (a Ctrl-C test ended in 0.14 s with no Godot
process left).

All startup variants pass: no other accepted quest is undone by its map's
startup scripts.

### Shelter Kel fixture

The full `quests` run also failed `quests/shelter_kel` and
`quests/shelter_kel_named` (5 checks each, co-op only; `shelter_kel_solo`
passed). This is not part of the riddle change: it also fails at `v1.24.0`
(retained bisect report). Since `1239620c` (“Align ScriptVM trigger scheduling
with the original”), `#OnBriefingComplete` starts in the next script pass. The
fixture ticked after a host-closed briefing but not after a guest-closed one,
so the Kel dismissal handler never ran. `shelter_kel.gd` now ticks once after
either closer; the game itself was not changed. All three variants pass.

### Test memory: retained maps

Running four programs at once filled the workstation's memory: one headless
`lia_campaign_shaina_startup` process grew at about 100 MB/s, past 12 GB.
The cause is in the test fixtures, not in the game, and also affects main:
`Game.attach_world` queues the previous map's world for deletion, which Godot
carries out at the end of a frame. The LiA fixtures freeze the session and
advance the script VM directly, so few frames pass and every visited map stayed
loaded. Earlier reports show up to 17 retained worlds and 13 GB of static memory
(`lia_campaign_shaina`), 9 worlds and 6 GB in `lia_kel_suslanger` on unchanged
main. A probe confirmed the old worlds were queued but still in the tree, and
gone after ten frames. In the game, frames pass continuously.

`tools/tests/world_release.gd` frees the already-queued worlds after a map
change, as the next frame would. `lia_kel_support.gd` calls it in `freeze()`
(every LiA quest program), as do `lia_slave_lists_return`,
`lia_revenge_return` and `quest_inventory_lifecycle`, the other programs that
retained several maps. Each of them now ends with the check “each map change
releases the previous map” (at most one world loaded after every freeze). With
the release disabled, `lia_kel_suslanger` fails that check (peak 9 worlds). With
it, four parallel programs peaked at about 4 GB each instead of growing past
10 GB.

### Runs on the final source

Related runs on the fixed source: `quests/catacomb_group_lever` 26/0,
`quests/lever_transition_save` 59/0.

The full `quests` category (106 programs before the startup variants and
fortune orders were added) passed except the two co-op Shelter Kel programs
fixed above (then 33/0, 24/0, 33/0); four programs it did not reach
(`base_campaign_side_ingos` 393, `base_campaign_side_suslanger` 461,
`base_campaign_map_points` 2482, `prison_alarm_state` 70) passed separately.

Final run with the final fixtures, four jobs: every `lia_` program
(base, startup variants, fortune orders, fragments, returns, tomb exit) and
`quest_inventory_lifecycle`, 62 programs, 12,621 checks, 0 failed, about
21 minutes (82 minutes of program time). Catalog minimums equal these counts.

## Scope and uncertainty

- Quest flags before each visit are supplied and travel is direct map entry;
  the fortune-teller dialogue itself is covered by `lia_kel_suslanger`.
- Only lever enabling was compared natively; the remake's correct/wrong answer
  results come from the existing `lia_kel_suslanger` native references.
- In `--map-startup` mode `start()` checks only that each named thread exists
  in the map; it does not confirm that the map started it. Positive outcome
  checks fail if it did not, but “remains closed” checks (for example
  `gate(..., false, ...)` in `lia_campaign_ingos_portal` and
  `lia_campaign_mid_ingos`) can pass without the thread having run. The plain
  programs still cover those.
- The static scan looks for the startup enable/disable pattern only. Other kinds
  of order-dependent locks are covered only where the fragment tests exercise
  them.
