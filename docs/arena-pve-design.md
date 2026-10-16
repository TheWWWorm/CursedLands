# Trials of the Allods

Implemented in the arena worktree, 16 October 2026. This is the current design;
older validation records describe earlier revisions. The unrestricted two-team
sandbox remains separate.

## The run

Thirty authored waves take the company from Gipath creatures through Ingos and
Suslanger opponents. Preparation is untimed, combat uses the original AI, and
three lives allow failed encounters to be retried. Each cleared wave pays once;
a failed retry cannot generate gold or experience. All survivors and casualties
return for the next preparation. Veteran and Champion unlock after clears and
add native enemies, without multiplying their stats.

The player starts with **no creatures, 16 gold and three army slots**. The first
shop offers one of each of the six opening families, in seeded order. Purchases
enter reserves; the player places them. The interface shows a single recruitment
prompt until a creature is owned. Refreshes, training and shop improvements cannot
spend the last three gold while the army is empty. A refreshed empty-company shop
always contains an affordable base recruit. The opening's sixth-slot lock moves
into the five-offer shelf when necessary.

The central tradeoff is immediate strength versus investment: buy a frontline,
finish an evolution, improve recruitment, train another army slot, or save for
interest. One-star creatures sell for their full purchase price, making a change
of direction affordable. Evolution refunds two thirds of investment, capped at
that form's shop price. Gift companions refund one third. None of these routes
can create resale profit.

## Recruitment and native forms

All HP, damage, attack/defense, armor types, equipment, spells and combat behavior
come from the original prototypes. No arena stat multipliers are used. New
families have two useful forms rather than charging three copies for several
small native age increments. They introduce higher armor, sturdier frontlines,
lightning, acid attacks and support spells. Stars describe evolution *within a
family*, not equal power across unrelated creatures.

| Family | Arrives | Native forms | Copies per step | Shop prices |
| --- | ---: | --- | --- | --- |
| Boars | 1 | `boarredf1 → boarredf3 → boardarkf6` | 3 / 3 | 3 / 6 / 11 |
| Tribal fighters | 1 | `goblinf1 → orcmalef3 → orcmalef5` | 3 / 3 | 3 / 6 / 11 |
| Wolves | 1 | `wolfgreyf1 → wolfgreyf3 → wolfwhitef6` | 3 / 3 | 3 / 6 / 11 |
| Tribal shooters | 1 | `goblina1 → goblina3 → orcfemalea5` | 2 / 3 | 4 / 7 / 12 |
| Bats | 1 | `batredm1 → batredm3 → batlightm7` | 2 / 3 | 4 / 7 / 12 |
| Toads | 1 | `toadm2 → toadm6` | 3 | 4 / 7 |
| White tigers | 10 | `tigerwhitef6 → tigerwhitef10` | 2 | 5 / 9 |
| Blue trolls | 13 | `trollbluef9 → trollbluef12` | 2 | 7 / 12 |
| Stony harpies | 13 | `succubbluem10 → succubbluem17` | 2 | 7 / 14 |
| Sand ogres | 19 | `ogrehadaganf13 → ogrehadaganf17` | 2 | 9 / 16 |
| Spiders | 19 | `spiderf10 → spiderf15` | 2 | 8 / 14 |
| Grey harpies | 19 | `succubgreym13 → succubgreym17` | 2 | 9 / 16 |

The table contains implementation IDs; players see original localized names.
These are 12 recruit families and 29 forms. The original map records place the
white-tiger, blue-troll and stony-harpy lines in Ingos, and sand ogres, giant
spiders and grey harpies in Suslanger. The earlier bat line already ended in an
Ingos Foxbat cub. No expansion-only creature database is mixed in.

New arrivals are guaranteed in their first unlocked shop, without overwriting a
locked offer. Later rolls favor the current region: a current family has weight
5, an older Gipath family weight 1, and an Ingos family weight 2 after Suslanger
arrives. Old families remain available to complete recipes. This avoids diluting
the six-family opening while giving later armies room to replace early units.
The next arrivals appear on the victory screen and in recruitment details.

Matching copies evolve on purchase, including wave one. A deployed copy retains
its position and identity. A purchase and its entire merge chain are one undoable
action. A short, nonmodal notice shows the old/new native model, stars, health
and attack; sound and a field/reserve highlight identify the changed creature.
Notices queue, disappear when the creature is sold or undone, and clear for battle.

Ordinary shops have five offers, six with Well connected. Refresh costs 2 gold,
or 1 with Quartermaster; one offer can remain locked. Improvements cost 10 then
18 gold and include a refresh of unlocked offers. Rank rolls are 100/0/0,
70/30/0 and 45/45/10 percent. A roll beyond a family's final form resolves to its
last form at that form's price; two-form families therefore have a 55% final-form
chance at shop level three. Shop investment never changes native stats.

## Economy, capacity and camps

| Component | Rule |
| --- | --- |
| Bounty | 5 through wave 9; 7 through wave 18; 9 thereafter |
| Victory | +1 for a newly cleared, nonfinal wave |
| Interest | +1 per 10 gold held at battle start; maximum +3 |
| Win streak | +1 from the third consecutive win; +2 from the sixth |
| Defeat | Lose one life; no income or XP; streak ends |
| Army | 3 initial slots; +1 per 3 experience; maximum 9 |
| Experience | 1 per cleared wave; training buys up to 3 for 5 gold |
| Reserves | 6 slots; 9 with Pack train |

