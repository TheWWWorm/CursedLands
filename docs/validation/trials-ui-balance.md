# Trials UI, encyclopedia and armor comparison

17 October 2026. These checks cover the work following the initial
[issue fixes](issues-5-9-15.md). They describe local source validation, not a
published release or measured human win rates.

## Changes exercised

- Company level, XP, price and odds are together in the shop. The level number
  buys XP. Reroll and level controls keep button surfaces; XP has no underline.
- Independent offer locks use open/closed padlocks, no background, and a border
  for the locked state. All six opening offers can remain locked together.
- The shop is available during combat. Recruits, XP, rerolls and reserve sales
  commit immediately. Upgrades of deployed creatures preserve the current
  battle's actors and bonuses, then appear in the next preparation.
- Every family reaches three stars. Six families use their strongest existing
  figure with private elite bonuses; grey harpies use their native level-20 form.
- Content-sized creature/alliance inspection, centered utility icons, complete
  clickable reward cards with native item artwork, upgrade hints and native
  transaction/result sound dispatch are exercised through real pointer input.
- Ordinary result notifications preserve the HUD and continue figure animation.
  Every result pays income and advances; defeat removes one life. The result
  clock remains at the top. Trials time out as a loss at two minutes of combat.
- Main-menu utility buttons sit in a bottom row. Trials is named
  Испытания аллодов in Russian and is unavailable from Lost in Astral.
- Wiki indexes retain their source context, invalidate when mods change, share
  selectively decoded map records and virtualize the search list. Navigation
  wraps with spacing; redundant difficulty prose is removed.

## Test method

Native Godot 4.7 on Linux with original English, Russian and German game data.
Each command owns isolated preferences and saves. Rendered checks used an RTX
3090 with Compatibility rendering. English was inspected at 3840×2160, Russian
at 1280×800 and German at 1024×768; the menu/wiki also ran in German at 4K.

The UI scenarios click the level control, all six locks, combat shop purchases
and sales, menu close and entire reward cards. They inspect every recruit family
at one and three stars, all five alliances, frozen combat actors during merges,
continued idle animation after victory, and all lock style states. The separate
interaction scenario checks model/health-marker picking, pause/menu focus,
actual combat damage numbers and live resizing.

Timeout regression checks the frame immediately before the limit, pause,
settlement at 120 seconds, income exactly once and next-wave progression. The
sandbox arena's existing five-minute rule is separately retained and checked.

Sound checks load the original archives and verify cue dispatch. The test audio
driver was Dummy, so this is not a listening assessment. No Windows, macOS,
Android or Web runtime was tested in this pass.

## Encyclopedia performance

The same English probe before/after measured first opening at 2,675 → 491 ms and
reopening at 2,717 → 42 ms. At measurement time, both catalogues contained 1,207 pages and 1,074 search
results. The rendered list now owns fewer than 40 row controls, while all results
remain searchable and reachable.

Independent end-to-end checks measured cold/warm opening at 640/50 ms (EN),
694/53 ms (RU), and 696/53 ms (DE). These are observations on this host, not a
universal latency promise. Each locale passed 18,607 checks comparing cached
unit fields and script text against full original map decoding, plus search,
last-row access, catalog reuse and invalidation. Existing wiki feature, lore and
construction suites also passed.

## Selected armor rule

Trials select the remake 80% absorption cap for both sides. This preserves the
relative value of strong armor while allowing low-damage attacks and spells to
contribute. The two-minute limit still bounds regeneration and positioning
stalemates. Campaign armor preferences and prototype data are not changed.

The judgement about better pacing is an inference from timeout frequency and
fight length. Human playtesting is still needed for subjective feel. The higher
clear rates informed the separate encounter tuning below.

## Balance method

`tools/benchmarks/arena_balance.py` runs real native movement, AI, armor, attacks,
spells, projectiles and terrain navigation at the game's fixed 55 ms tick. Balance
runs use the English archives; layout and localization checks use the
corresponding EN/RU/DE data.
Policies are balanced, Beast, Warrior, Mage, reroll-heavy and leveling-heavy.
These are biased purchase policies rather than pure-alliance teams, and they
use a shared automatic deployment strategy without counter-picking each wave.
Each policy uses seeds 1900–1907 on Standard, Veteran and Champion. Both armor
rules start from those same seeds, shops, economy, encounter lists and upgrades;
later shopping decisions can diverge when earlier outcomes change income/lives.

Original armor can absorb a damage type completely. The existing remake rule
limits absorption to 80% of each incoming damage type, leaving at least 20%.
It applies equally to both sides and to attacks and spells. The comparison uses
a 120-second limit for both; unfinished fights are losses. A completed expedition
means surviving all 30 waves, including a last-wave defeat if a life remains.
Individual final-wave wins are recorded separately to avoid hiding that distinction.

An earlier baseline of 144 expeditions / 4,248 battles used the previous encounter
lists and five-minute limit. A later five-minute tuning pilot was superseded by
the requested two-minute rule; its partial cases are not mixed into the comparison.

## Matched armor comparison

288 expeditions, 8,289 battles. The encounter lists were held fixed for this
comparison, before the final Standard/Veteran reinforcement adjustment.

