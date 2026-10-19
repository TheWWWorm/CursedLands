# Session performance diagnostics

Local validation on 19 October 2026, based on `233ba3b9`. The earlier
[sustained co-op run](../magic-refresh-lifetime-20261019/README.md) and
[full Trials/restart comparison](../session-retention-20261019/summary.json)
remain separate evidence. This change adds diagnostics; it does not establish
or fix the cause of the reported large restart-sensitive FPS loss.

## Captured evidence

The existing local game log now receives a `PERFORMANCE` JSON record every
30 wall-clock seconds, at campaign load/menu transitions, and immediately
before the existing report export. It records:

- Process ID, wall-clock interval, drawn frames, average interval FPS and
  recent FPS; frame cap, focus, pause, simulation speed and process timing.
- Actual window size, render scale, renderer, anti-aliasing and VSync state,
  together with the existing graphics/options summary.
- Global node, object and resource counts; supported heap/graphics allocation
  counters, draw calls and primitives.
- Live world count, per-world authority/presentation state, unit/corpse
  bookkeeping, simulation debt, pending inputs, effect and spell timers.
- Existing model, mesh, texture, derived-material and wound-cache entry counts.

Snapshots contain only plain values. The sampler has no frame callback,
viewport readback, renderer timing query, screenshot capture or network request.
World membership uses a scene-tree group; sampling cannot create ParticleFx,
keep a world alive or change gameplay/quality settings. At most 64 world
details are included, while the total remains exact. Existing log retention
and report controls are used; there is no new UI option or untranslated label.

The existing **Export log** action includes this history. For a slowdown,
exporting before restarting preserves the affected process's current state.
On a co-op client the world is a presentation replica; the host's private
authority writes its own ordinary worker log. A frontend report does not
currently bundle that separate worker log.

## Interpretation limits

Graphics counters describe renderer allocations, not resident GPU memory or
the size of an asset cache. Unsupported nonpositive memory/timing counters
are `null`, not evidence of zero allocation/cost. Headless processes draw no
frames, so their interval FPS is `null`. The debug-only orphan count is also
`null` in release builds.

A transition sample occurs at the transition trace and may still contain
the departing world. An interval spanning loading, a menu, a pause or a speed
change is not a steady-play FPS comparison. Use the surrounding timestamps,
worlds and settings. Cache entry counts do not measure bytes; process and
physics timing are recent engine counters, not interval averages.

## Verification

`tools/tests/performance_log.gd` covers registry entry/removal/re-entry,
world destruction, non-retention, exact timer observations, unchanged settings,
headless authority sampling without creating effects, unavailable counters,
bounded output, wall-clock cadence at 2x, pause/resume, stopping and the existing
report export. It passes 20 checks in the editor runtime and exported runtime.

`tools/benchmarks/menu_performance_log.gd` is a targeted rendered integration
fixture. It opens Trials using its main-menu button, sets up one populated
late-round battle, exits through the Trials menu button, loads a saved deep
Suslanger campaign using the ordinary save handler, plays for 95 seconds,
and exits through the campaign signpost and confirmation dialog. This is not
a full tournament or a replacement for the earlier sustained gameplay tests.
It uses an isolated user directory and a copy of the diagnostic save.

The final fixture passes all 20 integration checks with no script/engine
errors. It observes 0 gameplay worlds in the initial menu, 9 in the populated
Trials battle, 0 after leaving Trials, 1 in the campaign, and 0 after the
confirmed campaign exit. Both private workers terminate. The menu node count
returns to the same 886 after each exit; no manual cache purge is used.

During the campaign portion the equipped hero travels 70.8 m beyond the loaded
deep-map position, with three additional authored enemy deaths and 765 health
remaining. Eight cast commands are attempted. These are integration-fixture
observations, not another sustained two-client FPS comparison. The normal
periodic records and a final zero-world snapshot appear in the exported report.

The initial fixture run incorrectly required exactly 2.0 from a standalone
campaign's accelerated dial. The original standalone clock uses 55/27
(approximately 2.037); co-op uses exactly 2.0. Only the test expectation was
corrected, then the complete fixture was rerun in a fresh user directory. The
initial failed assertion and its evidence are retained separately.

Constructing six snapshots took 0.162–0.304 ms each in the final fixture.
This excludes JSON serialization and log writing; it is not a frame-time
overhead benchmark. Artifact hashes are recorded in `summary.json`; raw logs,
the exported report and a campaign screenshot are retained alongside this file.
