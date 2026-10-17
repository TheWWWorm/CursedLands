# Trials of the Allods

Current design, 17 October 2026. Older validation files describe earlier builds.

## Core loop

Buy a team, arrange it, fight under AI control, then reinvest the rewards.
Preparation lasts 60 seconds on Standard, 45 on Veteran and 30 on Champion;
Start battle begins early. Menus pause the
clock. An empty battlefield deploys owned reserves at expiry; an entirely empty
company forfeits a life. The final attack gets 1.6 seconds to finish animating,
then a four-second side result advances automatically. No wave confirmation is
required. Final victory/defeat offers a new expedition.

There are thirty authored waves, three lives, and harder expeditions after a
clear. A loss retries the same wave without income or XP farming. It grants one
free shop refresh to help the player change their formation. Every fifth victory
opens one camp reward choice; selecting the reward starts preparation immediately.

## Company level and recruitment

The opening has no creatures, ten gold, three army slots and eight reserve slots.
Its six offers include every early family. Purchases enter reserves. Subsequent
shops have five offers, six with Well connected. One offer can be locked. Refresh
costs two gold, one with Quartermaster, or zero for the first refresh after defeat.
An empty company cannot spend its last recruitment gold on refreshes or training.

Training is a direct HUD action: five gold buys five XP. Each cleared wave grants
one XP. Company level determines both army capacity and the odds of each recruit
tier. Leveling does not replace an existing shop; the next refresh uses the new
odds. All new offers have one star. Stars are earned by collecting copies, not by
purchasing a separate shop upgrade.

| Level / slots | Cumulative XP from start | Tier 1 | Tier 2 | Tier 3 | Tier 4 | Tier 5 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | 0 | 70% | 30% | 0% | 0% | 0% |
| 4 | 6 | 55% | 45% | 0% | 0% | 0% |
| 5 | 18 | 40% | 40% | 20% | 0% | 0% |
| 6 | 36 | 30% | 35% | 27% | 8% | 0% |
| 7 | 60 | 22% | 28% | 28% | 20% | 2% |
| 8 | 90 | 15% | 20% | 25% | 30% | 10% |
| 9 | 126 | 10% | 15% | 25% | 35% | 15% |

The shop first rolls a tier, then chooses uniformly among that tier's families.
An empty-company affordability guarantee is the one explicit exception. Tiers
measure recruitment rarity; prices also account for each family's native power.
The shop-odds tooltip shows the actual price range within each tier. Star rank
measures evolution within a family.

| Tier | Family | Price | Copies at each evolution |
| --- | --- | ---: | --- |
| 1 | Boars, Tribal fighters, Wolves | 1 | 3, then 3 |
| 2 | Tribal shooters, Bats | 2 | 2, then 3 |
| 2 | Toads | 2 | 3 |
| 3 | White tigers | 4 | 2 |
| 3 | Spiders | 3 | 3 |
| 4 | Blue trolls | 7 | 2 |
| 4 | Stony harpies | 6 | 2 |
| 5 | Sand ogres | 10 | 2 |
| 5 | Grey harpies | 7 | 2 |

Twelve families use twenty-nine existing forms from Gipath, Ingos and Suslanger.
The native forms and spells are retained. Recipes remain adapted to their actual
native power jumps; this is not a universal three-for-one conversion of original
creatures. Evolution works from wave one, preserves a deployed copy's identity
and position, and shows a short side comparison, sound and field highlight.

## Difficulty and spell damage

Standard retains the thirty base encounters. Veteran adds a melee reinforcement
from wave three, progressing through stronger original forms in later regions.
Champion also adds ranged/magic support from wave six and another caster from
wave ten. Its late caster additions include octopuses, providing pressure against
physical-armor formations. No prototype statistics are changed.

Damaging spells cannot hit creatures on the caster's own team in Trials. The rule
applies equally to both sides, including persistent acid fog. Beneficial spell
filters and campaign friendly-fire behavior retain their original rules.

## Automatic alliances

There is no pact selection, chosen alliance, star requirement or bonus guest.
Every distinct deployed family contributes to all of its listed traits. Copies,
different star forms of that family, reserves and camp companions add no extra
counts. Multiple alliances operate together. Removing a required creature updates
the bonus immediately; deaths during combat do not recalculate the starting lineup.