| Armor | Difficulty | Expeditions completed | Timeouts / battles | Mean fight | 90th percentile |
| --- | --- | ---: | ---: | ---: | ---: |
| Original | Standard | 41/48 | 72/1431 | 30.2s | 61.4s |
| Original | Veteran | 24/48 | 97/1385 | 38.3s | 87.0s |
| Original | Champion | 6/48 | 74/1273 | 39.5s | 80.5s |
| 80% cap | Standard | 48/48 | 2/1440 | 22.7s | 38.4s |
| 80% cap | Veteran | 43/48 | 19/1435 | 31.6s | 58.7s |
| 80% cap | Champion | 15/48 | 23/1325 | 35.4s | 64.2s |

Original armor produced **243 timeouts in 4,089 battles (5.94%)**; the 80% cap
produced **44 in 4,200 (1.05%)**. The cap reduced the timeout rate by about 82%,
and the 90th-percentile duration improved at every difficulty. Different battle
counts reflect earlier expedition elimination, not omitted cases.

No original-armor run won the final battle, even though 71 expeditions survived
it with a life remaining. With the cap, 78 final battles were won. This reinforces
the pacing concern: a hard block can turn an otherwise viable army into a forced
loss regardless of how much longer it attacks. The cap gives both sides a way to
make progress. It does not guarantee every fight finishes: healing, low damage,
misses and terrain can still run out the clock.

These are full expeditions with matched starting seeds, not paired fights with
identical late-game armies. Policy choices and resources diverge after different
outcomes. The measured reduction is evidence for selecting the cap in this mode,
not a universal claim that it is preferable in every campaign encounter.

## Final encounter pass

After selecting the cap, Standard and Veteran gain one native frontline creature
from wave six and a support creature from wave nineteen, progressing through
stronger forms. Champion retains its existing stronger caster reinforcements;
stacking both sets made the pilot disproportionately punishing. This adjusts
encounter composition without changing installed creature data or campaign rules.

The final complete matrix uses the 80% cap and 120-second limit: **144 expeditions,
4,147 battles**. It is separate from the matched armor comparison above.

| Difficulty | Expeditions completed | Final battles won | Timeouts / battles | Mean fight | 90th percentile |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard | 43/48 | 28 | 17/1439 | 31.2s | 58.1s |
| Veteran | 22/48 | 7 | 44/1383 | 39.6s | 79.2s |
| Champion | 15/48 | 5 | 23/1325 | 35.4s | 64.2s |

All six purchase policies were retained. Clears by policy provide a check against
one aggregate hiding a failed strategy:

| Policy | Standard | Veteran | Champion |
| --- | ---: | ---: | ---: |
| balanced | 8/8 | 4/8 | 2/8 |
| beast | 5/8 | 2/8 | 2/8 |
| warrior | 8/8 | 4/8 | 2/8 |
| mage | 7/8 | 3/8 | 3/8 |
| reroll | 8/8 | 5/8 | 5/8 |
| levels | 7/8 | 4/8 | 1/8 |

The harder settings remove companies earlier, so their mean fight duration need
not increase monotonically. The longest recorded battle was 120.01 seconds,
within one native 55 ms tick of the limit. Every timeout settled as a player
loss. Regression checks also verify that pause freezes the clock, settlement
pays income once, and the next wave starts when lives remain.

Standard remains forgiving for these competent automated policies; Veteran and
Champion impose more losses. This is a tuning checkpoint, not a claim that the
mode is perfectly balanced. Human positioning, learning, purchase speed and
subjective enjoyment are outside these simulations.

## Evidence and reproduction

- [Validation metadata and summaries](trials-ui-balance.json): 21 passing test runs,
  per-locale wiki timings, the historical baseline, both armor batches and final
  aggregates.
- [Armor comparison traces](trials-armor-traces.json.gz): all 288 expeditions,
  per-wave armies, outcomes, timings, timeout survivors and the encounter rules.
- [Final balance traces](trials-final-balance-traces.json.gz): all 144 expeditions
  and the final encounter rules.
- [Earlier issue validation](issues-5-9-15.md): reset dialog and campaign fixes.

The compressed trace archives include the corresponding `arena_rules.gd` source
and its SHA-256 in `encounter_rules`, because the comparison preceded the final
encounter adjustment. To reproduce that comparison, use a disposable checkout
of this change and replace `game/src/game/arena_rules.gd` with the comparison
archive's `encounter_rules.content` before importing. The final matrix uses the
checked-in rules directly. Do not mix the two encounter versions in one comparison.

With original game files available, import the source project once and run:

```sh
godot-4 --headless --editor --path game --import
python3 tools/benchmarks/arena_balance.py \
  --data /path/to/original/game \
  --output /tmp/trials-balance \
  --armor-formulas 0 1 --seeds 8 --start 1900 --jobs 8
```

Use `--armor-formulas 1` for the final 144-expedition matrix. The runner creates
separate preferences/saves for every case, checks process errors and time bounds,
and writes `summary.json` plus raw per-policy results. It does not change normal
player saves. The native benchmark checks that prototype data remain unchanged.

Translation coverage and Godot editor import pass. All new UI copy has EN/RU/DE
entries. No release version, published tag or release artifact was changed.
