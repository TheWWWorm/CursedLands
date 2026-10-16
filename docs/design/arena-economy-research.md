# Expedition economy and interaction decisions

Research and implementation: 16 October 2026. These are adaptations for an
18-wave solo expedition, not a claim to reproduce another game's current rules.

## References

[Valve's 18 December 2019 Underlords update](https://store.steampowered.com/news/posts/?appids=1046930&enddate=1576696070)
caps standard-mode interest at 3 on 30 gold, distinguishes unit tier from star
rank, and describes a faster Knockout variant with smaller merge recipes and no
interest or streak income. This makes pacing a design choice rather than a
reason to copy every system from one ruleset.

[Auto Chess's official introduction](https://ac.dragonest.com/en/gameIntroduction)
uses one to three stars for duplicate upgrades and separately describes race and
class synergies. The expedition retains that readable star convention, but its
native creature jumps determine recipe sizes. Pacts already reward related
families without editing native combat stats.

[Apple's historical Underlords gold guide](https://apps.apple.com/us/ipad/story/id1474387985)
explains the spend/save tension, buying army capacity and selling unused recruits.
Its older five-interest cap is not used as a current rules reference.

## Selected adaptations

| Decision | Expedition behavior | Purpose |
| --- | --- | --- |
| Economy | 5 bounty + 1 victory + 0–3 interest + 0–2 win streak | Saving has a visible return; buying immediate strength protects lives and streaks. |
| Interest | Snapshot at battle start; 1 per 10 saved, cap 3 | Clear thresholds, no mid-settlement manipulation. |
| Streak | +1 from third win, +2 from sixth; defeat resets | Modest reward for a stable formation without unlimited snowballing. |
| Losses | No income or experience for a retry | A repeatable PvE encounter cannot become a farming loop. |
| Training | 5 gold buys up to 3 XP and one earlier slot; cap 7 | Gives gold an army-size sink alongside recruits and shop quality. Free wave XP stays. |
| Selling | Full refund at one star; partial, capped refund for evolved forms | Early exploration is affordable; merging and reselling never yields profit. |
| Rank | 1–3 stars on field, reserves and offers | One meaning across every surface, not a second rarity ladder. |
| Information | Hover for native attack, defense, armor types and recipe | Supports composition decisions without a permanently open sidebar. |
| Interaction | Select, place, release; select, click sell area | One deliberate action per selection, with undo for sales. |
| Resolution | 1.6-second animation interval before the result | Makes the final hit readable without altering the combat result. |

A shared multiplayer recruit pool and an Underlord hero are absent. The existing
pacts, native spells, enemy preview and camp tradeoffs provide composition and
run variation. Additional rarity grades and equipment inflation would add
another power scale before the present native roster is understood.

## Evaluation

Regression tests cover exact interest/streak thresholds, no duplicate payment,
failed retry behavior, training/undo/save migration and original stat preservation.
Rendered checks cover actual pointer placement, returns, sales, hover lifetimes,
preview bounds across all evolution forms, stable lock geometry and result timing.
Seeded policy runs compare spending, saving, early training, rigid melee and a
melee opening that adds magic later. These are small deterministic design samples,
not estimates of human win rates. Results and limitations are recorded in
[the expansion validation](../validation/arena-expansion-2026-10-16.json).
