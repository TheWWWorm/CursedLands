# Autochess items and alliances

Updated 24 October 2026 from stable 1.26.0 (`96aaeb78`). This describes the playable
revision on `fix/autochess-balance-20261024`. It supersedes the earlier eight-item,
six-trigger-alliance design; the dated reports below retain that historical evidence.

## Design intent and references

An item should offer an understandable improvement or a deliberate change in how
a creature fights. The pool mixes raw statistics with conditional effects. Early
rewards establish a role; later rewards give that role enough power to matter
against evolved armies. Four alliances provide simple stat benefits, leaving two
tactical alliances for players who want more conditions to build around. One
recruitable Woodsfolk line removes the confusing duplicate silhouette from the shop.

The loop stays recruit → arrange → equip → watch combat → choose a reward.
One item per creature makes carrier selection meaningful without components,
crafting or another currency.

[Drodo's introduction](https://ac.dragonest.com/en/gameIntroduction) uses distinct
pieces and overlapping race/class thresholds. Its
[equipment catalog](https://ac.dragonest.com/en/equipment) mixes attack speed,
armor, health and spell power with triggered effects. Both patterns inform this revision.

[Valve's dated alliance notes](https://store.steampowered.com/news/posts/?appids=1046930&enddate=1575328116)
include simple Warrior/Scaled defenses alongside tactical Spirit behavior.
[Valve's item reward notes](https://store.steampowered.com/news/posts/?appids=1046930&enddate=1578361897)
describe regular item choices of equal quality independent of the round result.
These are structural references, not present-day competitive balance targets.

The user's [Underlords item reference](https://dotaunderlords.fandom.com/wiki/Items)
provides the five-tier model. Its indexed catalog was available; direct retrieval
was blocked, and the indexed odds table contained corrupted values. No odds from
that table were copied. Cursed Lands uses the explicit milestones below.

## Rewards and rarity

There are **40 items: eight per tier, 23 with only raw stats and 17 with a
triggered effect or a mixture of stats and effects**. Names, generated descriptions,
tier labels, roles and help are localized in English, Russian and German.
Descriptions read their percentages from the gameplay definitions.

| Completed round | Tier | Border on cards, tray, equipment slots and drag previews |
| --- | --- | --- |
| 3 | 1 | None |
| 5 | 2 | Green |
| 10 | 3 | Blue |
| 15 | 4 | Purple |
| 20 and subsequent multiples of five | 5 | Gold |

Creatures and items share the same palette. Tier text identifies rarity without
relying on color. Focus uses an underline or corner pointer, preserving the border.
Pictures are transparent renders of original game models and materials. The 32 new
pictures have source model, texture and camera provenance in the asset manifest.

Every surviving player receives three distinct choices of the same tier,
independent of winning the fight. Reward RNG leaves shop results unchanged.
An unresolved choice becomes the first displayed item in the stash when preparation
ends. Old saves receive no retroactive awards. Tier 5 continues through the existing
maximum reward round of 100.

## Item catalog

| Tier | Raw-stat items | Effect or mixed items |
| --- | --- | --- |
| 1 | Vitality Amulet, Iron Sword, Swift Boots, Iron Mail, Prismatic Gem, Sage's Wand | Vampiric Fang, Venom Seal |
| 2 | Steel Saber, Amber Heart, Mercury Gloves, Runic Mail, Wisp Stone, Seer Staff | Ward Stone, Thorn Shell |
| 3 | Stone Cleaver, Sentinel Plate, Sage Tome, Windrunner Boots | Storm Shard, Guardian Knot, Echo Rune, Berserker Charm |
| 4 | Archmage Scepter, Titan Plate, Duelist Blade | Bloodfang, Storm Heart, Plague Sting, Ancient Aegis, Spiked Mantle |
| 5 | Sunblade, Heart of the World, Dragon Scepter, Starweave | Blood Moon, Tempest Orb, Sacred Covenant, Echo Chronicle |

Raw attack items progress from +20% on Iron Sword to +120% on Sunblade; health
ranges from +25% on Vitality Amulet to +150% on Heart of the World. Mixed items
trade some of that dedicated power for flexibility. All bonuses use the recruit's
normalized arena budget. Percentages on the same statistic add to alliance bonuses.
Physical armor covers the three physical damage types; elemental armor covers
fire, acid and lightning. Action speed affects attacks and casting. Spell bonuses
increase offensive spell damage. Exact values live in `ArenaItems.RULES`.

Lifesteal heals a portion of actual basic-attack damage, with a per-hit maximum-health
cap. Venom reduces healing for five seconds. Each suppression strength retains its
own duration; a weaker application cannot overwrite or extend a stronger one.

Shields trigger once per battle when a hit would take the recipient below 35%
health. They last five seconds; Guardian items protect another ally within 5 m.
Only the strongest remaining shield applies, and sufficient personal protection
preserves an ally's unused Guardian effect. Absorption uses whole-creature health
even when native damage hits a head or limb. Ward/Guardian effects grow substantially
at tiers 4–5 to compete with passive health bonuses.

Every third basic hit triggers Storm items against other enemies within 4 m of
the wearer; the tier-5 orb hits two. Echo items repeat every third offensive cast,
or every second at tier 5, using the spell's element. Retaliation has a one-second
cooldown. Berserker accelerates actions while preventing casting. Generated damage
respects armor and cannot recursively trigger item hits or casts.

Preparation permits free reassignment between deployed creatures, reserves and
stash. Combat freezes equipment. Selling returns the item; evolution retains the
surviving creature's item and returns items from consumed copies. Dragging,
click-to-assign and keyboard targets use the same ownership actions. Scouted boards
permit inspection. Cancellation preserves inventory and formation.

## Alliances and roster

Unique deployed families count once, regardless of copies or stars. Membership
and thresholds freeze at the bell. Stat bonuses activate from a fresh recruit
budget and cannot compound when the board is refreshed.

| Alliance | Thresholds | Benefit |
| --- | --- | --- |
| Beasts | 2/4/6 | Members gain 10/20/30% attack damage |
| Horde | 2/4 | Members gain 15/30% maximum health |
| Warriors | 2/4 | Members gain 30/60% physical armor |
| Mages | 2/4 | Members gain 15/30% spell damage |
| Hunters | 2/4 | Completed enemy casts mark the caster for 3 seconds. Hunters prioritize it within reach; at four Hunters, all allies do. |
| Spirits | 2/4 | The first Spirit death heals the nearest 1/2 wounded allies within 5 m for 12% of the fallen unit's maximum health. At four Spirits, it also leaves one wisp with 20% health for 6 seconds. |

Spirit echoes have no items, do not count toward alliances and cannot repeat death
effects. Hunter preference does not grant extra range or bypass screening. The old
pack, retaliation-on-death, neighboring guard and combined-cast reaction rules
are removed. Bots value the new stats, place armored Warriors in front and use
close formations for Spirit aid or Guardian equipment.

The shop has **29 recruit lines**. Woodsfolk archers (family 11) are its only
Woodsfolk line; visually similar seers (family 29) are retired. Orc warriors remain
available. Old owned seers retain their identity, equipment and position. Their
family ID stays reserved for compatibility.

## Combat feedback and victory

Lifesteal and Spirit healing use the original healing particles. Shields use the
native lightning-protection sphere for their lifetime, with a short impact flash
on depletion. Storm effects draw source-to-target lightning bolts. Echo, venom,
thorns, frenzy, Hunter marks and Spirit arrivals reuse native spell effects.
Repeated healing or poison notices cannot pile up identical emitters.

These presentation events do not alter health, stats or combat random streams.
Online and solo-worker replicas receive the same events. Full board snapshots
restore shields with their remaining duration when scouting or reconnecting.

The local champion hears the original **`stream/victory.mp3`** once at the end of
the game. It replaces background music, follows the music-volume setting and does
not restart on UI refresh or board changes. Individual round wins, defeats and
watching another player's championship do not trigger it. Starting a new game
resets the cue. No additional music file is bundled.

## Compatibility and validation

Arena save schema is 15. Pending rewards from schema 14 preserve their original
eight-item pool and exact choices, including saving again or undoing a choice.
Future milestones use the tiered pool. Old shop offers for the retired seer become
empty and unlocked; owned seers survive. Current saves and commands cannot create
new retired offers. Online protocol is 3 and requires matching builds. Campaign
equipment and monster data are untouched.

[Validation for this revision](../validation/autochess-balance-2026-10-24.md)
records state, migration, combat, localization, UI, native feedback, victory audio
and complete tournament checks. These values are an initial tuning pass, not a
claim of solved competitive balance. Further player feedback should compare
conditional items with passive alternatives and assess late-tier power.

Earlier reports remain historical evidence for the
[first equipment implementation](../validation/autochess-equipment-alliances-2026-10-23.md),
[roster comparison](../validation/autochess-roster-2026-10-23.md) and
[equipment interface](../validation/autochess-equipment-ui-2026-10-23.md).
No release or version tag is created by this change.
