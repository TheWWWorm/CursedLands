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

The round settles once every living owner reports a result. Health and income
cannot be applied twice. Defeat costs `3 + floor(round / 5) + surviving enemy stars`
health, plus `5 × (round − 30)` after round 30. A fight ends after two simulated
minutes, or ten seconds without positive damage. Draws cost both owners ten
health and grant no victory bonus. A copied army never penalizes its donor.

At zero health a player is eliminated; the last survivor wins. For a simultaneous
final elimination, highest post-damage health wins, then lowest seat number breaks
a tie. The human receives a final place on elimination or victory.

## Building armies

CPUs spend the same gold on the same offers, training and refreshes as the human.
They recruit in visible steps throughout preparation, favor family groups, pursue
matching copies, level gradually and keep savings when healthy. They receive no
free units or stat multipliers. Starting early completes their outstanding shop
choices before all formations lock. Models prepare one per frame across all boards
while shop transactions and formation changes are briefly locked. After staging,
all boards begin on the same bell and the combat shop reopens. CPU purchase
preferences follow traits across the expanded forty-family pool. The five shop
tiers contain 7, 9, 10, 8 and 6 families; sixteen are available at the opening.

Each CPU seat keeps one of four spending strategies. Economy targets fifty
saved gold, expansion targets thirty and an earlier company level, evolution
targets forty and more searches for matching copies, and tempo targets twenty.
Savings ramp up after round three; low health and losing streaks release the
bank. All strategies fill empty army slots, replace weak units, value native
spells and armor, and retain coherent upgrade lines rather than unrelated bench
singles. Upgrade estimates count the lower-rank copies needed to complete either
remaining evolution, including progress already held in two-star copies. Native
AI casters do not pay player stamina costs, and shopping estimates follow that
rule. Formation selection considers distinct-family tribe thresholds and
places ranged recruits behind melee troops. These estimates affect shopping
only; combat uses the same native stats and rules as the player's army.

Sixteen appended families preserve existing save indices:

| Family | Tier | Gold | Copies for first evolution | Tribes |
| --- | ---: | ---: | ---: | --- |
| Brigands | 1 | 1 | 3 | Warrior, hunter |
| Marksmen | 2 | 2 | 2 | Hunter |
| Battle mages | 3 | 4 | 3 | Mage |
| Zombies | 3 | 4 | 3 | Horde, warrior |
| Guards | 4 | 6 | 2 | Warrior |
| Ice elementals | 4 | 6 | 2 | Warrior, mage |
| Apprentices | 1 | 1 | 3 | Mage |
| Hounds | 2 | 3 | 3 | Beast, hunter |
| Woodsfolk mystics | 3 | 3 | 2 | Mage |
| Ghouls | 4 | 6 | 2 | Horde, hunter |
| Red eyes | 4 | 7 | 2 | Beast, mage |
| Dragons | 5 | 9 | 2 | Beast, mage |
| Cyclopes | 5 | 10 | 3 | Horde, hunter |
| Shadows | 5 | 8 | 2 | Horde, mage |
| Imperial archers | 5 | 8 | 2 | Warrior, hunter |
| Storm banshees | 4 | 7 | 2 | Horde, mage |

Every second evolution needs three copies. Cross-kin forms follow a role or
tribal connection: apprentices become forest spellcasters, and woodsfolk mystics
become a white unicorn through the forest/mage theme. The campaign's source
prototypes remain unchanged. Dragons and storm banshees gain stronger native
effect runes on evolution. The final grey harpy and cyclops use 44 general armor
instead of their original boss value of 150, preserving each elemental
resistance ratio. Shop details and combat use these same recruit adjustments.

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

Held Q/E smoothly accelerates camera rotation; right-button dragging rotates
after a small drag threshold and a stationary right click keeps its cancel
behavior. Camera motion uses real elapsed time at either battle speed. Menus
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
Classic saves do not update expedition difficulty unlocks.

The compact right-hand list shows names and health, with a small grid button for
the overview. Expanding it reveals company level and gold. Names and health use 14-pixel
reference text; the compact panel is 164 pixels wide before HUD scaling. A copper
left-edge marker identifies the watched board without adding a row background.
The last ten seconds of preparation or combat change the clock to coral and pulse
its opacity; pausing also stops the pulse. CPUs use original
localized NPC names: Erfar, Estera, Babur, Tilvar, Valrasian, Diera, Shei-Var and
Kardaur. Hover details temporarily replace the standings. Names, help, status,
errors and both modes' rules are localized in English, Russian and German.

## Online play

The opening also offers **Play online**. Up to nine humans compete with their
own companies; computers occupy empty seats. A co-op-style host/join window
handles addresses, passwords, readiness and the roster. The host owns the shared
60-second preparation timer and all native battles; menus never pause online
play. Guests who disconnect become computers, and eliminated players can keep
watching. See [online autochess](autochess-online.md) for connection instructions,
rules, implementation and limitations.
