# Trials species rebalance, 2026-10-19

This is an unpublished diagnostic change on the working tree based on
`e0abbb1e9bdb8d641085daf7dfb51816ae48357a` (1.17.0). No published release was replaced.

## Design and references

The supplied Autochess_Balance_Workbook.xlsx and Single_Player_Autochess_Design.docx
were read without changing either file. The documents are design proposals, not
instructions. The requested multiplayer/solo mode structure remains. The useful
principles are recognizable creatures, explicit roles, soft counters, modest
alliance bonuses, and checking acquisitions and real combat together. Their
fictional roster, percentage-armor model, three-price economy, two-copy merges and
single-player campaign structure were not imported.

The abandoned cross-species ladder was replaced by 28 species. Each has one
shop price, three ranks and three-copy merges. No human recruits remain.
There are 7/6/5/5/5 entries at costs 1/2/3/4/5. Thirteen species can occur at
opening level; an observed 7.75% pairwise duplicate rate across 2,000 early rerolls
keeps hunting copies meaningful. Opening six-offer shops remain distinct and
include front-line and ranged/magic choices.

Stats, native actions, typed armor, spell runes, health recovery and all six
alliances are described in [the maintained design](../arena-autochess-design.md).
Migration accepts exact older prototypes before mapping their species and
preserves rank, identity, investment and placement. Removed humans map by combat
role. Current bot reserves now receive stable slots before snapshots, and saved
bot plans accept the existing twelve-roll low-health limit.

## Native verification

Tests used the patched Linux Godot 4.7 runtime with original English game data.
All nine regression suites in [checks.json](trials-species-rebalance-2026-10-19/checks.json)
passed: species/migration 2,154 checks; roster/shop distribution 1,515; economy 590;
alliances 602; readability 51; immediate result health 11; bot planning 21;
tournament lifecycle 175 (214 native boards); multiplayer host/client 80.
Campaign database hashes remained unchanged. Full reserves, both merge stages,
shared model IDs with explicit ranks, saved slots and old schemas 10/11/12 are covered.

The last UI pass covers 571 English checks and 569 each in Russian and German.
Every species at each star rank was inspected at 1280×720 and 1280×800. All details
and the final upgrade rank fit without vertical scrolling. Health and armor share
a row, the preview is compact, and the redundant recruit heading is removed.
The planning boundary is one front line, with no side/rear edges or fill.
Russian and German were also run against their original localized archives,
including native creature and spell names. The separate interaction/readability
suite passed 86 checks. English UI combat runs through the actual private worker
at 2×. Camera fitting, retained pose, watched damage, swapped reserves, instant
merges, shop highlights, result expiry, native loss numbers, one bolt per survivor,
no duplicated volley and particle cleanup are exercised. All test sessions use
free cursor, FPS display and muted sound. Translation lint found 2,809 entries,
179 dynamic arena keys and no missing translations.

## Armor and spell findings

The 588 raw-hit samples in [armor.json](trials-species-rebalance-2026-10-19/armor.json)
use Combat.absorb on each three-star species: seven damage channels at 12, 30 and
70 incoming damage. These use native flat subtraction and the existing Trials
80% absorption cap, not a percentage-armor approximation. The original campaign
armor option is not changed.

A solo three-star golem has 698 health and 24.505 general armor. Incoming 12/30/70
packets deal 2.4/6/45.495 damage. The horror has 440 health and 12.675 armor, taking
2.4/17.325/57.325 respectively. Their slow attacks, spell timing and regeneration
also participate in the fight tests; these examples alone do not determine power.

Native persistent spells scale both effect and armor by `4 / duration` each
pulse. An intermediate tuning pass incorrectly treated the listed effect as
per-pulse damage and weakened walls too far. The corrected budget uses total
lifetime damage and an estimated 65% contact fraction. Trials AI uses the same
fraction instead of multiplying the full-lifetime damage by the pulse count.
Campaign AI keeps its original behavior. Harpy teams changed from 0/8 wins in
both rank fixtures to 7/8 at one star and 5/8 at three stars. This is evidence that
the broken budget was repaired, not proof those exact win rates generalize.

## Mirrored comparisons

[Star fights](trials-species-rebalance-2026-10-19/star-fights.json) use two seeds
and both sides, including native movement, spells, hit checks and armor.

| Comparison | Fights | Wins for upgraded recruit | Draws |
| --- | ---: | ---: | ---: |
| promotion | 224 | 217 | 6 |
| three_gold | 140 | 65 | 2 |
| nine_vs_ten_gold | 140 | 19 | 3 |

`promotion` compares adjacent ranks of the same species. `three_gold` compares a
two-star one-gold recruit against a one-star three-gold recruit. `nine_vs_ten_gold`
compares a three-star one-gold recruit with TWO one-star five-gold recruits. The
last comparison uses two opposing slots and omits search/level spending; it must
not be presented as a complete strategy comparison. None of these fights timed out.

Supported-team tests place melee candidates in front and ranged/magic candidates
behind two shared protectors. Every same-price pair uses the same seed in either
order and both positions. There are 66 unordered pairs per rank, 528 simulations
across one and three stars, with repeated reversed pair orders. These are not
528 independent samples. Fixed protection and formation favor particular alliances
and attack patterns; zero wins in one fixture is a reason to inspect a unit, not
alone a reason to inflate its stats.

