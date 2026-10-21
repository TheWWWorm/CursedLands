# Autochess

A second mode alongside Expedition. One human and eight computer opponents each
start at 100 health, with ten gold, level three and an independent shop and army.
The nine home boards form a 3×3 map, with the human in the center.

## Rounds and opponents

Rounds 1–3 and every fifth round use the expedition's native creep encounters.
Other rounds shuffle surviving players into pairs. The human receives a different
opponent from the previous player round when alternatives remain. With an odd
population, one CPU fights a copy of another living army; that donor cannot lose
health from the copied fight. Pairings are announced before preparation and
survive reloads. Enemy copies teleport onto each home board at the shared bell.

All home boards run concurrently in the native combat engine, including spells,
armor, movement and both armies' alliances. Scouting switches the live view,
without pausing or replacing a company. The overview shows every board and its
moving army markers; clicking a cell focuses that board. Menu and combat pause
stop all boards. Each native world has its own simulation state; only the human
match controls global speed. Scouting enables the viewed world's battle audio.
Particles, lightning and their bounds use their own board origin, and hidden
boards hide their top-level effect renderers. Combat stops damaging projectiles
at resolution, then drains the remaining visual effects for up to 1.5 seconds
without advancing health or the combat clock.

Elemental charge-up particles use the same animated mouth or hand as the
released projectile. Horror lightning follows its extended fingertips. Its
authored hovering death cycle descends onto the snow and then holds its final
pose, including after combat and when a finished board is first scouted.

Health is deducted when a board finishes, while the other boards keep fighting.
The shared round settles income and places once every owner who entered the round
reports a result, including owners eliminated by that result. Repeated results
cannot charge health twice. Defeat costs `3 + floor(round / 5) + surviving enemy stars`
health, plus `5 × (round − 30)` after round 30. A fight ends after ninety simulated
seconds, or ten seconds without positive damage. Draws cost both owners ten
health and grant no victory bonus. A copied army never penalizes its donor.

At zero health a player is eliminated; the last survivor wins. For a simultaneous
final elimination, highest post-damage health wins, then lowest seat number breaks
a tie. The human receives a final place on elimination or victory.

## Building armies

Balance comparisons must include damage after armor for the actual damage type,
resistances, armor reduction, attack/cast cadence and alliances. Raw health and
damage totals alone are not a balance verdict. Use mirrored native fights in
both duels and supported teams, including equal-investment alternatives.

The roster has **28 species with three star ranks each**. A species has one shop
price and stays that species through both upgrades. Different age variants are
rank appearances, never separate offers. Five original species have one model
reused at higher ranks; their stars and combat values identify the upgrade.
There are no human recruits. Goblins, lizardmen, woodsfolk, orc shamans and undead
retain distinct native silhouettes alongside animals, spirits and larger monsters.
All figures and pixel portraits use the original models and clan palettes.
Sixteen species use different native palettes as they gain stars. Species with
two palettes reserve the contrasting appearance for three stars; species with
three palettes use one per rank. Trolls progress from green to blue to black,
banshees from light to dark, and dragons from green to blue to red. Original
prototype tiers determine the order where the variants differ in strength;
equal-tier variants are cosmetic choices. Palettes have no additional combat
effects. Original localized names follow the visible colour or clan.

| Cost | Species |
| --- | --- |
| 1 | Boars, wolves, rats, bats, goblins, toads, skeletons |
| 2 | Tigers, spiders, armadillos, lizardmen, woodsfolk, zombies |
| 3 | Orc shamans, trolls, ogres, harpies, hyenas |
| 4 | Evileyes, banshees, unicorns, wisps, elementals |
| 5 | Dragons, golems, horrors, wormheads, cyclopes |

Only one-star recruits appear in the shop. Three matching copies form two stars,
and three two-star copies form three stars: nine base copies in total. Thirteen
species can appear at the opening; its six offers are distinct and include melee
and ranged/magic choices. Later offers roll a tier with the existing level table
and choose uniformly within it. Ownership does not increase duplicate odds.

