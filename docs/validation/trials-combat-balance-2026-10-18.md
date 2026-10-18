# Trials combat-budget follow-up — 18–19 October 2026

Development follow-up to `5a562c9d`, on `fix/creature-projectiles-wisp`.
The 30 chains, 90 native forms, 1–5-gold prices, three-copy upgrades, shop odds
and interest remain unchanged. Late-level XP thresholds are reduced; training
still costs five gold for five XP. This is an unpublished balance experiment.

## Problems reproduced and changes

- Equal per-hit damage overlooked native attack intervals of 49–130 ticks.
  Physical damage now accounts for cadence; ordinary ranged attacks also receive
  additional accuracy and damage. Slow heavy shots and quick attacks retain
  their original timing.
- Native boss regeneration could erase the normalized damage budget. Recruit
  regeneration is now one quarter of the original rate, capped at 0.5% maximum
  health per 15 ticks. Original campaign regeneration remains the fallback.
- Area and extra-target spells did not consistently pay for their reach.
  The budget now uses actual area and target count, retaining native non-effect
  runes. Healing receives 60% of the comparable offensive budget. Curse uses
  the native Cut Effect rune and a slower action rate to retain a heavy strike.
- Bow casters could not parry but paid the lower caster health factor. They now
  retain ranged health and show zero defense in previews. Utility-only spells
  no longer classify a dagger fighter as a caster or put it behind the frontline.
- Naya repeatedly healed light wounds and cast fire protection against physical
  opponents. Trials self-healing now waits for half health; elemental protection
  requires a matching opposing attack or spell. Ally healing keeps its native
  priorities.
- Fairakh's final form spent two opening casts on night vision and quieter
  footsteps. Native Silence changes hearing detection, not spellcasting. These
  buffs are skipped in the already-revealed Trials arena; campaign use remains.
- A one-enemy AI shortcut retained the current weapon order even when a stronger
  spell was available. The shortcut now requires one attack option as well as
  one enemy. Spell scoring also uses the actual damage school; Curse damage is
  lightning, independently of its knowledge school. These two corrections apply
  to native AI generally, including the campaign.
- CPU valuation now considers sustained damage and survival, including parry,
  instead of heavily favoring the largest damage packet. The four spending
  policies retain their existing reserves, level timing and refresh limits.
- Levels seven through nine now require 55, 80 and 110 cumulative XP instead of
  60, 90 and 126. Earlier thresholds are unchanged. Training purchases and camp
  XP rewards stop at the new maximum; older saves retain accumulated training
  through 126. The displayed progress clamps to a complete level-nine bar.

Recovery per second is visible in unit details in English, Russian and German.
The friendly damage/alliance sidebar remains transparent and borderless. Spell
details use the wiki's translated fallback for native spells lacking an archive
title, including Astral Rift.

## Direct combat results

The baseline is the committed 30-chain rules in `5a562c9d`, before the cadence,
regeneration and spell-budget corrections. The final matrix keeps all 1,872
fights' seeds and orientations identical.

| Same-cost duel/team result | Baseline | Final |
| --- | ---: | ---: |
| Decided by defeating the opposing army | 1,671 | 1,828 |
| Ninety-second timeouts | 179 | 27 |
| No-damage stalemates | 22 | 17 |
| Mean simulated duration | 37.69 s | 31.99 s |

Timeouts fell by 84.9%. Every form has at least one win in both tested contexts;
there is no expectation that every form wins exactly half its duels. For example,
the stony harpy is particularly effective behind a frontline, while the two-star
Black Clan archer performs strongly in duels. These are observed specialties,
not universal counter guarantees.

| Star / purchase comparison | Fights | Candidate wins | Draws | Timeouts |
| --- | ---: | ---: | ---: | ---: |
| Every adjacent promotion against its previous form | 240 | 240 | 0 | 0 |
| 1-gold two-star versus 3-gold one-star | 168 | 86 (51.2%) | 1 | 0 |
| 1-gold three-star versus two 5-gold one-stars | 112 | 17 (15.2%) | 0 | 0 |

