# Path-tracing CPU, standby worker and covered gathering — 27 October 2026

Local changes based on `9e6aa3a7` (1.33.0 release candidate). Nothing was
committed, pushed or published. All measurements below come from one Windows
workstation: RTX 4090 Laptop GPU (driver 32.0.16.1664), Ryzen 9 7940HS,
Windows 11 26300, Direct3D 12, Safe render thread (the Windows production model).

The executable is the released 1.31.1 Windows engine. No engine patch changed
between 1.31.1 and this source. Each pack was exported from source with stock
Godot 4.7.2 and placed beside that executable; the release template refuses
`--path` and `--main-pack`. The unchanged comparator is a pack exported from a
clean `9e6aa3a7` worktree and run on the same executable. Profiles were fresh and
isolated (`APPDATA`), with free cursor, FPS display and muted audio.

## Findings and changes

| Area | Measured cause | Change |
| --- | --- | --- |
| PT frame time at 4K | The main thread is the limit: ~10 ms frames against ~5 ms of GPU work. The PT controller used ~2.5 ms CPU per frame. About 0.5 ms rescanned all 476 traced groups for replaced figures, and ~0.3 ms walked 109 figures for first-person presentation, every frame. | Figure replacement bumps `GameUnit.model_revision`; entering or leaving first-person view bumps `EIUnitModel.view_revision`. The PT scene scans only after a revision changes and keeps a list of presented figures. A replacement still rebinds every part on its first frame. |
| First save load / new game | Each solo campaign starts a separate simulation process. Its startup compiles the game's scripts: 4.2 s before the first autoload `_ready`, against 0.1 s for an empty project on the same engine. | The menus start one worker in advance (`LocalHost.prepare_standby`). It boots, marks its crash record as `standby` and waits for its configuration. The next `start()` for the same game files publishes that configuration with one rename and adopts the process. A standby exits cleanly when its owner deletes or stops refreshing the heartbeat file, on owner shutdown, or when the game files differ. If it has already exited, the ordinary worker starts on the same configuration. Android keeps its service backend. |
| Worker crash markers on Windows | `CrashReport.alive()` cannot see another PID on Windows. Every worker's startup scan therefore deleted its running owner's crash marker and logged it as a crash. | Simulation workers (`--local-host-config`, `--autochess-host-config`) never offer reports and no longer scan. An orphaned `standby` marker is removed without a report. |
| PT preparation under a cover | Geometry gathering used 6 ms per frame even while the preparation cover paused the game. | Under an explicit preparation cover the budget is 16 ms. Live replacement (1.5 ms) and uncovered loading (6 ms) are unchanged. |
| PT boundary popping while travelling | Traced receivers faded out at 60–72 m from the snapshot centre. The centre trails the camera by up to the 16 m recentre step, so the far PT edge crept toward a moving camera and jumped back when the recentred snapshot was published. Water refraction already followed the eye for this reason. | One shared `ei_rt_coverage()` fades by distance from the eye (reach = receiver radius − 16 m) and keeps the existing centre fade as a bound. Receivers therefore stay within the same 72 m centre limit and occluder margin. The PT edge now holds a constant ~50 m instead of oscillating between ~53 and ~67 m. |

No simulation rule, save format, graphics option or player text changes. The
boundary change deliberately trades the farthest 53–67 m band for a constant edge.

## PT boundary measurements

`path_trace_receiver_coverage.gd` renders terrain with its PT blend and eye
distance and reads back the 50% blend distance. Tone mapping, glow, fog and
grading are disabled for the readback.

| Camera | Unchanged | Changed |
| --- | ---: | ---: |
| At the snapshot centre | 66.4 m | 50.0 m |
| 14 m ahead, same snapshot | 52.9 m | 50.0 m |
| After the recentred snapshot is published | 66.9 m | 50.0 m |

## Path-tracing frame measurements

`path_trace_location_walk.gd --pt-location-benchmark`: Ultra preset, live
Foothills location (`gz4g`), first-person camera, NRD, uncapped and vsync off. It
has three rounds of forward and ground views, 180 measured frames each, after 60
settling frames. The fixture now accepts `--pt-qhd` (2560×1440) and `--pt-fg`
(DLSS frame generation). With DLSS selected the Ultra preset enables Ray
Reconstruction, which traces at the full DLSS input size instead of NRD's
quarter-resolution lattice.

Final matched run: one process each in base/changed/base/changed order on the
same executable. Each row shows the range of the six per-block medians across both
processes of that pack.

| Configuration | Unchanged frame | Changed frame | PT controller CPU, unchanged → changed | Main GPU | PT GPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| 3840×2160 output, 1920×1080 internal, NRD | 9.6–11.1 ms | **8.4–9.2 ms** | 2.47–2.91 → 1.75–1.93 ms | 3.1–3.8 ms | 1.5–1.9 ms |
| 2560×1440, DLSS Performance + RR + FG | 11.9–12.5 ms | 11.8–12.6 ms | 2.06–2.42 → 1.46–1.60 ms | 8.9–9.6 ms (includes PT) | 2.4–3.3 ms |