Each offer shows one native figure, price, traits and a short line of nonzero
owned counts by star rank. The inspector shows the three appearances in a compact
strip and a short description of the creature's role. Its compact preview and
paired health/armor row leave all three ranks visible without a repeated recruit
heading. The panel uses the available height above the reserves, with scrolling
reserved for longer company/alliance help. Upgrade-ready offers pulse
cyan and carry an arrow separated from the lock; four- and five-gold rarity glows
remain steady. One owned copy plus two matching shop offers marks both offers.
Inspector accents and stars use the species' price-tier color.

Reserves retain individual slot positions through purchases, swaps and saves.
Selecting a field creature and then an empty reserve slot withdraws it there.
Selecting an occupied reserve swaps the two creatures; either selection order
works. Matching triples combine even when reserves are full. Rank appearances
retain the species' rig, body proportions and combat prototype. Field models,
reserves, placement ghosts, evolution notices, inspector previews and portraits
share the same family/rank appearance, including online board snapshots.

Preparation travel uses native paths and locomotion at a faster presentation
pace. Blocked creatures retry around all current bodies after a quarter second
without progress. Routes and clear entrance positions may extend outside the
field into the navigable courtyard, then return to the exact deployment point.
Slow creatures receive a minimum travel speed; fast ones have a presentation
cap. This movement does not advance combat or apply damage. Pausing freezes it,
and a replacement command takes effect immediately.

Large native figures retain their fitted arena size through model replacements,
body effects and full enemy records. The authoritative fit travels with each
actor's appearance data, and is applied once to its collision body and to each
new model, including its locomotion height factor.

The default camera fits the playable clearing and tall figures between the side
HUD and reserves, using a 34-degree tilt and a diagonal horizontal orbit. Its
starting world height is unchanged from 1.18.0. The lower view fits the full arena
at a closer scale instead of cropping its outer combat positions. Manual orbit, zoom and panning survive
round transitions. The shop folds away at the battle bell and can be reopened.
Lighter ambient illumination and snow-colored fog avoid a dark frame at the map
edge. An atlas-textured snow ring continues beyond the courtyard, including the
nine-board overview. The arena retains all 256 footprint tiles across the clearing
and a 2.5 m shoulder; campaign deformation retains its 128-tile budget.
Preparation shows one low fire line along the forward deployment limit,
without side edges, a rear edge or a filled rectangle. The original animated fire
atlas supplies tapered orange flames anchored to the snow, with reduced brightness,
soft contact shading and warm reflected light. One visual emitter is capped at
256 particles, keeps flame geometry below a metre,
and creates no light nodes, scorch marks, sound or combat effects. It follows the
actual boundary while orbiting or scouting. Combat and overview remove the emitter
and clear the ground reflection, including deformed snow receivers.
The arena excludes procedural snow mounds and pebble scatter even at Ultra;
authored perimeter scenery and the campaign cover preference remain unchanged.

Round notices use bold, outlined, unframed text above the action, below an open
shop or near the top edge when it is closed. The opening title lasts at least
one second, and results last two seconds; a very short fight queues its result
without delaying health loss. Income omits zero bonuses. Damage and alliances
follow the watched company.

When a watched board resolves, every surviving winning creature launches the
native fire-bolt particle effect toward the losing player's standings entry.
The name flashes red. Health-loss numbers use the same original number atlas,
red/green colors, scaling, three-second drift and fade as combat: red for the
local player, green for opponents. Offscreen results still flash the name and
show the number. Health remains authoritative and immediate; the effect cannot
apply damage or replay on an unchanged snapshot. Its temporary particle world
and viewport stop after the animation.

Campaign prototype levels are not shop prices. Trials apply explicit price/star
budgets to copies of the native data. Base health by cost is 44/60/78/99/122, with
role factors of 1.0 melee, 0.9 ranged and 0.78 magic. Bow-using casters retain the
0.9 factor because they cannot parry. Star health is ×1/×2.1/×5.0, and attack
and offensive spell damage is ×1/×1.75/×4.0. Individual species modifiers distinguish
frontline endurance, damage and protection. Completing nine copies pays a larger
final-rank dividend than the initial species rebalance; it still compresses an
investment into one deployment slot and does not guarantee beating several units
at once. Price, shop odds, copy requirements and experience costs stay unchanged. Native movement, reach, damage types,
attack timing and spell effects remain.

