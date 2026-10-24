# Attack preview, snow-only deformation and tutorial scaling

This follows the [complete issue review](../issues-109-112-2026-10-24/issue-review.md)
and [load-crash/cursor investigation](../load-crashes-cursor-2026-10-25/README.md).
The broader follow-up is in the [regression audit](../regression-audit-2026-10-25/README.md).

## Why the attack-path fix was still incomplete

The original living-target attack preview obtains the target's current position,
then builds a separate path to that position. The remake's paused preview already
did this, but its live attack branch passed the predicted interception point to
`motion_notice`. The path shown to the player could therefore end well ahead of a
running батрак, even though pursuit itself should remain predictive.

Two distinct historical changes explain the reports:

- `862032c97832904936351486ff42b53ed616f8c3` (October 5) moved the live preview
  from `OrderMarks` to the authority path, where the interception point became
  its endpoint. This introduced the current-position preview mismatch.
- `3de46557d79131e57b0581a3f4588112e27f0b9e` (October 23, 1.25.0) corrected the
  closing-speed sign from adding the target's projected velocity to subtracting
  it. That pursuit correction remains present. It did not correct the preview,
  despite [#85](https://github.com/TheWWWorm/CursedLands/issues/85) being closed
  as fixed in 1.25.0. The recent fix was incomplete; it was not later removed.

The older hidden-creature placement repair (`162f666e47b099f141b17c60dc36210fbe546c7d`,
October 4) also remains. A visibility-restoration assertion explicitly protects it.

`GameUnit._do_attack` now consumes `path_notice` through the same independent
`preview_order_path` used for paused orders, after choosing a valid target and
before the approach/height-wait branches. Actual pursuit still uses prediction.
The preview does not mutate the actor's navigation route or the target's motion.

## Original-code evidence

REA/Ghidra inspection of the unchanged English GOG 1.06 executable shows:

1. `0x54e600` reads the command's target pointer; `0x54e688` calls its position
   getter at vtable offset `0xd4`.
2. The living-unit getter `0x52fdf0` returns the current position at offset `0x1c`.
3. The helper `0x54df50` does not substitute a predicted position for attack type 3.
4. `0x54e877` passes that position to the fresh pathfinder `0x5bb350`; later the
   path message uses the same position through `0x66d450`.

[Disassembly](original/54e600.asm.txt), [decompiled preview](original/54e600.txt),
[helper](original/54df50.txt), and [message function](original/66d450.txt) are retained.
The [runnable native replay](../../../tools/parity/attack_preview_target.py) executes
the original bytes through the pathfinder call with three distinct target
positions and a deliberately different fallback position. All three forward the
current target position. [Results and executable hash](original/native-attack-preview.json).
Object records and constructor/path-container boundaries are supplied by the
harness; this is not a complete original moving-AI or Wine gameplay replay.
The earlier trap/corpse investigation separately includes actual Wine gameplay.

## Behavior checks

| Check | Result and scope |
|---|---|
| Attack preview, prior production PCK | 41 checks, **12 expected failures**: moving live/approaching/queued/revealed endpoints. Stationary and paused previews pass. |
| Attack preview, corrected production PCK | 41/41; the real zone-18 fearful peasant runs on a clear, dry corridor in the loaded base map. |
| Rendered attack preview | 42/42; the received event reaches the real particle buffer. [Capture](layout/running-peasant-path.png). Marker lifetime is held during capture; gameplay is not changed. |
| Existing campaign order/dialogue checks | 28/28; paused path, attack-move, gait and voice-queue controls. |
| Existing LiA visibility check | 72/72, including 24 blocked-eye samples. |
| Snow-only surface policy | 11/11, real zone-11 snow, zone-15 sand and packed-snow profile. |
| Existing deformation capacity/lifetime | 24/24, including native-worker completion and cache lifetime. |
| Snow mounds, OpenGL | 50/50, deformation, fading, restoration and rendered height. |
| Sand mounds, Vulkan production PCK | 31/31, no contact marks, rigid surface and identical pixels with a neighboring field cleared/installed on the same mesh. |
| Sand cover, OpenGL | 12/12, rigid ground-cover roots and rejected sand contacts. |
| Tutorial/HUD, OpenGL | 496/496; EN/RU/DE, mouse/controller, 800×600, 720p, 1080p, ultrawide, actual 3840×2160 captures, and portrait. |

[Logs and structured results](checks/) retain assertion detail. Production PCKs
and original executable hashes are in [provenance](provenance.json). Native parity
requires Unicorn and the owned original executable; no original binaries are included.

## Sand and UI details

Sand type 3 no longer enters `SoftGroundDeform`, and both raster and ray-traced
ground profiles give it zero deformation. Snow types 9/12 retain their behavior.
The mound shader checks the local terrain profile before applying a neighboring
track field, so a snow field cannot compress adjacent sand. Static desert mounds,
vegetation, and the original footprint/blood decals are retained.

The first sand fixture still expected the old deformable-sand profile. Its oracle
was updated independently to the requested rigid surface. A whole-frame comparison
also included different tessellation meshes and reported tiny lighting differences;
the accepted check compares the same installed mesh with only the deformation field
changed and separately verifies rendered surface height. A headless cover attempt
was rejected by its renderer requirement and rerun graphically.

Tutorials retain the 28-pixel desktop book and 16-pixel header icon at base scale.
The book, card, header icon and spacing now follow `GameHUD.top_scale()` in landscape;
touch keeps its existing minimum target and portrait/camp keep their existing layouts.
[800×600 German](layout/hint-de-800x600.png), [4K Russian](layout/hint-ru-4k.png),
[4K German](layout/hint-de-4k.png), and [portrait controller](layout/hint-en-portrait-pad.png)
were inspected. Original item names follow the installed archive language; remake
text follows the selected language. The pre-existing portrait controller-strip
clipping is outside this tutorial change.

Graphical acceptance runs used GPU Lab auto selection and a muted, unconfined
isolated profile. These tests do not qualify every renderer, native Windows GPU
driver, Android device, or uninterrupted multiplayer campaign.
