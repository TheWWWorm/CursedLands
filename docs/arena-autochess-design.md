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

The experimental roster has **30 recruit chains and 90 original forms**. Each
chain has three different archetypes. No step merely ages the previous creature,
and no archetype appears in two chains. Distinct original combat roles, clans and
named characters provide the larger roster without inventing new models.

| Shop cost / tier | Recruit chains |
| --- | ---: |
| 1 gold | 7 |
| 2 gold | 7 |
| 3 gold | 6 |
| 4 gold | 6 |
| 5 gold | 4 |

Only first forms appear in the shop. Both upgrades require three copies, making a
three-star creature an investment of nine first forms. Two- and three-star forms
are obtained through evolution. Tier-four and tier-five shop figures have a subtle
rarity glow. Fourteen low-cost chains can appear at the opening; the six starting
offers are distinct and include melee and ranged/magic choices. Later offers roll
a tier with the existing level table and choose uniformly within it. Owning a chain
does not secretly increase the chance of finding more copies.

Campaign prototype levels are not shop prices. Trials apply explicit price/star
budgets to copies of the native data. Base health by cost is 35/48/66/90/120, with
role factors of 1.0 melee, 0.9 ranged and 0.78 magic. Bow-using casters retain the
0.9 factor because they cannot parry; utility-only spells do not classify a melee
fighter as a caster. Star health is ×1/×2.2/×5;
attack damage is ×1/×1.6/×2.8. Accuracy, defense, action speed and general armor
also grow with cost and stars. Native resistance ratios, movement, attack types,
weapons and spell behavior remain. Physical attack damage accounts for native
attack cadence, with additional damage and accuracy for ordinary ranged attacks.
Recruits recover one quarter of their native regeneration, capped at 0.5% maximum
health per 15 native ticks (0.825 seconds). Faster-recovering creature types retain
their advantage without outhealing the entire bounded attack budget.

Offensive spells use real effect runes to fit the same budget, including area
and extra-target costs. Healing receives 60% of the comparable offensive budget.
When a native spell cannot reach a small enough effect, the Cut Effect rune and
a slower action rate preserve its heavy hit. Trials self-healing waits until
half health, and elemental protection requires a matching enemy damage source.
Recruits skip night vision and quieter-footstep buffs in the revealed arena.
Native AI also re-evaluates multiple attack options against its last opponent
and scores spell damage using the damage school used by combat.

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

Version-11 saves migrate the previous forty-family roster to these chains,
preserving rank, deployment and recorded investment. Loaded snapshots are copied
before migration. A first-form sale returns its recorded investment; evolved
sales return the lesser of the full copy cost and two thirds of investment.
Online previews use the host's quote. If the unit changes before a quoted sale
arrives, the host rejects it instead of accepting a different price.

See [the roster experiment](validation/allods-challenge-2026-10-18.md) and
[the combat-budget follow-up](validation/trials-combat-balance-2026-10-18.md)
for native fight comparisons, policy results and remaining playtest questions.

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
The transparent left sidebar shows only the local company’s damage, sorted by
contribution, with native pixel portraits, stars and bars. Dead combatants remain
in that round’s list. Compact alliance icons show thresholds below it. Brief central
banners announce rounds, preparation countdowns, income and victory/defeat. Online
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