| Candidate | One-star wins/fights | Three-star wins/fights |
| --- | --- | --- |
| Boars | 9/12 (0 draws) | 9/12 (1 draws) |
| Wolves | 6/12 (0 draws) | 7/12 (0 draws) |
| Rats | 1/12 (0 draws) | 5/12 (0 draws) |
| Bats | 7/12 (0 draws) | 7/12 (0 draws) |
| Goblins | 7/12 (0 draws) | 6/12 (1 draws) |
| Toads | 6/12 (0 draws) | 7/12 (0 draws) |
| Skeletons | 6/12 (0 draws) | 0/12 (0 draws) |
| Tigers | 6/10 (0 draws) | 7/10 (0 draws) |
| Spiders | 5/10 (0 draws) | 4/10 (0 draws) |
| Armadillos | 7/10 (0 draws) | 5/10 (0 draws) |
| Lizardmen | 4/10 (0 draws) | 3/10 (0 draws) |
| Woodsfolk | 4/10 (1 draws) | 6/10 (0 draws) |
| Zombies | 3/10 (1 draws) | 5/10 (0 draws) |
| Orc shamans | 5/8 (0 draws) | 7/8 (0 draws) |
| Trolls | 1/8 (0 draws) | 1/8 (0 draws) |
| Ogres | 2/8 (0 draws) | 3/8 (0 draws) |
| Harpies | 7/8 (0 draws) | 5/8 (0 draws) |
| Hyenas | 5/8 (0 draws) | 4/8 (0 draws) |
| Evileyes | 7/8 (0 draws) | 2/8 (0 draws) |
| Banshees | 1/8 (0 draws) | 5/8 (0 draws) |
| Unicorns | 3/8 (0 draws) | 5/8 (0 draws) |
| Wisps | 4/8 (0 draws) | 4/8 (0 draws) |
| Elementals | 5/8 (0 draws) | 4/8 (0 draws) |
| Dragons | 3/8 (0 draws) | 4/8 (0 draws) |
| Golems | 7/8 (0 draws) | 5/8 (0 draws) |
| Horrors | 2/8 (0 draws) | 4/8 (0 draws) |
| Wormheads | 4/8 (0 draws) | 1/8 (0 draws) |
| Cyclopes | 4/8 (0 draws) | 6/8 (0 draws) |

Raw fixtures: [one star](trials-species-rebalance-2026-10-19/teams-one-star.json),
[three stars](trials-species-rebalance-2026-10-19/teams-three-star.json).

## Complete acquisition runs and limits

Four complete nine-player tournaments used two seeds with rotated policy seats.
All companies used the actual shop, XP prices, interest, purchases, merges,
alliances, losses and native combat. No free gold, units or combat bonuses were
injected. The games ended in rounds 29, 31, 30 and 30. Each policy supplied nine
seat samples across the four games.

| Policy | Seats | Mean place (lower is better) | First places |
| --- | ---: | ---: | ---: |
| Economy | 9 | 5.33 | 0 |
| Expansion | 9 | 4.22 | 2 |
| Evolution | 9 | 6.00 | 0 |
| Tempo | 9 | 4.44 | 2 |

[Full acquisition records](trials-species-rebalance-2026-10-19/tournaments.json).
Expansion and tempo won this small batch. The evolution purchasing heuristic
remains weaker here; these results do not establish strategy parity or human
optimal play. A larger multi-seed sample and human matches should examine cheap
three-star reliability, persistent-area spell positioning, and the cost of
searching compared with buying XP. The clearer species system is a readability
improvement; whether the pacing is more fun needs playtesting.

This pass did not resume the stopped long-session co-op performance experiment
and does not resolve the reported Windows performance degradation.

## Visual evidence

- [Combat framing and upper-screen notice](trials-species-rebalance-2026-10-19/en-combat.png)
- [Native bolts and green opponent loss](trials-species-rebalance-2026-10-19/en-loss.png)
- [Native red player loss](trials-species-rebalance-2026-10-19/en-local-loss.png)
- [Original Russian names and new role text](trials-species-rebalance-2026-10-19/ru-inspector.png)
- [Original German names and new role text](trials-species-rebalance-2026-10-19/de-inspector.png)

The fire-bolt overlay reconstructs alpha from the native additive sprites' RGB.
It avoids opaque black quads and preserves their color over bright snow. Health
loss reuses FlyingHP's original atlas, red/green colors, scaling, motion and fade.
It does not use a separate label font or delay the health update.

## Reproduction

Use the diagnostic's patched executable and PCK with an isolated XDG_DATA_HOME
and the five development settings from AGENTS.md. Pass original data with
`--ei-path=/absolute/original/game` after `--`.

- `--tool=/absolute/repo/tools/tests/arena_species.gd` (headless)
- `--tool=/absolute/repo/tools/benchmarks/arena_armor_audit.gd` (headless)
- `--tool=/absolute/repo/tools/benchmarks/arena_star_balance.gd` (headless)
- `--tool=/absolute/repo/tools/benchmarks/arena_roster_teams.gd --rank=0` or `--rank=2` (headless)
- `--tool=/absolute/repo/tools/benchmarks/arena_bot_tournaments.gd --games=4 --all-new` (headless)
- `--tool=/absolute/repo/tools/tests/arena_species_ui.gd --lang=en` (rendered, repeat ru/de with their original archives)

Do not replace the patched executable with a stock export template. Export a new
pack with `--export-pack Linux /absolute/output/CursedLands.pck`.

## Linux diagnostic

`CursedLands-diagnostic-species-linux-20261019.tar.gz` (50,862,794 bytes).
SHA-256: `f4ec4275dbe0f45b2dae08b73e6cec4cc321e0a222e83cd15a534e0bc9725e14`.

The exact packaged executable/PCK passed 2,154 species/migration/native-combat
checks. Archive verification confirmed the executable bit, both native libraries
and the tested PCK checksum. [Build metadata](trials-species-rebalance-2026-10-19/linux-build.json).
The previous diagnostic archives were retained unchanged.
