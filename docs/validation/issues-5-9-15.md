# Campaign fixes and Trials balance review

17 October 2026. Local changes based on stable v1.9.2,
`7c77cb16eff2ec758b88506fbdd26f6b7b16efd1`. No release or issue-state changes.
The next release containing the reset choice is a compatible MINOR release
(1.10.0 if 1.9.2 is still the latest published stable release).

## Issue outcomes

| Issue | Result |
| --- | --- |
| [#5](https://github.com/TheWWWorm/CursedLands/issues/5) | Camp now opens a dialog with **Restore starting skills**, **Full reset**, and **Cancel**. Starting allocation comes from the active campaign's NPC data. For Zak this preserves Backstab 1, Melee 10, Science 3, Sense 12, and Astral 9. |
| [#9](https://github.com/TheWWWorm/CursedLands/issues/9) | Confirmed original behavior: crouch and walk use the same translation speed. Crawl uses 80% of walking after native byte quantization. No movement rebalance applied. |
| [#10](https://github.com/TheWWWorm/CursedLands/issues/10) | Quest dialogue suppresses queued and new incidental acknowledgements, bored chatter, and animation voices. Scripted scenario and blocking dialogue lines remain allowed; normal voices resume afterward. |
| [#11](https://github.com/TheWWWorm/CursedLands/issues/11) | The signpost renders its opening pose while hidden before it becomes visible. Pointer hover cannot replace the opening animation. |
| [#12](https://github.com/TheWWWorm/CursedLands/issues/12) | Paused commands immediately send authoritative route previews. Path particles are initialized for display without advancing actors, combat, or world/FX clocks. Replacing a paused command removes its previous preview. |
| [#13](https://github.com/TheWWWorm/CursedLands/issues/13) | Explicit Ctrl attack-move engages enemies in either stance. Defensive idle and ordinary movement remain passive. |
| [#14](https://github.com/TheWWWorm/CursedLands/issues/14) | Attack-move requests a new route when it automatically acquires a target. |
| [#15](https://github.com/TheWWWorm/CursedLands/issues/15) | Revised recruit prices and availability, stronger higher-difficulty reinforcements, preparation time by difficulty, and symmetric spell friendly-fire protection in Trials. See the scope and balance evidence below. |

## Reset dialog and point accounting

The dialog uses the original carved `saveload` frame, amber message-box heading,
serif text and stone buttons. An opaque black inset keeps camp text from showing
through it. Its height follows the content in each language, ending with normal
padding below Cancel rather than a fixed-height empty area.

Starting-skill restoration refunds the allocation value above the original ranks
and perks. After a full reset it can spend the refunded pool to restore that
allocation; insufficient points disable the choice. Missing NPC data disables
only starting-skill restoration. Labels explain these states in EN/RU/DE.
Base attributes, equipment and lifetime earned XP are preserved.

Repeated switching conserves the point budget. Legacy pricing credits are
consumed once. The authority checks ownership, life state and camp access before
applying either mode, and updates live combat stats. The new `reset_training`
command carries the choice; legacy `refund_training` remains a full reset.
An older host cannot interpret the new choice as a legacy full reset. Co-op
testing uses matching builds, as required by the project compatibility policy.

## Trials tuning

The opening prices and income are retained. A blanket 1.6× price increase would
also compress the opening purchases and make early ranged/caster options more
expensive. The implemented changes instead increase investment in the strongest
later recruits:

| Recruit | Previous price | New price | Availability / evolution |
| --- | ---: | ---: | --- |
| White tiger | 3 | 4 | Tier 3, two copies |
| Blue troll | 4 | 7 | Tier 4, two copies |
| Stony harpy | 4 | 6 | Tier 4, two copies |
| Sand ogre | 5 | 10 | Tier 5, two copies |
| Spider | 4 | 3 | Tier 3 instead of 4; three copies instead of two |
| Grey harpy | 5 | 7 | Tier 5, two copies |

Spiders can appear at company level five, before trolls. Three copies keep their
earlier evolved form from becoming a six-gold dominant purchase. Veteran's melee
reinforcements and Champion's ranged/magic reinforcements progress through
stronger existing prototypes. Champion gains an additional caster from wave ten,
including octopuses in later regions to pressure physical-armor formations.
Creature database stats and alliance bonuses are unchanged.

Preparation is 60/45/30 seconds for Standard/Veteran/Champion. Menus still pause
the timer. Schema 9 preserves an older active 45-second countdown through loading
and saving again, then uses the new duration for the next preparation. Existing
recruits retain their original purchase investment and sale proceeds.

Spell damage in Trials excludes the caster's team, including persistent acid
fog. This applies equally to the player's team and opponents. Beneficial spell
filters and campaign spell friendly fire remain unchanged.

## Balance evidence

Seeded policies exercise actual AI, spells, projectiles, economy and all thirty
waves. They are design samples, **not human win-rate estimates**. Initial and
final samples use the same policy and seeds where shown as a comparison.

| Build | Difficulty | Policy | Seeds | Clears | Defeat waves |
| --- | --- | --- | --- | ---: | --- |
| v1.9.2 baseline | Standard | Warrior | 1900–1902 | 3/3 | — |
| Revised | Standard | Warrior | 1900–1902 | 2/3 | 30 |
| v1.9.2 baseline | Champion | Balanced | 1900–1902 | 3/3 | — |
| Revised | Champion | Balanced | 1900–1902 | 0/3 | 30, 26, 30 |
| Revised | Champion | Mage | 1910–1912 | 2/3 | 27 |
| Revised | Veteran | Balanced | 1920–1922 | 2/3 | 30 |

The revised samples show late-game resistance while retaining successful
compositions. Mage results warrant further human playtesting rather than a
claim that every strategy is equally difficult. Encounter traces include timed
draws and retries; a completed run can include lost lives.

Reproduce with original game data and the development runner, for example:

```sh
godot-4 --headless --path game -- --no-local-worker --ei-path=/path/to/original-data \
  --tool=/path/to/CursedLands/tools/benchmarks/arena_alliance_runs.gd \
  --arena-challenge=2 --arena-policy=balanced --arena-seeds=3 --arena-seed-start=1900
```

Use an absolute `--tool` path if starting from a different directory. Results
are written to `user://alliance-runs-<policy>.json`. Challenge is 0/1/2.

## Remaining suggestions from #15

- **Separate graphics settings:** a useful presentation feature, independent of
  this balance pass; no new graphics profile was added.
- **Permanent-death hardcore:** a distinct optional ruleset, with consequences
  for recovery, rewards and saves; it was not substituted for ordinary Champion.
- **Octopus companion strength:** no individual stat buff was added. Its value
  should be compared with alternatives under the revised prices and safe spell
  damage before selecting a specific buff.

## Original movement evidence for #9

The original Human Male race stores run/walk/kneel/crawl speeds as
`0.4666666985 / 0.1600000113 / 0.1600000113 / 0.1250666827`.
Crawl is 78.17% of walk before the native byte representation and 80% afterward.
The original executable's posture selector at `0x52f920` reads the separate
run/walk/kneel/crawl bytes and applies the same movement multiplier. It does not
apply an additional crouch slowdown. The executable digest, decompilation and
supporting addresses are retained in [native movement evidence](issue-9-native-movement.json).

## Validation

The machine-readable [validation record](issues-5-9-15.json) records final test
results and per-seed outcomes; the [compressed encounter traces](issues-5-9-15-balance-traces.json.gz)
retain all 18 baseline/final runs. Coverage includes live camp actions, cancellation,
point conservation, legacy saves, co-op replication and reload, rendered paused
paths, defensive attack-move, chatter suppression, and the first rendered frame
of the pause menu. Existing economy, recruitment, alliance, route, movement,
stamina and companion regressions also pass.

The reset dialog was rendered with original EN/RU/DE archives at 1024×768 and
German at 3840×2160. Bounds, choice-label widths and bottom padding were checked.
All 15 new translation keys include Russian and German text with matching format
placeholders, including dynamically selected reset reasons and guide entries.
Validation ran on Linux/Godot 4.7; Windows, macOS, Android and browser runtime
checks, human difficulty assessment and release packaging remain outside this
local implementation pass.
