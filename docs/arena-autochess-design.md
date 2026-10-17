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
match controls global speed.

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
choices before all formations lock. Strategy still needs broader balance testing.

Every completed round pays five base gold plus interest. A win adds one gold and
the existing winning-streak bonus. XP advances on every round, including defeat.
There are no expedition camps, retries or free refreshes after a loss. Level,
shop odds, stars, prices and alliance rules are shared with Expedition. Combat
purchases enter reserves or defer deployed evolutions until the next round;
existing fighters and their bonuses keep their start-of-round state.

## Interface and saves

The opening remembers the last mode. Each mode retains its own resume action and
save (`arena-expedition.json` / `arena-autochess.json`). The save contains all nine
companies, health, places, pairings and unfinished CPU shop plans. Interrupted
fights restart preparation against the same opponent without partial payment.
Old ten-seat local previews migrate to nine, retaining the human army and economy.
Classic saves do not update expedition difficulty unlocks.

The compact right-hand list shows names and health, with a small grid button for
the overview. Expanding it reveals company level and gold. CPUs use original
localized NPC names: Erfar, Estera, Babur, Tilvar, Valrasian, Diera, Shei-Var and
Kardaur. Hover details temporarily replace the standings. Names, help, status,
errors and both modes' rules are localized in English, Russian and German.
