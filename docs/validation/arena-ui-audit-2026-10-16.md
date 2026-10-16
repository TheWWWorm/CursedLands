# Expedition interface audit and revision

Scope: every control and overlay in Trials of Gipath, plus its shared battlefield
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
| Landing title and introduction | Keep, scale | Clear company choice before entering the run; no tiny upper-left block at high resolution. |
| Starter choices | Keep, scale | Three labelled companies, roles, selected state and three live models; localized descriptions remain readable. |
| Difficulty and seed | Keep | Secondary controls below starter choices; difficulty unlocks remain explicit and seed remains optional. |
| Begin / resume / replace-run confirmation | Rework confirmation | Primary action stays visible. Replace-run confirmation uses the same framed modal as the rest of the mode. |
| Recruitment shelf | Keep, refine | Unboxed native models and prices preserve the battlefield. Full names appear on hover/focus and in bounded help. Locked and recruited states remain distinct. |
| Copy progress and evolution | Replace manual control | Show matching-copy progress; combine automatically from wave 1, including chained upgrades. Details explain and preview the next original form. No disabled evolution button or wave gate. |
| Offer quality | Add restrained feedback | Roman II/III marks identify upgraded offers without another row of text. Original forms and native stats are used. |
| Refresh / offer lock | Keep | Refresh price and blocked reason are readable; one lock survives an ordinary refresh and a shop improvement. |
| Shop improvement | Add | One small shelf action opens costs, quality odds and a purchase button. Insufficient gold and maximum level are explicit. An improvement includes an immediate refresh of unlocked offers. |
| Wave / phase / clock | Keep, scale | Compact corner badge; encounter and seed move to help. Clock appears only in combat. |
| Menu button and contents | Rework | Labelled button and themed modal replace the tiny icon/native popup. State-aware Continue, Company, Arrange, Undo, Guide and navigation. Combat pause state survives opening/closing. Keyboard focus stays in the modal. |
| Guide | Rework | Five short topics in a bounded scroll area; fixed Close action. Minimum-size changes recenter/reflow the panel after localized text wraps. |
| Battlefield picking | Rework | Current posed mesh/part bounds and a small screen-space tolerance replace ground-origin proximity. A bat is selected on its visible body. |
| Team circles | Remove in expedition | Team identity uses health bars. Small corners appear only on hover or selection. A placement preview still shows where a creature will land. |
| Health feedback | Rework | Current / maximum HP above the line; bars anchor to the actual model head, including flight height. Scale follows the HUD. |
| Damage feedback | Restore | Real native hit events drive the campaign number atlas, critical labels and fade; the existing damage-number display option is respected. |
| World hover information | Add | Name, live HP, armor, damage range, spells and copy progress appear without selecting. Same bounded tooltip system as buttons. |
| Inspector | Refine | Optional rail with scrolling details; Return to reserves and Sell stay fixed below it. Enemy and pact guests have appropriate read-only actions. |
| Company / synergy details | Keep | Army counter opens the same optional rail with pact conditions, contributing families, native guest and acquired run upgrades. No permanent extra sidebar. |
| Army and reserve counters | Refine | Both capacities are labelled. An active pact is explained through the company rail; color is not the only cue. |
| Reserve shelf and return flow | Rework interaction | Selecting a deployed ally enables empty reserve slots as return targets. The inspector also says Return to reserves. Direct reserve-to-ally swaps and Undo remain available. |
| Gold / lives | Keep, scale | Compact resource cluster next to the main action; full meanings in bounded help. |
| Start battle | Keep, refine | One primary action with a restrained 310-unit wrapped tooltip. No oversized tooltip window. |
| Pause / speed | Keep | Replace recruitment actions during combat. Space pauses, speed stays explicit, opening the menu preserves prior pause state. |
| Victory / defeat / final outcome | Rework | Centered, content-sized opaque panel with a clear result, wave, income/lives, summary and one next action. Old placement hints and health markers disappear. |
| Camp choices | Keep, reflow | Intermittent two/three-choice panels; localized text, native models and actions fit. Bench and field inspection are inactive during the decision. |
| Error / action feedback | Keep, contextualize | One restrained line during preparation/combat, including automatic evolution confirmation. Hidden during results. |
| Tooltip infrastructure | Replace | One scaled, wrapped, viewport-clamped control handles buttons and world hover. A 350 ms delay prevents immediate obstruction. |
| Courtyard, ruins and shadows | Keep | Existing textured 3D field and corrected orthographic shadows remain. No new decorative panel competes with the field. |

## Verification and findings

The [validation record](arena-usability-2026-10-16.json) contains source/log hashes,
checks, captures and current balance samples. Functional checks exercise actual
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
still expose a harder final encounter for rigid melee purchasing; the shop
upgrade feature does not justify claiming equal build balance. See the current
validation data rather than the historical progression clear rates.

Reviewed captures: [hover and HP](../screenshots/arena-usability-en-hover.png), [menu](../screenshots/arena-usability-en-menu.png), [shop improvements](../screenshots/arena-usability-en-shop.png), [native damage](../screenshots/arena-usability-en-hit.png), [victory](../screenshots/arena-usability-en-victory.png), [German guide](../screenshots/arena-usability-de-guide.png).
