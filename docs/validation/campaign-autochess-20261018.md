# Campaign and autochess validation

18 October 2026. Local changes on `fix/suslanger-and-campaign-feedback`, based on
published v1.15.0 (`ecfd9122b943cfde2d48d6dff2b1104a9de0325f`). These checks
preceded the 1.16.0 version bump and release packaging. Changes are described in
the 1.16.0 changelog; this document records evidence and limits.

The final Linux Vulkan / RTX 3090 build averages **66.0 FPS** in the heavy
first-person desert view, **66.3 FPS** while hosting the nine-army stress battle
at 1×, and **62.7 FPS** at 2×. All use native 3840×2160 at Ultra. The two tested
safe zones average **65.9 and 95.4 FPS** with the same rendering code. These are
averages, not minimums or Windows RTX 4090 Laptop measurements. See
[final runtime qualification](#final-runtime-qualification) for exact artifacts,
frame-time tails, the connected guest and simulation clocks.

## Campaign

- `campaign_feedback.gd`: 35 checks. Saves and loads every pause/speed combination,
  excludes temporary menu pause, handles older saves, preserves quest variables
  while revisiting `gz15h` and `gz16h`, and verifies the route back to `gz17h`.
  A living companion prevents premature defeat; the last controlled party death
  opens game over in solo play, while co-op remains active.
- `local_host_play_clock.gd`: 22 checks with a real separate solo authority
  process. Saves and restores the owner's gameplay clock through RPC.
- `campaign_presentation_feedback.gd`: 15 checks for glow settings in classic,
  third-person and first-person views, bounded Low-shadow direction changes,
  continuous higher-quality lighting, animated toad-mouth emission and low acid
  launch height.
- `campaign_feedback_ui.gd`: six rendered checks each in EN/RU/DE. The selection
  glow row and all three choices fit the First / third person panel. The journal
  map text remains readable and its map context opens through F7.

The journal's old underlined map/wiki links had already been removed in the
published 1.15.0 source. The actual published Linux package was also checked
separately: three journal/F7 checks passed. This change does not replace them a
second time. The retained Windows 1.15.0 archive matches the recorded publication
checksum, and its journal, HUD and unit-panel bytecode matches that Linux package.
This is a resource comparison, not a Windows execution test.
[Package comparison](campaign-autochess-20261018/published-journal-packages.json).
The screenshots supplied with the request show the older links; their originating
executable could not be identified here.

## Autochess and Trials

| Suite | Passing checks |
| --- | ---: |
| LAN discovery, mode isolation and advertised connection details | 12 |
| Existing online host/guest synchronization | 64 |
| Online names, stable hover updates, host-only shared speed, formation movement and stationary end poses | 26 |
| Entire combat clearing and mirrored paths for all eight movement classes | 41 |
| Formation arrivals, including fifteen large creatures | 22 |
| Q/E and middle-drag rotation, Home reset, modal input and ground picking | 10 |
| Interest boundaries, round-start savings, once-only payouts and saved economy | 483 |
| Tournament settlement and elimination | 151; 172 native fights |
| Banshee and comparison-model morph bounds across four animation phases | 72 |

The saved reproduction for issue #19 starts and completes a native battle and
still permits preparation rearrangement. Scenery retains all 21 objects, moved
outside the playable rectangle and the largest navigation clearance. Original
free-placement coordinates are retained when copied to the opposite side.

The rendered online fixture checks a real host, stable creature hover through
countdown packets, player names, sword markers, host 2×, all nine visible boards,
board picking and returning to the focused camera. Its spectator case finishes
the home board at 0:15, watches another board at 1:05, receives its 1:10 update,
switches to a copied opponent at 1:52, verifies the warning/result and returns to
the home result. The watched player's level and gold are also visible beside
their name. Final runs pass 38 checks each in Russian at 2560×1440 and
English/German at 1280×800; each spectator layout was visually inspected.

Representative captures were visually inspected:

- [Russian spectator view](campaign-autochess-20261018/spectator-ru.png)
- [Complete nine-board overview](campaign-autochess-20261018/overview-ru.png)
- [Banshee preview framing](campaign-autochess-20261018/banshee-framing.png)

The additional five gold is **interest**, reached at 50 saved gold. Base income,
victory income and streak rewards remain separate. New options and help include
English, Russian and German. Translation coverage: 2,623 entries, 141 dynamic wiki
keys and 145 dynamic arena keys, with zero missing translations or format errors.

## Performance evidence

Hidden-board effects keep aging but skip draw allocation, frustum work, buffer
uploads and material updates. `particle_visibility.gd` passes 38 checks, including
revealing a board again. Native draw/animation regressions pass 1,723 particle
buffer, 19,580 fire and 76,995 spell-emitter comparisons. The particle shader
fixture passes 106 checks across soft, through-object, additive and marker modes.

`tools/benchmarks/particle_gpu.gd` alternates the original and optimized shaders
in the same process, with 3,593 frozen particles from 24 original fire/smoke
emitters in a 2560×1440 viewport. On the RTX 3090, original median GPU times were
2.615, 2.423 and 2.434 ms; optimized times were 1.703, 1.705 and 1.705 ms. This is
about 30% less GPU time for this effects fixture. Five image comparisons found
no channel difference greater than 1/255. It is not a full-game FPS improvement
or an RTX 4090 Laptop result. [Raw results](campaign-autochess-20261018/particle-gpu.json).

The fixed-seed headless campaign probe measures 400 native ticks after 100 warmup
ticks. Median tick costs are 3.354 ms for Canyon of Death (74 actors), 13.912 ms
for Necromancers' Desert (341), 1.197 ms for `bz14h` (23) and 0.971 ms for `bz15h`
(21). These show the desert's larger simulation workload, but do not explain a
similar loss in the small camps. [Raw simulation measurements](campaign-autochess-20261018/suslanger-logic.json).

First-person sampling at 4K Ultra identified ground-contact blending as a
substantial graphics cost, especially in the desert. A conservative per-map
lookup now excludes terrain cells whose authored XY bounds cannot cover a
fragment. It preserves the original triangle order, highest-surface choice,
folded-map-edge fallback and live vertical footprint deformation. The lookup
uses 4.5 MiB for the 384×384 desert and took about 0.6 seconds to build in the
prototype. Mobile and Compatibility retain their original sampler budgets.

`ground_contact_candidates.gd` passes 226,267 geometry/encoding checks, including
folds, inverted cells, exact boundaries and barycentric tolerance. The rendered
benchmark alternates original/candidate/candidate/original queries at two angles
on the desert, both camps and an Ingos snow map. All 40 checks pass; 24 image
comparisons have no channel difference greater than 1/255. Median GPU cost in
these scenery fixtures falls by 6–26%, depending on map and angle. The two
desert views fall from 6.77 to 5.22 ms and 5.61 to 4.46 ms.
[Raw ground-blending results](campaign-autochess-20261018/ground-contact-gpu.json).

The final contact ownership/material/alpha suite passes 51 Forward+ checks
and 53 Compatibility/OpenGL checks on NVIDIA. The static comparison viewport
disables physics interpolation: its scripted teleports must settle immediately,
even when three rendered frames take less than one physics tick. The authored snow
wall fixture with real installed footprints passes 136 checks. Complete-search
and optimized images are byte-identical under sun, packed point light and local
light; the original footprint-normal response remains visible.
[Footprint and lighting results](campaign-autochess-20261018/ground-contact-tracks.json).

The full first-person fixture includes the HUD and all Ultra effects in a
3840×2160 viewport. It alternates the original and optimized shaders three
times in one process; each pass records 160 frames after warmup. Simulation is
held so the scene composition does not change. Median GPU times across the
three passes are:

| Location | Original | Optimized | GPU time reduction |
| --- | ---: | ---: | ---: |
| Necromancers' Desert (`gz17h`) | 22.19 ms | 18.97 ms | 14.5% |
| Camp `bz14h` | 16.69 ms | 14.47 ms | 13.3% |
| Camp `bz15h` | 11.30 ms | 11.07 ms | 2.0% |

The gain depends on how much blended scenery the camera sees. These are GPU
measurements on Linux Vulkan/RTX 3090, not a guarantee of the same FPS gain in
live gameplay or on the reported laptop.
[Full first-person comparisons](campaign-autochess-20261018/suslanger-first-person-comparison.json).

Camera and aiming calls were separately profiled at 16 headings in all four
campaign locations. Median first-person camera work was 0.106–0.116 ms and
aiming work 0.202–0.281 ms in these samples. Those paths were not changed.
[CPU samples](campaign-autochess-20261018/suslanger-first-person-cpu.json).
The earlier cumulative graphics-option removals are retained only as diagnostic
evidence, not as before/after FPS measurements or proposed quality settings.
[First-person diagnostic samples](campaign-autochess-20261018/suslanger-first-person-render.json).

### Opaque scenery and cutout work

Godot classifies a shader declaring `ALPHA_ANTIALIASING_EDGE` as transparent
even when its uniform branch is false. Solid scenery now uses a separate shader
without that declaration; tree atlases retain their smoothed alpha variant.
This also puts solid scenery in the opaque depth and screen copies used by
refraction. Scenery and foliage reject texels below the existing 0.5 scissor
threshold before their relief, foliage and contact calculations. Translucent
unit materials are unchanged.

`scenery_opaque_pass.gd` passes 44 rendered checks: solid objects, open cutouts,
contact materials and camera fades in the screen copy, plus filtered alpha
edges with relief and foliage lighting at MSAA off and 4×. All twelve cutout
comparisons stay within 1/255 per channel. The expanded material option suite
passes 470 checks across 144 rendered variants. The foliage sharing suite passes
27 checks with byte-identical images between shared and separate materials.

In a same-process frozen 4K scene, moving solid scenery to the opaque pass
reduces median GPU time from 19.24/19.27 ms to 18.67/18.91 ms.
[Raw comparison](campaign-autochess-20261018/scenery-opaque-gpu.json).
On the physical NVIDIA display, the subsequent early-cutout change improves a
30-second live desert run from 46.7 to 54.9 average FPS; median frame time falls
from 21.28 to 18.24 ms and p95 from 24.69 to 21.17 ms. Both use native 4K Ultra,
Safe rendering and the ordinary separate solo authority, with a 320×320 carrier
window. This isolates the cutout change relative to the already optimized
opaque-scene build, not relative to published 1.15.0.
[Before](campaign-autochess-20261018/suslanger-live-opaque-xorg.json),
[after](campaign-autochess-20261018/suslanger-live-cutout-xorg.json).

### Live 4K display measurements

`suslanger_live.gd` now drives ordinary first-person gameplay with the separate
solo worker, all 341 desert actors or 21–23 camp actors active, and advancing
simulation clocks. `--onscreen` displays the complete 3840×2160 view; `--turn`
makes one full camera turn in 30 seconds. Vsync, the frame cap and automatic
graphics changes are disabled; the Ultra preset, native render scale and 4×
MSAA remain enabled. GPU timestamp readback is disabled for these FPS runs.

The physical-display results and camera headings are retained in
[the live measurement bundle](campaign-autochess-20261018/suslanger-live-onscreen.json).

| Live first-person view, 30 seconds | Average FPS | Median frame | p95 frame |
| --- | ---: | ---: | ---: |
| Desert, fixed heavy view, Safe | 53.2 | 18.68 ms | 21.92 ms |
| Camp `bz14h`, fixed view, Safe | 60.4 | 16.51 ms | 18.00 ms |
| Camp `bz15h`, fixed view, Safe | 76.5 | 13.07 ms | 14.48 ms |
| Desert, full turn, Safe | 72.0 | 13.13 ms | 20.41 ms |
| Lava camp `bz14h`, full turn, Safe | 60.9 | 16.09 ms | 19.85 ms |

A complete turn includes both expensive scenery and lighter views, so its
average must not replace the sustained result at the heavier fixed angle.
Neither the desert nor every part of the camera sweep sustains 60 FPS here.

### Live online hosting

`arena_host_presentation.gd` passes 56 checks for nine hidden authority worlds,
no visual terrain/contact allocations and continued native simulation. The host
renders its network replica; authority figures retain the bone and navigation
data needed by combat. Navigation-only terrain no longer receives visual
ground-contact materials.

Independent online boards now become due across their 55 ms tick interval.
Their player order and whole combat ticks stay unchanged; active board clocks
differ by at most one tick. This spreads the usual CPU burst across rendered
frames. `arena_host_tick_schedule.gd` passes 5,765 checks against the former
whole-board loop at 1× and 2×, comparing complete rounds, positions, paths,
health, effects, random state, payouts and final results under uneven frame
intervals. The existing ENet/WebSocket suite passes 64 checks and online
feedback passes 26 checks after this change.

The live host benchmark connects a loopback guest and seven bots, simulates
nine boards with 162 initial fighters, and adds 18 original fire/smoke emitters
to the watched battle. Native attacks, projectiles, deaths, clocks and network
packets continue throughout the 30-second sample. The baseline before spreading
ticks averages 49.8 FPS, with 17.98 ms median, 30.91 ms p95 and a 428 ms initial
spike, at native on-screen 4K Ultra/Safe on the physical NVIDIA display.
[Baseline](campaign-autochess-20261018/arena-host-before-scheduling.json),
[rendered stress scene](campaign-autochess-20261018/arena-host-4k.png).
The production scheduler averages 52.2 FPS, with 18.01 ms median,
24.58 ms p95, 36.44 ms p99 and a 343 ms opening spike. The sample reaches
4,827 drawn particles; all nine simulation clocks continue advancing.
The p95 improvement is about 20%; the median does not materially improve.
[Scheduled host run](campaign-autochess-20261018/arena-host-scheduled.json).
The opening navigation/AI spike is not solved by the scheduler. Its improvement
must not be described as a sustained 60 FPS result.

NPC acknowledgements now skip voice-database lookup when no controlled party
member can receive a line, as in autochess authority worlds. Recipient selection
uses the world party registry while retaining ownership and perception checks.
`ai_reaction_recipients.gd` passes seven checks for empty recipients, newly owned
units, duplicate player ownership, perception and ownership changes. The native
round comparison still passes all 5,765 checks. In a separate headless diagnostic
with eight fighters on each board, the home board's first tick drops from
46.28 to 23.02 ms and the nine-board total from 201.96 to 174.93 ms. These are
first-tick samples, not FPS measurements.
[First-tick diagnostic](campaign-autochess-20261018/arena-first-tick-diagnostic.json).

The live host run including these two changes averages 52.3 FPS, with
17.88 ms median, 25.24 ms p95, 33.47 ms p99 and a 346.87 ms opening spike.
It reaches 4,550 drawn particles with all nine clocks advancing. This confirms
the remaining navigation/AI spike and does not establish 60 FPS.
[Host run before effect-quality initialization](campaign-autochess-20261018/arena-host-final.json).

Viewport initialization now applies the same renderer-wide SSAO, volumetric fog
and glow sampling settings as campaign initialization. Previously a cold
autochess launch retained the engine's full-resolution Ultra SSAO, while a launch
after visiting a campaign inherited the game's High/half-resolution profile.
This removes that mode-history dependency; it changes the cold-launch sampling
profile, so this gain is not a pixel-identical optimization against that former
cold-launch state. Effect enablement and strength, native resolution and 4× MSAA
are retained.

`arena_effect_quality.gd` passes five rendered checks, including byte-identical
images before and after initializing a campaign environment. The fixture also
confirms that the engine-default profile produces a different image, so the
history comparison exercises the affected effect.
[Rendered checks](campaign-autochess-20261018/arena-effect-quality.json).
With this initialization fix, the host run averages 55.2 FPS, with
17.07 ms median, 23.71 ms p95, 33.82 ms p99 and a 350.72 ms opening spike.
It reaches 4,447 drawn particles and all nine battle clocks advance.
[Host run before the frame budget](campaign-autochess-20261018/arena-host-effect-quality.json),
[4K stress scene](campaign-autochess-20261018/arena-host-effect-quality.png).
That run still has the opening hitch and does not establish sustained 60 FPS.

A separate first-person desert GPU profile identifies the opaque pass (5.12 ms),
depth prepass (3.45 ms) and transparent pass (3.31 ms) as the largest median
stages. Timestamp queries affect frame timing; this is diagnostic evidence,
not an additional FPS measurement.
[GPU stage samples](campaign-autochess-20261018/desert-gpu-passes.json).

### Scenery relief sampling

Scenery relief now takes its screen derivatives before the visibility branch
and supplies explicit texture gradients. Once the existing distance or
minification fade reaches zero, it returns the same normalized base normal
without four texture reads. The fade range, near detail and visual strength
are unchanged.

A frozen first-person desert comparison measured 18.08/17.73 ms GPU time for
the former formula and 17.67/17.40 ms for the candidate, a 0.33–0.41 ms saving.
Excluding the animated first-person HUD, the first candidate image differed
by at most one channel byte; the second pair was byte-identical.
[Shader comparison](campaign-autochess-20261018/surface-relief-gpu.json).
This isolated measurement is not a live FPS result.

The focused rendered regression passes 23 checks on each of NVIDIA Vulkan and
NVIDIA OpenGL, including both fade boundaries, four-sample MSAA, minified
textures, and a control confirming that near relief remains visible. All
reference/candidate comparisons are within one channel byte. The shader-option
suite passes 470 checks. [Vulkan](campaign-autochess-20261018/surface-relief-vulkan.json),
[OpenGL](campaign-autochess-20261018/surface-relief-gl.json).

The matched on-screen desert harness averages 53.36 FPS after this change,
versus 53.21 FPS in the earlier final run. That difference is too small to
establish a live FPS improvement despite the isolated shader savings.
[Matched final run](campaign-autochess-20261018/suslanger-live-relief-comparison.json).

The benchmark now also accepts `--root-viewport`, which draws directly in the
normal game window instead of presenting a full-size SubViewport texture. This
checks that the harness's extra copy is not responsible for the slowdown.
Native 3840×2160, Ultra, 4× MSAA, scale 1.0, live separate solo authority,
Safe render-thread mode, no GPU readbacks, 30 seconds per fixed first-person view:

| Map | Actors | Average FPS | Median | p95 |
| --- | ---: | ---: | ---: | ---: |
| Necromancers’ Desert | 341 | 53.66 | 18.59 ms | 21.68 ms |
| Lava camp (`bz14h`) | 23 | 61.13 | 16.23 ms | 17.95 ms |
| Camp (`bz15h`) | 21 | 76.71 | 13.00 ms | 14.41 ms |

The direct-window run confirms the heavy desert view remains below 60 FPS.
The safe zones average above 60 in these sampled views; this does not establish
60 FPS at every camera position. [Desert](campaign-autochess-20261018/suslanger-root-final-gz17h.json),
[lava camp](campaign-autochess-20261018/suslanger-root-final-bz14h.json),
[second camp](campaign-autochess-20261018/suslanger-root-final-bz15h.json).

### Host catch-up budget

The host now yields between complete board ticks after approximately 6 ms of
simulation work per rendered frame, or 12 ms at 2×. When more than two native
ticks of time are owed, the allowance doubles temporarily to drain the backlog.
A single native tick can
exceed this budget; this is not a frame-time cap. The remaining time debt and
player cursor carry into the next frame, so no combat time is dropped and no
board is skipped. Explicit deterministic advances remain unbudgeted by default.

The expanded scheduler suite passes more than 24,000 checks, comparing full native rounds
with no budget and a forced 1 microsecond budget at both speeds. After draining
only the already owed time, actor state, paths, health, effects, RNG, payouts
and results match. These explicit-tick comparisons run without automatic
presentation callbacks; they do not establish identical animation-driven
hit geometry at every rendered cadence. The ENet/WebSocket and feedback suites still pass 64 and 26
checks respectively. [Checks](campaign-autochess-20261018/arena-host-budget-checks.json).

The initial fixed-budget candidate's 30-second native 4K Ultra host run averages 53.7 FPS,
with 17.45 ms median, 24.52 ms p95, 32.55 ms p99 and an 87.43 ms worst frame.
The earlier prototype measured 83.23 ms at worst, so both runs reduce the
approximately 351 ms opening spike substantially. Average throughput does not
improve: this change spreads expensive catch-up work and the opening simulation
temporarily trails wall time. It trails by up to 0.69 simulation seconds in the recorded census and catches
up by the five-second sample while retaining all nine clocks.
The final sample reaches 4,632 drawn particles. The sustained 60 FPS target
remains unmet.
[Budgeted host run](campaign-autochess-20261018/arena-host-budget-final.json),
[4K stress scene](campaign-autochess-20261018/arena-host-budget-final.png).

At 2×, the previous build without a frame budget averaged 42.2 FPS with a
423.2 ms worst frame in the 15-second stress sample. The initial fixed budget
averaged 39.9 FPS with an 83.5 ms worst frame, but fell behind by up to 3.52
simulation seconds and did not catch up until the ten-second sample. The
adaptive-budget prototype reduced the maximum observed lag to 1.48 simulation
seconds and caught up by six seconds, averaging 39.6 FPS with a 93.2 ms worst
frame. These results show the responsiveness/simulation-delay tradeoff; they
are not a throughput improvement or a 60 FPS result.
[Before budget at 2×](campaign-autochess-20261018/arena-host-speed2-before-budget.json),
[fixed budget at 2×](campaign-autochess-20261018/arena-host-budget-speed2.json),
[adaptive prototype at 2×](campaign-autochess-20261018/arena-host-adaptive-prototype.json).

The rebuilt candidate includes adaptive budgeting and faded-relief sampling.
Its final live runs retain all previews, nine boards, 162 initial fighters and
18 added native fire/smoke emitters:

| Speed / sample | Average FPS | Median | p95 | p99 | Worst frame | Maximum observed simulation lag |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1× / 30 seconds | 56.0 | 16.46 ms | 25.57 ms | 36.36 ms | 85.83 ms | 0.42 seconds |
| 2× / 15 seconds | 40.5 | 18.74 ms | 50.74 ms | 71.63 ms | 86.38 ms | 1.51 seconds |

Lag is the wall clock multiplied by battle speed minus the slowest board clock
at the once-per-second census; it is not a per-frame maximum. Both runs catch up
and retain all boards. The 2× run reaches 5,134 drawn particles. Compared with
the unbudgeted 2× sample, the opening stall is much shorter, but average FPS
is lower and the simulation temporarily runs behind. Sustained 60 FPS remains
unmet in this host stress test.
[Final 1×](campaign-autochess-20261018/arena-host-adaptive-final-1.json),
[final 2×](campaign-autochess-20261018/arena-host-adaptive-final-2.json).

A separate GPU diagnostic disables shop preview viewports to stay within the
engine's timestamp-query capacity. Its battle-view medians are 6.18 ms opaque,
2.89 ms depth prepass and 2.28 ms transparent. There are no timestamp errors
inside that measurement window; it is not an FPS acceptance run. The full
live benchmarks retain the previews.
[Battle-view GPU stages](campaign-autochess-20261018/arena-main-view-gpu-passes.json).

Additional profiling and rejected cache/loop/navigation warm-up experiments are
kept as [diagnostic evidence](campaign-autochess-20261018/rejected-performance-prototypes.json).
Unsuccessful prototypes are not included in production source.

### Separate desktop autochess authority

Desktop hosting now starts a separate headless authority with its own 60 Hz
frame loop. The visible owner authenticates over loopback into seat zero; it
occupies no additional human slot. ENet and WebSocket guests retain the same
protocol. The worker advertises the LAN lobby, while the frontend owns router
mapping and its status display. Host-only start/speed actions are checked by the
authority. Cancelling startup, leaving, or removing the lobby cleans up the
child and private startup files. Worker shutdown releases battles before global
resources, and departing owners are removed before the next state broadcast.
Fresh queued frames are processed before the client silence timeout is checked,
so a stalled scene/shader build does not discard an otherwise live connection.
The transport also permits the same scene-loading grace as campaign co-op.

The verified live fixture uses the actual seat-zero owner and one connected
guest, seven bots, nine boards with 162 initial combatants, all shop previews,
and 18 additional original fire/smoke emitters. Its guest assertion requires a
live transport, connected view and two-human authority roster. The external
child fixture only sets up those armies and pauses at measurement barriers; it
adds no network command to the game. Both inline and separate-process runs use
the same final pack. Native 3840×2160, Ultra, 100% render scale, 4× MSAA plus SMAA,
Safe render thread, no GPU timestamp queries, Linux RTX 3090 / Ryzen 9 5950X:

| Speed / sample | Inline average | Separate-process average | Separate median | Separate p95 | Separate p99 | Worst frame, inline → separate | Maximum observed simulation lag, inline → separate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1× / 30 seconds | 53.7 FPS | 58.3 FPS | 17.06 ms | 19.41 ms | 24.06 ms | 86.63 → 57.53 ms | 0.476 → 0.053 seconds |
| 2× / 15 seconds | 41.3 FPS | 57.3 FPS | 17.05 ms | 21.05 ms | 28.39 ms | 89.88 → 61.66 ms | 1.585 → 0.198 seconds |

All nine authority clocks advance. The separate-process 1× and 2× views reach
4,550 and 4,151 drawn particles. Army, seed, quality and added emitters match the
inline fixture. Individual combat outcomes and effect counts can vary with
animation cadence; this comparison does not establish identical per-frame hit
geometry across processes. The separate-process census also continues briefly
during capture/teardown, so its final clock is later than the FPS window.
Lag uses each authority census's own wall time and slowest board clock, not the
frontend's potentially older copy of that census. FPS remains below the sustained
60 target. These are Linux measurements, not a result for the reported Windows
RTX 4090 Laptop.
[Inline 1×](campaign-autochess-20261018/arena-host-connected-inline-1.json),
[separate 1×](campaign-autochess-20261018/arena-host-connected-process-1.json),
[inline 2×](campaign-autochess-20261018/arena-host-connected-inline-2.json),
[separate 2×](campaign-autochess-20261018/arena-host-connected-process-2.json),
[verified runtime](campaign-autochess-20261018/performance-runtime-process-checked.json).

Earlier exploratory process samples reported about 59 FPS, but their guest
check only retained its assigned seat. A strict follow-up exposed a disconnected
guest during cold scene creation: ENet's default transport timeout could fire
after approximately five seconds without frontend polling. Autochess now uses
the same 60-second transport allowance as campaign co-op. The original 15-second
application-level silence check remains, after queued packets are consumed;
explicit disconnects still close immediately. The table above supersedes those
exploratory measurements and verifies that the guest stays connected.

The real-process suite passes 74 checks covering both transports, LAN metadata, invalid owner-token
rejection, seat-zero ownership, all nine boards, recruitment, host-only start
and speed, queued-frame recovery, a deliberately non-polling guest for 6.5
seconds, startup cancellation, an occupied port, owner departure closing connected guests, private-file cleanup and clean
worker logs. The rendered lobby suite passes 41 checks in each of EN/RU/DE,
including repeated startup cancellation, combat, wiki, menus, scouting, overview
and shutdown. Actual captured viewports are 1280×726 for EN/DE and 2560×1366 for
RU; these layout checks are separate from the exact 4K performance windows.
Translations still cover 2,623 entries with no missing keys or format errors.
[Check record](campaign-autochess-20261018/arena-local-host-checks.json),
[Russian scouting](campaign-autochess-20261018/process-ui-ru.png),
[German lobby](campaign-autochess-20261018/process-ui-de.png).

### Further first-person desert attribution

An alternating frozen-camera diagnostic removes one category at a time. Removing
contact blending reduces median GPU time from about 17.47 to 14.06 ms; removing
terrain detail reduces it from 17.47 to 14.66 ms. Hiding scenery reduces a nearby
17.81 ms baseline to 12.32 ms, including render CPU time from 2.79 to 0.35 ms.
Removing particles changes 17.58 to 17.46 ms in this particular view. These costs
overlap and must not be added. Each removal changes quality and is only an
attribution probe: none was adopted as an optimization or counted as a highest
preset FPS result. The full first-person desert result remains 53.7 FPS.
[Diagnostic rows](campaign-autochess-20261018/desert-cost-attribution.json).

Explicit Forward+ scenery batching increased GPU, CPU and draw-call costs and
was discarded. An AI area-damage cache passed 11,557 differential score checks
and a full 807-cycle state comparison, but did not improve live instrumented
host throughput; it was also reverted. Details are in the rejected-prototype
record linked above.

### Shared arena tile colours

Forward+ arenas now share a four-layer immutable colour texture for the identical
32×32-tile boards. It replaces repeated atlas colour lookups, including those in
terrain relief, without baking geometry, normals, light, footprints or marks.
The ordinary material still draws fire, smoke and combat. Its 128 pixels per tile
use 113,246,112 bytes, about 108 MiB, shared across the boards; weak ownership
releases that memory after the last board and material disappear. Larger source
atlases, Mobile, Compatibility and headless authority retain their original
sampler. The first prototype took about 1.8 seconds to build during loading.

The same strict live fixture above, now using the cache, yields:

| Speed / sample | Average | Median | p95 | p99 | Worst frame | Maximum observed simulation lag |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1× / 30 seconds | 65.4 FPS | 15.17 ms | 17.61 ms | 20.12 ms | 54.67 ms | 0.059 seconds |
| 2× / 15 seconds | 63.4 FPS | 15.40 ms | 19.40 ms | 22.59 ms | 59.79 ms | 0.201 seconds |

These runs keep the real guest connected, seat-zero ownership, nine boards and
18 added native fire/smoke emitters. They reach 4,417 and 4,272 drawn particles.
They exceed 60 FPS on average, **not** a 60 FPS minimum; slower frames remain.
The earlier process runs in the table above are the uncached baseline, rather
than a fresh alternating live comparison. A separate frozen-scene ABBA probe
measures baseline GPU medians 14.71/14.90 ms and cached 12.65/12.52 ms.
[Live 1×](campaign-autochess-20261018/arena-host-color-process-1.json),
[live 2×](campaign-autochess-20261018/arena-host-color-process-2.json),
[frozen GPU probe](campaign-autochess-20261018/arena-color-cache-frozen.json),
[runtime and checks](campaign-autochess-20261018/performance-runtime-arena-color.json).

The cache is not pixel-identical: sampling a derived colour field changes
filtering slightly. Eight frozen views cover four headings and close, normal
and wide zoom. In the array prototype the maximum mean channel difference is
0.042/255; at most 804 of 8,294,400 pixels differ by more than 1/255. Largest
isolated differences occur at antialiased silhouettes; close crops were checked.
The final production-material comparison has a maximum mean channel difference
of 0.041/255 and at most 886 pixels above 1/255. Seven baseline repeats are
identical; one view has isolated repeat differences up to 14/255. The largest
candidate difference is an isolated 89/255. Close crops retain the same visible
units, effects and terrain. This comparison freezes 4,342 drawn particles.
[Array prototype differences](campaign-autochess-20261018/arena-color-array-quality.json).
[Production differences](campaign-autochess-20261018/arena-color-production-quality.json),
[reference crop](campaign-autochess-20261018/arena-color-reference-crop.png),
[cached crop](campaign-autochess-20261018/arena-color-cached-crop.png).

The production lifecycle suite passes 40 Forward+ checks and 17 checks each on
Mobile and NVIDIA OpenGL. It covers live footprints across all four sector
seams, option changes, two-board sharing, headless exclusion, larger source
fallback and release after the final world. The real online UI suite also
passes 41 checks with the cache. [Forward+](campaign-autochess-20261018/arena-terrain-color-forward.json),
[Mobile](campaign-autochess-20261018/arena-terrain-color-mobile.json),
[OpenGL](campaign-autochess-20261018/arena-terrain-color-gl.json),
[live footprints](campaign-autochess-20261018/arena-color-live-tracks.png).

Frozen arena probes must disable `ArenaOnlineScreen` processing along with the
simulation: that screen otherwise restores `Engine.time_scale` every frame.
Earlier exploratory profiles that only set time scale to zero allowed effects
to keep aging and are not used as quality or GPU acceptance. This correction
does not affect the live host benchmarks. The fully paused render-category
probe attributes substantial cost to terrain detail, with smaller overlapping
costs from contact, soft ground, lights and particles; no category removal was
adopted. [Attribution](campaign-autochess-20261018/arena-render-cost-attribution.json).

### Campaign terrain colour pages

The Forward+ campaign path now reuses the bounded native colour-page worker for
maps with no admitted Natural terrain transitions. Each resident sector uses a
specialized colour sampler, avoiding the expensive fallback branch at every
sample. Cliff projections, geometry, normals, lighting, weather and effects
remain live. Replacement atlases above the supported native density retain the
original sampler. The arena's smaller shared cache remains separate.

In the heavy desert view, eight pages at the source's 96 pixels per tile occupy
127,401,088 bytes (121.5 MiB), below the 128 MiB residency limit. A frozen
diagnostic measures about 17.10 ms baseline GPU time versus 15.32 ms with the
specialized terrain sampler. An earlier 16-page cache with a shader branch and contact-result reuse
did not add useful gains and were not adopted. Live follow-up probes of a
16-page specialized cache and screen-area cache priority also failed to
improve frame rate; the 128 MiB nearest-sector policy is retained.
[Diagnostic](campaign-autochess-20261018/desert-color-specialized-diagnostic.json).

The first live 30-second native-4K Ultra run averages 59.99 FPS with a 16.56 ms
median, 19.00 ms p95 and 20.25 ms p99. It keeps the ordinary separate solo
authority and all 341 actors; the cache is fully resident throughout sampling.
This is about 60 FPS on average, not a guaranteed minimum. The repeated timing
checks below qualify that first result.
[First sample](campaign-autochess-20261018/suslanger-color-live-first-gz17h.json).

The sequential same-pack live comparison is below. All runs use the root
viewport at 3840×2160, scale 1.0, Ultra, 4× MSAA plus SMAA, the safe render
thread and the ordinary separate solo worker. GPU timestamp queries are off.

| First-person view | Average FPS | Median / p95 / p99 frame ms |
| --- | ---: | ---: |
| Heavy desert, colour cache disabled | 53.16 | 18.78 / 21.72 / 22.98 |
| Heavy desert, colour cache enabled | 59.54 | 16.65 / 19.59 / 20.88 |
| Desert, full turn | 82.01 | 11.39 / 18.22 / 20.07 |
| Safe zone `bz14h` | 60.65 | 16.41 / 17.98 / 18.84 |
| Safe zone `bz15h` | 85.97 | 11.60 / 13.01 / 13.73 |

The heavy-view average improves by 12.0%, but remains slightly below 60 FPS.
The turning run includes lighter directions and does not replace that result.
[Baseline](campaign-autochess-20261018/forward-color-live-baseline.json),
[repeat](campaign-autochess-20261018/forward-color-live-repeat.json),
[turn](campaign-autochess-20261018/forward-color-live-turn.json),
[first safe zone](campaign-autochess-20261018/forward-color-camp-bz14h.json),
[second safe zone](campaign-autochess-20261018/forward-color-camp-bz15h.json).

Five frozen native-4K first-person views cover four headings and a close downward
view. Maximum mean channel difference is 0.068/255; at most 37,905 of 8,294,400
pixels (0.46%) differ by more than 1/255. The largest isolated difference is
32/255. Baseline repeats have isolated variations up to 19/255. Near-floor and
distant-floor crops were inspected; the colour cache changes filtering slightly
and is not pixel-identical. [Differences](campaign-autochess-20261018/campaign-color-image-differences.json),
[reference](campaign-autochess-20261018/campaign-color-worst-0-reference.png),
[cached](campaign-autochess-20261018/campaign-color-worst-0-cached.png).

The authored Ingos snow fixture passes 36 Forward+ lifecycle checks: native
tracks and their clocks, graphics changes, unsupported Natural-transition
fallback, valid scripted water changes, eviction beneath a live footprint,
restoration, larger-source fallback, expiry and joining pending workers on
clear. The existing Mobile lifecycle suite also passes all 14 checks after
the Forward+ hooks. The Forward+ screenshots are 5120×2880, independent of the 3840×2160 FPS fixture.
The first desert fixture contained no usable soft-ground location; a later
fixture initially addressed an unused water-material ID. Those failed fixture
runs are excluded; the passing run uses actual snow and water metadata.
[Checks](campaign-autochess-20261018/terrain-color-forward-checks.json),
[cached footprints](campaign-autochess-20261018/campaign-color-tracks.png),
[after eviction](campaign-autochess-20261018/campaign-color-evicted.png),
[after expiry](campaign-autochess-20261018/campaign-color-restored.png).

### Directional shadow blend work

The custom Forward+ engine now skips the second directional PCF lookup when
the adjacent cascade has zero blend weight. Positive-weight transitions retain
the existing kernel, samples, atlas, bias and blend equation. Neither the
angular soft-shadow path nor the Mobile/Compatibility shaders changes. This
requires the new native template; updating only the game pack is insufficient.

Two Linux release engines were built with the same recipe and the first twelve
common patches; the candidate adds only `forward-shadow-blend-guard.patch`.
They use identical game-pack and native-extension hashes. The baseline is a
freshly rebuilt control, not the previously shipped executable. All thirteen
patches reverse and reapply successfully in an isolated copy of their 26 touched
files, returning identical hashes. The audit does not independently authenticate
the upstream archive. [Build receipt](campaign-autochess-20261018/performance-runtime-forward-shadow.json),
[source stack](campaign-autochess-20261018/forward-shadow-source-stack.json).

All 72 deterministic shadow captures are byte-identical across the two engines.
They cover Hard, Soft Low and Soft High filtering, one/two/four cascades,
blending on/off and four camera offsets. The 24 two/four-cascade positive
controls differ when blending is disabled, so the fixture exercises
the transitions being preserved. [Image hashes](campaign-autochess-20261018/forward-shadow-images.json),
[baseline](campaign-autochess-20261018/shadow-blended-baseline.png),
[candidate](campaign-autochess-20261018/shadow-blended-candidate.png),
[unblended control](campaign-autochess-20261018/shadow-unblended-control.png).

In the frozen 4K heavy desert diagnostic, median GPU time falls from 14.94 to
13.71 ms (8.2%). This uses GPU timestamps and is not live FPS acceptance.
The full-scene captures contain independently initialized portal particles and
are not suitable as exact pixel controls; the deterministic shadow fixture
above supplies that check. [Baseline diagnostic](campaign-autochess-20261018/shadow-frozen-baseline.json),
[candidate diagnostic](campaign-autochess-20261018/shadow-frozen-candidate.json).

The matched 30-second live desert runs retain the full HUD, effects, all 341
actors and ordinary separate solo authority. They use the native 3840×2160
root viewport, Ultra at scale 1.0, 4× MSAA plus SMAA and safe render-thread
mode, with GPU timestamps disabled. The rebuilt baseline averages 59.89 FPS;
the candidate averages 65.55 FPS, a 9.4% gain. Median/p95/p99 frame times
change from 16.61/19.12/20.14 ms to 15.10/18.29/19.60 ms.
[Live baseline](campaign-autochess-20261018/shadow-live-baseline.json),
[live candidate](campaign-autochess-20261018/shadow-live-candidate.json).

Sequential follow-ups on the same candidate engine give these results:

| First-person view | Average FPS | Median / p95 / p99 frame ms |
| --- | ---: | ---: |
| Heavy desert, repeated | 65.76 | 15.09 / 18.00 / 18.95 |
| Safe zone `bz14h` | 65.90 | 15.16 / 16.57 / 17.30 |
| Safe zone `bz15h` | 95.40 | 10.42 / 11.78 / 12.36 |
| Desert, full turn | 87.42 | 10.68 / 16.83 / 19.19 |

The turn includes lighter directions and does not replace the heavy fixed
view. All four processes exit cleanly without script, shader or native runtime
errors. [Desert repeat](campaign-autochess-20261018/shadow-final-desert.json),
[first safe zone](campaign-autochess-20261018/shadow-final-camp-bz14h.json),
[second safe zone](campaign-autochess-20261018/shadow-final-camp-bz15h.json),
[turn](campaign-autochess-20261018/shadow-final-turn.json).

Two initial hosted follow-ups measure 65.30 FPS at 1× and 63.70 FPS at 2×,
with the guest connected throughout measurement. Both then expose an ENet
roster-send error during simultaneous guest/owner teardown. These are recorded
as pre-fix runs, not clean final acceptance:
[1× log](campaign-autochess-20261018/shadow-host-before-departure-fix-1.log),
[2× log](campaign-autochess-20261018/shadow-host-before-departure-fix-2.log).

`arena_online_disconnect.gd` reproduces this independently with real ENet
peers: two guests disconnect before a server poll while a third remains. All
three repetitions attempt a roster send to a peer whose native connection
has already reset. Deferring the roster broadcast until all disconnect
signals have removed their members fixes the race. The same fixture then
passes all 27 checks, including the surviving guest's roster and readiness.
[Before](campaign-autochess-20261018/disconnect-race-before.log),
[after](campaign-autochess-20261018/validated-disconnect.log).

### Final runtime qualification

The final pack includes the departure fix. The shadow-optimized native engine
and terrain extension are unchanged; only autochess roster-broadcast scheduling
differs from the preceding pack. The final exported runtime passes the real
disconnect regression (27 checks), authority lifecycle over ENet/WebSocket (74),
online synchronization (64) and lobby suite (75). The authority suite's occupied
port negative test deliberately logs an ENet bind failure; successful authority
instances assert clean runtime logs. [Network checks](campaign-autochess-20261018/final-network-checks.json).

The final pack then passes three sequential native-4K Ultra live runs, with no
script, shader, native transport or teardown errors:

| Final runtime | Average FPS | Median / p95 / p99 frame ms | Maximum frame ms |
| --- | ---: | ---: | ---: |
| First-person heavy desert, 30 s | 66.01 | 15.01 / 18.15 / 19.11 | 59.89 |
| Hosted autochess, 1×, 30 s | 66.30 | 14.92 / 17.25 / 20.19 | 63.60 |
| Hosted autochess, 2×, 15 s | 62.75 | 15.45 / 20.00 / 26.19 | 73.77 |

The hosted fixture starts nine armies with 162 fighters, a real connected
guest, seven bots and 18 added fire/smoke emitters. The host retains seat-zero
ownership. Peak visible particle counts are 4,404 and 4,378; maximum sampled
authority-clock lag is 0.0555 s at 1× and 0.3051 s at 2×. Both guests remain
connected through measurement, and both authority processes terminate cleanly.
The safe-zone and camera-turn measurements above use the previous pack with
identical campaign/rendering code; their only subsequent pack change is the
autochess departure fix.

[Runtime hashes and commands](campaign-autochess-20261018/performance-runtime-validated.json),
[desert data](campaign-autochess-20261018/validated-desert.json),
[host 1× data](campaign-autochess-20261018/validated-host-1.json),
[host 2× data](campaign-autochess-20261018/validated-host-2.json),
[first-person capture](campaign-autochess-20261018/validated-desert.png),
[hosted capture](campaign-autochess-20261018/validated-host-1.png).

These are averages on the Linux RTX 3090 test machine. Some individual frames
still exceed 16.67 ms. Windows Direct3D 12/Vulkan and the RTX 4090 Laptop remain
unvalidated; this is not a minimum-60 guarantee for that hardware.

## Reproduction and platform limits

Headless suites use Godot 4.7 with `--render-thread safe`, `--path game`, an
isolated `XDG_DATA_HOME`, original game data and an absolute `--tool` path.
Rendered fixtures use Vulkan on Linux and an RTX 3090; localized campaign
checks use the corresponding original EN/RU/DE archives. Startup messages about
Xvfb input grabs or the unavailable shader-cache directory are environmental.
The successful export also logged an unavailable editor ObjectDB snapshot
directory; the resulting PCK passed the live runtime checks. Final runtime
validation excludes runs with script or shader errors.
The older pre-cutout baseline records a fixture teardown RPC warning after the
measurement window; command callbacks are stopped before teardown in final runs.

Earlier pixel/GPU diagnostics used Xvfb. Its software presentation overhead makes its
total frame times unsuitable as live FPS acceptance, even with a small carrier
window. The final FPS runs instead use the NVIDIA-backed Xorg display `:0`.
Hardware is an RTX 3090 and Ryzen 9 5950X. Safe render-thread mode matches the
shipped Windows setting; a separately identified Linux Separate-mode desert
sample is diagnostic. [Candidate runtime hashes](campaign-autochess-20261018/performance-runtime.json).

The reported first-person RTX 4090 Laptop / Windows 11 / 4K / highest-preset
configuration was not available; its renderer was not specified. The changes
address measured graphics costs, but their effect on that laptop's overall
performance still needs verification. Windows, Android and browser exports
have not been tested for this change.
