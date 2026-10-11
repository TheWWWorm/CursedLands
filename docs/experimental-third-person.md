# Experimental third-person controls

Choose **Options → Remake → Camera → Control mode**. **Auto (gamepad)** is the default: a gamepad uses the shoulder view, while keyboard/mouse and touch use the existing controls. **Classic** keeps the existing controls with every input device. **Third person (experimental)** enables the shoulder view for keyboard/mouse too.

| Input | Action |
| --- | --- |
| WASD | Move relative to the camera; selected companions follow |
| Shift while moving | Run, using the normal stamina and posture rules |
| Mouse | Turn and tilt the view |
| Left mouse button / RT | Swing or shoot in the aimed direction; hold to repeat after the weapon cooldown; cast a selected spell |
| E / A | Talk, loot, revive or use the object under the crosshair; pick up nearby loot without exact aiming; confirm a nearby open area exit. A also confirms the selected spell target. |
| Tab / R3 | Release the pointer for the HUD and existing point-and-click actions |
| Mouse wheel | Adjust shoulder distance |
| Right mouse button | Cancel spell targeting |
| Left / right stick | Move / look |
| LB / RB | Spell / item wheels; previous / next page while open |
| X with a heal/buff selected | Cast on yourself, without changing selection |
| D-pad left / right with a spell selected | Cycle valid targets, including your co-op partner |
| X on an enemy | Open the six-part aimed-strike wheel; stick or D-pad selects, A confirms |
| LT + RT | System wheel (RT by itself attacks in this mode) |

Visible living characters within the health-bar range keep their bars, including full-health allies and village characters. The view follows the drawn, interpolated hero position. Walls and floors shorten the camera arm using the current navigation geometry, including moving doors and floors. Dialogues and movies retain ownership of their cameras.

Movement follows held input directly on the authority, without choosing a route around obstacles. Releasing input stops at the authority position. Diagonal input can slide along a wall; actors, slopes, stance clearance and village boundaries still block movement. Stick tilt controls speed within the selected gait. Interaction takes priority until held movement is released.

Each weapon swing is a committed animation. The hero stays ready between repeated swings and relaxes after attack recovery, or when walking away. Contact is checked against nearby bodies in its arc at the impact time; turning away, being too far away, another floor or a solid obstruction prevents contact. Arrows travel straight and can miss a moving target. Geometric contact replaces the normal weapon hit/miss roll in this mode. Damage, armour, wounds, equipment wear and weapon spells still use the combat system. Spells retain their existing targeting and resource rules.

The controlled leader's idle combat AI is suspended until classic controls return or the player disconnects. This prevents an unrequested pursuit after a missed swing. Selected companions retain their own follow/combat behavior. Mode ownership is transient and does not change saved aggression preferences.

The host validates ownership, direction, cooldown and script blocks. The new commands use the existing area/load-generation fence. Safe zones reject direct attacks and spell casts at both input and host authority. Free attacks can still hit friendly characters outside safe zones. Authored camp walking limits, blocked characters, closed exits and scripted escape orders still apply. Movement held across a loading screen needs to be released before it can start in the new area.

Experimental 6 shipped these controls with protocol **11**, but a Camera key-binding row overwrote the control-mode selector. The local follow-up moves the selector to its own row. 1.0.4 Experimental 1 uses protocol **14**, including mod/profile matching; peers need matching builds. The selector and safe-zone changes were included in 1.0.3.

[Follow-up validation](gameplay-controls-followup-validation.json) records the reproduced hidden selector in the published package, ten passing rendered settings checks, and 108 passing input, authority, real ENet and camp-escape checks. The earlier device validation below predates this follow-up.

[Initial validation receipts](gameplay-third-person-validation.json) cover 28 geometry/authority checks, 31 loaded-scene input/camera checks, 11 ENet checks and the existing 20-check LiA camp/escape regression. The 28 geometry checks and 31 loaded-scene checks also pass on Retroid Pocket 5. The device scene uses Original graphics at 1× and injected keyboard/gamepad events through the normal input path. English desktop and Russian Retroid screenshots were reviewed.

The [1.0.4 Experimental 1 validation record](validation/experimental-1.0.4-2026-10-11.json) adds direct steering, normal run posture/stamina, collision and pickup checks on Linux and Retroid, plus attack recovery and real ENet command checks. Keyboard/gamepad events are injected through the normal input handlers.

These are focused functional checks. Long combat/chapter playthroughs, dense-map shoulder-view performance, camera clearance around decorative geometry and Windows runtime still need coverage. Camera collision follows the navigation solids rather than exact decorative triangles. Full-map 60 FPS and Windows 4K performance remain unqualified.

The 9 October controller follow-up defaults healing and buffs to self, keeps a selected ally when the shoulder camera moves, and lets A/RT use that target. Enemy body-part choices have six equal sectors with labels; the D-pad cycles them precisely, and slight stick jitter does not change the chosen sector. A stick already held while opening a wheel must return to neutral before selecting. Invalid learned spells remain equipped but grey out and cannot cast until their training/stamina requirements are restored. Item and scripted magic retain their existing rules. See [focused validation](gameplay-network-pad-spells-validation.json). These changes are included in 1.0.3.
