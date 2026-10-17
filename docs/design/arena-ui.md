# Autochess interface

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
- Bottom left: a round training button shows company level and fills its ring with
  XP toward the next level. The gold badge shows the price. Refresh uses the same
  round control beside the shop. Both purchases play original UI sounds; gaining
  a level has a separate cue.
- Bottom: army/reserve counts, retained preview slots, income, gold, lives, Start
  battle or combat pause/speed. Reserve portraits match shop width and height;
  excess slots scroll horizontally. Selecting a unit reveals the sell destination;
  empty reserve slots withdraw a selected deployed creature.

Menu contains Continue, Auto arrange, Undo, Guide and Main menu. Arena/Sandbox
navigation is absent from both this menu and the main menu, including controller
focus targets. The PvE expedition and ten-player Autochess share the opening mode selector.
Autochess shows a health leaderboard on the right; clicking a player opens their
army. Hover details and round results use this same right-hand space, with the
standings hidden while either is shown.

## Feedback and transitions

The opening offers Expedition and Autochess, each with its own save. It combines
a large title, starting budget and direct action
with animated original creatures from three allods. Expedition difficulty stays visible;
the optional seed field expands on request. This composition differs from the
small in-game menu and reward panels, including when a saved run can be resumed.

Buying a creature places it on clear ground while there is army capacity. With
a full field it enters reserves. A purchase never selects the creature or leaves
a placement ghost; a merge keeps the deployed copy and its position.

At the start of preparation, creatures run into their formation. Moving a deployed
creature retains its model and issues a native move order; returning it to reserves
removes it. Native paths, turning, run clips and snow footprints carry the movement.
Combat waits for moving creatures to settle, and menus pause formation movement.

Evolution shows one complete comparison below the alliances on the left. Both
models finish loading before it appears, alongside formatted health and attack
changes. Hover details remain usable on the right; menus pause the notice. Sound
and a field highlight accompany the upgrade. Details use native names,
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

Escape dismisses creature details or the selected creature before opening Menu.
The dismissed hover stays closed until the pointer leaves. Combat speed is one
button that alternates 1×/2×; the last choice persists across both modes, old saves
and new games.

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
