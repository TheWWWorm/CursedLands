# Trials readability and roster follow-up

Validation date: 2026-10-19. Source changes are on top of `e0abbb1e`, using
schema 12. This is an experimental roster revision, not a published release.

## Presentation and interaction

The native desktop renderer was exercised in English, Russian and German with
the corresponding original game archives. The fixture opens a fresh solo
match, buys matching archers, selects field and reserve units in both orders,
switches the watched company, opens unit details, resizes the window and starts
real private-worker combat at 2×. The English run includes combat; the Russian
and German runs cover translated preparation and inspection layouts.

- Six offers fit, including all three evolution portraits per offer. Upgrade
  arrows do not intersect the lock controls. Rarity stays steady while upgrade
  readiness pulses cyan.
- A field unit returns to clicked reserve slot five. Occupied slots swap units
  in either selection order. Positions survive save, reload and undo.
- Three matching white-clan archers merge on the triggering purchase. Both
  white- and green-clan triples also merge with full reserves in the state test.
  Different clans remain different recruits and now have their native palettes.
- Damage names and values follow the viewed company, including its battle ledger.
- All battlefield corners, with heights from 0 to 4.5 metres, fit the default
  camera's HUD-safe area at 1280×720, 1280×960 and 1600×900. Round start preserves
  the manual camera pose. Returning to 1280×800 keeps the Start battle button
  inside the window.
- Unit details have tier accents and one compact evolution strip; complete form
  names are available on portrait hover. Player standings cannot cover the card.
- Round notices are unframed in the upper HUD. A short battle keeps its start
  title for one second, then displays its result for two seconds. The result does
  not replay when the other boards finish. Income omits zero bonuses and dots.
- The company level cue uses a separate UI sound player so a world audio rebind
  does not cut it off. The renderer fixture checks that the cue is playing.

The online regression runs real loopback ENet and WebSocket host/client pairs.
It verifies exact reserve positions, invalid-slot rejection and white-clan
appearance replication, alongside existing purchase, combat and snapshot checks.

| Check | Passed |
| --- | ---: |
| Roster integrity and opening pool | 1608 |
| Economy and save compatibility | 626 |
| Live/preview combat budgets and campaign data isolation | 919 |
| Slots, merges, highlights, migration and notice timing | 51 |
| Online host/client behavior | 80 |
| Rendered English UI | 66 |
| Rendered Russian UI | 63 |
| Rendered German UI | 63 |

Translation checking covers 2743 entries, 141 dynamic wiki keys and 151 dynamic
arena keys, with zero errors. All final checks above have no engine errors.
See [check output](trials-readability-2026-10-19/checks.txt).

## Armor-inclusive comparisons

The final three-star tests use the actual Trials terrain, navigation, native AI,
hit/parry rolls, typed damage, armor, resistance ratios, spell effects, cadence,
regeneration, alliances and 90-second battle limit. Four seeds are mirrored across
both sides, giving eight trials per pairing. Supported fights use the same two
melee allies on both sides. Opponents are all other chains of the same gold tier.

| Final form | Duel wins | Supported wins | Wins against three two-star units |
| --- | ---: | ---: | ---: |
| Ironhide walking golem, 1-gold chain | 25/48 | 18/48 | 33/56, one draw |
| Sand stalkers crawling golem, 4-gold chain | 16/40 | 19/40 | 36/48 |
| Elemental Pact Curse, 5-gold chain | 16/24 | 15/24 | 16/32 |

The last column compares nine invested base copies on each side: one three-star
unit against three two-star units. It includes the candidate's own chain. Slots,
target count and alliance composition still differ, as they do when choosing to
merge. There were no time-limit finishes in these 360 battles.

These results do not justify a blanket golem armor reduction. The Curse remains
strong in single-target fights. Against the revised five-gold final forms it beat
the red dragon in 8/8 duels, lost to the wormhead in 8/8, and beat the necromancer
in 8/8. With matched supporting allies those results became 3/8, 5/8 and 7/8.
Against equal-investment trios it lost every trial against red harpies and storm
harpies, and won against green evileyes and black-clan mages.

