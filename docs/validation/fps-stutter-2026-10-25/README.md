# FPS and stutter investigation

The supplied `CursedLands-report-20261025-002241.txt` confirms sub-40 FPS
samples and uneven pacing. It does **not** establish that this slowdown has the
same cause as the earlier loading crash. No frame-rate fix is claimed here.

## What belongs to this session

The report covers client session `e2ff563f7527`, version 1.28.0, on an RTX 4090
Laptop GPU, using Direct3D 12 / Forward+ at 3840×2160 and render scale 1.0.
The recorded frame cap and VSync are off. There are 120 performance records and
17 loads across five Lost in Astral maps. [Extracted evidence](report-summary.json)
retains the report hash, original line numbers and measurements without copying
the private report wholesale.

The preceding crash belongs to session `99e2d7cc779a`, whose log was rotated as
`godot2026-10-24T23.40.44.log`. Its entire error tail in this report is already
present in the previously supplied `CursedLands-report-20261024-234059.txt`.
Those descriptor-heap, null-uniform and device-removal messages are **not new
errors during the slow session**. The current log starts at line 2530 and has
no engine/script errors or warnings. The [earlier allocation investigation](../load-crashes-cursor-2026-10-25/README.md)
remains separate evidence.

| Approximate local time | Original line | Observation |
|---|---:|---|
| 23:43:18 | 2560 | `gz1h`: 85.4 FPS interval average; 86 recent FPS; window unfocused at the sample. |
| 23:58:18 | 2626 | `gz2h`: 42.8 average; **35 recent FPS**. |
| 00:14:48 | 2733 | `gz1h`: 50.8 average; **36 recent FPS**. |
| 00:18:18 | 2746 | 1.75 interval FPS immediately after a 16-second load; a 1.14-second sample, with stale recent FPS / engine peak counters. This is not sustained 1.75 FPS gameplay. |
| 00:18:48 | 2747 | After that load: 59.1 average, with a preceding-second engine process peak of 70.8 ms. |
| 00:22:18 | 2755 | Last full gameplay interval: 57.9 average; 59 recent FPS. |
| 00:22:40 | 2762 | Returned to menu: no live worlds, 2,079 nodes and 630 resources. |

Wall times are approximate, reconstructed from the first timestamp and engine
uptime. Across the 62 intervals longer than 20 seconds with one world, two
recent-FPS samples are below 40 and ten recorded process peaks exceed 50 ms.
Some such intervals contain travel/menu actions or end with the window
unfocused. Both sub-40 samples have focus in. Graphics settings are unchanged
across these intervals, but neither camera poses nor focus throughout each
interval are known. The minimum interval average is 42.8. Thirty-second averages
cannot reconstruct hitch frequency, percentile
frame times or every brief FPS drop.

The engine's `process_ms` value is the **preceding second's maximum**, and
includes renderer synchronization/drawing. It is neither a thirty-second mean
nor isolated CPU script time. This was checked in `Main::iteration`, where
`process_ticks` spans main-loop processing, renderer sync and draw, and
`Performance::set_process_time(process_max)` publishes once per second. The
small physics counter belongs to the client; it cannot diagnose host simulation
performance.

## Accumulation checks

- Every settled sample has one world. Two worlds occur only at replacement
  boundaries, followed by the old world's removal.
- Late `gz1h` node counts stay around 35,500–36,500, rather than multiplying
  with reloads. Resource counts stay at 630–635 and return to 630 in the menu.
- Reported graphics allocations rise while new maps/assets are visited, then
  settle around 2.48 GiB late in `gz1h`. Brief peaks at travel/UI/loading do
  not persist. This is the engine's allocation counter, not a complete OS GPU
  residency/budget measurement.
- Figure meshes settle at 2,592; wound layers reach 51, below the source's
  64-entry bounded cache, with no outstanding wound jobs at the samples.

These observations do not demonstrate a retained-world leak or sustained
allocation failure. They also cannot rule out transient allocation pressure,
driver stalls, camera-dependent rendering cost, network snapshot processing,
shader compilation, thermal/power limits or other workload contention. The old
report lacks camera poses, per-frame distributions, GPU timing, pipeline counts
and path-tracing/upscaling/frame-generation settings. There is no matching
post-restart capture at the same camera view.

## Controlled reload replay

The [17-load sequence](pacing-config.json) completed in 609 seconds on an
RTX 3090 Ti through the standard Windows executable, Wine 11.20 and VKD3D 3.1,
at native 3840×2160. GPU Lab job `7d775bf96d6e4249` used automatic GPU selection
and the heavy workload class. The PCK contains the preceding local fixes
(`c577499e`), including increased allocation capacity; it predates the new
logging-only change. [Runtime and source hashes](pacing-provenance.json).

