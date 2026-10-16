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
the final one pays 7 gold. Army capacity grows from 3 to 4/5/6/7 at waves
4/7/10/13. The bench holds six, or nine with Pack train. Five offers appear per
shop, or six with Well connected. Melee recruits cost 3 gold; shooters, bats and
toads cost 4. Refresh costs
2, or 1 with Quartermaster. One offer can be locked between shops.

Camps follow waves 3, 6, 9, 12 and 15. The first camp commits the company to one
pact for the run. Camps 9 and 15 offer its next support form, an unused shop/bench
boon, or recovery (one life if injured, otherwise 6 gold). Taking supplies,
recovery or a boon means foregoing that support upgrade. If all three boons are
already owned, the last camp has two distinct choices instead of a redundant
currency offer.

Boss camps at 6 and 12 offer a native Orc seer companion, an unused boon, or a
life if injured (otherwise 12 gold). Companions join the permanent reserves and
use ordinary army slots when deployed. A full bench can accept one temporary
overflow creature; purchases remain blocked until a slot is freed. A second
overflow companion is disabled with a reason, leaving the other rewards usable.

Defeat costs one life and no gold is paid. The entire army recovers for a retry of
the same encounter with a new combat roll. Death at zero lives ends the run.
Clearing the expedition unlocks Veteran, then Champion: harder difficulties add
native enemies instead of changing their stats. There is no interest economy,
paid XP, equipment draft or permanent combat-stat progression. Composition
synergies now work through pact reinforcements, without passive stat bonuses.

A seed determines shops and encounter mirroring. Separate shop RNG state is saved;
combat does not consume shop randomness. Save validation checks content, formation,
economy and nested data before replacing live state. Save writes use a flushed
intermediate file and rename. An interrupted fight returns to preparation with
its attempt seed. Version 1 saves migrate without resetting their army,
investment, gold or RNG. A legacy run without a pact can choose one at a later
pact camp. Campaign saves and network sessions are not involved.

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
| Tribal shooters | `goblina1 → goblina3 → orcfemalea5` | 2, 3 | 8, then 24 gold |
| Bats | `batredm1 → batredm3 → batlightm7` | 2, 3 | 8, then 24 gold |
| Toads | `toadm2 → toadm6` | 3 | 12 gold |

IDs here document implementation; players see localized original names. Evolution
is explicit and previews its result, stats, copy requirement and unlock. First
steps unlock at wave 4; second steps at wave 10. Toads have one useful step.
Native melee/magic roles are retained; the tribal promotion crosses goblin/Orc
species. Weak intermediate ages are skipped. The chosen unit retains its place;
other required copies are consumed. Undo is available during preparation until
a refresh or battle commits the transaction. Sales recover one third of invested
recruitment cost.

## Company pacts

Only the selected pact can activate. Count distinct eligible families among the
player's deployed army: duplicate copies, reserves and the summoned ally do not
add families. The Tribal council additionally requires both forms to have evolved.
Auto-arrange reserves the strongest eligible member of each required family when
it can activate the pact, then fills remaining slots by native level.

| Pact | Deployed condition | Initial ally → first upgrade → final upgrade |
| --- | --- | --- |
| Wild kin | Three different families among boars, wolves, bats and toads | `wolfgreyf1 → wolfgreyf3 → wolfwhitef6` |
| Tribal council | Evolved tribal fighter and evolved tribal shooter | `orcfemalem3 → orcfemalem5 → orcfemalem7` |
| The vanguard | Boars, tribal fighters and wolves | `goblina3 → orcfemalea5 → orcfemalea7` |

The ally is an extra combatant, not an army/bench entry. It has no resale value,
cannot merge, does not consume capacity and never triggers its own pact. It is
visible before Start at a deterministic clear position and uses the ordinary
native spawn/AI/combat path. Its death does not remove the pact; it returns next
battle if the deployment condition is still met. Benching a required family
removes the ally immediately during preparation. Changing shop/formation state,
saving/reloading and retrying cannot duplicate the ally.

The composition cost is deliberate: Wild kin requires variety among beasts;
Tribal council commits recruitment to two evolved tribal lines; The vanguard
requires three melee families and supplies a stronger ranged specialist to help
that less forgiving composition. Support upgrades change the original creature
prototype rather than applying a numeric modifier to the existing one.

## Balance evidence

Current progression measurements are recorded in
[the progression validation](validation/arena-progression-2026-10-16.json).
The simulator runs the real run economy, native AI/combat/spells/projectiles and
authored terrain/navigation in 55 ms ticks. Native database hashes remain unchanged.
The first two tuning batches added pacts to the old formations, then tightened
income. Both let all 18 starter-focus runs clear, so the final rules also add a
native guard to bosses 6, 12 and 18. Veteran reinforcements advance from a goblin
to Orc fighters; Champion adds increasingly capable shooters. The same policy
and seeds are used across difficulties in the new comparison.

| Difficulty | Recruitment policy | Clears | 95% Wilson interval | Native fights |
| --- | --- | --- | --- | --- |
| Standard | Starter focus | 15/18 (83%) | 61–94% | 325 |
| Veteran | Starter focus | 14/18 (78%) | 55–91% | 301 |
| Champion | Starter focus | 10/18 (56%) | 34–75% | 320 |
| Standard | Ranged / magic | 16/18 (89%) | 67–97% | 332 |
| Standard | First affordable | 14/18 (78%) | 55–91% | 343 |
| Standard | Melee / Vanguard | 13/18 (72%) | 49–88% | 319 |

The comparison contains 108 runs and 1,940 native fights, using seeds 3000–3017
in each row (six runs per starter). Intervals describe each small cohort; they
do not establish a statistically significant ordering between policies.

These are automated policy clear rates, **not human win rates**. All policies
merge available forms, use pact-aware auto-arrange, recover a life when injured
and otherwise choose the companion or pact upgrade. The first-affordable policy
still has that competent formation/evolution behavior; it is not a human novice
model. The ranged policy buys a missing melee beast to enable Wild kin. The melee
policy chooses The vanguard. Other starter-focus runs choose Wild kin for the wild
hunt and Tribal council for the other starters. Fixed formations do not adapt to
each enemy, and cohorts are small. Native spell-heavy builds remain more forgiving
than narrow melee builds; more human play is needed before claiming equal balance.

The unchanged eleven evolution recipes previously passed 264 paired-side native
fights (12 seeds, both sides per recipe); outputs won 19–24 of 24 in those fixtures.
That screens out poor exchanges but does not prove universal power ratios. The
historical pre-pact batch was 186 runs / 3,280 fights and is preserved in
[the initial validation](validation/arena-pve-2026-10-16.json). Its economy and
challenge rows describe the previous rules, not the new mode.

Presentation, frame interpolation and incidental runtime randomness are not
reproduced by the fixed-step runner, so bit-for-bit parity with live fights has
not been established. Rendered interaction tests separately exercise live combat,
company details, camp choices and formation changes.

## Interface

The [UI design](design/arena-ui.md) documents the selected generated concept and
its implementation. Recruitment models occupy a thin top shelf; reserves sit
unboxed at the lower edge; a small round badge and one battle action complete the
neutral HUD. The shop hides in combat. Creature stats and evolution are shown on
selection. The army counter opens pact status and owned upgrades in the same
optional detail rail. Recruitment tooltips identify the relevant family and any
evolution requirement. Reserves can swap directly with a deployed creature even
when both army and bench are full; the swap can be undone. Camp choices show live
native models and localized requirements, with creature stats in their tooltips.
The original game's bronze frame atlas and native creatures establish
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