| Alliance | Members | Thresholds | Effect at each threshold |
| --- | --- | --- | --- |
| Beasts | Boars, Wolves, Bats, Toads, White tigers, Spiders | 2 / 4 / 6 | All allies: +10 / 20 / 30% attack damage |
| Horde | Tribal fighters, Tribal shooters, Blue trolls, Sand ogres | 2 / 4 | Members: +15 / 30% maximum health |
| Warriors | Boars, Tribal fighters, Blue trolls, Sand ogres | 2 / 4 | Members: +20 / 40% physical armor, plus 2 / 4 armor |
| Hunters | Wolves, Tribal shooters, White tigers, Spiders | 2 / 4 | Members: +15 / 30% accuracy, +10 / 20% action speed |
| Mages | Bats, Toads, Stony harpies, Grey harpies | 2 / 4 | Enemies: −20 / 40% fire, acid and lightning armor |

Bonuses are applied to private encounter actors, restored from cached native values
on each formation change. They never edit the prototype database or campaign.
Health bonuses preserve native body-part mechanics. Armor keeps the original damage
types; elemental reductions cannot make zero armor negative. Action speed uses the
native action calculation, including animation-duration limits. Live inspection
shows effective combat values and identifies that alliance bonuses are included.

A compact left-edge list shows progress. Hover reveals the current bonus, thresholds
and contributing families. Shop icons and creature details show membership before
purchase. Original localized creature names remain in EN/RU/DE.

## Economy and camps

Each newly cleared, nonfinal wave pays five bounty plus one victory gold. Savings
at combat start earn one per ten, capped at three. Three consecutive wins add one;
six add two. A defeat ends the streak. Base prices and income stay consistent across
regions, so unlocking stronger offers is an investment decision rather than a wave
schedule that also inflates the purse.

One-star sales refund their purchase price. Evolved sales return two thirds of
investment, capped at replacement cost. Gift companions return one third. Training,
purchases, deployment, sales and their merge chains are undoable; refreshing reveals
new randomness and clears undo. Neither undo nor purchasing refunds preparation time.

Camps at waves 5, 10, 15, 20 and 25 offer ten XP, an unowned company improvement,
and eight gold or one recovered life. Ten XP is worth more than the cash alternative
when spent on training; cash has broader uses. At maximum level, a native companion
replaces XP. Exhausted improvement pools also offer a companion without duplicates.
Pack train adds three reserve slots; Quartermaster reduces refresh cost; Well
connected adds an offer. Companion overflow is preserved rather than silently lost.

## Presentation and compatibility

The native Ingos snow battlefield, original trails, blood and scenery remain.
Moving creatures reconciles existing actors without restarting other animations.
At each round's preparation, both sides run into formation. Placement issues a
native pathfinding command at an accelerated presentation pace; it does not
teleport an existing actor. New deployments enter from nearby clear ground.
Returning a creature to reserves removes its field actor. Movement keeps native
run clips, turning and snow footprints, without advancing combat or perception.
An early start waits for formation to settle; menus pause that movement. A second
move replaces the destination, and saved formations store their intended positions.
Shop/reserve previews retain their render targets and render at physical HUD scale.
The UI uses a 1280×800 logical canvas and scales consistently through 4K. Hover
inspectors, sell/return targets and notices leave the center of the battlefield clear.
The opening uses a separate, wider composition with original creature previews,
starting gold, difficulty and a prominent Begin action. Its optional seed entry
is collapsed initially; saved expeditions retain a visible resume action.

Arena/Sandbox buttons are removed from player menus and controller targets. The
PvE expedition remains accessible. The internal `--arena` entry remains available
for development and regression tests.

Save schema nine migrates older runs without losing armies or purchased capacity.
Existing recruits keep their actual paid investment, including when sold. An old
active 45-second preparation is preserved through migration and subsequent saves;
the next preparation uses the chosen difficulty's duration.
Retired shop investment and earned pact upgrades convert to XP. Old pending camp
screens advance into preparation; no retired pact choice can reappear. Completed
18-wave saves stay complete. Public release versions and artifacts are unchanged.