Every settled load retained exactly one world and released its predecessor.
There were no engine/script errors, new draw pipelines during the measured
windows, or frames longer than 50 ms. The worst measured frame was 35.28 ms.
Each measurement lasts eight seconds after three seconds of warm-up and excludes
loading and screenshot readback. [Full measurements](pacing-reloads.json),
[summary](pacing-summary.json), [log](checks/pacing.log).

At the fixed `gz1h` view, the first/last measurements were 90.7 / 81.2 FPS,
with 95th-percentile frame times of 13.9 / 16.2 ms. There is some variation,
including a modest early-to-late slowdown, but no reproduced single-digit or
sub-40 collapse. Node counts remain exactly 37,352 in that view, and late
allocations plateau at 1,631 MiB after visiting new assets. Both the
[first](rendering/pacing-00-gz1h.png) and
[last](rendering/pacing-16-gz1h.png) screenshots were inspected.

This is a live separate-authority frontend, with prepared authored saves and a
fixed camera per map. It is not the player's save, combat history or camera
route, nor a native Windows/laptop benchmark. Standalone accelerated time is
55/27 rather than the co-op log's 2.0. CPU checks overlapped parts of the run;
no precise regression percentage is inferred. Path tracing and frame generation
were explicitly disabled in the fixture because their original states were not
recorded. The replay therefore narrows the evidence to repeated-load behavior
under the tested configuration; it does not establish the stutter's cause or
certify the reported performance fixed.

To repeat with owned archives, prepare isolated saves using
`tools/tests/rendering_reload_fixtures.gd --seed-save=/absolute/test.sav`, then
run `tools/benchmarks/astral_reload_pacing.gd` with
`--pacing-config=/absolute/pacing-config.json` on GPU Lab (`heavy`, automatic
GPU, 6,000 MiB estimate). Keep the isolated profile muted, unconfined and with
FPS shown. The retained command identifies the accepted Windows invocation;
these scripts also support a native Godot renderer.

## Changes to future diagnostics

`PerformanceLog` now collects a fixed-size wall-clock histogram between process
callbacks. Each ordinary export includes mean frame duration, worst frame and
its uptime, counts over 25/50/100 ms, and a labelled **upper bound** for the 95th
percentile. These are engine callback intervals, not generated/displayed-frame
measurements. A deliberate frame cap can legitimately put every interval over
a threshold; the frame cap remains in the same record.

Foreground, background and loading intervals have separate counters. Focus
and synchronous scene transitions discard their boundary gap, so an Alt-Tab or
blocking load cannot be presented as a foreground gameplay hitch. The report
also records the camera pose, rendering driver and requested path-tracing / DLSS
/ FSR options. Requested options do not certify that the corresponding runtime
feature was active.

No render-time queries, image readbacks, unbounded frame arrays, retained scene
references, network calls or graphics-quality changes were added to production.
Counters reset with the existing 30-second/scene/report samples and stop at
shutdown. This improves diagnosis; it is not a claimed correction of the
reported slowdown.

The performance-log scenario is now registered in both regression catalogs.
The focused check is:

```sh
python3 tools/check_regressions.py \
  --engine /absolute/path/to/godot \
  --base-data /absolute/path/to/base-game \
  --only performance_log --output /absolute/path/to/new-results
```

## Validation

The diagnostic scenario passes **42 assertions** headlessly and in rendered
OpenGL, including an actual injected 120 ms stall, bounded histogram storage,
threshold/percentile boundaries, scene/focus transitions, immutable snapshots,
camera teardown, shutdown and ordinary report export. The staged full catalog
also passes the same 42 assertions; these are integration replays, not distinct
additional coverage. The 31 gameplay-runner and seven focused-runner Python
checks pass. The OpenGL run reports the known virtual-monitor EDID diagnostic,
retained separately from game errors.

[Validation metadata](diagnostic-results.json) identifies the retained logs and
source hashes. A [local CPU microbenchmark](cost.json) measured a median
**1.14 microseconds per callback** over nine batches / 180,000 observations;
this is an overhead check on the workstation, not a laptop FPS result.
The repeatable probe is `tools/benchmarks/performance_log_cost.gd`.

Initial fixture parse checks caught two missing explicit variable types; they
were corrected before the accepted executions. No failed attempt is counted as
passing validation.
