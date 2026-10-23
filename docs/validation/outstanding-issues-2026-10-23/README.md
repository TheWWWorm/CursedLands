# Outstanding issues and Autochess fixes — 2026-10-23–24

This pass investigated the 17 open reports in the [public tracker](https://github.com/TheWWWorm/CursedLands/issues), including #99–102 added during testing, and implemented the requested shader-screen, menu-return and Autochess changes. The table below distinguishes implemented fixes from original-game parity and reports that remain unreproduced. No release was published and no GitHub comments or status changes were made.

The checkout started at `993a9d70`; its game code matched published v1.25.0 (`c407614ff27f104d3413f643411419cb46aedb28`). Tests used isolated profiles with a free cursor, FPS visible, and SFX, music and voices muted. Rendered tests ran through GPU Lab with automatic GPU assignment. Original assets, executable and saves remain outside this repository.

## White Wolf / issue #94

**The tested pack-alert behaviour agrees with the original. These results do not support changing the encounter to unconditional whole-pack aggression.** The original also leaves wolves uninvolved when their own perception and local alert conditions have not been met.

The original was the English GOG Evil Islands 1.06 executable, SHA-256 `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`, run through Wine on an isolated GPU Lab display. The encounter was the authored White Wolf pack in `gz3g`: White Wolf 3325, grey wolves 3326–3329. Quest flag `q.gz3g.q1g=1` was applied in both games, removing the extra quest wolf 4741. The leader was a fresh, crawling, defensive Zak; the original native `GodMode(0,1)` protected him while leaving enemy perception and attacks active. Time of day was fixed at noon. Console queries recorded native positions, HP and `UnitSee`; actual attack input was issued through the original UI.

| Scenario | Original observation | Remake observation and scope |
| --- | --- | --- |
| Approach from the left, Zak `(44,235)`, no player attack | Three grey wolves converged; right-hand guard and White Wolf stayed put. All wolves retained their starting HP. | Same-coordinate source run drew three greys. A packaged run with different roaming patrol positions drew two. This is not a matched patrol-state comparison. |
| Closer right approach, Zak `(52,237)` | All four greys detected and engaged Zak. White Wolf stayed at `(44.75,251.25)`, 50 HP. | Published v1.25.0, with grey-wolf starting positions matched to the original capture: all four greys attacked, White Wolf stayed calm. Native query and perception extensions were active. |
| Attack the left wolf from `(44,235)` | The attacked wolf died and the other three greys converged and attacked. White Wolf stayed at its post, 50 HP. | Source runtime with starting positions matched to the original attack capture: attacked wolf died; all other greys attacked; White Wolf remained calm. This comparison used CPU simulation with the native query/perception extensions, not another rendered packaged run. |

Patrol movement, random choices and attack timing prevent a claim of frame-for-frame equivalence. The original attack observation ran for approximately 100 seconds, versus 88 seconds of simulated time in the remake. The matched tests establish the relevant engagement outcome, not every possible save state or the exact timing of the reporter's video.

Evidence: [original detection](original-detection.png), [original attack](original-attack.png), the six `original-*.txt` native query captures, [matched remake observations](wolf-comparison.json), and [native help-call inspection](original-help-evidence.json). Full traces and runnable encounter fixtures are retained at `/home/llm2x/Documents/EI/local/scratchpad/outstanding-issues-20261023`.

## Shader progress and return to menu

The previous FSR preparation key included the temporary frame-generation gate and camera instance. Menus/tutorials toggle the gate; loads replace the camera. Those transitions started fresh progress owners even when native preparation finished immediately. Repeated messages therefore did not establish that shader caches were being lost.

The key now tracks requested FSR configuration and viewport size. Actual SDK initialization flags and advancing native evaluation/dispatch counters still control readiness. Standalone FSR preparation waits 500 ms before requesting a cover; it joins existing preparation immediately. The shared shader screen itself now waits 500 ms before drawing, so all producers, including non-FSR paths, suppress short work. Finishing an unseen owner never flashes its completion screen. Input and readiness gates remain active while preparation is pending.

Autochess checks the warmed material variants before creating progress. A cached Start Fight performs its readiness check without creating a progress owner. New materials still receive the real Vulkan warm-up. Gameplay, opening animation and bell remain gated until preparation finishes.

Returning to the main menu retains the last presented frame through teardown and menu construction, then removes the cover after the new menu draws. **The exact reported one-second grey screen was not independently reproduced.** The final separate-worker return test observed four covered frames and zero uncovered camera-less frames.

The actual FSR comparison used the published Windows executable and AMD runtime DLLs in a separate candidate package, Wine 9 / VKD3D-Proton, D3D12 on RTX 3090, 1280×720 at 30 rendered FPS. SR reported **3.1.5**, FG **3.1.6**. It does not qualify native Windows, FSR 4 or Radeon hardware.

| Transition | Published v1.25.0 | Final shader candidate |
| --- | --- | --- |
| Each of three menu opens and closes | 5 frames with an active shader screen | 0 |
| Each of three tutorial opens and closes | 5 frames with an active shader screen | 0 |
| Save / settled reload | 0 / 0 | 0 / 0 |
| Actual reload preparation | 3 finishing preparation frames | 3 finishing preparation frames |
| Return to menu | FSR cover, then menu | Retained campaign image, then menu |

The real-SDK fixture counts active preparation owners at presentation, including the final implementation's invisible short owners; the three reload frames are not a claim that three shader-message frames were visible. Native FG dispatches advanced after every resume and SDK status reported no error. The non-FSR test separately checks displayed frames during three menu/tutorial open/close cycles and observed none. Loading pictures for real loads remain expected.

Evidence: [baseline](fsr-before.json), [final real-SDK run](fsr-final.json), [fixture](fsr_transitions.gd), [shared shader UI](shader-ui-final.json), [Autochess warm-up](shader-arena-final.json), [menu return](menu-return-final.json). The earlier `fsr-after.json`, `shader-ui.json` and `menu-return.json` retain intermediate results and are superseded by the final files.

## Autochess presentation

- Mouse reward selection opens without assigning keyboard focus. Every card can be hovered and clicked. Keyboard/controller navigation establishes focus when used; returning to mouse input clears reward focus. The controller key bridge now preserves the keyboard device ID required by Godot UI actions while keeping controller input mode active.
- The simulation starts at 14:00, matching the daytime field lighting.
- Item activation no longer writes an effect name above the creature. Existing particles, shields, summoned echoes and damage/healing numbers remain.
- “Choose item” / “Выбрать предмет” has no trailing arrow.
- Middle-button dragging turns and tilts the camera, matching right-button dragging; Shift-middle still pans. Help text was updated in EN/RU/DE.

The rendered reward and equipment flows cover mouse hovering/clicking, keyboard selection, drag/drop, equipping, cancellation and battle locking. EN/RU/DE layouts were checked at 1280×720; the localization fixture checks all item definitions. Native combat still produced guardian, ward, echo and other item effects without floating effect-name labels. [Russian rewards](autochess-rewards-ru.png), [German rewards](autochess-rewards-de.png), [combat effects](autochess-item-effects.png).

## Tracker results

| Issue | Result in this checkout | Evidence and limits |
| --- | --- | --- |
| [#102 — shop filter resets](https://github.com/TheWWWorm/CursedLands/issues/102) | Fixed. A manually selected bag tab survives page changes. Item and spell goods keep separate tabs/scroll positions. A fresh inventory opening retains its normal initial defaults. | 116 rendered camp UI checks, including constructor/trade/dressing round trips and physical Shift-click. |
| [#101 — transfer sound](https://github.com/TheWWWorm/CursedLands/issues/101) | Fixed. Moving goods into a trade pile plays `put_on`; returning them plays `put_off`, once per successful transfer. Invalid requests retain cancellation feedback. | Camp UI and campaign regression fixtures. Audio is verified through requests, mixer state and routing because test profiles remain muted. |
| [#100 — full-stack transfer](https://github.com/TheWWWorm/CursedLands/issues/100) | Implemented Shift-click in both directions. Ordinary clicks and held repeats remain single-item actions. | Native handler inspection confirms Shift (scan codes 0x2a/0x36), not an assumed modifier. Tests cover stock, quest items, pending trades, distinct wear/charge states, the combined 4096-item cap and stack return. [Native evidence](original-shop-handlers.json). |
| [#99 — sounds in shop](https://github.com/TheWWWorm/CursedLands/issues/99) | Fixed. Shop pages suppress world SFX and speech while retaining music and UI sounds. Already-playing one-shots stop; loops are retained for returning to the world. | Real mixer checks cover existing loops, rejected new world sounds, UI allocation, loops started in the shop and restoration. Companion chatter is also suppressed at its queue source. |
| [#98 — fast equals normal](https://github.com/TheWWWorm/CursedLands/issues/98) | Not reproduced using the supplied save/profile. | Separate authority measured **0.936× normal, 2.030× fast, 1.015× normal**, with pause stopping its clock; 9 checks passed. Graphics were reduced for clock measurement, so performance saturation on the reporter's machine remains possible. [Result](issue98-worker-clock.json). |
| [#97 — White Wolf item translation](https://github.com/TheWWWorm/CursedLands/issues/97) | Fixed by routing dialogue item names through canonical `Items.title`. | Actual original archives now return **White wolf's head**, **Голова белого волка**, **Kopf des weißen Wolfs**. The final fixture clears the text cache between archives and compares against each archive's raw entry. [Result](campaign-ui-final.json). |
| [#96 — blood disappears on reload](https://github.com/TheWWWorm/CursedLands/issues/96) | Confirmed original behavior; no persistence change made. | In original GOG 1.06 near White Wolf, native `KillUnit(GetObject(3326))` produced a visible ground pool. F5 save / F9 reload removed the pool while body/wound coloration remained. This check used a console-triggered death, not an ordinary combat kill. [Before](original-blood-before.png), [after](original-blood-after.png). |
| [#95 — ignoring a corpse](https://github.com/TheWWWorm/CursedLands/issues/95) | Not reproduced in the authored pack's basic corpse-reaction case. | An observer 1.75 m away noticed the killed pack member, acquired suspicion 800, approached and looked around. Native query/perception were active. This is not an original comparison of the reporter's exact state. [Result](issue95-corpse.json). |
| [#94 — pack aggression](https://github.com/TheWWWorm/CursedLands/issues/94) | Tested remake outcomes match the original near White Wolf; no whole-pack alert change made. | Matched approach and attack comparisons above. Patrol state and timing still matter. |
| [#93 — overlapping acknowledgements](https://github.com/TheWWWorm/CursedLands/issues/93) | Fixed. Replacing a voice stops its active mixer handle. Cast acceptance comes from the authority after the stamina check; rejection no longer overlaps optimistic acceptance. | Normal and crouched acknowledgements tested; semantic order identity survives the quiet-voice remap. [Initial reproduction](issue93-acks.json), [final checks](campaign-ui-final.json). |
| [#92 — dialogue during pause/fast speed](https://github.com/TheWWWorm/CursedLands/issues/92) | Fixed. Dialogue begins at normal speed and releases tactical pause. The host owns shared-clock changes. Manual camp pause remains available. | SP authority/save/reload plus real two-peer ENet tests: guests cannot override the clock; host dialogue resets both peers. |
| [#91 — vertical middle-button orbit](https://github.com/TheWWWorm/CursedLands/issues/91) | Implemented. Middle drag turns and tilts like right drag, in campaign and Autochess. Shift-middle pans. | Rendered input checks and translated camera help. |
| [#90 — changing campaign difficulty](https://github.com/TheWWWorm/CursedLands/issues/90) | Implemented as a live single-player rule with save/reload persistence. Network games retain Normal difficulty. | The current combat multiplier changes immediately; separate-worker persistence and mod-profile regression checks pass. The network restriction has EN/RU/DE text. |
| [#89 — Linux pause-menu flash](https://github.com/TheWWWorm/CursedLands/issues/89) | Not reproduced. Kept separate from the confirmed FSR progress flash. | Five source scenarios, ten menu reopenings and a cold published-Linux opening were checked. Cold first-frame peak/steady brightness was about 1.02. No claim that the FSR fix resolves this Linux report. |
| [#62 — game speed / pause effects](https://github.com/TheWWWorm/CursedLands/issues/62) | Fixed remaining pause behavior: world weather/audio clocks stop with simulation; order indicators expire on their own real-time clock. | Tests at normal/fast speed verify visible indicators expire while world particles/weather remain paused. Earlier movement-rate fix was already acknowledged by the reporter. |
| [#61 — village camera](https://github.com/TheWWWorm/CursedLands/issues/61) | Fixed. Entry/shop exit centre on the hero and respect follow. The option resets the angle; off retains the chosen angle after initialization. Saved camera poses remain usable. | 68 rendered checks across both camera styles, reset/follow combinations, entry, shop exit and saved poses. |
| [#29 — footprints under terrain](https://github.com/TheWWWorm/CursedLands/issues/29) | Not reproduced on the current implementation; no decal-placement change made. | Authored running footfalls on original village terrain with enhanced surface options: 93 generated marks, 15 checks passed at normal/fast simulation speeds with moving camera. Unoccluded nonfading marks remained visible. This covers dry village soil, not every slope/material in the old 1.16 report. [Result](footprints-current.json), [capture](footprints-current.png). |

## Validation

Final fixture verdicts and full local log locations are in [final-checks.json](final-checks.json). The main groups are:

| Fixture | Passed checks |
| --- | ---: |
| Shared shader screen, readiness/input contracts, EN/RU/DE at 640×480 and 1280×720 | 380 |
| Autochess real Vulkan shader preparation and cached Start Fight, FSR off | 27 |
| Actual Windows FSR SDK through Wine/D3D12 | 64 |
| Separate-worker load, menu/tutorial cycles without FSR, return to menu | 29 |
| Campaign fixes, real mixer behavior and original localized archives | 45 |
| Shop UI, filters, transfers, held input and transaction settlement | 116 |
| Village camera transitions | 68 |
| Separate-worker live difficulty and dialogue clock persistence | 28 |
| Two-peer co-op dialogue clocks | 12 |
| Autochess item localization | 714 |
| Autochess native combat effects | 23 |
| Autochess rendered English UI, including actual D-pad and A-button events | 74 |
| Autochess rendered Russian / German UI flows | 69 / 68 |
| Mod-profile regression | 87 |
| Audio channel routing (60,000 reuses across SFX, speech and UI) | 2 |
| Current running footprints | 15 |

The GPU Lab X11 tests emitted the known virtual-monitor refresh-rate diagnostic. Stock Godot 4.7 also emits the existing TexUpscale push-constant diagnostic in enhanced scenes; the project's release engine does not. No new GDScript errors are accepted as successful validation. The shared shader fixture injects SDK status for contract checks; only the separately identified Windows run qualifies real SDK behavior. Audio tests assert mixer behavior without making the isolated test profiles audible.

The [latest issue snapshot](issues-snapshot-latest.json) records the 17 open reports. The earlier snapshot and reproduction JSONs remain as evidence of the original failures. `git diff --check` passed. All changes are local and unpublished.