The promotion results support retaining the star multipliers instead of a
blanket increase. The last comparison still exposes a cost of concentrating
power: one unit can lose to two targets even at a similar purchase price. Full
tournaments include army slots, interest, training and the gold spent on refreshes.

Four hand-authored formations each contain six two-star units costing 54 gold.
They preserve real traits and use the same mirrored seeds. The physical-heavy
formation wins 4/4 against the caster formation and 3/4 against the mixed
formation. The mixed formation beats the casters 3/4; adding two melee screens
to the caster formation splits that matchup 2/2. This small fixture shows that
caster-heavy CPU selection is not evidence of unavoidable caster dominance.

## Spending strategies and progression

The XP comparison holds the final combat rules and CPU policies fixed. Each
version plays sixteen nine-seat tournaments over eight paired seeds, rotating
the four policies to give each **36 seats**. Lower mean placement is better.

| Policy | Mean place, old XP | Mean place, final XP | Final wins | Final top-three finishes |
| --- | ---: | ---: | ---: | ---: |
| Saving / economy | 5.97 | 5.36 | 1 | 9 |
| Earlier levels / expansion | 5.50 | 5.81 | 2 | 8 |
| Copies / evolution | 4.17 | 4.72 | 8 | 15 |
| Mixed spending / tempo | 4.36 | 4.11 | 5 | 16 |

All four policies win, but they are not equally successful. Mixed spending has
the best mean placement; collecting copies has the most wins and more variable
finishes. The lower late-level thresholds improve the saving policy's mean
placement, while the earlier-level policy still underperforms. This supports
keeping cheaper late levels as an experiment, not declaring the four policies
equivalent or promising equal human win rates.

The final average gold spent per seat confirms that the policies make different
choices rather than merely receiving different names:

| Policy | Recruits | Refreshes | Training |
| --- | ---: | ---: | ---: |
| Saving | 78.86 | 13.22 | 89.86 |
| Earlier levels | 75.28 | 9.22 | 86.94 |
| Copies | 97.19 | 44.22 | 55.14 |
| Mixed | 88.22 | 17.33 | 90.00 |

At round twenty the copy policy averages level 7 and 1.41 three-star units
among surviving seats, versus levels 8.17–8.58 and 0–0.19 three-star units for
the other policies. These checkpoint averages are conditional on survival.
Final armies use 22 of 30 families and 47 of 90 forms, averaging 6.92 distinct
families per army. The remaining families are available and have wins in the
direct fixtures; this CPU sample does not demonstrate equally attractive
purchasing choices across the entire roster.

The separate Standard expedition cross-check uses four seeds for each policy.
The final rules clear **1/16** runs, with mean last wave **26.31**, compared with
0/16 and 25.13 before the XP change. The successful run uses the copy policy;
the other runs finish on waves 20–30. Expedition difficulty remains demanding,
and these simple policies are not proof of human accessibility. No blanket
creep-health, damage or regeneration reduction was adopted.

Machine-readable results: [summary](trials-combat-balance-2026-10-18/summary.json),
[full tournaments](trials-combat-balance-2026-10-18/tournaments.json),
[expeditions](trials-combat-balance-2026-10-18/expeditions.json), and
[control before the XP change](trials-combat-balance-2026-10-18/before-xp-summary.json).

## Method and limits

All fights run through the real native simulation with fixed 55ms ticks, original
models, attacks, spells, armor, wounds, movement and alliances. Data hashes check
that the campaign database is not mutated. Combat is limited to 90 simulated
seconds, with the existing no-damage stalemate rule.

The same-cost matrix uses every unordered pair within a shop tier, at each star
rank. Each pair fights alone and alongside the same two melee supports. Each
fixture runs at seeds `8519` and `10777`, in both orientations: 468 fixtures and
1,872 fights. Supports are selected deterministically by closest cost, excluding
the two candidates. This reveals different solo and team strengths; it does not
measure the cost of finding copies.

