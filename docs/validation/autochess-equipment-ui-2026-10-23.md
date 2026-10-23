# Autochess equipment UI validation — 23 October 2026

The final interface follows the user-provided Underlords gameplay reference:
three reward cards float over a dimmed board, while owned equipment stays in a
compact icon tray below alliances. The pictures are direct 256×256 native renders
of eight existing game items, shared by rewards, the tray, creature badges and
tooltips. The cards reuse the original stone and metal textures around larger
objects, serif names, short effect roles, left-aligned descriptions and explicit
Choose actions. Highlighted values come from the same translated effect text.
Hover and keyboard focus illuminate the frame and gently enlarge the object.
The earlier inventory modal and recipient dropdown have been replaced.

A reward click closes the cards and selects the newly owned item. Players can
click an item and then a friendly deployed or reserve creature, or drag the item
directly. Circular creature targets appear during assignment. Equipped field and
reserve badges remain visible afterward and can transfer the same owned item.
Replacing an item returns the former item to the shared stash; returning without
a replacement uses the explicit stash button or drop target. Escape and right
click cancel both logical assignment and the native drag preview.

Keyboard navigation reaches the actual creature targets, return control and
cancel action. Temporary focus links are removed after assignment or cancellation.
The tray follows focused items when scrolling. Item detail appears on pointer
hover or keyboard focus, including during combat. Combat badges read frozen
battle placement data. Foreign boards, enemies, summons and combat reject
assignment. The online screen uses the existing authoritative equipment command;
the UI waits for host state before selecting a newly awarded item.

The sidebar shrinks to its contents and stays above reserves at 720p. Space freed
by hiding the damage panel allows two full item rows; larger inventories scroll.
Field badges avoid every visible creature's HP and star rectangle, including
neighboring creatures. Reward cards isolate background input and keep focus
inside the modal. Opening and closing them restores the tray's editing state.

## Compact assignment controls

The follow-up size refinement uses 40 px tray slots (previously 50), 34 px
assignment targets (44), 28 px equipped badges (32), and a 44 px drag preview
(74). The preview sits beside the pointer, keeping the drop target visible.
The tray takes only its required width, with 4 px gaps and a 28 px return row.
Scrolling reserves complete icon rows above that control. Reward cards and item
description text retain their readable sizes. Empty targets and the return row
appear only during assignment; equipped badges remain visible afterward.

The current source passed 173 checks on isolated GPU Lab virtual displays,
submitted with automatic GPU scheduling and the X11/Dummy audio drivers:

| Evidence run | Language/window | Checks | GPU Lab job |
| --- | --- | ---: | --- |
| `compact-items-en-720` | English, 1280 × 720 | 28 | `521c519789d74a59` |
| `compact-items-de-720` | German, 1280 × 720 | 28 | `631f301894a349dc` |
| `compact-items-ru-720` | Russian, 1280 × 720 | 28 | `814b0a66707a4451` |
| `compact-items-de-1080` | German, 1920 × 1080 | 28 | `4706c1cb372047a9` |
| `compact-items-input-en` | English, 1280 × 720 | 61 | `b5008346bb494459` |

Visual review confirmed readable translated return controls, complete visible
item rows, smaller targets and badges, and clearance around HP and stars. The
61 interaction checks include native drags, returning to stash, swapping,
cancellation, keyboard navigation and combat inspection. All fixtures exited
successfully without captured UI errors. Startup diagnostics on the virtual
displays include the existing OpenGL antialiasing warning and a null-monitor
refresh-rate query from crash-report metadata, before the fixture begins.
Complete GPU job metadata and combined logs are retained beside each profile.

## Rendered interaction checks

`tools/tests/arena_equipment_ui.gd` ran against native game assets in Godot 4.7,
OpenGL compatibility rendering. All six runs passed without runtime errors.

| Language | Window | Checks | Evidence run |
| --- | --- | ---: | --- |
| English | 1280 × 720 | 61 | `equipment-tray-ui-en-720-final` |
| Russian | 1280 × 720 | 61 | `equipment-tray-ui-ru-720-final` |
| German | 1280 × 720 | 61 | `equipment-tray-ui-de-720-final` |
| English | 1920 × 1080 | 61 | `equipment-tray-ui-en-1080-final` |
| Russian | 1920 × 1080 | 61 | `equipment-tray-ui-ru-1080-final` |
| German | 1920 × 1080 | 61 | `equipment-tray-ui-de-1080-final` |

The 366 checks cover reward selection, physical press/move/release native drags,
click assignment, replacement conservation, reserve-to-field transfer, stash
drops, enemy rejection, Escape/right-click cancellation, deployment preservation,
keyboard assignment and restored focus order. They also cover target removal
during assignment, retained item control identity, focus scrolling, modal
isolation, a different-match scouting guard, combat locking, frozen equipment
badges, keyboard inspection and all six translated alliance explanations.
The scouting check changes the viewed match; it is not an online end-to-end test.

After the native artwork and reward framing refinement, `native-rewards-input-en`
reran all 61 interaction checks successfully. `native-rewards-localization`
passed 735 checks, including all eight short effect roles and complete item text.

