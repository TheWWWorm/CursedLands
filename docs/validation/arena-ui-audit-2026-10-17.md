# Expedition interface review — 17 October 2026

Current implementation and captures are indexed in
`arena-alliances-2026-10-17.json`. Earlier audits describe historical revisions.

| Surface | Decision and observed behavior |
| --- | --- |
| Opening | Rebuilt as a wide composition with a large title, animated original creatures, budget and Begin action. The harpy has a wide flight frame above and beside the troll. Difficulty is visible; the seed field expands only on request. Saved runs retain Continue. |
| Recruitment | Keep native animated previews. Price reflects tier; stars reflect earned evolution. Add small alliance marks without adding another text row. Lock position and viewport identities stay stable. |
| Training | Move the purchase into the HUD with level and XP. One click buys five XP for five gold. Disable with a reason when unaffordable, in combat or at maximum level. |
| Alliances | Replace pact selection and summoned guests with automatic overlapping traits. The left list shows progress and active state; hover shows the current effect and contributing families. Dark backing keeps text readable on snow. |
| Army management | Keep body-based selection, direct sale and reserve destinations. Native movement commands replace repositioning teleports. Ordinary placement releases selection. |
| Round entrance | Both teams run to formation before combat; arrivals use original pathfinding, turning and locomotion. Early start waits for arrival. Preparation movement cannot cause attacks or advance the combat clock. |
| Outcomes | Preserve final-animation settling. Victory and income share one row, with the countdown below; the notice has no background or border. Empty phase/timer labels no longer hold the wave badge open. Ordinary results contain no button and advance after four seconds. Camps every five wins retain one framed reward choice. |
| Menu | Remove Arena/Sandbox and training navigation. Preserve Continue, formation/undo tools, guide and Main menu. Menus pause combat, countdown and formation travel. |
| Live details | Show native names and effective combat stats, acknowledging active bonuses. Longer membership lists scroll within the side panel. |
| Localization and scale | Inspect EN/RU/DE at 1024×768 or above, plus 3840×2160. The HUD and preview pixels scale together; long German and Russian text wraps in bounded containers. |

The rendered tests use actual clicks, native actor/model identities and image
readbacks. Battle balance is reported separately from layout and interaction checks.