Physical damage follows native attack cadence. Ordinary ranged attacks receive
an accuracy and damage allowance; melee gets a smaller allowance for travel and
exposure. Stars improve accuracy and defense, but do not also multiply action
speed. General armor starts at `3 + 2 × cost`, modified by species and
`1 + 0.15 × rank_index`; final-rank melee uses ×1.65 so flat armor
retains value against larger late-round damage packets. Typed resistance ratios are clamped to 0.6–1.8 before
applying that budget. Combat retains native flat subtraction with the existing Trials 80% mitigation
cap. There are no campaign-scale boss immunities hidden in five-gold recruits.
Recruits recover one quarter of their native regeneration, capped at 0.5% maximum
health per 15 native ticks (0.825 seconds). Faster-recovering creature types retain
their advantage without outhealing the entire bounded attack budget.

Offensive spells use real effect runes, including half steps from Cut Effect,
so the inspector, AI and combat share one definition. Multi-target budgets account
for each target paying flat armor. Persistent walls use their native total-lifetime
effect, not that value multiplied by the number of pulses; both power and Trials
AI valuation allow for partial contact with moving targets. Campaign AI retains
its original wall evaluation. Healing receives 50% of the comparable offensive
budget. A curse's minimum native packet remains large, so the horror pays for it
with a longer action interval.

Every star retains its species' spell kit. Unicorns add healing, orc shaman
Strength gives 15% damage and 25% health, and wormhead Haste gives three action
points to three allies. Self-healing waits until half health; elemental protection
requires an enemy with matching damage. Night-vision and quieter-footstep buffs
are skipped in the revealed arena. Native AI evaluates damage against the actual
school's armor and reconsiders attack options against its last opponent.

Six overlapping alliances reward distinct deployed species. Repeated copies and
reserves do not increase the count; most benefits apply only to members.

| Alliance | Thresholds | Benefit |
| --- | --- | --- |
| Beasts | 2/4/6 | +8/16/24% physical attack damage |
| Horde | 2/4 | +12/24% maximum health |
| Warriors | 2/4 | +2/4 flat physical armor |
| Hunters | 2/4 | +10/20% accuracy and +8/16% action speed |
| Mages | 2/4 | Opponents lose 15/30% elemental armor |
| Spirits | 2/4 | +3/6 flat fire, acid and lightning armor |

Creep accuracy, avoidance and exceptional boss armor are capped
by wave, while their native bodies, damage and spells remain. These changes apply
to Trials only, leaving the campaign database immutable.

CPUs spend the same gold on the same offers, training and refreshes as the human.
They recruit in visible steps, pursue copies, level gradually and keep savings
when healthy. They receive no free units or stat multipliers. Starting early
completes their shop choices before all formations lock. Models prepare one per
frame across all boards; after staging, all boards begin at the same bell.

Each seat keeps one of four spending policies. Economy targets fifty saved gold,
expansion thirty and earlier levels, evolution forty and more searches for copies,
and tempo twenty. Low health and losing streaks release savings. The evolution
policy delays levels to leave room in its budget for rolls; every policy still
fills empty slots, values spells and alliances, and replaces weak units. Army
valuation estimates sustained damage and survival, including parry, instead of
ranking units by the largest damage packet. These
are testable purchasing heuristics, not a claim of optimal or human play.

Level thresholds from the opening level three are 6, 18, 36, 55, 80 and 110
cumulative XP for levels four through nine. The last three thresholds were
reduced from 60, 90 and 126 so expansion leaves more gold for recruits and
upgrades. Training still costs five gold for five XP, and completed rounds
still grant one XP. At level nine the XP control is disabled and camp offers
a companion instead of more XP. Previously purchased training up to 126 remains
loadable and round-trips without changing its stored value; displayed XP caps
at 110. Shop odds, interest and the four policy reserves are unchanged.