Each run captures reward, drag and combat-tooltip views. EN/RU/DE captures were
visually reviewed for readable text, bounded layout and clear item ownership.
Viewport input events avoid late desktop mouse-warp events; failed actions are
not retried by the fixture.

Selected repository evidence: [item tray](autochess-equipment-alliances-2026-10-23/items-tray-en.png),
[reward cards](autochess-equipment-alliances-2026-10-23/items-rewards-en.png),
[drag targets](autochess-equipment-alliances-2026-10-23/items-drag-en.png),
[German detail](autochess-equipment-alliances-2026-10-23/items-tooltip-de.png), and
[Russian detail](autochess-equipment-alliances-2026-10-23/items-tooltip-ru.png).

## Final presentation checks

`tools/tests/arena_equipment_presentation.gd` separately exercises a two-creature
formation, one reserve and eight owned items. It captures the normal tray,
Ward Stone / Guardian Knot / Storm Shard reward cards, circular targets, an actual
native drag, the resulting equipped badge and the illustrated item tooltip.
The shield cards include the complete rule that shields do not stack. The final
checks also verify that each whole card and its Choose action are visible without
scrolling, rich text preserves the full translated effect, and the reward uses
the native PNG without an icon medallion.

| Evidence run | Checks |
| --- | ---: |
| `native-rewards-en-720-final` | 28 |
| `native-rewards-ru-720-final` | 28 |
| `native-rewards-de-720-final` | 28 |
| `native-rewards-en-1080-final` | 28 |
| `native-rewards-ru-1080-final` | 28 |
| `native-rewards-de-1080-final` | 28 |

All 168 checks passed without runtime errors. They include badge-rectangle
intersection checks against every visible HP/star marker. Visual review confirmed
the two-row inventory, translated return control, full reward descriptions and
uncovered health markers. The final captures use the revised item tray rather
than the superseded modal inventory.

The [native item manifest](../../game/assets/arena/items/manifest.json) records
original item IDs, source models, textures and camera orientation. The eight
images use original materials without repainting or recoloring. The art fixture
checks source dimensions, caller sizes and pointer transparency; its contact
sheet shows the pictures at 138 px reward size and 32/44 px inventory sizes.
`native-rewards-item-art-final` passed all 58 checks, including the requested
1280×720 viewport; the final sheet was visually inspected at those actual sizes.

## Native combat at both speeds

`tools/tests/arena_equipment_native_visual.gd` runs native AI, attacks, spells,
projectiles, equipment and alliances without injecting damage or effect events.
The seed-15877 fixture deploys the same six equipped creatures on each side.

| Evidence run | Mode | Checks | Simulation time | Measured battle wall time |
| --- | --- | ---: | ---: | ---: |
| `equipment-native-headless` | Headless reference | 13 | 27.665 s | 0.262 s |
| `equipment-native-en-1x` | English OpenGL, 1× | 20 | 27.665 s | 28.088 s |
| `equipment-native-de-2x` | German OpenGL, 2× | 20 | 27.665 s | 14.248 s |
| `equipment-native-de-2x-tray-final` | German OpenGL, final tray, 2× | 23 | 27.665 s | 14.271 s |

All original 53 checks passed without runtime errors. These three runs match
exactly on battle seed, winner, survivors, damage, simulation duration, effect
totals and every recorded native `arena_proc` event including its timestamp.
The player side wins with two survivors. Both rendered runs create two temporary
Spirit echoes and display live numeric HP for echoes and normal recruits.
Real Spell reaction, Spirit aid, Spirit echo and shield feedback are captured.
The measured simulation-to-wall ratios are 0.985 and 1.942 at 1× and 2×.

The final German 2× run after the tray redesign passed all 23 checks without
runtime errors. It explicitly opens the actual summoned echo's inspector and
asserts the localized heading “Geisterecho”, rather than its base prototype name.
Frozen equipment badges remain visible alongside native feedback and live HP.
The resulting seed, winner, survivors, damage, duration, effect totals and all
34 timestamped native effect events exactly match the headless reference.
The measured clock ratio is 1.939×. The fixture now populates result metadata,
so the finished capture correctly displays “Sieg”. This is a small deterministic
combat fixture, not a full expedition or multiplayer session.

## Evidence and scope

The earlier 450-check modal interaction matrix and synthetic feedback captures
remain in the task evidence as historical validation of the previous interface.
They do not describe the final interaction model. Synthetic `arena_proc` captures
validated localized notice placement only; the native runs above prove actual
combat triggering. Feedback reserves all visible HP/star rectangles and clears
when the battle finishes. Nine-board worker parity and backend ownership tests
are recorded separately by their owners.

All evidence is under the task directory
`local/scratchpad/autochess-equipment-alliances-20261023/runs/<run>/`.
Each run contains `run.log`, `exit-code.txt`, and PNGs under
`data/godot/app_userdata/Cursed Lands/`. Test profiles were isolated and set
`confine_mouse=0`, `show_fps=1`, and all three audio volumes to zero before launch.
Player preferences were not changed. The only renderer warning was the existing
unsupported screen-space antialiasing setting in OpenGL compatibility mode.
