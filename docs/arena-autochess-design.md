# Autochess

A second mode alongside Expedition. One human and nine computer opponents each
start at 100 health, with ten gold, level three and an independent shop and army.
This is a local game against the CPU. No network players are implied.

## Rounds and opponents

Rounds 1–3 and every fifth round use the expedition's native creep encounters.
Other rounds shuffle the surviving players into pairs. The human receives a
different opponent from the previous player round when alternatives remain.
With an odd population, one CPU fights a copy of another living army; that donor
cannot take damage from the copied fight. Pairings are fixed before preparation
and survive reloads.

Each board runs the existing native combat engine, including spells, armor,
movement and both armies' alliances. The human board is rendered. Other boards
run in bounded work per frame and cannot change global time scale or sound.
Menus and combat pause stop the background work too. The round settles once all
boards report a result; health and income cannot be applied twice.

Defeat costs `3 + floor(round / 5) + surviving enemy stars` health. A draw damages
both players. After round 30, add `5 × (round − 30)` to defeat damage so a stalled
game ends. At zero health a player is eliminated; the last survivor wins. For a
simultaneous final elimination, highest post-damage health wins, then lowest seat
number breaks a tie. The human receives a final place on elimination or victory.

## Building armies

CPUs spend the same gold on the same offers, training and refreshes as the human.
They favor different family groups, pursue matching copies, level gradually and
keep savings when healthy. They use persistent armies and the regular evolution
recipes, then arrange melee and ranged creatures. They receive no free units or
stat multipliers. Army strength still needs broader playtesting across seeds.

Every completed round pays five base gold plus interest. A win adds one gold and
the existing winning-streak bonus. XP advances on every round, including defeat.
There are no expedition camps, retries or free refreshes after a loss. The level,
shop odds, stars, prices and alliance rules are shared with Expedition.

## Interface and saves

The opening mode selector remembers the last mode. Each mode retains its own
resume action and save (`arena-expedition.json` / `arena-autochess.json`). The
new save contains all ten companies, health, places and pairings. An interrupted
fight restarts preparation against the same opponent without partial damage or
income. Classic saves do not update expedition difficulty unlocks.

The round badge shows the current round. Health replaces expedition lives, and
an inspectable player list shows standings and the current rival. Creature hover
details temporarily replace that list. Scouting, rule explanations, results and
errors are translated into English, Russian and German.
