# Expedition interface

Current surface brief, 17 October 2026. Mode: Operate during preparation and
Experience during combat. Preserve the original game's creatures, serif titles,
bronze frames and snowy battlefield. Keep the battlefield dominant.

## Persistent controls

- Top: animated native recruits, price, copy progress, evolution stars and small
  alliance marks. A stable lock holds one offer. Refresh and hoverable shop odds
  sit beside the shelf. New offers have one star; prices identify tiers.
- Top right: wave, phase, preparation countdown and Menu.
- Left: only represented alliances, with current count toward the next threshold.
  Gold identifies an active bonus. A compact dark backing keeps text legible over
  snow. Hover reveals the actual active effect, other thresholds and membership.
- Bottom left: company level, XP toward the next level and the direct Train purchase.
  This action is never hidden in Menu or an extra dialog.
- Bottom: army/reserve counts, retained preview slots, income, gold, lives, Start
  battle or combat pause/speed. Selecting a unit reveals the sell destination;
  empty reserve slots withdraw a selected deployed creature.

Menu contains Continue, Auto arrange, Undo, Guide and Main menu. Arena/Sandbox
navigation is absent from both this menu and the main menu, including controller
focus targets. The PvE expedition remains available.

## Feedback and transitions

The opening combines a large expedition title, starting budget and direct action
with animated original creatures from three allods. Difficulty stays visible;
the optional seed field expands on request. This composition differs from the
small in-game menu and reward panels, including when a saved run can be resumed.

At the start of preparation, creatures run into their formation. Moving a deployed
creature retains its model and issues a native move order; returning it to reserves
removes it. Native paths, turning, run clips and snow footprints carry the movement.
Combat waits for moving creatures to settle, and menus pause formation movement.

Evolution compares the old and new model at the right edge, with sound and a field
highlight. Hover details temporarily cover and pause it. Details use native names,
current HP, attack/defense, typed armor and weaknesses. Applied alliance bonuses
are acknowledged on a deployed creature's live stats.

Combat settles for 1.6 seconds before a borderless side result. Victory and income
share the first row; the countdown sits below. Text has a fine dark edge for
contrast on snow. The wave badge shrinks when its phase and timer are hidden.
Ordinary results have no button;
a four-second countdown advances to preparation, retry or the camp reward choice.
Menus pause this transition. Final outcomes retain New expedition. Camp rewards
need one choice only. Preparation then begins with 45 seconds; Start battle is an
optional early start, not a next-wave confirmation.

## Layout, input and copy

A 1280×800 reference canvas scales HUD geometry and type together through 4K.
Field rendering remains at physical resolution. Portrait viewports allocate pixels
at that same physical scale. Preview fitting includes weapons and wings. Creature
body bounds drive picking, including flying bats.

Container widths remain fixed through hover, selection and locking. Shop/reserve
previews are keyed by identity and form; changed counts never recreate unrelated
models. Formation edits retain actors and animation phases. Thin, consistent line
icons supplement text. Short action labels and exact current effects replace log-like
instructions; longer explanations stay in the guide or a hover panel.

EN/RU/DE labels, dynamic alliance descriptions, timers, errors and options ship
together. Rendered checks cover 1024×768, 1280×800 and 3840×2160, plus native
combat, return/sell interactions, training, automatic results and camp choices.
They also cover the opening, its optional seed and saved-run layout, and formation
movement through intermediate positions without teleporting or early attacks.
Earlier screenshot/validation records are historical, not the current design.
