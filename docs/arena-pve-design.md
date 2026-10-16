# Trials of Gipath: implemented PvE expedition

Implemented in the arena worktree, 16 October 2026. This document supersedes the
initial proposal; the [earlier research](validation/arena-pve-research-2026-10-16.json)
is retained as historical evidence. The unrestricted two-team Arena remains a
separate mode.

## Run structure

An expedition contains 18 authored encounters, untimed preparation and fully
AI-controlled combat. Three starter companies provide different opening roles.
Six recruit families keep duplicates findable; enemy variety includes creatures
outside that shop. The battlefield is an authored 3D ruined courtyard using native
terrain, scenery and navigation, with a generated stone paving albedo.

The run starts with three creatures, 6 gold and three lives. Every victory except
the final one pays 8 gold. Army capacity grows from 3 to 4/5/6/7 at waves
4/7/10/13. The bench holds six, or nine with Pack train. Five offers appear per
shop, or six with Well connected. Every base recruit costs 3 gold. Refresh costs
2, or 1 with Quartermaster. One offer can be locked between shops.

Waves 6 and 12 offer a native Orc spellcaster companion, a random unused economy/
capacity boon, and a life if injured (otherwise 12 gold). A companion can occupy
one temporary overflow bench space, so a full bench cannot destroy a chosen
reward. Purchases remain blocked until that space is cleared.

Defeat costs one life and no gold is paid. The entire army recovers for a retry of
the same encounter with a new combat roll. Death at zero lives ends the run.
Clearing the expedition unlocks Veteran, then Champion: harder difficulties add
native enemies instead of changing their stats. There is no interest economy,
paid XP, synergy bonus, equipment draft or permanent combat-stat progression.

A seed determines shops and encounter mirroring. Separate shop RNG state is saved;
combat does not consume shop randomness. Save validation checks content, formation,
economy and nested data before replacing live state. Save writes use a flushed
intermediate file and rename. An interrupted fight returns to preparation with
its attempt seed. Campaign saves and network sessions are not involved.

## Native creatures and evolution

All forms use the original database's HP, armor, attacks, equipment, spells,
resistances and AI. The match explicitly uses the original difficulty/combat-rule
settings; there is no mode-specific HP/DPS multiplier. Original and expansion
pools are not mixed into a normalized stat table.

| Family | Explicit native path | Copies per evolution | Base recruitment investment |
| --- | --- | --- | --- |
| Boars | `boarredf1 → boarredf3 → boardarkf6` | 3, 3 | 9, then 27 gold |
| Tribal fighters | `goblinf1 → orcmalef3 → orcmalef5` | 3, 3 | 9, then 27 gold |
| Wolves | `wolfgreyf1 → wolfgreyf3 → wolfwhitef6` | 3, 3 | 9, then 27 gold |
| Tribal shooters | `goblina1 → goblina3 → orcfemalea5` | 2, 3 | 6, then 18 gold |
| Bats | `batredm1 → batredm3 → batlightm7` | 2, 3 | 6, then 18 gold |
| Toads | `toadm2 → toadm6` | 3 | 9 gold |

IDs here document implementation; players see localized original names. Evolution
is explicit and previews its result, stats, copy requirement and unlock. First
steps unlock at wave 4; second steps at wave 10. Toads have one useful step.
Native melee/magic roles are retained; the tribal promotion crosses goblin/Orc
species. Weak intermediate ages are skipped. The chosen unit retains its place;
other required copies are consumed. Undo is available during preparation until
a refresh or battle commits the transaction. Sales recover one third of invested
recruitment cost.

## Balance evidence

The final rules were tested through `ArenaRun` and `ArenaPveMatch`, including the
actual economy, original monster AI, projectiles, spells, armor, authored terrain
and scenery navigation. The simulator advances native combat in 55 ms ticks. It
is not a synthetic HP/DPS estimator. Source hashes in the records match the four
current rules/run/match/terrain files. Native database hashes remained unchanged.

Eleven final evolution recipes were each tested with 12 seeds, from both sides:
264 fights, no draws. The output beat its consumed inputs 19–24 times out of 24
across the recipes (20/24 for the first boar step, 19/24 for the first wolf and
final shooter steps). This screens out plainly bad exchanges while retaining
counterplay; it does not prove a universal power ratio. Earlier tests rejected
weak age-by-age bat/toad paths and the initial three-copy shooter opening.

The final full-run batch contains **186 runs and 3,280 fights**:

| Difficulty / policy | Seeds | Clears | Wilson 95% interval |
| --- | --- | ---: | --- |
| Standard / starter-family focus | 2000–2059 | 39/60 (65%) | 52–76% |
| Standard / ranged and magic focus | 2000–2059 | 52/60 (87%) | 76–93% |
| Standard / first affordable recruit | 2000–2029 | 10/30 (33%) | 19–51% |
| Veteran / starter-family focus | 3000–3017 | 9/18 (50%) | 29–71% |
| Champion / ranged and magic focus | 3000–3017 | 16/18 (89%) | 67–97% |

The first policy favors each starter's three families. The ranged policy favors
shooters, bats and toads. The simple policy buys the first affordable offer and
allows one refresh rather than three. All policies merge legal forms, choose life
when injured or the companion otherwise, and arrange by native level with ranged
units behind melee. They do not adapt formations intelligently to each encounter.

These are **policy clear rates, not human win rates**. The two challenge rows use
different policies and cannot establish a difficulty gradient. Standard clears
also differ by starter: 8/20, 20/20 and 11/20 for the starter-focus policy, versus
19/20, 18/20 and 15/20 for ranged focus. That is a remaining balance concern:
magic-heavy recruitment is forgiving and the warband's focused route is harder.
The implementation is a tested first balance, not a claim of an optimal or equally
strong strategy set. Further tuning should compare the same policies and seeds
across difficulties and include human play before changing original creature stats.

Winning standard simulations took median 7.5 / 6.2 / 8.3 minutes of combat for the
three policies. Preparation time is excluded. Rendering, audio, frame interpolation
and incidental runtime randomness are not reproduced by the fixed-step runner;
bit-for-bit parity with live fights has not been established. Live UI tests also
exercise normal frame-driven combat, separately from the simulated batches.

Raw final runs, recipe results, source hashes, regression logs and screenshots are
indexed in the [validation record](validation/arena-pve-2026-10-16.json).

## Interface

The [UI design](design/arena-ui.md) documents the selected generated concept and
its implementation. Recruitment models occupy a thin top shelf; reserves sit
unboxed at the lower edge; a small round badge and one battle action complete the
neutral HUD. The shop hides in combat. Creature stats and evolution are shown on
selection. The original game's bronze frame atlas and native creatures establish
visual continuity. EN/RU/DE are checked in real rendered layouts, including the
expanded shop and bench at 1024×768 and the battlefield at 1280×720.

## Genre references

The design borrows untimed PvE preparation, authored encounters and limited lives
from [Tocker’s Trials](https://teamfighttactics.leagueoflegends.com/en-us/news/game-updates/new-tft-workshop-mode-tockers-trials/),
and recruitment/positioning decisions between automated battles from
[The Last Flame](https://store.steampowered.com/app/1830970/The_Last_Flame/).
[Riot’s Magic n’ Mayhem retrospective](https://teamfighttactics.leagueoflegends.com/en-us/news/dev/dev-tft-magic-n-mayhem-learnings/)
informed the restraint around extra systems and variance. These are design
references, not evidence that this game's native combat is balanced. The user's
Auto Chess images guided the battlefield-dominant composition.
