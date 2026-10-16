# Expedition interface audit and revision

Scope: every control and overlay in Trials of the Allods, plus its shared battlefield
picking and battle feedback. Inline review by the implementing agent, using the
game-design, Godot UI Builder and Impeccable workflows; no delegated review.
Disposition: ready for the local desktop preview. The balance limitation below
remains explicit; this is not a perfect-score or equal-build-balance claim.

The design authority is [arena-ui.md](../design/arena-ui.md), the existing generated
concept and the native game's materials. This audit supersedes the earlier
small-window usability review. Ratings of a concept are not runtime acceptance.

## Decisions

| Element | Decision | Implemented treatment / acceptance |
| --- | --- | --- |
| Overall HUD and type | Rework | One logical canvas scales fonts, targets, models, spacing and frames together. Field remains full resolution. Body text uses a readable sans serif, with native serif headings. |
| Landing title and introduction | Rework | Centered setup, 16 starting gold, optional seed/difficulty and Begin. Empty army is explicit. |
| Starter choices | Remove | No free creatures. All six opening families appear in the first shop. |
| Difficulty and seed | Keep | Secondary controls in the setup panel; difficulty unlocks remain explicit and seed remains optional. |
| Begin / resume / replace-run confirmation | Rework confirmation | Primary action stays visible. Replace-run confirmation uses the same framed modal as the rest of the mode. |
| Recruitment shelf | Keep, refine | Unboxed native models and prices preserve the battlefield. Full names appear on hover/focus and in the hover inspector. Locked and recruited states remain distinct. |
| Copy progress and evolution | Replace manual control | Show matching-copy progress; combine automatically from wave 1, including chained upgrades. Details explain and preview the next original form. No disabled evolution button or wave gate. |
| Offer quality | Add restrained feedback | One to three stars identify evolution rank on offers, reserves and field units. Original forms and native stats are used. |
| Refresh / offer lock | Keep | Refresh price and blocked reason are readable; one lock survives refresh and shop improvement. Equal state padding keeps icons still. |
| Shop improvement | Add | One small shelf action opens costs, quality odds and a purchase button. Insufficient gold and maximum level are explicit. An improvement includes an immediate refresh of unlocked offers. |
| Wave / phase / clock | Keep, scale | Compact corner badge; encounter and seed move to help. Clock appears only in combat. |
| Menu button and contents | Rework | Labelled button and themed modal replace the tiny icon/native popup. State-aware Continue, training, Arrange, Undo, Guide and navigation. Combat pause state survives opening/closing. Keyboard focus stays in the modal. |
| Guide | Rework | Six short topics in a bounded scroll area; fixed Close action. Minimum-size changes recenter/reflow the panel after localized text wraps. |
| Battlefield picking | Rework | Current posed mesh/part bounds and a small screen-space tolerance replace ground-origin proximity. A bat is selected on its visible body. HP/star markers are also targets when bodies overlap. |
| Team circles | Remove in expedition | Team identity uses health bars. Small corners appear only on hover or selection. A placement preview still shows where a creature will land. |
| Health feedback | Rework | Current / maximum HP above the line; bars anchor to the actual model head, including flight height. Scale follows the HUD. |
| Damage feedback | Restore | Real native hit events drive the campaign number atlas, critical labels and fade; the existing damage-number display option is respected. |
| World hover information | Add | Hover opens native live HP, attack, defense, armor weaknesses/resistances, damage type, spells and recipe progress in the side panel. |
| Inspector | Refine | Delayed hover rail with scrolling details and a leave grace period. It remains open while hovered; selection does not pin it. |
| Company / synergy details | Keep | Hovering the army counter opens the rail with experience, pact conditions, native guest and acquired upgrades. Clicking opens training. No permanent extra sidebar. |
| Army and reserve counters | Refine | Both capacities are labelled. An active pact is explained through the company rail; color is not the only cue. |
| Reserve shelf and return flow | Rework interaction | Selecting a deployed ally enables empty reserve slots as return targets. The first empty slot is labelled Return. Successful placement/withdrawal releases the creature. Direct reserve-to-ally swaps and Undo remain available. |
| Gold / lives | Keep, scale | Compact resource cluster next to the main action; victory-income forecast with interest and streak breakdown in bounded help. |
| Start battle | Keep, refine | One primary action. No redundant tooltip. |
| Pause / speed | Keep | Replace recruitment actions during combat. Space pauses, speed stays explicit, opening the menu preserves prior pause state. |
| Victory / defeat / final outcome | Rework | Centered, content-sized panel after a 1.6-second animation interval, with result, wave, income breakdown/lives and one next action. |
| Camp choices | Keep, reflow | Intermittent two/three-choice panels; localized text, native models and actions fit. Bench and field inspection are inactive during the decision. |
| Error / action feedback | Keep, contextualize | One restrained line for actionable errors. No repeated placement or merge announcements; hidden during results. |
| Tooltip infrastructure | Replace | One scaled, wrapped, viewport-clamped control handles button help. Creature details use the hover rail. A 350 ms delay prevents immediate obstruction. |
| Courtyard, ruins and shadows | Rework for winter | Native Ingos snow and winter scenery; courtyard art shares the native terrain surface so trails, footprints and blood remain visible. Orthographic shadows remain. |
| Evolution result | Add | Brief queued before/after models, stars, HP/attack changes, sound and creature highlight; click-through and cleared on undo/sale/battle. |
| Regional recruitment | Add to existing surfaces | Arrival families in the result and recruitment dialog; no permanent extra HUD strip. |