The 4K case is about 12% faster. At 1440p with DLSS, RR and frame generation the
GPU is the limit, mostly raster, RR and frame generation, so the CPU saving does
not change frame time there; it only adds CPU headroom. An earlier 1440p DLSS +
RR run without FG measured 10.1–10.5 ms with main GPU 7.8–8.4 ms. FG was
confirmed active: 3,001 presented frames for 1,503 game presents. With RR, PT
runs inside the main viewport timestamps.

The remaining controller CPU is mainly the native transform tracker (~0.7 ms)
and render submission (~0.5 ms). The pinned DXC compiler is not available on
this workstation, so no ray-tracing shader was changed.

## Loading measurements

`tools/benchmarks/save_loading.gd`, Foothills (`gz3g`) with PT, 1280×720. It now
accepts `--bench-fps=N` (default 30, unchanged) and `--bench-standby`. Runs used a
60 FPS cap. `reload-0` is the first save load and starts the worker.

| Case | Unchanged | Changed, no standby | Changed, standby |
| --- | ---: | ---: | ---: |
| First save load (worker start) | 12,931 ms | 12,806 ms | **8,246 ms** |
| Repeat load | 6,615–6,650 ms | 6,446–6,488 ms | 6,446 ms |

The standby removes ~4.6 s (36%) from the first load of a session. Covered
gathering shortens the PT gather stage from 664 to 548 ms per reload at 60 FPS.
These are single-machine samples, not a general loading-time guarantee.

A cold application start spends ~4.2 s compiling scripts before the menu
(headless 4.3 s, rendered 6.7 s to the first trace). That cost remains for the
owner process; reducing it needs a structural change to the script dependency
graph.

## Regression evidence

Three cases are registered in `tools/regressions.json`. Each fails against the
unchanged pack on the same engine:

| Case | Unchanged pack | Changed pack |
| --- | --- | --- |
| `path_trace_cpu_caches` | Fails: no single-scan replacement, rescans continue (2 failed assertions, then an access violation at exit) | 14 checks |
| `local_host_standby` | Fails to compile: no standby API | 24 checks; takeover of a booted standby 244 ms, discarded standby exits in 361 ms |
| `path_trace_receiver_coverage` | Fails: boundary 66.4 → 52.9 → 66.9 m | 7 checks; 50.0 m in all three cases |

Related existing regressions on the final pack: `path_trace_controller` (49),
`path_trace_lifecycle` (168), `path_trace_retirement` (29),
`path_trace_loading_recenter` (14), `path_trace_figure_live` (8),
`path_trace_figure_continuity` (42), `first_person_models` (11),
`save_load_render_cache` (27), `local_host_clock_resync` (13),
`local_host_shader_stall` (7), `local_host_play_clock` (28),
`worker_travel_clock_rendered` (29), `worker_rate_presentation_rendered` (21),
`crash_report_hover` (51), `loading_worker_budget` (4), `picking_figures` (1,403),
`path_trace_terrain_horizon` (25), `path_trace_cover_receivers` (65),
`path_trace_material_receivers` (7), `path_trace_grazing_normals` (44),
`path_trace_ground_irradiance` (97), `path_trace_water_bounds` (12),
`path_trace_terrain` (120), `path_trace_rr_guides` (95),
`path_trace_handoff_deltas` (50) and `path_trace_zone_traversal_river` (50).
All passed with zero failures, no `ERROR`/`SCRIPT ERROR` lines and exit code 0.

Python was installed later in the session (3.13.15). `tools/check_regressions.py`
only set `XDG_*` variables, which Godot on Windows ignores, so a case could read
and write the player's real `%APPDATA%` profile. Staging also re-encoded test
scripts with the system code page. The runner now also sets `APPDATA` and
`LOCALAPPDATA` inside each case profile and reads/writes UTF-8. Two new runner
unit tests fail against the previous runner and pass now (13 runner tests in all).

With the corrected runner, `--packaged` on the same engine passes nine headless
cases: `worker_travel_clock` (29), `crash_report_hover` (51),
`local_host_clock_resync` (13), `local_host_shader_stall` (7),
`local_host_play_clock` (28), `picking_figures` (1,403),
`path_trace_figure_continuity` (42), `first_person_models` (11) and
`loading_worker_budget` (4). The runner still requires GPU Lab for rendered
cases. Rendered cases ran through a local PowerShell harness instead. It
reproduces the runner's arguments, isolated profile and verdict rules: one
summary line, `min_checks`, zero failures, no error lines and exit 0. They ran
directly on the Windows desktop. `test_regression_runner.py` and
`test_path_trace_build_inputs.py` pass. `test_path_trace_qualification.py`
imports the Linux-only qualification runner (`fcntl`). Translation coverage
reports 3,570 entries and zero errors. Linux/Vulkan, Android and macOS were not
run. The standby path is desktop-only by design.

## Original-game comparison

The original executable has no path tracer, no separate simulation process and
no script compiler. A Wine comparison is therefore not applicable to these
changes. Simulation, saves and timing are unchanged; the standby only moves
the existing worker startup earlier.
