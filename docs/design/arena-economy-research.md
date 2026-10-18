# Auto-battler systems research

Reviewed 17 October 2026. These are PvE adaptations, not a claim that the expedition
reproduces either game's current complete ruleset.

## Primary sources

[Auto Chess's official introduction](https://ac.dragonest.com/en/gameIntroduction)
distinguishes star upgrades from race/class synergies. Different deployed pieces
with shared traits activate bonuses, and overlapping synergies support lineup
choices. Its usual merge recipe is three identical pieces per star step.

[Valve's Big Update](https://store.steampowered.com/news/posts/?appids=1046930&enddate=1572065617&feed=steam_community_announcements)
describes five-gold/five-XP purchases, a rising level curve and tiered alliance
effects. Its hero examples carry multiple alliances. These structural relationships
are the reference, not that historical update's Underlord hero or dated balance values.

[Valve's December 2019 update](https://store.steampowered.com/news/posts/?appids=1046930&enddate=1576696070)
provides the historical three-interest cap and separates tier from star rank.
[Auto Chess's lineup UI notes](https://ac.dragonest.com/en/news/detail/ea86bc29767)
show synergy membership in the shop and indicate when a lineup activates a bonus.

## Historical decisions (17 October)

- Replace a selected pact and free summon with automatic overlapping alliances.
  Deployed unique families count once. The HUD shows current progress; details live
  on hover. No extra choice screen interrupts forming an alliance.
- Connect level, capacity and shop tiers. Five gold buys five XP directly on the HUD.
  Each level costs more XP. Buying copies, rolling, leveling and keeping interest
  compete for the same gold. Shops no longer sell higher-star rolls.
- Use one-to-five-gold tiers and fixed bounty. Preserve the existing native forms
  and adapted two/three-copy recipes; forcing three copies of small native stat
  increments would make some evolutions a poor trade.
- Keep the original creature database immutable. Alliance buffs belong to the
  temporary PvE encounter. Effective stats are inspectable; bonuses do not leak
  into the campaign or development sandbox.
- Advance results automatically after a brief readable notice. Retain five sparse
  camp choices for the requested roguelite structure. Camp XP and cash have distinct
  opportunity costs; no weaker duplicate currency reward is offered.
- Retain three lives, seeded PvE opponents, income/interest, evolution, reserves and
  later-region recruits. A multiplayer shared pool, multiplayer economy, items and
  an Underlord hero are outside this change.

## Balance iteration

The first level table completely excluded tier-four recruits below level seven.
Across seeds 1900–1902, the duplicate-focused policy stalled at wave 14, whereas
earlier leveling cleared all three runs. That was a sharp access gate rather than
an interesting tradeoff. The revised table adds an 8% tier-four chance at level six,
a 2% tier-five chance at seven, and raises tier-five chances at eight to 10%.
Higher levels still improve the odds while lower-level rolling has a route forward.

The native AI simulation uses the same economy, terrain navigation, spells and
projectiles as play. Policies use known prices, native levels, copies and a savings
target; they are deterministic purchasing heuristics, not human players or proof of
optimal play. Preference-based policies can transition to late native recruits.
Their outcomes and losses are recorded separately from functional/UI checks in
`docs/validation/arena-alliances-2026-10-17.json`.

The revised sample contains 18 Standard runs and 545 native encounters. Seventeen
runs clear all thirty waves; the beast-preference policy loses one run at wave 24.
The six policies each use the same three seeds, so these are correlated design
samples, not eighteen independent player observations. Several policies recover
from individual losses. Six encounters reach the existing 300-second draw limit;
long native matchups and higher difficulties still need dedicated playtesting.
The later formation-animation and opening-screen changes do not alter these
headless combat policies. The cash camp reward was reduced from twelve to eight
gold after checking that it otherwise dominated the ten-XP reward; these policies
choose XP or recovery rather than cash.

The core design tension is spend for immediate strength versus save for broader
choices. The revision removes the unrelated pact selection and independent shop
quality purchase rather than adding another currency or upgrade ladder.

## 18 October experiment

The 30-chain roster, uniform three-copy evolution, bounded Trials stats and
expanded native simulation checks supersede the roster and merge recipes above.
See [the current experiment](../validation/allods-challenge-2026-10-18.md).
The historical 18-run expedition sample above describes its earlier ruleset.
