# Arena expedition interface

Scope: the PvE expedition only. Native Godot desktop UI, mouse and keyboard.
The surface is an Experience: the player watches and arranges creatures on a
battlefield. Persistent controls must leave that battlefield clear.

## Visual target

The [selected generated concept](arena-ui-concept.png) combines the original
game's muted bronze, warm ivory lettering and native creatures with an open
autobattler layout. The [generation record](arena-ui-concept.provenance.json)
contains both prompts and subjective ratings: first 8/10, refined 9/10. These are
design judgments, not usability scores or proof that every runtime state is done.

The implementation uses real Godot controls and live model previews. No screenshot
is used as an interactive UI background. Frames come from the original `saveload`
atlas; icons are small authored SVG geometry. The paving has its own
[generated texture provenance](../../game/assets/arena/courtyard.provenance.json).
Creatures, scenery and other terrain textures load from the user's game files.

## Composition and interaction

- Full-screen battlefield. The shop is an unboxed shelf across the top left.
  Models, prices and owned-copy progress stay visible. Names appear on hover or
  keyboard focus; tooltips provide full names, role, price and blocked reasons.
- A small top-right badge carries wave and preparation/combat state. The encounter
  name and seed are in its tooltip. Combat adds an elapsed clock.
- Reserves are live models above faint slot marks along the lower edge. The
  lower-right group holds gold, lives and the single main action. Combat replaces
  Start with pause/speed controls and removes the recruitment shelf.
- Selection opens one detail panel. It contains native stats and spells,
  bench/sell actions and the next evolution. The evolution action stays outside
  the scrolling content. Esc or right-click clears it.
- The deployment boundary appears only while placing a selected creature. Rings
  mark selection or hover; health bars identify the two sides. Enemies are
  inspected directly on the field.
- Guide, auto-arrange, undo and navigation share the corner menu. Instructions
  appear during placement or when an action fails. There is no persistent help
  footer, opponent list, progress strip or full-width header/reserve panel.

The primary action uses an ivory serif label and the original thin bronze frame.
Compact resource values and help text use the game's legible sans serif. Color is
supported by labels, counts, placement geometry and disabled controls.

## Verification

Rendered interaction fixtures cover EN at 1280×800 and 1280×720 and RU/DE at
1024×768, including six offers, nine reserves, selection, rewards and completion.
They exercise pointer deployment, purchasing, evolution, menu undo/auto-arrange,
live native combat, pause and speed. Visual inspection supplements bounds checks:
it caught collapsed price labels, which now have an explicit regression check.
See the [validation record](../validation/arena-pve-2026-10-16.json) for evidence
and platform limits. Controller/mobile layouts are outside this validation.