Without training, capacity grows at waves 4/7/10/13/16/19. Income is previewed
before commitment and broken down on the result screen. Higher bounties fund
later native creatures while the interest ceiling remains three.

Camps follow every third wave through 27. The first offers a choice of three
pacts. Later camps offer pact improvements, native companions, an unowned shop
or reserve boon, and recovery or gold. Pact rank is capped at two improvements;
completed pacts receive useful companion choices instead of another upgrade.
When the boon pool is exhausted, a camp may have two useful choices. It does not
offer six gold beside an otherwise identical twelve-gold reward.

Companions progress from Orc seers to Ingos and Suslanger wormheads. They use
normal reserve/army slots and native stats. One temporary reserve overflow slot
prevents a camp companion from disappearing when the bench is full; a second
overflow is blocked while other rewards remain available.

## Pacts

Only the selected pact applies. Count distinct eligible **deployed** families;
reserves, duplicates and the guest cannot satisfy their own condition.

| Pact | Condition | Native guest line by recruitment region |
| --- | --- | --- |
| Wild kin | Three beast families: boars, wolves, bats, toads, white tigers, spiders or either harpy family | Wolf → white tiger → giant spider |
| Tribal council | Two evolved families among tribal fighters/shooters, trolls, ogres and harpies | Orc seer → foxbat → black wormhead |
| The vanguard | Three melee families | Tribal shooter → foxbat → grey harpy |

Each regional guest line has three native forms selected by pact rank. Advancing
to waves 10 and 19 changes the guest to the stronger regional line while keeping
its earned rank. Camp previews and evolution feedback show the actual output.
The guest occupies no slot, cannot be sold or merged, disappears if the formation
no longer qualifies, and returns next battle. Auto-arrange preserves an eligible
pact before filling remaining positions by native level.

## Winter battlefield and interface

The arena uses the original Ingos `zone11` snow atlas, snow surface metadata,
winter trees/rocks and the existing ruin models. A continuous powder surface
replaces the courtyard pattern. Uneven conifer and rock groups, smaller saplings,
rolling perimeter banks and snow-covered ruin tops frame the flat fighting area.
There is no second opaque floor over the snow. Native footprint geometry, connected travel troughs, blood
decals and contact shadows all reach that same surface. The local material
increases compacted-snow contrast for the spectator camera and survives graphics
option changes without modifying campaign shaders.

Ground marks are ready before the first attack. Arena blood events create native
hit splatter as well as particles. A local spectator death queue uses the native
death delay to create corpse pools: the campaign's controlled-party visibility
filter does not apply to these fully AI-controlled teams. Pools can finish while
combat is frozen for the result animation. The existing blood, footprint and
snow-deformation options remain respected.

The existing compact HUD stays: recruitment above, reserves below, round/menu
in one corner, gold/lives and one main action at the bottom. Details appear on
hover. The opening is now a centered, bounded setup panel; no starter-company
selector remains. Placement, swapping, withdrawal and selling release selection.
All added and changed copy is in English, Russian and German.

## Saves and evidence

Schema 7 preserves earlier armies, investment, gold, shop RNG and training, and
adds the remaining preparation time.
Active old runs can continue into the extended sequence. A completed 18-wave
save remains completed with its original length, including after re-saving.
Campaign saves are untouched. Schema numbers are independent of public releases.

The [winter validation record](validation/arena-winter-2026-10-16.json) records
native combat runs, real pointer interactions, snow/blood pixel checks,
localization coverage and layout captures. Historical research and older
benchmarks remain in `docs/validation`; their clear rates are not current rates.
The [economy research](design/arena-economy-research.md) explains the selected
Auto Chess / Underlords patterns.

Automated purchase policies are probes, not estimates of human win rates. Native
power gaps make some openings more forgiving than others; the current limits and
measured outcomes are recorded with the validation, rather than claiming equal
build strength or completed human playtesting.

## Preparation and feedback

Each preparation round lasts up to 45 seconds. The player may start early;
expiry starts the encounter. If no creature is deployed but reserves are owned,
they are arranged automatically. A company without recruits forfeits one life.
Menus, guide, training and shop-improvement dialogs pause the timer; camp choices
and results are untimed. Shopping, selecting, placing and undo do not refund time.
Schema 7 saves the remaining countdown. Older saves and interrupted battles resume
with 45 seconds; subsequent waves, retries and departures from camp reset it.

Moving a creature updates its existing actor and navigation position. Other
actors retain their identity and animation. Offer and reserve previews retain
render targets through selection and price/count/lock changes; arena previews
render at physical HUD resolution. Evolution and results appear on the right,
leaving the battle center clear. Results keep the 1.6-second finish interval and
one next action. Camp rewards remain deliberate choices.

Pact selection shows the actual summoned ally, current qualifying-family count,
eligible families and the two-star requirement where applicable. The company
counter shows Pact N/N; hovering lists which families are deployed, waiting in
reserves, still missing or need evolution. Multiple copies of one family count
once. These presentation changes do not alter pact bonuses or native creature stats.

See [flow validation](validation/arena-flow-2026-10-16.json) for current evidence.
