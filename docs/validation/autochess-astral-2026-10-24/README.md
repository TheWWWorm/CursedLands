# LiA autochess validation — 2026-10-24

The optional LiA mode combines the standard 29 recruit families with eight
expansion families and five native commanders. It requires both installations.
Original campaign rows and the standard recruitment pool stay unchanged.
Expansion saves use `arena-autochess-astral.json`; old schema-15 saves remain
readable. Schema 16 records the mode, and online protocol 4 requires matching
mode and native combat data.

## Native content and portraits

`ArenaExpansion.RECRUITS` records the source prototypes and MOB palettes for
foxes, leopards, exploding hares, undead deer, Jigran wolves, Jun lizards,
undead warriors and undead mages. Each has three arena ranks. Creature icons
were rendered from those models, equipment and palettes.

The commanders are Kir, Kel, Feiruz, Aliya and Sahilia. LiA assets have their
own namespace because its human bodies and interface heads differ from the
base edition. The selected interface meshes use the same `(2u, 2v - 1)` atlas
mapping as the original portrait renderer, including group-4 male meshes
with negative V coordinates. Texture repeat maps those coordinates correctly.
Skipping this transform painted neck/clothing regions over the face. Group-1
and group-4 replacement heads are fitted only for the selected commanders;
ordinary LiA creatures retain their authored body heads.

Native LiA executable evidence in `kir-native-rendering-evidence.json` traces
`FUN_00578e80` and `FUN_005788b0`: face names use the actor's runtime skin,
sex, build and hair, and a 128-square face is placed in the 256-square atlas.
The existing original HUD reproduction provides a second mapping comparison.
Interface paintings are displayed without scene lighting, avoiding extra dark
facets on their already-painted cheek highlights. All 21 selectable appearances
were rendered in neutral, smile and frown states. Attached neutral portraits
show the resulting mapping; short blends and event ownership remain in use.

Original story variants are sub-selections under the same character: Zak has
three appearances, Kir four, and Kel two. Other characters have one. Skin IDs
are validated and saved in the existing commander field. Multiplayer preserves
the complete choice while NPC allocation excludes the human's base character.
Kir's transformed variant uses native Hero4/skin44; Hero1/skin41, Hero2/skin42
(face wrap), and Hero3's equipment remain selectable. These use the installed
paintings; no facial markings were invented or painted over them.

## Checks

| Fixture | Result |
| --- | --- |
| `arena_astral.gd` | 1,087 checks, zero failures |
| Standard `arena_roster.gd` | 1,548 checks, zero failures |
| `arena_astral_online.gd` | 40 checks, zero failures |
| `arena_astral_worker.gd` | 43 checks, zero failures; nine boards match inline combat |
| `arena_astral_ui.gd` | 152 checks, zero failures; EN/RU/DE layouts, all 21 appearances, all eight creatures |
| Skin layout subset | 64 checks, zero failures; 1280×720 and 1600×900 EN/RU/DE |
| `arena_astral_events_ui.gd` | 213 checks, zero failures; live and historical reactions over ENet and WebSocket |
| Independent host/client processes | Both transports pass six rounds, including PvP rounds 4 and 6 |

The independent peers agree on all nine health values after round six. Both
receive rabbit explosion events. Wrong-mode and mismatched-content clients
are rejected before gaining a seat. Local combat workers mount the same second
installation and return matching results, survivors and simulation clocks.

Headless rules tests cover repeated mounting, original-data immutability,
three-star merges, shared shop pools, legacy saves, malformed mode snapshots,
localization, all selected models and skins, save restoration, the face UV transform, and deterministic
combat. Rabbit blasts happen once, affect at most three nearby enemies, and do
not damage allies; distant kills provide a counter.

Graphical checks ran through GPU Lab with isolated muted profiles, a free
cursor, FPS visible and a 30 FPS limit. Source UI checks used Godot 4.7; their
logger excludes the already-known stock-engine TexUpscale push-constant
diagnostic. Export checks use the qualified project engine separately.

## Balance evidence

The final native-combat sweep contains 1,392 duels: each expansion family versus
all 29 standard families, from both sides at all three star ranks. The separate
composition sweep contains 112 battles across eight equal-budget teams, two
seeds and both sides. Each team has six two-star creatures costing 54 gold.
These are bounded counter checks, not proof of an optimal metagame.

| Formation | Wins out of 28, draws count half |
| --- | ---: |
| Standard casters | 13 |
| Standard screened casters | 3.5 |
| Standard mixed | 20 |
| Standard assault | 18.5 |
| LiA mixed | 17 |
| LiA hunters | 10 |
| Rabbit screen | 10 |
| Screened plague casters | 20 |

Early sweeps overvalued deer, Jun damage and plague output. Final multipliers
reduce those outputs while preserving the Jun frontline role. The hare has a
weak bite and a single 30/55/120 fire-damage blast, up to three enemies within
2.5 m. Its proximity fuse is 0.6 seconds. The bot planner values its bounded
blast instead of treating it as a weak conventional attacker.

Single-target duels are unfavorable for a sacrificial hare and understate
plague area damage, so team results informed these choices. The two-star deer
won the ten same-tier duel cases in this sample; mixed LiA teams won 17/28.
Additional player feedback may justify tuning that rank, particularly in
compositions beyond this fixed sample.

## Reproduction

Use the game tool runner with `--ei-path` pointing at base data and
`--astral-path` pointing at LiA data. CPU fixtures can run headlessly. Run
`arena_astral_matchups.gd` with `--from=30 --opponents=29` and
`--rank=0`, `1`, or `2`; `arena_astral_compositions.gd` uses the fixed equal-budget
formations. The peer runner accepts `--astral /absolute/path/to/LiA`.
Graphical fixtures require GPU Lab and the normal development profile settings.
