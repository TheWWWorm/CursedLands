# Portal single-player checkpoint — 8 October 2026

Ordinary single-player Portal on Retroid improves from **11.83 to 43.95 FPS
median** across three matched 60-second controls and candidates. Both modes
use the same APK, actual Original graphics and 1×. A three-minute walk averages
**44.65 FPS**, advances 179.85 simulated seconds and keeps both party members
alive. **Stable 60 FPS is not achieved.** This is an unpublished local checkpoint
on top of `866e9c5`; the public Experimental 5 build remains unchanged.

## Why this change matters

The existing separate simulation process served co-op hosting only. Ordinary
single player still performed simulation and presentation in the same frame
loop. Campaign creation and loading now start a private worker on supported
desktop and Android builds. Separating the two allows rendering to benefit from
the previous hidden-replica scheduling work while every actor remains simulated.
This is a measured complete-gameplay improvement, not a faster isolated kernel.
No engine or native module changes are included.

`Session.online` continues to describe transport. `Session.multiplayer_game`
selects gameplay rules and UI, so using a local connection preserves offline
difficulty, XP, story branches, death/travel rules, optional fog and selection.
Menus, dialogs, tutorials and controller pauses use the single-player clock;
the original accelerated rate remains 55/27. The owner retains save/load access.
The worker binds ENet to loopback on an ephemeral port, independently of the
multiplayer transport preference. It does not use LAN advertising, directory
registration or UPnP. Unsupported platforms and startup failures retain inline
simulation; cancelled startup does not start an unwanted campaign.

Worker readiness is published atomically with the actual port. On Android the
worker saves authoritative single-player state when the application pauses.
The Home test exposed that the frontend's asynchronous autosave could otherwise
remain queued until reopening the app. The final test verifies a fresh save on
disk while both processes are still backgrounded, then successful resumption.

## Repeatable measurements

The fixture walks a loop near Portal entrance 3 with normal commands and a
terrain-aware rotating gameplay camera. All 415 actors remain active; neither
mode changes health or disables AI. Both controlled actors remain alive at
every recorded census. Actual Original look disables every remake graphics
switch. Settings are 1920×1080 viewport, 75% render scale, OpenGL ES on Adreno
650, four worker threads, Distant AI off, exact 1× and difficulty 0. The full
options hash matches in all six runs. Profiling is disabled. These settings
are distinct from the user's Windows 4K/max configuration.

| Run | Inline FPS | Worker FPS | Inline p95 ms | Worker p95 ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 11.73 | 43.95 | 113.194 | 29.416 |
| 2 | 11.83 | 42.30 | 113.266 | 31.456 |
| 3 | 12.30 | 45.10 | 110.706 | 29.685 |

Median gain is **3.72×**. Simulation advances 59.565–59.675 seconds inline and
59.785–59.895 seconds with the worker per 60 wall seconds. The third pair runs
in reverse order. Battery temperature spans 32.2–35.0°C; raw receipts retain
the readings. Screenshots show the same Original scene, party and HUD; moving
animation poses preclude a pixel-equality claim.

The 180-second worker run has p50/p95/p99 frame times of 21.151/30.098/32.846 ms
and a worst frame of 90.791 ms. Ten-second windows range from 42.3 to 48.6 FPS.
This is living-party exploration coverage, separate from the earlier close
combat fixture whose later frames included a death view.

The matched series and long run use private APK40. APK41 adds atomic readiness;
APK42 adds the Android background-save correction. The final APK42 gameplay
smoke run averages **43.56 FPS**, advances 59.895 simulated seconds and keeps
both characters alive; p95 is 29.886 ms and the worst frame is 96.289 ms.
Source snapshots and exact artifact hashes are recorded in the
[validation record](portal-single-player-validation.json). Engine and module
hashes are identical throughout. Private APKs and benchmark fixtures are not
player release packages.

## Correctness coverage and limits

- Single-player rules: 52 checks each on stock Linux and physical Retroid.
- Ordinary rendered load, owner commands while paused, authoritative save and
  reload, selection, speed, menu pause and shutdown: 30 checks on each platform.
- New campaign, movie barrier, deferred save, replacement campaign and cancelled
  startup: 19 checks on stock Linux safe GL, packaged GL and packaged Forward+.
- Existing co-op owner/save/reload fixture: 33 checks on packaged Forward+;
  original multiplayer travel: 19; worker clock: 8,255; camp grants: 130.
- Final physical Home/resume lifecycle: 12 checks, 20.019 seconds backgrounded,
  0.275 simulated seconds elapsed around the transition, fresh autosave verified
  on disk before returning, then successful menu-close resume and worker exit.

An initial one-second post-reload resume check failed. Tracing confirmed clock
delivery followed by a slow first tick/snapshot, so the fixture now uses a
bounded progress check and a reliable pause barrier. Measured resume latency
was 3.406 seconds on Linux and 2.147 seconds on Retroid. This stall remains open.

The co-op fixture on the entrance save under separate GL/llvmpipe failed two
pause assertions in both the candidate and the previous `866e9c5` package.
Safe GL with diagnostic tracing passed. Stock separate GL also had two engine
CowData crashes. These retained failures do not establish a new regression,
but they prevent claiming universal renderer/lifecycle coverage. The established
co-op save passed all 33 checks under packaged Forward+.

No new complete-simulation throughput gain is claimed. The preceding checkpoint
takes 35.354 wall seconds for 60.5 simulated seconds on Retroid. No Windows
runtime measurement was made; the reported 7945xh/4090 mobile, 4K, 100% scale,
maximum remake settings, D3D12 co-op result near 40 FPS remains unresolved.
Longer campaign coverage, other large maps and release packaging remain open.

## Reproduction

Use `tools/benchmarks/original_city_loop_gameplay.gd` with
`tools/benchmarks/portal_gameplay.gd` version 2, the recorded Portal entrance
fixture, `host: false`, `speed: 1`, `seconds: 60`, and the settings above.
The ordinary campaign load automatically starts the single-player worker.
Set `inline_single: true` only for the matched control. Run control/candidate
pairs without other work on the device and keep simulation progress, census,
frame percentiles and full effective options alongside FPS. Repeat with
`seconds: 180` for the longer walk. The validation record contains the fixture,
tool, source and artifact hashes needed to identify this checkpoint.