## Verification and findings

The [winter validation](arena-winter-2026-10-16.json) supersedes the earlier
opening and battlefield evidence: empty start, stronger regional recruits,
readable evolution feedback and actual snow/blood rendering. Earlier captures
below remain historical references.

Current captures: [snow tracks and blood](../screenshots/arena-winter-en-trails-blood.png),
[evolution](../screenshots/arena-winter-en-evolution.png),
[later recruits](../screenshots/arena-winter-en-late-roster.png),
[4K HUD](../screenshots/arena-winter-en-4k-empty.png),
[Russian recruitment](../screenshots/arena-winter-ru-market.png),
and [German late camp](../screenshots/arena-winter-de-late-camp.png).

The [earlier expansion record](arena-expansion-2026-10-16.json) covers income, training, hover/sell interactions, preview bounds, stable icons and delayed results. Its rendered cases cover EN/RU at 1280×800, DE at 1024×768 and EN at 3840×2160. The earlier [usability record](arena-usability-2026-10-16.json) contains source/log hashes,
checks, captures and historical balance samples. Functional checks exercise actual
pointer routing, visible bat bounds, both return paths, shop improvements, native
hit events, modal focus and pause behavior. Rendered cases include 1024×768 RU/DE,
1280×720/800, 1920×1080, 2560×1440, 3840×2160 EN/RU/DE and 5113×2856 EN.
The latter matches the physical dimensions of the high-resolution reference.

Visual inspection covered the starter screen, preparation/hover, inspector,
menu, guide, recruitment improvements, native critical-hit feedback and victory.
It found a real localized guide width problem after deferred text wrapping. The
panel now responds to minimum-size changes and has bounded scrolling. The old
small-window fixture also compared physical screen positions with local HUD
positions; those checks now use a consistent coordinate space and wait for
startup window settings before selecting a resolution.

The first multi-resolution run in a single process terminated in the private
native preview after a focus assertion. Fresh-process cases isolate renderer
caches and window setup; only their completed results count as resolution evidence.
The final native sandbox regression checks the shared picking/combat changes.
The headless logic checks cover wave-one wolves, chained final forms, full-reserve
recipes, undo, quality odds, locked offers, save migration and first-tick enemy
movement. The original prototype database remains unchanged.

## Limits

Desktop mouse/keyboard on Linux Forward+ is the reviewed target. Controller,
touch, other renderers and text scaling below the supported desktop sizes are
not covered. Dense combat can still overlap health labels, as in the native game.
The original low-polygon models and textures remain deliberately visible.

Automated purchasing policies are not human win rates. Current small cohorts
show that a frontline-first opening survives more consistently than the preset
affinities used by the comparison policy. Both buy late casters; neither is a
pure-melee test. Native power gaps and regional transitions still need human
playtesting. See the winter validation rather than historical clear rates.

Reviewed captures: [hover and HP](../screenshots/arena-usability-en-hover.png), [menu](../screenshots/arena-usability-en-menu.png), [shop improvements](../screenshots/arena-usability-en-shop.png), [native damage](../screenshots/arena-usability-en-hit.png), [victory](../screenshots/arena-usability-en-victory.png), [German guide](../screenshots/arena-usability-de-guide.png).

## Economy and interaction follow-up

The completed follow-up makes these interaction and economy decisions explicit:

| Element | Final decision |
| --- | --- |
| Selected creature details | Replace persistent selection panel with delayed hover details and a short leave grace period. |
| Placement | Clear selection/ghost after successful placement or swap; retain it on invalid placement. |
| Reserve withdrawal | Keep clickable empty slots; remove inspector action duplication. Fit reserve widths to the real localized control space. |
| Selling | Contextual sell area with refund appears for selected owned creatures; support undo. |
| Preview figures | Fit posed body, weapons and wings to each actual slot; remove arena zoom overrides. |
| Rank badges | Replace Roman numerals with consistent 1–3 star geometry on board, reserves and shop. |
| Stat block | Add native attack/defense and armor-derived weaknesses/resistances; keep live HP and spells. HP markers also act as hover targets in crowded combat. |
| Army counter | Hover shows company; click opens optional training purchase. |
| Purse | Add conditional victory-income preview and bounded breakdown tooltip. |
| Victory/defeat | Keep centered frame, wait 1.6 seconds for figure animations; include income breakdown. |
| Icons and reserve states | Equal padding for normal, hover, pressed and focus; assert unchanged lock/row rectangles. |
| Copy | Remove repeated merge announcements, developer-facing provenance and redundant Start tooltip; keep rules in guide. |

The updated design and validation supersede the earlier selection/selling and
flat-income behavior. Existing lighting, textured court, native damage numbers,
resolution scaling, modal focus and automatic evolution remain.

Earlier captures: [selection and sell destination](../screenshots/arena-expansion-en-selection.png),
[income and victory](../screenshots/arena-expansion-en-victory.png),
[Russian training](../screenshots/arena-expansion-ru-training.png),
[German expanded reserves](../screenshots/arena-expansion-de-expanded.png),
and [4K company selection](../screenshots/arena-expansion-en-4k-landing.png).
