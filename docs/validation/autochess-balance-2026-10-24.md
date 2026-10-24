# Autochess balance and feedback validation — 24 October 2026

Local branch: `fix/autochess-balance-20261024`, based on stable 1.26.0 (`96aaeb78`).
The [design and catalog](../design/autochess-equipment-alliances.md) describe the
40 items, five tiers, four stat alliances, two tactical alliances, retired second
Woodsfolk line, native effects and victory cue. No release was published.

## Environment

Godot 4.7 stable (`5b4e0cb0f`), original extracted game assets. CPU checks used
headless mode. Graphical checks ran through GPU Lab with automatic GPU selection,
light workloads, isolated X11 displays, Compatibility rendering, 1280×720 and a
30 FPS cap. Every run used its own profile with `confine_mouse=0`, `show_fps=1`,
`volume_sfx=0`, `volume_stream=0`, `volume_voice=0` and Dummy audio. Player settings
and the physical desktop were not changed.

## Automated checks

| Check | Passed assertions | Coverage |
| --- | ---: | --- |
| Equipment state | 51 | Ownership, moving equipment, sale, merges, undo and save round trips |
| Equipment localization | 951 | All item names/descriptions and dynamic strings in EN/RU/DE |
| Combat effects | 31 | Native hit/cast hooks, shields, lifesteal, suppression, proc limits and isolation |
| Alliances | 616 | Distinct-family thresholds, normalized stats and refresh behavior |
| Item tiers and migration | 165 | Eight items per tier, equal-tier distinct offers, old reward RNG, retired offers, additive stats and high-tier effects |
| Bot equipment and formation | 108 | Carrier fit, item upgrades, spacing and Guardian variants |
| Roster | 1,548 | Active pool, costs, native ranks and retired-seer compatibility |
| Opponent alliances | 12 | Same benefits on opposing armies |
| Online equipment | 29 | Ownership validation and replicated equipment |
| Native headless battle | 13 | Native combat, echoes and item/alliance notices |
| Tier UI, each language | 264 × 3 | All 40 cards, text fit, tier borders, slots and victory cue lifecycle |
| Native rendered battle | 23 | Visible markers, spawned echoes, item feedback and completion |
| Native effect probe | 21 | Lifesteal, shield lifetime/depletion, replica effects and victory standings |
| Actual item drag | 28 | Mouse press/move/release, ownership transfer, tooltips and badge clearance |

All fixtures exited 0. [Machine-readable receipts](autochess-balance-2026-10-24/checks.json)
retain their summaries and source-log hashes. Translation scanning found 3,288
entries, 183 dynamic arena keys and zero errors. `git diff --check` passed.
The native art exporter produced 40 valid textured item renders; 32 are new assets.
The original eight images were retained to avoid unrelated raster changes.

The isolated X11 startup reports `Parameter "monitors" is null` before graphical
fixtures attach their error logger. No script/runtime errors were recorded during
the test scenarios. This is not described as a warning-free engine launch.

## Visual inspection

All 40 item choices were checked for complete descriptions and reachable Choose
actions at 1280×720 in EN/RU/DE. Selected captures demonstrate the five borders:

- [Tier 1, English — no border](autochess-balance-2026-10-24/tier-1-en.png)
- [Tier 2, English — green](autochess-balance-2026-10-24/tier-2-en.png)
- [Tier 3, English — blue](autochess-balance-2026-10-24/tier-3-en.png)
- [Tier 4, Russian — purple](autochess-balance-2026-10-24/tier-4-ru.png)
- [Tier 5, German — gold](autochess-balance-2026-10-24/tier-5-de.png)

[Healing and shields](autochess-balance-2026-10-24/healing-shields.png) were captured
after real native lifesteal, Ward and Guardian triggers. The protective emitter
persists while the shield remains, ends on expiry and flashes on depletion.
The [replicated-effect capture](autochess-balance-2026-10-24/native-effects.png)
shows lightning and the reused spell effects. Replaying these presentation events
left health, stats and both combat random streams unchanged. Repeated healing did
not accumulate identical emitters. Full snapshots replaced existing shields with
their remaining duration rather than duplicating them.

The victory cue selects the original `stream/victory.mp3`, a decodable 66.09-second
track. Tests verified one playback for the local champion, no restart on refresh,
reset on a new run, and no cue for an ordinary round, defeat or another champion's
win. The dedicated player uses the normal Music bus. Audio routing and decoding
were verified with the required muted test profile; no audible audition is claimed.

## Full-match exercise

Two nine-player self-play variants completed at round 29. Both use seed 7319,
with strategy offsets 0 and 1; they are not two independent random seeds.

| Strategy offset | Winning seat, zero-based | Board encounters | Longest fight | Timeouts/draws | Distinct chosen items |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 2 | 226 | 56.760 s | 0 | 22 |
| 1 | 6 | 230 | 48.895 s | 0 | 27 |

All 456 encounters ended with an army defeated. Tiers 1–5 first appeared in the
next preparations on rounds 4, 6, 11, 16 and 21, matching rewards after rounds
3, 5, 10, 15 and 20. All 27 final tier-5 items across both variants were equipped.
The [tournament summary](autochess-balance-2026-10-24/tournament-summary.json)
records placements, equipment tiers, selected items, effect counts and winning
compositions. The run exercised the native neutral-creature action-speed default
as well as player combat.

## Limits

This checks progression, compatibility and full-match stability; the small sample
does not establish competitive balance or human win rates. In particular, compare
conditional items with passive stat items during play and watch late-tier power.
These checks cover 1280×720; the previous 1920×1080 interface report is historical,
not a fresh validation of all new descriptions.

The native battle had the same winner and effect counts headlessly and rendered,
but simulation durations differed (20.570 s versus 19.305 s), as did damage totals.
Native animation timing means this is not evidence of exact replay parity.
The explicit replica probe separately establishes that added feedback cannot
change health, stats or combat RNG. The rendered run took 19.804 wall seconds at
1× speed; this isolated check is not a nine-board rendering benchmark.
