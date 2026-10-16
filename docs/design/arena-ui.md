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
[generated texture provenance](../../game/assets/arena/courtyard-v2.provenance.json).
Creatures, scenery and other terrain textures load from the user's game files.

## Battlefield treatment

The courtyard uses smaller, worn limestone blocks, a restrained central stone
inlay and a broken perimeter band. These are an actual diffuse texture on a 3D
surface; subtle relief follows its seams and mipmaps keep distant paving stable.
The original fallen columns, boulders and trees still provide the scenery.

Shorter, less saturated grass gathers at the edges instead of growing through
the fighting area. A courtyard-only `TerrainDetails` subclass changes the grass
and optional ground-cover shaders; native vegetation generation, terrain types,
heights, navigation costs and scenery collision remain unchanged. Campaign
materials are not edited. Grass, wind, interaction and ground-cover options can
be toggled without losing this presentation.

A warm sun separates the creatures from the paving, with cool ambient shade,
optional ambient occlusion and lighter contact shadows. The small orthographic
arena uses one shadow map and a 90 m camera far plane; the old 180 m range and
cascade splits gave the opposing rows visibly different shadows. Softer filtered
edges, shorter shadows and a lower bias retain contact with the ground.

The central paving is opaque so ambient shading reaches feet and rubble bases.
Only four narrow, non-overlapping border strips blend into the grass, using the
same texture coordinates. The arena viewport applies the selected anti-aliasing,
texture filtering and shadow quality; ambient occlusion also responds to changes.
The distant woodland fades into black at maximum zoom instead of exposing the
old cyan map edge. Previous lighting and fog uniforms are restored on exit.
The shop, reserve shelf and selection-only detail layout remain as documented.

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
- Clicking the army counter opens company details in that same optional rail:
  the selected pact, distinct eligible families, the support creature and owned
  expedition upgrades. Its flag is gold while the pact is active. There is no
  persistent synergy sidebar. Shop tooltips and creature details identify family
  membership and the Tribal council's evolution requirement.
- Five camp visits interrupt the run with one deliberate choice. The first shows
  three pact candidates with live native models and concise conditions. Later
  visits trade support upgrades against economy or recovery. A completed boon
  collection leaves two useful options. Names and descriptions wrap in RU/DE;
  native stats are available in each creature reward's tooltip. Inactive army and
  reserve controls cannot show tooltips over camp choices. Reward emblems use
  larger SVG imports to remain crisp at their 44 px display size.
- A selected reserve can replace an ally directly by clicking that creature on
  the field. This works with both budgets full and remains undoable. Camp screens
  disable reserve/field selection, preserving focus on the reward decision.
- Guide, company details, auto-arrange, undo and navigation share the corner menu. Instructions
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
The later [field validation](../validation/arena-field-2026-10-16.json) records
the visual refinement, option checks and exact before/after navigation hashes.

The [progression validation](../validation/arena-progression-2026-10-16.json)
adds native support, camp and reserve-swap coverage. It includes first-pact and
upgrade choices, all-owned-boon fallback, final-form labels, full reserves and
720p camp layout. An initial hover-padding mismatch clipped the army capacity;
the normal and hover states now reserve identical text space. The same record
includes the shadow correction, close/default/wide and rotated captures, graphics
option coverage, and exact physical-data equivalence. The
[final review](../validation/arena-progression-review-2026-10-16.md) covers this
pass; the earlier field review is historical evidence.