Armor was inspected independently using the same `Combat.absorb` calculation:

| Three-star form | Health | Armor in each damage type | Damage received from a raw 30 hit |
| --- | ---: | ---: | ---: |
| Walking golem | 175 | 9.8 | 20.2 |
| Crawling golem | 450 | 18.2 | 11.8 |
| Curse | 469 | 21 | 9 |

All three receive 2.4 from a raw 12 hit because absorption is capped at 80%.
The Curse retains a native lightning hit reduced to 175 by an effect rune, with
cast cadence scaled to 0.576. It has no regeneration. Its armor is the normal
three-star five-gold budget, not a unique immunity.

The revised prices retain 7/7/6/6/4 chains across gold tiers and fourteen opening
chains. Only two of the ten four/five-gold recruits are human, versus seven
before the price changes. Base-form follow-up comparisons for Moonwatch,
Sentinels and Arcane pilgrims add 112 mirrored native fights. An intermediate
two-gold Arcane pilgrims trial was rejected after winning all 48 comparisons;
that chain remains five gold.

Raw results: [armor](trials-readability-2026-10-19/armor.json),
[three-star contexts](trials-readability-2026-10-19/three-star-contexts.json),
[equal investment](trials-readability-2026-10-19/equal-investment.json),
[final recruit price checks](trials-readability-2026-10-19/recruit-price-checks.json).

These are controlled native-combat comparisons, not a measurement of human fun
or proof that no dominant composition exists. Seed selection, placement,
purchase opportunities and mixed alliances can change practical results. No
additional golem or Curse stat nerf was made from this sample.

## Complete bot matches

Four nine-company matches completed in 26–32 rounds, using two seeds and rotating
the four spending policies between seats. All companies use the same recruit
pool, economy and native combat; no policy gets extra resources. Each policy
appears nine times across the four matches.

| Spending policy | Wins | Top-three finishes | Average placement | Companies ending with a three-star unit |
| --- | ---: | ---: | ---: | ---: |
| Economy | 2/9 | 4/9 | 4.89 | 4/9 |
| Expansion | 1/9 | 4/9 | 4.11 | 1/9 |
| Evolution | 0/9 | 1/9 | 6.00 | 6/9 |
| Tempo | 1/9 | 3/9 | 5.00 | 2/9 |

The evolution policy did collect more three-star units: thirteen across its
final armies, versus two to five for each other policy. It still placed worst
in this sample, ending at an average capacity of 7.22 while the others averaged
8.56–8.78. Every winner reached capacity nine; three winners had no three-star
unit, and the fourth had two. This supports the concern that staying at a lower
level to chase evolutions can give up too much board strength.

This is a remaining balance concern, not evidence that every three-star form
needs stronger stats. These are four heuristic-bot matches, not independent
human strategy trials. Spending, family commitment and formation quality are
confounded with each policy. In particular, the strong golem/Curse results above
argue against applying an undifferentiated three-star buff. The next balance
comparison should isolate the cost of reaching three stars and the opportunity
cost of delaying capacity, then repeat mixed-army matches.

Raw match timelines: [bot tournaments](trials-readability-2026-10-19/bot-tournaments.json).

## Discord

The public ID `1561645781533069393` is stored in project settings and exported
with the game. A real local IPC socket test runs with `EI_DISCORD_APP_ID` unset
and verifies the bundled handshake ID, fragmented READY response, Suslanger
activity, ping/pong, disabling and clean exit. This verifies the protocol and
default configuration; it does not claim observation of a live Discord profile.
[Player and maintainer instructions](../integrations/discord.md).

## Captures

- [English shop](trials-readability-2026-10-19/en-shop.png)
- [Compact English inspector](trials-readability-2026-10-19/en-inspector.png)
- [Russian inspector](trials-readability-2026-10-19/ru-inspector.png)
- [German inspector](trials-readability-2026-10-19/de-inspector.png)
- [Russian income notice](trials-readability-2026-10-19/ru-income.png)
- [All 90 native portraits and revised prices](trials-readability-2026-10-19/native-portraits.png)
