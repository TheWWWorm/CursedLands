# Six outstanding issue fixes — 24 October 2026

Implemented changes for all six reports against public **1.26.0**
(`96aaeb782fb023b7d536ca415a7507892121495f`) in local branch
`fix/remaining-issues-20261024`, plus the requested auto-chess item-display change.
This supersedes the earlier investigation-only disposition. Nothing has been
published, and no GitHub issue has been closed or commented on.

## Changes

| Report | Implemented behavior | Evidence |
| --- | --- | --- |
| [#98 — fast becomes normal](https://github.com/TheWWWorm/CursedLands/issues/98) | Scale the bounded simulation delivery budget with game speed. Inline worlds cap elapsed wall time before applying speed; workers retain excess time and repay it with the scaled budget. Physics still uses 55 ms ticks. | The same slow-callback test fails **7 assertions before** and passes **8,279 afterward**. At 250 ms callbacks, fast/normal changes from **1.105× to 2.044×**; at 500 ms, the old ratio was exactly **1×**. [Before](clock-before.txt), [after](clock-after.txt). |
| [#96 — blood disappears on reload](https://github.com/TheWWWorm/CursedLands/issues/96) | Persist death-pool position, pigment, rotation, size and age; replay them for local loads and connected clients. Growth/fade continue from the saved age. Pools survive removal of the corpse and disappear naturally on expiry. Preserve the death clip too, so loading cannot select another pose and move the body away from the pool. Old saves remain readable. | Full kill/save/load, replay deduplication, stale events, removal, expiry and pose checks: **18 passed**. [Results](blood-pool-save.json), [before](blood-pool-before.png), [after](blood-pool-after.png). **10 separate-worker checks** cover reliable replay, the saved corpse clip and a second reload. [Worker results](worker-blood-pool-save.json). |
| [#95 — wolf ignores corpse](https://github.com/TheWWWorm/CursedLands/issues/95) | Keep a noticed allied corpse pending while combat or a stronger suspicion prevents investigation. The wolf subsequently approaches and looks around instead of permanently consuming the discovery. Investigate one pending body at a time. | Authored wolf 3327/3326, including stronger-alert recovery; ordinary approach/look behavior also passes. [Combined regression](pack-after.txt), [original approach trace](authored-wolf-corpse.json). |
| [#94 — packmates ignore detection](https://github.com/TheWWWorm/CursedLands/issues/94) | A nearby ally receives the identified hostile as well as the warning point. Ongoing combat warns allies that enter range after the first detection. Preserve authored help radii and the 26-tick delay. Unidentified noise conveys only a point; a warning does not make neutral listeners hostile. | A listener facing away acquires the enemy and issues an attack. A distant listener stays unaware. Combined corpse/pack/stealth fixture: **14 passed**, versus **6 failures** on unchanged 1.26.0. [Before](pack-before.txt), [after](pack-after.txt). |
| [#89 — pause-menu flash](https://github.com/TheWWWorm/CursedLands/issues/89) | Unbind the previous viewport image while hidden/opening, reset the initial pose, then bind after the existing render barrier. An ancestor resetting opacity can no longer expose a stale fully-open menu. Ignore pointer input while the opening is pending. | **25 checks each** on Vulkan and OpenGL, including normal/fast/paused clocks and partial reopenings. **Ten openings over a running game** showed no settled-frame/reset flash. [Vulkan](pause-clock-vulkan.json), [OpenGL](pause-clock-gl.json), [in-game](pause-menu-ingame.txt). |
| [#29 — footprints under terrain](https://github.com/TheWWWorm/CursedLands/issues/29) | Campaign marks now use pigment geometry clipped to the actual terrain and receiving floor triangles, with a small surface offset. This follows soft-ground deformation and avoids relying on projected decal depth while the camera moves. It also fixes the confirmed complete absence of campaign decals in OpenGL. Arena keeps its existing snow-ink path. | Moving-camera Vulkan sweep: **687 passed**. Running trails at 1×/2×: **15 passed per renderer**, 93 marks each. Slopes, bridges, options, fade, blood/scorch and cleanup: **13 passed per renderer**. [Vulkan running](running-vulkan.json), [OpenGL running](running-footprints.json), [camera sweep](footprints-vulkan.json), [running image](running-vulkan.png). |

The pack work also fixes a stealth edge case: `seen_murder` used to let the
victim perform perception before its dead flag was set, potentially warning
nearby allies about its own unseen lethal hit. The victim and already-dead
observers are now excluded. The authored bridge-goblin regression, visible
murder, surviving attacks and neutral-witness hostility all pass: **20 checks**
in [creature-alerts.txt](creature-alerts.txt).

## Auto-chess item display

The item tray, deployed-unit item targets/badges and reserve item badges are
hidden throughout combat, including tactical pause, and restored during
preparation. Hidden items cannot receive focus or drops. The damage panel uses
the space released by the hidden tray. Equipment remains assigned and unchanged.

The actual reward/equipment UI fixture passed **89 checks in each language**:
[English, 1280×720](autochess-en.txt), [Russian, 1280×720](autochess-ru.txt), and
[German, 1024×768](autochess-de.txt): **267 total**.

## Original comparison and limits

The original comparison used owned English GOG Evil Islands 1.06, SHA-256
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`, with a copied
Wine prefix and separate saves. Ghidra 12.1.4 inspected perception acquisition
`0x005ca5a0`, retained perception `0x005caa00`, help `0x005d5990` and suspicion
`0x005cbbe0`. [Evidence provenance](original-ai-evidence.json) and the
[earlier runtime comparisons](../outstanding-issues-2026-10-23/README.md) remain available.

Original help is local and delayed, and original corpse detection creates
suspicion. Those constraints remain. Passing enemy identity in a warning and
preserving deferred corpse investigations strengthen the remake's response;
these changes are not claimed to reproduce every original AI instruction.
Original blood marks were transient across reloads. Persisting death pools is
an intentional improvement requested here, rather than an original-parity claim.

The exact historical running-only #29 clip and intermittent #89 Linux flash
were not reproduced on the tested current build. Both now have direct rendering
changes and targeted regression coverage; this is not a claim of testing every
GPU/driver combination. The speed fix removes a software cap; it cannot create
CPU capacity when the simulation itself exceeds the available processing time.
Old saves cannot recover blood-pool recipes that were never stored.

## Additional validation

- Supplied #98 save through a real separate authority: **15 passed**. Direct
  resume measured **2.033×** simulation/wall time; later fast samples measured
  approximately **2.045–2.063×**. Normal samples were **0.997–1.016×**.
  These checks reduce graphics load and vary the owner callback rate; the
  separate slow-callback regression above exercises the limiting code itself.
  [Measurements](saved-fast-clock-final.json).
- Native/script perception adapter: **2,857 passed**; script perception:
  **7 passed**. [Adapter](perception.txt), [script API](script-perception.txt).
- Quiet/paused spawn and corpse presentation: **42 passed**. [Log](paused-pose.txt).
- Live soft-ground displacement and disabling it: **3 passed** on Vulkan.
  [Log](soft-vulkan.txt). Earlier OpenGL coverage also passed.
- Existing Arena snow ink: **5 passed**, including twenty simultaneous blood
  marks and visibility. [Log](arena-gl.txt).
- EN/RU/DE translation coverage: **0 errors**; no player-visible text was added.
- `git diff --check`: passed.

All graphical tests used GPU Lab with automatic GPU assignment. Test profiles
were isolated, the cursor stayed free, FPS remained visible, and SFX/music/voice
were muted. Source runs used Godot 4.7 with the repository's native extensions
on Linux and RTX 3090/3090 Ti. Accepted runs contain no script or shader errors;
the virtual display's existing null-monitor refresh-query diagnostic is unrelated.
Windows, browser and Android qualification are not claimed.

Reusable fixtures live in `tools/tests/`: `worker_clock.gd`,
`pack_alert_recovery.gd`, `blood_pool_save.gd`, `worker_blood_pool_save.gd`,
`ground_mark_receivers.gd`, `ground_mark_soft_surface.gd`,
`authored_wolf_corpse.gd`, `local_host_resume_rate.gd`,
`pause_menu_clock.gd`, `pause_menu_ingame_frames.gd` and `arena_equipment_ui.gd`.
They use the usual `--tool=/absolute/path/to/test.gd` launch path. The worker
blood test takes `--resume-save=` pointing to the save generated by the blood
fixture; the speed fixture takes the reporter's paused/fast save.

Full logs, videos, original evidence and isolated profiles remain outside the
repository in `/home/llm2x/Documents/EI/local/scratchpad/remaining-issues-20261024`.
`artifact-hashes.json` records the retained report artifacts; `source-hashes.json`
records the changed source and fixtures at validation time.
