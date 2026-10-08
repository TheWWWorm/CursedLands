# Experimental third-person controls

Choose **Options → Remake → Camera → Control mode**. **Auto (gamepad)** is the default: a gamepad uses the shoulder view, while keyboard/mouse and touch use the existing controls. **Classic** keeps the existing controls with every input device. **Third person (experimental)** enables the shoulder view for keyboard/mouse too.

| Input | Action |
| --- | --- |
| WASD | Move relative to the camera; selected companions follow |
| Shift while moving | Run, using the normal stamina and posture rules |
| Mouse | Turn and tilt the view |
| Left mouse button / RT | Swing or shoot in the aimed direction; hold to repeat after the weapon cooldown; cast a selected spell |
| E / A | Talk, loot, revive or use the object under the crosshair; confirm a nearby open area exit |
| Tab / R3 | Release the pointer for the HUD and existing point-and-click actions |
| Mouse wheel | Adjust shoulder distance |
| Right mouse button | Cancel spell targeting |
| Left / right stick | Move / look |
| LB / RB | Existing spell / item wheels |
| LT + RT | System wheel (RT by itself attacks in this mode) |

Visible living characters within the health-bar range keep their bars, including full-health allies and village characters. The view follows the drawn, interpolated hero position. Walls and floors shorten the camera arm using the current navigation geometry, including moving doors and floors. Dialogues and movies retain ownership of their cameras.

Each weapon swing is a committed animation. Contact is checked against nearby bodies in its arc at the impact time; turning away, being too far away, another floor or a solid obstruction prevents contact. Arrows travel straight and can miss a moving target. Geometric contact replaces the normal weapon hit/miss roll in this mode. Damage, armour, wounds, equipment wear and weapon spells still use the combat system. Spells retain their existing targeting and resource rules.

The controlled leader's idle combat AI is suspended until classic controls return or the player disconnects. This prevents an unrequested pursuit after a missed swing. Selected companions retain their own follow/combat behavior. Mode ownership is transient and does not change saved aggression preferences.

The host validates ownership, direction, cooldown and script blocks. The new commands use the existing area/load-generation fence. Free attacks and spell casts are allowed in villages in this mode, including against friendly characters. Authored camp walking limits, blocked characters, closed exits and scripted escape orders still apply. Movement held across a loading screen needs to be released before it can start in the new area.

Protocol **9** requires matching builds for co-op. These changes are local experimental checkpoints; no public release was made. The Linux export is `gameplay-gaps23`; private Retroid APK58 contains the same game code. Test autorun is disabled after validation.

[Validation receipts](gameplay-third-person-validation.json) cover 28 geometry/authority checks, 31 loaded-scene input/camera checks, 11 ENet checks and the existing 20-check LiA camp/escape regression. The 28 geometry checks and 31 loaded-scene checks also pass on Retroid Pocket 5. The device scene uses Original graphics at 1× and injected keyboard/gamepad events through the normal input path. English desktop and Russian Retroid screenshots were reviewed.

These are focused functional checks. Long combat/chapter playthroughs, dense-map shoulder-view performance, camera clearance around decorative geometry and Windows packaging/runtime still need coverage. Camera collision follows the navigation solids rather than exact decorative triangles. Full-map 60 FPS acceptance and the reported Windows 4K slowdown remain separate open work.