The separate star matrix contains all 60 adjacent promotions, all one-gold
two-star versus three-gold one-star pairs, and one-gold three-star versus two
five-gold one-star pairs. The same two seeds and mirrored sides yield 520 fights.

Full tournaments use nine seats, actual shops and native battles, without free
gold, units or combat multipliers. Seats rotate between saving, leveling,
collecting copies and mixed spending. Placement is descriptive: seats in a
game are correlated and these four heuristics are not optimal human strategies.
Formation tests likewise check specific counters, not every possible army.

The benchmarks demonstrate working choices and identify implementation defects.
They cannot establish human fun or a permanent final metagame. In particular,
low-cost three-star units compress nine recruits into one slot but are not
expected to beat every two-unit formation costing slightly more gold.

## Reproduction

Use a fresh `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` per process.
From the repository root:

```sh
godot-4 --headless --path game --render-thread safe --audio-driver Dummy -- \
  --ei-path=/path/to/original/data \
  --tool=/absolute/repo/tools/benchmarks/arena_context_balance.gd \
  --rank=0 --seeds=8519,10777
```

Repeat the context tool for ranks 1 and 2. Run `arena_star_balance.gd` for the
promotion/price comparisons and `arena_composition_balance.gd` for the equal-cost
formations. Run `arena_bot_tournaments.gd --all-new --games=4 --first-game=N`
for `N=0,4,8,12`, and `arena_challenge_runs.gd --seeds=7319,8316,9313,10310`
for the sixteen Standard expeditions.
The optional `--creep-recovery-budget` flag changes only the expedition benchmark;
it is an unadopted comparison and is not a production rule.

`arena_balance_summary.py` combines JSON results and records input hashes. If
targeted reruns are supplied, identical fixtures are replaced in order, never
counted as extra independent fights. The final matrices include a targeted rerun
of Fairakh after the last utility-spell change; its other rank's unchanged
results are also rerun in the star fixture. The complete final rules can be
reproduced by running each matrix once without filters.

The XP change does not alter direct-combat fixtures, which use fixed armies.
The tournament pilot and completion runs use the same XP thresholds; the later
maximum-XP guard does not alter these policies, which already stop training by
army capacity. Expeditions were rerun after that guard because it changes camp
rewards at level nine. Source fingerprints are retained for the combat/control
revision and the final revision.

## Co-op and regression verification

The real ENet guest fixture passes **24 checks**. Both the third-copy two-star
merge and a ninth-copy merge into three stars display their upgrade notice after
the acknowledged purchase, without another action. Unrelated purchases and
repeated snapshots do not replay the notice. The fixture also discovers the
lobby with default settings and confirms that two-/three-star sale proceeds
equal the displayed host quotes.

Additional passing checks cover all 90 forms' live/preview statistics, actual
regeneration and native fallback, AI spell choice, database immutability, bot
planning, original AI eligibility and senses, filtered spell targets, native
opening recruitment fights, private-worker parity, online feedback and sale
quotes. See [the test output](trials-combat-balance-2026-10-18/checks.txt).
The economy fixture passes 626 checks, including every XP boundary, maximum
training, undo, old 110–126-XP snapshots and camp reward eligibility. The alliance
fixture also passes 626 checks per edition. Its old assertions were updated to
the current roster's memberships and price/star budgets; native names are
validated from each edition's text archive rather than by requiring duplicate
entries in the remake dictionary.

The rendered interface fixture passes **33 checks in each of EN/RU/DE** using
the corresponding original text archives. The recovery text fits the unit
inspector, and the player list gives way to the hovered details. All three
captures were visually reviewed. [Translation coverage](trials-combat-balance-2026-10-18/translations.txt)
reports 2,728 remake entries, 141 dynamic wiki keys and 151 dynamic arena keys,
with zero errors.

[English](trials-combat-balance-2026-10-18/en-recovery.png) ·
[Russian](trials-combat-balance-2026-10-18/ru-recovery.png) ·
[German](trials-combat-balance-2026-10-18/de-recovery.png) ·
[Co-op upgrade notice](trials-combat-balance-2026-10-18/online-upgrade.png)