Schema 13 migrates the former forty-family and thirty-chain saves by each
stored creature's actual species, retaining rank, UID, position, reserve slot and
paid investment. Retired human forms map to a creature with a corresponding
combat role. Exact old prototype IDs are validated before conversion. Migration
copies its input and combines newly matching triples. Current companies keep
stable reserve slots through round trips, including CPU reserves.

A first-form sale returns its recorded investment; evolved sales return the
lesser of the full copy cost and two thirds of investment. Online previews use
the host's quote and reject changed prices.

See [the balance depth validation](validation/trials-balance-depth-2026-10-19.md)
for paired full matches, armor-aware mixed-support comparisons, acquisition costs,
rendered UI evidence and remaining playtest questions. The initial
[species rebalance validation](validation/trials-species-rebalance-2026-10-19.md)
records the baseline before this tuning pass. The earlier experiment reports describe superseded
rosters and are retained as historical evidence.

Desktop solo combat uses a private authenticated loopback worker. The visible
process owns shopping, economy and saves, and displays the worker's frozen
start-of-round armies. A worker failure before combat falls back to local
simulation; a failure during combat returns to preparation with purchases kept
and partial outcomes discarded. Courtyards and static navigation survive rounds,
while old combat worlds, creatures and effects are released. Hidden boards do
not sample visual foot contacts. Shop render targets survive rerolls, and new
models are admitted across frames after background animation preparation.
Field models and shop portraits share one construction budget. Returning armies
appear at their saved deployment positions; newly recruited units still walk in.
Hidden courtyards suspend vegetation updates. Snow footprint/travel rasterization
uses an optional native kernel with the same ordered timestamps and shape math.
Prepared opponents remain hidden under their final world parent, outside combat
and navigation, so joining the fight retains their animation bindings. Arrows
share one immutable mesh and material; repeated volleys reuse compiled pipelines.
Known combat effects warm when entering the mode. Further warm-up collects one
courtyard per frame and spreads effect preparation across frames, before the
shared battle bell.

Combat health markers retain their canvas commands while their positions follow
the animated heads each frame. Health, rank and scale changes refresh those
commands; death, scouting and overview changes release obsolete markers. Stars
use cached images of the same shape. Picking resolves health-label hits before
body geometry, then visits overlapping silhouettes from nearest to farthest and
stops at the first exact hit. Nearby empty-space selection retains the exhaustive
comparison. Snow geometry coalesces new tiles over 50 real milliseconds and
publishes at most one completed sector per frame across all boards; existing
track textures keep updating each frame.
The native picking helper applies morphs and skeleton weights before exact
projection, preserving the script's vertex results and keeping its fallback.
Conservative extrema only skip frustum classification for wholly inside or
outside meshes; returned bounds still use the actual posed vertices. Immutable
picking geometry warms before the battle bell. Battlefield and tooltip positions
come from mouse events, with refreshes on entry, resize and focus, avoiding
repeated operating-system pointer queries during combat.

The nine-board overview retains interpolated movement at display rate, with
distant figure poses updated at 10 real updates per second and lightning
geometry at 20. Actor and bolt deadlines keep their individual phases after
slow frames. Repeated spell attachment samples share one result within the
same synchronous effect update. Focused boards retain their normal animation detail. Subpixel foot
contacts, hidden vegetation and particles beyond their existing draw distance
do not consume pose or emission work; emitter lifetimes and combat continue.
Private overview snapshots arrive one board per staggered slice, retaining ten
updates per board per real second and all pending visual events. The unit dots
use cached circle textures instead of retessellating hundreds of antialiased
circles on every frame. Native lightning geometry preserves the authored
noise, projection, colors and random stream, with a script fallback. Branch and
glow calculations use the same native random sequence. Compatible lightning
surfaces reuse their GPU buffers; short flashes draw immediately. Current
figure-part bounds are measured in native code without retaining older poses.
Overview labels retain canvas commands, and one courtyard publishes the shared
wind and cloud state. Clock theme settings change only at urgency transitions.
Arena snapshots apply their exact body-health payload directly. They do not
temporarily damage/heal actors through rounded aggregate health before restoring
the precise values; unchanged health leaves wound textures and poses clean.

