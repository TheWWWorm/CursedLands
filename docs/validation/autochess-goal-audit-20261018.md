# Autochess goal audit — 2026-10-18

The second unpublished preview contains forty recruit families and the completed
follow-up fixes. The detailed [validation report](autochess-preview2-20261018.md)
records source, binaries, commands, frame times and remaining platform limits.

| Requirement | Evidence | Result |
| --- | --- | --- |
| Clear menu and HUD fonts | Scaled text renders in EN/RU/DE | Passed for scalable labels; original stone-sign lettering remains source artwork. |
| Smooth Q/E and right-drag at either speed | Camera: 21 checks | Passed, including focus and pointer-coordinate behavior. |
| Tribe icons and original cursor | Feedback UI: 64 checks; all added families rendered in three languages | Passed. |
| Persistent global multiplayer name | Profile persistence/reload checks in first-preview evidence | Passed; settings entry and reuse retained. |
| 60+ FPS at 2× through later rounds, overview, scouting and hosting | Final six-case frame-time suite | Main-resolution Ultra cases pass; lowest rolling second is 62.35 FPS. Additional 4K stress remains below 60. Windows/4090-laptop FPS is unmeasured. |
| Remove multi-second transition freezes and recurring bursts | Round entry/advance traces, exact health and phase scheduling | No multi-second blocked frame in the measured transitions. Staged preparation, isolated short frame spikes and cold stress-setup hitches remain documented. |
| More recruitment variety at every tier | 40 families, tier counts 7/9/10/8/6 | Sixteen additions include humans, zombies and upper-tier choices. |
| Stronger CPU, interest and distinct strategies | Four paired legacy games and four self-play games | New planner wins all four legacy comparisons; four spending profiles exhibit different banking/evolution behavior. |
| Balance after additions | 5,056 native fights plus complete tournaments | Prices, copy counts, evolved spells and recruit-only armor adjusted; no claim of perfect human-play balance. |
| All visible additions in EN/RU/DE | Translation audit and rendered roster checks | 2,687 entries, 141 dynamic wiki keys and 161 dynamic arena keys; zero coverage errors. |
| No combat resource accumulation | Three lifecycle cycles, frame-time retirement census | All tracked old worlds/creatures released; environments intentionally reused. |

The [reference roster](https://www.trackautochess.com/units) informed the goal of
providing meaningful choices throughout all five tiers. This implementation uses
native Cursed Lands models, attacks and spells, with logical tribe connections
for cross-kin evolution. The Windows preview is cross-compiled and unpublished;
the original preview, stable tags and published artifacts remain unchanged.