Every completed round pays five base gold plus interest. A win adds one gold and
the existing winning-streak bonus. XP advances on every round, including defeat.
There are no expedition camps, retries or free refreshes after a loss. Level,
shop odds, stars, prices and alliance rules are shared with Expedition. Combat
purchases enter reserves or defer deployed evolutions until the next round;
existing fighters and their bonuses keep their start-of-round state.

## Interface and saves

Finished battle damage uses a snapshot of that battle's roster throughout
preparation, including after selling, evolving or withdrawing creatures. The next
battle clears it. Full board snapshots carry the previous report to workers and
online viewers. Standings keep winners green and losers red through preparation,
with localized result text available in the name tooltip; the next battle clears
those colors. Draws remain neutral.

Zero-health players show a localized pending status until all boards settle and
the round's tie rules assign a finishing place. Eliminations are announced once
per player, with sequential notices for simultaneous eliminations. Native result
fire bolts start at animated casting sockets, resolve their source and
destination through the HUD projection, and follow the losing player's identity
when standings rows move.

WASD pans relative to the current view, using the modern camera pan-speed setting.
Held Q/E smoothly accelerates rotation; right-button dragging rotates and tilts
after a small drag threshold. A stationary right click keeps its cancel behavior.
Shift + middle-drag pans, the wheel zooms, and Home explicitly resets the view.
Round starts and scouting retain the current yaw, tilt, zoom and pan. Text fields,
menus and focus loss suppress held camera input. Camera motion uses real elapsed time at either battle speed. Menus
use the original game cursor. Creature details pair localized tribe names with
their emblems, and text uses the displayed UI pixel density.

The player name is saved in the existing global configuration, edited under
Settings → Remake → Network and co-op, and reused by multiplayer and autochess.
It accepts up to 24 characters. Names, controls and recruit descriptions retain
English, Russian and German coverage.

The opening remembers the last mode. Each mode retains its own resume action and
save (`arena-expedition.json` / `arena-autochess.json`). The save contains all nine
companies, health, places, pairings and unfinished CPU shop plans. Interrupted
fights restart preparation against the same opponent without partial payment.
Old ten-seat local previews migrate to nine, retaining the human army and economy.
Partial combat saves retain the health from the beginning of the round so replaying
an interrupted fight cannot charge an earlier partial result again.
Classic saves do not update expedition difficulty unlocks.

The compact right-hand list shows names and health, with a small grid button for
the overview. Expanding it reveals company level and gold. Names and health use 14-pixel
reference text; the compact panel is 164 pixels wide before HUD scaling. A copper
left-edge marker identifies the watched board without adding a row background.
The last ten seconds of preparation or combat change the clock to coral and pulse
its opacity; pausing also stops the pulse. CPUs use original
localized NPC names: Erfar, Estera, Babur, Tilvar, Valrasian, Diera, Shei-Var and
Kardaur. Hover details temporarily replace the standings and remain available after elimination.
The transparent left sidebar shows only the watched company’s friendly damage, sorted by
contribution, with native pixel portraits, stars and bars. Dead combatants remain
in that round’s list. Compact alliance icons show thresholds below it. Brief upper-screen
notices announce rounds, income and victory/defeat without covering combat. Online
evolution notices follow the acknowledged roster update, without another purchase. Names, help, status,
errors and both modes' rules are localized in English, Russian and German.

## Online play

The opening also offers **Play online**. Up to nine humans compete with their
own companies; computers occupy empty seats. A co-op-style host/join window
handles addresses, passwords, readiness and the roster. Desktop hosts advertise
automatically through the same LAN discovery implementation as campaign co-op,
on autochess discovery port 27018; private solo workers never advertise. The host owns the shared
60-second preparation timer and all native battles; menus never pause online
play. Guests who disconnect become computers, and eliminated players can keep
watching. See [online autochess](autochess-online.md) for connection instructions,
rules, implementation and limitations.
