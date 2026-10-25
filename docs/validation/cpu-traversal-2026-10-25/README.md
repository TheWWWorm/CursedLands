# CPU traversal investigation — 25 October 2026

## Scope and change

The report concerns standard rendering, with Portal dropping to 40–50 FPS.
The starting source is local main `8f8dfd77`, including accepted fixes newer
than the public release. Testing uses the qualified 1.29.0 release engine,
isolated remake profiles, free cursor, visible FPS and muted audio. No player saves,
graphics defaults, simulation cadence, AI rules or release artifacts change.

The first optimization moves nested read-only quest expressions into the
existing C++ GDExtension. It handles arithmetic, comparisons, variables,
`GetObject` and `GetLeverState` without repeatedly entering the GDScript
dispatcher or allocating argument arrays. Unknown operations, special forms,
statements and the scheduler still use the existing interpreter. There is no
cached quest result, object lookup or lever state. Derived VMs keep their
overrides; older native libraries automatically retain the script path.

## Simulation measurements

Each sample executes 600 complete 55 ms world ticks: 33 simulated seconds.
The same candidate pack/library is run with native expressions on or with
`--ei-script-expressions`. Portal uses three samples per mode in reversed
order; the other areas use two. All start from copies of the same respective
authored save, preserve the full population and end with both party members
alive. These are bounded simulation workloads, not rendered FPS benchmarks.

| Area | Actors | Script tick total | Native tick total | Reduction |
| --- | ---: | ---: | ---: | ---: |
| Portal (`gz1h`) | 415 | 3.612 s | 2.697 s | 25.3% |
| Suslanger (`gz2h`) | 323 | 3.069 s | 2.606 s | 15.1% |
| River and Islands (`gz16g`) | 294 | 2.378 s | 1.656 s | 30.4% |
| Dead City (`gz7g`) | 262 | 1.722 s | 1.365 s | 20.7% |
| City Environs (`gz21k`) | 207 | 1.361 s | 1.230 s | 9.6% |

Values are medians of the complete tick totals. The separate full elapsed
windows, per-run ranges and tick percentiles are retained in
[the raw series](logic-series.json) and [summary](simulation-summary.json).
Hardware is Ryzen 9 5950X; these are local CPU measurements, not estimates
for the user's CPU. Other workstation tasks were active. Short samples and
run-to-run variation limit precision, especially outside Portal.

The fixture yields after every five ticks as the existing throughput benchmark
does. Presentation callbacks and wall-time budgets consume work/RNG differently
between separate runs, including repeated runs of the same evaluator. The
state/RNG hashes therefore differ even within a mode; they are retained, not
treated as a deterministic replay or proof of behavioral equivalence. Semantic
equivalence is checked separately in the registered expression test.

A diagnostic Portal run counted 295,925 expression evaluations, 163,623 argument
arrays, 41,331 `GetLeverState`, 44,326 `GetObject` and 48,519 `IsEqual` calls over
600 ticks. This justified the narrow native traversal. Instrumented timings
include substantial probe overhead and are excluded from the table. Native
navigation, perception and unit-state helpers already exist; porting arbitrary
scripts without this distinction would miss work already accelerated.

## Original comparison

REA inspected the original game 1.06 executable, SHA-256
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
The retained evidence is decompiled pseudocode, not recovered original source:

- Scheduler `0x004bf000`, evidence
  `ev_ff394f4ea58f2c5d281ccd5cec4d3d31d44427751773d8c037b7274bf18204f2`:
  separate body/trigger processing.
- Condition gate `0x004bb520`, evidence
  `ev_7ae39984c7233aa98e8e8597b58bd2917f37ddc5120604faffa9448efa128cbc`:
  ordered conditions stop on a false result.
- Numeric dispatcher `0x004b41e0`, evidence
  `ev_45625908966ab65402b05c2e7284b2cd647231318b364e163212b688bbae3b7f`:
  native opcode dispatch and float32 stores for nested results.

These observations support keeping the scheduler and its order unchanged while
removing interpreted expression dispatch. Every numeric node in the new helper
still rounds to float32. RNG, writes and lazy forms delegate without duplicate
argument evaluation.

The original executable was also run under Wine 11.20 in GPU Lab, using a
private prefix and copied configuration. In a fresh Gipat session, the console
statement below displayed `You picked up: Money (17)`:

```text
#0) GiveMoney(0,Add(Sub(Mul(7,3),Div(8,2)),Add(16777217,-16777216))
```

The rounding subexpression contributes zero. A regression asserts the same
17 result in the remake. The private screenshot, config, executable and REA
bundle hashes are in [provenance](provenance.json). Direct arithmetic entered
as a top-level console statement was rejected; those exploratory commands are
not positive evidence. This confirms a numerical boundary, not every quest or
original-versus-remake frame-rate parity. Original Portal gameplay performance
was not measured.

## Compatibility checks

The registered `script_expression_native` check passes 21,575 assertions on
Linux and the Windows release executable under Wine. It compares values,
local/global/campaign writes and RNG consumption from independently restored
inputs; covers float boundaries, object identity/removal, live lever changes,
AST edits, lazy forms, nested mutating fallback calls and derived VM overrides.
The original library fails the new native-implementation assertion. Windows,
Linux and Android ARM64 libraries were rebuilt; Android execution was not
qualified on a device in this investigation.

[Registered checks](registered-checks.json) also cover dialogue/co-op clocks
(12 assertions) and side-quest lifecycle (590). Related release-runtime checks
cover script clocks (1,408), co-op clocks (17), numeric boundaries (20), dead
predicates (16), future queries (1,257), perception (7), hero references (11),
quest waits/save-restore (56), lever save/transition (59), lever flags (240),
zone19 lever quest (12) and Catacomb group lever (26).

The scheduler's 15 assertions pass, with its pre-existing shutdown leak of
three resources reproduced on the original runtime as well. It is recorded
separately from clean regression results. Two initial base-map tests were
mistakenly launched with LiA data; their load failures are excluded and both
were rerun with base-game data. An early expression fixture lacked campaign
state; it was corrected before the clean registered and release checks above.

## Rendered traversal qualification

The unmodified baseline crashed before measurement. The weather geometry fix
from task `01a1723f-99b5-77a3-ae4e-2a02398e8ad2`, commit `18b58726`, removes that
failure. Both rendered comparison packs include that identical `figure.gd`
dependency. The performance change itself does not duplicate the weather fix.

The first repaired load/traversal completed with 415 actors, both party members
alive and 34.76 simulated seconds in a 35-second window. Its viewport was
2880×1800 rather than the requested 1920×1080, and other validation work was
active; it is a crash/movement control, not an acceptance timing comparison.
An intrusive per-function lifetime profiler corrupted its diagnostic process;
it is excluded and replaced by explicit frame-callback timing wrappers.

The matched runs use 1920×1080, 100% render scale, Very High, standard
raster rendering with Mirror water (option 2), path tracing off, no upscaling
or frame generation, normal 1× single-player with its real worker process,
and a 45-second walking/camera route (antialiasing disabled by the fixture).
They run sequentially within one GPU Lab
heavy job on RTX 3090. Each sample retains 415 Portal / 294 River actors, both
party members alive in every census, 16 movement commands, and at least 44.8
simulated seconds. Raw frame timelines, options and complete logs are retained. All controls and
candidates emit the same startup `Parameter "monitors" is null` diagnostic on
the virtual display, without a script error or interrupted traversal.

| Area / order | Evaluator | Whole-window FPS | FPS after first 5 s | p95 after first 5 s |
| --- | --- | ---: | ---: | ---: |
| Portal 1 | Script | 83.77 | 87.20 | 14.84 ms |
| Portal 2 | Native | 81.48 | 84.80 | 15.42 ms |
| Portal 3 | Native | 86.97 | 90.73 | 14.54 ms |
| Portal 4 | Script | 86.59 | 90.11 | 13.92 ms |
| River and Islands 1 | Native | 128.87 | 129.45 | 10.32 ms |
| River and Islands 2 | Script | 126.04 | 128.02 | 10.51 ms |

A roughly 1.4-second startup hitch appears in
these fresh profiles. Both the full window and the window after five seconds
are reported; excluding that hitch is not a claim to have fixed it. Portal's
post-five-second median is 88.65 FPS script versus 87.76 native: effectively
unchanged within run variation. The quest optimization improves simulation
headroom but does not itself resolve the frontend traversal bottleneck.
See [render series](render-series.json) and [run receipts](render-receipts.json).

A separate two-sample resolution probe on RTX 3090 Ti rendered the same Portal
route at 100% and 200% scale (1920×1080 and 3840×2160 internal rendering).
Post-five-second FPS was 87.11 and 89.00 respectively. This supports a CPU limit
for this route, but two resolution samples are not a GPU scaling
curve. The runs ended before the next native build began.
See [resolution probe](resolution-series.json).

## Mechanism picking

An explicit callback profile, followed by a finer Game profile, located a
larger presentation cost: `pick_lever` ran 5,334 times over 2,739 frames and
accumulated 9.31 seconds (about 3.4 ms/frame) in the instrumented run. Cursor
and tooltip queries can see different camera transforms within one frame;
loosening their cache key would return stale bounds. General unit hover
picking was much smaller in this particular route.

`ScreenRectKernel.retained_bounds` now fuses the live morph weights, world
transform and existing exact native clipping/projection into one native call
for small authored mechanism meshes. It reads their retained upload arrays;
there is no new render-buffer readback or cached pose. Skins, multiple surfaces,
missing metadata and meshes over 2,048 vertices retain the existing general
path/cache. Click eligibility, visibility, closest-depth priority and the
existing 40-pixel origin assist are untouched. Existing script-only builds
and older libraries retain their fallback.

The registered `picking_retained` test compares exact integer rectangles for
432 configurations spanning projection modes, indices, triangle strips, near/
far/behind-camera clipping, large coordinates, normalized/relative morphs,
same-frame changes, hidden meshes and fallback cases: 2,209 checks pass on the
Linux editor and qualified Linux/Windows release executables (Windows under
Wine, explicit safe render-thread mode). The prior library fails the
new native-path assertion. A non-gating moving-camera geometry fixture takes
16.5–16.9 ms on the old path and 8.3 ms fused (1,920 part queries per sample).
This synthetic result is separate from complete-gameplay measurements.

Related release checks pass: bounds 432, deformation 1,558, exhausted
interactions 378, real LiA torch 17, and real LiA chest permission/use 32.
Ingos interaction picking passes, but two unrelated reload/late-join lock-state
assertions fail in both unchanged and candidate builds (63 checks, 2 failures).
Those failures are retained in the evidence rather than counted as a clean
suite. An initial Windows headless run used the release engine’s default
separate render thread and emitted dummy-renderer errors despite passing the
assertions; rerunning with the same explicit safe-thread mode as the Linux
launchers passes both new tests without game/renderer errors. Wine emits EGL
probe warnings before startup. The regression runner’s seven Python unit tests
also pass. The initial new fixture used BoxMesh directly in the old bounds oracle,
which only accepts ArrayMesh; it was corrected to upload equivalent arrays
before the clean runs.

Original comparison uses the existing local Ghidra exports in
[the source receipt](original-picking-sources.json). `0x5a7640` and `0x5a7a70`
copy the renderer rectangle after mesh processing; `0x4e9010` sends partly
clipped geometry through TLP +0x94/+0x88 before `0x4e86b0` collects bounds,
while `0x4e8900` collects the wholly-inside projected vertices. Both round to
integer coordinates. This supports preserving real clipped mesh bounds,
rather than substituting box corners. The new Godot retained-array entry point
has no direct counterpart to invoke in the original executable under Wine;
no fresh original picking runtime or FPS parity claim is made.

The uninstrumented 45-second comparisons below run on the same RTX 3090 Ti
inside one GPU Lab heavy job, with order old/fused/fused/old. Both packs already
contain native quest expressions and the identical weather dependency; only
mechanism picking differs. Quality, resolution and route match the previous
rendered controls.

| Order | Mechanism path | Whole-window FPS | FPS after first 5 s | p95 after first 5 s | p99 after first 5 s |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | old | 79.28 | 82.24 | 15.56 ms | 17.59 ms |
| 2 | fused | 91.15 | 94.69 | 13.94 ms | 15.85 ms |
| 3 | fused | 107.96 | 113.28 | 11.78 ms | 13.46 ms |
| 4 | old | 83.87 | 87.19 | 14.77 ms | 17.17 ms |

Median sustained FPS rises from **84.71 to 103.98 (+22.7%)**; median p95 falls
from **15.17 to 12.86 ms**. Including the startup hitch, median FPS rises
from **81.58 to 99.56 (+22.0%)**. There is substantial variation, especially
between candidate runs, but both candidate samples outperform both controls.
This is a two-samples-per-mode local result, not a predicted improvement for
another CPU/driver or proof that every Portal frame meets a target.

Every run simulates 44.88 seconds, issues 16 move commands, retains all 415
actors and keeps both party members alive at every census. The unchanged
simulation speed and quality matter: these measurements do not obtain FPS by
throttling AI or lowering graphics settings. See [the four raw summaries](picking-render-series.json),
[aggregate](picking-render-summary.json), [matching options and run receipts](picking-run-receipts.json),
and the full compressed timelines/logs
under [logs](logs).



## Remaining limits and follow-up candidates

The earlier callback profile also measured particle presentation (~0.57 ms/
frame), ground marks (~0.28 ms), audio scanning (~0.27 ms) and terrain detail
updates (~0.21 ms). These are instrumented, inclusive measurements from this
route, not independent FPS savings to add together. An occasional terrain
callback took 186 ms. These areas deserve more focused profiling before any
further native port; already-native navigation, perception and renderer work
must not be counted as interpreted script overhead.

The local CPU/GPU, Linux Vulkan driver and bounded entrance route differ from
the user's Windows environment. The reported 40–50 FPS dip was not reproduced
at that absolute rate here, and no stable-60-FPS or Windows D3D12 claim follows
from these measurements. Original Portal FPS, every area/view/combat encounter,
and Android device execution remain unmeasured. The existing startup
hitch remains visible in the full-window timelines.

All work is isolated on `perf/cpu-traversal-20261025`, starting from local main.
The separate weather fix must be integrated alongside this work before a
release is qualified. No public release, player profile or remote main was
changed. Local benchmark recipes and fixed fixture paths are retained under
[recipes](recipes); source/artifact and external fixture hashes are in
[provenance](provenance.json).


## Follow-up inventory (after ef6cc817)

The user requested continued work through the remaining legitimate CPU targets.
This inventory separates measured costs from hypotheses; none of the open rows
is a promised FPS improvement. GPU Lab job `45d739a3b90f468c` ran 35 seconds each
in Portal, River and Islands, and City Environs on the same RTX 3090 Ti. The
qualified engine, settings and weather fix match the earlier candidates. This
is an instrumented diagnostic build, not an acceptance FPS measurement. Values
are inclusive microseconds divided by frontend process frames; nested rows
must not be added together.

| Work | Portal ms/frame | River ms/frame | City ms/frame | Status |
|---|---:|---:|---:|---|
| Mechanism picking | 1.851 | 1.224 | 0.469 | Open: split geometry, eligibility and loop overhead |
| Hidden actor presentation | 0.436 | 0.174 | 0.126 | Open: identify expensive pose work without reducing update rates |
| Particle presentation including simulation | 0.560 | 0.465 | 0.331 | Open: census by emitter type; several types already native |
| Ground marks | 0.324 | 0.182 | 0.133 | Open: separate animation events from projection refresh |
| Unit sound scan | 0.245 | 0.143 | 0.109 | Open: preserve cue timing and RNG order |
| Daylight update | 0.245 | 0.066 | 0.120 | Open: inspect repeated parameter work |
| Terrain detail updates | 0.213 | 0.200 | 0.143 | Open: includes one 330 ms River callback |
| Ambient life | 0.058 | 0.052 | 0.365 | Open: city-specific resident/particle cost |
| Cloud preparation | first call 185 ms | first call 186 ms | first call 186 ms | Open: resource setup occurs after loading |

The approximately 1.4-second startup stall was previously described as a
first-movement hitch. The raw phase-two timestamps disprove that attribution:
the worst frames end at 2115, 2171, 2212 and 2142 ms; the first movement commands
are issued at 2122, 2179, 2221 and 2149 ms. The stall delays the first command.
The benchmark camera is already rotating, so renderer preparation remains a
hypothesis, not a confirmed cause. It is not explained by the 185 ms cloud
callback alone. Further frame-phase and pipeline measurements are required.

Hardware sampling with `perf stat -e task-clock true` is unavailable on this
workstation (`perf_event_paranoid=4`, permission denied). The explicit function
profiles avoid changing workstation security settings.


### Mechanism loop batching and deeper attribution

The deeper profile (`fb34652891ce4a78`, RTX 3090, 20 seconds/area) measures
449,120 retained-part queries across 1,672 Portal frames: roughly two passes
over 140 parts belonging to 82 usable mechanisms. Geometry takes 1.06 ms/frame
(including 0.24 ms in the general fallback); permission checks take 0.18 ms,
and the full picker takes 2.00 ms. Instrumentation adds overhead relative to
the earlier profile. The loop and call boundary remain legitimate targets.

`ScreenRectKernel.pick_mechanisms` now batches that loop. It calls the existing
`LeverSystem.usable` predicate in insertion order, uses the same exact retained
bounds, and calls the existing general path for unsupported geometry. Part
depth, ties, exclusive right/bottom edges and the 40-pixel origin assist are
unchanged. No eligibility, scene references or query results are cached by
this helper. Older libraries and custom permission scripts retain the script
loop. Linux, Windows and Android ARM64 native binaries were rebuilt.

The new registered `picking_mechanisms` test passes **5,205 assertions** on
Linux and on Windows under Wine 11.20. It compares live camera, morph,
visibility, permission and fallback changes to the pre-existing script loop
and separately asserts boundary/tie cases. The prior library fails the new
helper-presence assertion (1 check, 1 failure). An isolated Linux
workload takes 27.229/26.788 ms with the script loop and 21.706/21.903 ms with
the native loop, about 19% less time; this is not a whole-game FPS result.

Related Linux checks pass: retained bounds (2,209), clipping bounds (432),
deformation (1,558), base interaction permissions (378), LiA interaction and
lift recall (2,391), real LiA torch (17) and chest (32). Ingos has the same two
snapshot assertions failing as the frozen baseline documented above; its
picking checks pass. Windows retained bounds also passes 2,209 assertions.
The regression runner's seven Python checks pass. Android execution is not
available on this workstation.

The original-code comparison remains the inspected renderer path at
`004e9010` and exact projected-vertex rectangle collectors at `004e86b0` /
`004e8900`, copied by `005a7640` / `005a7a70`. Batching does not replace those
geometry rules. Native permission evidence is also retained in
`tools/tests/fixtures/original_lever_use.json` and exercised by the interaction tests.
A Wine comparison of this specific script/native boundary is inapplicable:
the original executable has no Godot meshes or this dispatch boundary. The
prior original Wine expression observation is retained above; no original
Portal FPS or new original picking-runtime measurement is claimed.

The emitter census changes the remaining priorities. In Portal, fire
`0x2003`, campfire `0x2001` and tornado `0x200a` account for most particle work
and already have native kernels. Per-emitter worker timings overlap and must
not be added to frame time. In River, still-scripted exit stars `0x2038` and
wisp ambient stars `0x204d` cost 0.174 and 0.149 inclusive ms/frame. City exit
stars cost 0.124 ms/frame. City's ambient resident movement accounts for
0.317 of its 0.368 ms/frame ambient-life callback; its repeated authored
terrain-triangle queries are a candidate for a focused native geometry helper.
These targets remain open pending differential tests and measured benefit.

A separate phase trace (`5f20ff0f2cdd472a`) places the 1.437-second startup
stall between `frame_pre_draw` and `frame_post_draw`. In that same frame,
pipeline counters increase by 16 surface, 10 draw and 11 specialization
pipelines. This confirms rendering-phase work, correlated with pipeline
preparation; it does not yet identify the responsible material/mesh variant.
The reported delayed viewport GPU time is about 2.75 ms and is not a timer
for that stalled CPU interval.


### Matched standard-rendering traversal after loop batching

GPU Lab job `3b697832e68442da` completed eight 45-second runs on RTX 3090 Ti.
Both modes use the same PCK and native library; a benchmark-only switch selects
the existing script loop or the native batch. Portal runs script/batch/batch/
script, River batch/script, and City script/batch. Options hashes match across
all eight runs (1920×1080, 100% render scale, standard rendering, same Very
High preset and anti-aliasing override).

| Area | Script loop FPS after 5 s | Native batch FPS after 5 s | Change | Evidence |
|---|---:|---:|---:|---|
| Portal | 91.73 | 109.60 | +19.5% | Median of two runs/mode; every batch run exceeds both controls |
| River and Islands | 142.91 | 142.77 | −0.1% | One pair; effectively unchanged |
| City Environs | 152.08 | 171.79 | +13.0% | One pair; preliminary |

Portal p95 frame time improves from 14.60 to 12.95 ms. Its full-window median,
including startup stalls, improves from 87.75 to 104.44 FPS. These are local
Linux measurements, not predicted Windows FPS or a cumulative percentage to
multiply by earlier experiments on different run conditions. All census
samples retain the expected 415 / 294 / 207 actors, both controlled actors
remain alive, and every run issues 16 movement commands at normal simulation
speed. This phase adds the loop improvement to the earlier retained-geometry
and expression changes; those are present in both controls.

Final review added a null-system guard for an empty world before mechanisms
are initialized. This is the only script difference between the timed and
final runtime packs, recorded verbatim in [provenance](mechanisms-provenance.json);
every timed world has a valid mechanism system. The final regression also
asserts that the production query dispatches exactly one native batch. Final
Linux and Wine tests use these guarded packs, with the same compiled native
libraries used for the timings.

See [the aggregate](mechanisms-render-summary.json),
[all eight results](mechanisms-render-series.json) and
[settings, census and command receipts](mechanisms-run-receipts.json).
The original-code comparison, raw phase traces and remaining-target inventory
above remain part of this work. The mechanism script loop is complete; the
remaining measured particle, ambient-ground, actor-presentation and startup
resource costs are still under investigation.


### Streamed vegetation and remaining CPU targets

A follow-up diagnostic profile (`dc6deca54ad14a17`, RTX 3090 Ti) wraps 205
script methods. These inclusive timings include instrumentation overhead;
worker timings overlap and nested rows must not be added together.

| Scope | Portal ms/frame | River ms/frame | City ms/frame |
|---|---:|---:|---:|
| Mechanism picking after native batching | 1.444 | 0.934 | 0.378 |
| Unit frame presentation | 0.740 | 0.606 | 0.318 |
| Hidden-presentation scheduler | 0.630 | 0.236 | 0.177 |
| Animation flush (included in presentation) | 0.303 | 0.130 | 0.114 |
| Ambient-life processing | 0.063 | 0.056 | 0.399 |
| Ambient terrain-triangle search (nested) | 0.019 | 0.018 | 0.261 |

The admission trace in that job records the first grass, biome cover,
stone-contact and mound meshes in frame 15,682. Its pre/post-draw interval is
**1,387.353 ms**, with +16 surface, +10 draw and +11 specialization pipelines.
The benchmark has not issued a movement command yet, although the camera is
already turning. Delayed viewport GPU/CPU timings do not measure this stalled
interval. The earlier independent phase trace measured the same stall at
1,437 ms.

The biome-cover-off control (`21bdc02e6e7f419e`, RTX 3090) has no comparable
stall: its maximum pre/post-draw interval is 15.543 ms. This is an isolation
control, not a quality-reduction fix or an FPS comparison. Its device differs
and it overlaps another task's Dar Leanos run; neither whole-game throughput
nor a precise speedup is inferred from that control.

Inspection found that loading-time preparation included loose leaf/stone
layouts but omitted the distinct contact and mound shaders/layouts. Loose
cover also used the default one-sided shadow setting, while streamed chunks
use double-sided casting. The change adds collapsed representatives for both
missing layouts and carries the actual shadow setting through admission,
deduplication and drawing. It does not generate chunks or alter placement.

The registered `vegetation_warmup` regression compares representatives with
production geometry builders and installed chunks for inland, sea and cave
combinations. It checks the full vertex formats, material identities, shadow
states, per-light draws, cache separation, option gates, unchanged placement
data/RNG and absence of streaming work. It passes 124 checks on Linux and on
Windows under Wine 11.20. The unchanged previous pack fails all four missing
coverage assertions (16 checks, 4 failures), without parse or runtime errors.
The existing stone-contact geometry test also passes 26 checks under Wine.
The final frozen pack also passes the same 124 layout checks and 26 contact
checks. Arena preparation passes 27 checks. Campaign preparation completes
42 checks with the same two screenshot-cover failures on both the previous
and corrected packs: `fsr2-pre-presented` and `terrain-pre-presented`. Their
captured corner error and text samples are identical. These pre-existing
presentation failures remain recorded; no assertions were relaxed.

In the matched Portal pair (`55ee717ff8224089`, RTX 3090), the first streamed
cover frame takes **1,466.660 ms before and 46.177 ms after**. The graphics
options hashes, 1920×1080 output and 100% render scale match; standard
rendering, all 415 actors and normal single-player simulation remain enabled.
Both runs issue four movement commands and both controlled actors stay alive.
This is removal of a startup freeze, not a steady-state FPS claim. The total
10-second sample still includes other startup work, including cloud setup.

The first cover frame still increments the same 16 surface / 10 draw / 11
specialization counters. Preparing the missing shaders/layouts removes the
long compilation cost; this is not a claim that every subsequent pipeline
creation is eliminated. The test also reapplies viewport settings after load,
so these remaining counters are not a direct measurement of ordinary loading
with already-applied player settings. See the [paired summary](vegetation-pair-summary.json),
[pack provenance](vegetation-provenance.json) and compressed raw traces.

An original-runtime comparison of these warm-up pipelines is inapplicable:
this biome-cover/contact/mound system and Godot's pipeline preparation are
remake additions. No original terrain, placement or gameplay behavior is
changed, and no original-game FPS comparison is claimed for this change.


### Ambient creatures' terrain queries

The next measured script target is the ordered 3×3-cell triangle search in
`AmbientHabitats.ground`. `AmbientGroundKernel` performs that search in one
native call, borrowing the current terrain arrays without retaining a terrain
snapshot or query cache. It preserves the highest triangle, scan/tie order,
authored XY offsets, normal, material code/type, edge tolerances and scalar
rounding. Visible loose-ground elevation stays in its existing script callback,
before selecting the highest result. Missing libraries and unsupported arrays
keep the complete script implementation. The grass helper cannot substitute for
this search: it uses different first-hit and boundary rules.

The registered `ambient_ground_native` regression passes **5,117 checks** on
Linux and Windows under Wine 11.20. It checks exact result dictionaries on
folded/jittered triangles, shared boundaries, drawn ground, live terrain/material
edits, full-width material types, collapsed triangles, invalid inputs and both
fallbacks. The previous frozen pack fails the missing-native assertion cleanly
(one check, one failure). For 3,000-query batches in script/native/native/script
order, Linux native authored-height queries take 6.2–6.3 ms versus 65.4–66.3 ms;
drawn-height queries take about 10.0 ms versus 68.3–69.8 ms. Height sums agree.

GPU Lab job `7f28b87e4a184e52` then compares both dispatch paths in the same
instrumented pack on City Environs. Only three functions are wrapped. Standard
rendering, 1920×1080, 100% scale, options hashes and 207 actors match; both runs
issue six movement commands at normal speed and keep both controlled actors
alive. These inclusive scopes are nested, so their savings must not be added:

| Scope | Script ms/frame | Native ms/frame |
|---|---:|---:|
| Ambient terrain query | 0.2394 | 0.0787 |
| Drawn-ground elevation, included above | 0.0497 | 0.0500 |
| Entire ambient-life callback | 0.3570 | 0.1972 |

The entire callback saves **0.160 ms/frame**, approximately 45% on this route.
Average ground-query cost falls from 37.61 to 12.18 µs including the unchanged
drawn-ground callback. Whole-window FPS is 174.63 versus 186.22, but this is one
instrumented pair and another task records on the other GPU during part of it;
it is not a controlled whole-game FPS claim. The query benefit applies wherever
ambient creatures use it; earlier profiles show much less such work in Portal
and River. See [the normalized scopes](ambient-profile-summary.json),
[validation receipts](ambient-checks.json), [provenance](ambient-provenance.json)
and compressed raw results.

The related actual LiA ambient-life regression passes 108 checks. Base campaign
ambient-life reports the same three failures on both the previous and corrected
packs (136 checks each): loose-ground shader-profile assertions for small
animals in `gz4g`, `gz9g` and `gz18h`. Those assertions inspect the unchanged
drawn-ground profile; they do not compare the native query. They remain recorded
without relaxing coverage. Windows vegetation preparation still passes 124
checks, and the regression runner's seven Python tests pass. Linux, Windows and
Android ARM64 native libraries are rebuilt; Android has not been run on a device.

The ambient wildlife/loose-ground system is a remake addition, so comparing this
specific query boundary in the original executable under Wine is inapplicable.
The change retains the authored triangle data and existing query semantics; it
does not alter original gameplay navigation. No original ambient-performance
measurement is claimed. Original expression/picking comparisons above remain
separate evidence. Particle loops, actor presentation and cloud startup remain
open measured targets.

### Exit and wisp particle updates

`StarParticleKernel` moves the existing per-particle update and stable removal
pass for exits (`0x2038`) and wisps (`0x204d`) into one native call. The original
spawn callbacks still handle terrain, carrier state, gait, death and emission.
It preserves exact particle fields, interpolation, random draws and order.
Derived emitters, custom callbacks and older libraries retain the scalar path;
`--ei-script-stars` selects it explicitly. Exit workers and main-thread wisps
keep their existing ownership rules. No particles or updates are omitted.

The registered regression passes **17,473 checks** on Linux and Windows/Wine,
including concurrent exit emitters, lifecycle boundaries, changing settings,
carrier transitions, callbacks and fallback. The preceding pack fails the
native availability assertion. An initial exact comparison found a one-ULP
difference in Godot's parsed wisp RNG multiplier; the helper now uses its exact
binary value, and the assertions remain exact. Related fire (43,389), spell
(101,055), original wisp callback (4,428) and Linux ambient-ground (5,117) checks
pass. The actual rendered wisp lifecycle/combat fixture passes 438 checks on
all three wisp skins (GPU Lab `3d449cf4fb444489`). Android ARM64 is rebuilt,
but has not been executed on a device.

GPU Lab `7984b610e5764f6e` compares script/native dispatch in the same diagnostic
pack on River: standard rendering, 1080p/100%, identical options, 294 actors,
six movement commands and normal speed. Average exit update cost falls from
845.9 to 438.4 µs/call; wisp update cost from 38.52 to 25.17 µs/call, including
unchanged spawning. Total main-thread particle processing falls from 0.3448 to
0.3041 ms/frame. Worker sums overlap wall time and must not be added to this.
Whole-window FPS is effectively unchanged (163.09 versus 163.44); this single
instrumented pair is evidence of a smaller CPU cost, not a whole-game FPS gain.
The isolated 600-tick Linux fixture takes 226–234 versus 88–89 ms for exits and
10–11 versus 4.7–4.8 ms for wisps. See [scopes](star-profile-summary.json),
[checks](star-checks.json) and [source/runtime provenance](star-provenance.json).

Original English v1.06 `game.exe` (SHA-256
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`)
has the matching exit factory at `0x48783b`, spawn at `0x492d30`, update at
`0x492f40`, and wisp update at `0x4961b0`. Disassembly confirms lifetime,
alpha-table order, 0.05 exit rise, atlas cycle and wisp RNG/size behavior.
The remake adapter's existing field layout and precision are retained.
The original wisp replay fixture continues to pass. The saved
[REA evidence](star-original-rea-snapshot.json.gz) records the addresses and
bytes. A controlled original-instruction Wine harness was attempted, but Wine
could not map the required `0x490000` address (exit 5); its receipt is retained.
Thus the new evidence is original code plus controlled replay, not a successful
full original-game Wine particle observation or original FPS measurement.

### Cold cloud preparation before gameplay

The remaining first-frame terrain scope contains synchronous volume-noise
setup. Terrain graphics initialization precedes active-world attachment, so
its atmosphere callback correctly declines to publish an inactive world.
`Game.attach_world` now publishes the destination cloud frame after its weather
and daylight are attached, before the loading cover's shader preparation.
This moves resource creation into loading without changing volume quality,
cloud phases, time advancement or active-world ownership.

The registered rendered `cloud_load_preparation` test uses the actual campaign
attachment with cold resources. It fails 8 of 11 checks before the change and
passes all 11 afterward. The first explicit terrain atmosphere callback takes
204.109 ms before (203.911 ms setup) and 0.075 ms afterward; the 196.521 ms cold
setup now happens during attachment. These are boundary measurements on a
fixed test, not an FPS comparison. Retained-world reuse, cave clearing,
sheet-only clouds and disabled ownership also pass. The related cloud
analytic/lifecycle fixture passes 29 checks. See
[checks and timings](cloud-preparation-checks.json) and
[pack provenance](cloud-preparation-provenance.json). Both rendered runs emit
the already recognized GPU Lab missing-EDID refresh-rate diagnostic; neither
has a script error. This Godot volumetric-cloud system is a remake addition,
so an equivalent original-game Wine callback comparison is inapplicable.

### Dar Leanos actor bounds after integrating local main

Local main `42e3365f` was merged into this branch as `62c59000`, preserving the
other task's Dar renderer, hidden-pointer, crash and solo-authority changes.
The location is LiA `gz31j`, with 334 actors. The first standard-rendering
diagnostic route spends about 2–3 ms/frame in per-part screen bounds. Actor
queries also rebuild their ordered rectangles and union in script, despite
the individual geometry helper already being native.

`ScreenRectKernel.figure_rects` now handles that ordered actor query in one
native call. It uses the same exact current morph/transform/clipping helper;
unsupported geometry returns to `MeshScreenRect.of_context`. Visibility, part
order and integer union are unchanged. No pose, actor or selection result is
cached, and no actors, updates or geometry are removed. Older libraries and
`--ei-script-figure-picking` use the complete previous loop.

The registered `picking_figures` test passes **1,403 exact checks** on Linux
and Windows/Wine, and another 1,403 with actual LiA models on Linux. The
previous pack fails its missing-helper assertion cleanly. Coverage includes
production dispatch, authored human/winged idle/walk/attack/death poses,
same-frame transforms and morphs, perspective/orthogonal/frustum views, hidden
parents, deleted/non-mesh rows, skins, multiple surfaces, missing metadata and
missing-library fallback. Related retained (2,209), mechanism (5,205), bounds
(432), deformation (1,558), touch selection (1,352) and arena selection (3,331)
checks pass on both Linux and Windows/Wine. Linux, Windows and Android ARM64
libraries are rebuilt; Android has not been executed on a device.

In the isolated 360-query fixture, stationary-camera work takes about 34.2 ms
with the previous loop and 20.2 ms with the batch; moving-camera work takes
85.0–85.2 ms and 20.9–21.0 ms respectively. These are CPU microbenchmarks,
separate from the real traversal below. In the diagnostic Dar pair, actor
screen rectangles take 3.615, 3.385, 2.889 and 2.387 ms/frame on the four walking
legs before, versus 0.930, 0.725, 0.637 and 0.492 afterward. Instrumentation
adds overhead, and inclusive nested scopes must not be added together.

GPU Lab heavy job `73c7b3d8b6a643e4` then runs the **uninstrumented production
pack** in script/native/native/script order on one RTX 3090 Ti. All four runs
pass 54 assertions, reach every waypoint, keep controls and solo authority
alive, and record no route detours or blocked frames. The initial save, options
hash, 334-actor population and 1920×1080 window match. Very High standard
rendering retains soft ground, volume clouds and mirror water at 100% render
scale; PT, RT lighting, reconstruction and frame generation are disabled.
Real W input drives the production first-person camera and normal simulation.
God mode and neutral diplomacy isolate traversal. No per-phase PNG encoding,
video capture, CPU builds or other checks run during these measurements.

| Walking leg | Previous FPS | Native batch FPS | Previous p95 ms | Native batch p95 ms |
|---|---:|---:|---:|---:|
| 0 | 53.26 | 65.01 | 25.11 | 20.28 |
| 1 | 63.22 | 81.75 | 22.29 | 16.83 |
| 2 | 71.06 | 83.33 | 18.62 | 15.53 |
| 3 | 51.36 | 55.25 | 25.15 | 22.92 |

Across walking phases, total rendered frames divided by total wall time rises
from **59.73 to 71.47 FPS (+19.65%)**. The individual before runs are 59.76 and
59.70 FPS; afterward they are 72.42 and 70.53. Table p95 values average the two
per-run percentiles, rather than claiming a pooled percentile. This isolates
the actor batch on top of the combined source; it does not measure all earlier
CPU changes again. It is not a prediction for another CPU, Windows/D3D12 or
every zone. The largest walking frame is 31.21 ms before and 32.96 ms after,
so this is not a claim that every isolated stall is eliminated.

The same projected-vertex and integer-rectangle contract is confirmed in the
original executable's `5a7640`/`5a7a70` and `4e9010`/`4e86b0`/`4e8900` paths;
see [the original source evidence](original-picking-sources.json). This change
only batches the already-validated geometry calls. A fresh original-game Wine
Dar traversal comparison was not performed: the remake's first-person route
and synthetic mesh/pose fixtures have no equivalent original entry point.
The Windows/Wine results above execute the remake. Original runtime/FPS
equivalence remains unmeasured.

The separate tactical diagnostic is retained as a **failed** run: 54 checks,
one failure because five frames on walking leg 1 activate the shader preparation
barrier. All waypoints are reached, but that does not satisfy the unchanged
continuous-control assertion. It is excluded from the accepted comparison.
The remaining native-pair scopes include about 0.82–0.94 ms/frame in ground
marks, 0.44–0.51 in direct-pose composition and 0.68–1.10 in animation flushing;
these remain investigation targets. The other task's synchronous PT candidate
activation is a separate path from this standard-rendering improvement.

See [the six-run comparison](dar-figure-comparison.json),
[exact checks](figure-checks.json), [build/source provenance](figure-provenance.json)
and the compressed raw logs, per-frame render metrics and scope captures.
The maintained `dar_leanos_standard_route` uses the same fixed waypoints with
standard rendering; the existing PT route retains its PT/native-NRD assertions.
Both registered routes pass **54 checks** on the combined production pack.
The same registered run passes cold cloud preparation (11), actor bounds (1,403),
solo clock resynchronization (13), recovery from a 90-second blocking shader
stall (7), and play-clock behavior (28). The runner's eight Python checks pass.
See [registered integration results](dar-integrated-registered.json).

The earlier merged-source headless selection also passes expressions (21,575),
retained bounds (2,209), mechanisms (5,205), vegetation preparation (124), ambient
ground (5,117), star particles (17,473) and the revival overlay (9); see
[its receipt](merged-main-headless-registered.json). A first invocation omitted
`--packaged`, so the release runtime rejected `--path` before executing tests;
the [failed setup receipt](merged-main-runner-setup-failure.json) is not a game
regression. All current game scripts, shaders, scenes, resources and native
libraries were compared with the measured export snapshot without differences.

Follow-up GPU Lab `0708e54d364e496c` identifies the tactical interruption as
delayed **mirror-water preparation**. Its initial request stays pending with
no visible plane; on walking leg 1 the first visible plane advances the water
preparation serial from 0 to 1, coinciding with the preparation cover. The
cover remains active for about 57 ms after the diagnostic observes it. The
two-leg fixture fails the same continuous-control check (36 checks, one
failure); see [the diagnostic receipt](dar-tactical-water-state.json). This
is not included in the FPS results, and no water-preparation guard has been
removed. Preparing that first real reflection during loading remains a
separate investigation from the native actor-bounds change.

## Direct-control animation sampling

On integrated source `2a912713`, a further Dar profile identifies about
0.33 ms/frame in the per-track `DirectPose.sample` loop while walking. The
native `DirectPoseKernel` batches the same engine interpolation and ordered
quaternion composition. It retains only track paths/types, synchronously
invalidated by `Animation.changed`; current nodes, authored parents, values
and sample times remain live. Weak source references, a 64-clip limit,
512-track limit and 65,536 path-character limit bound retained metadata.
Eviction and destruction disconnect invalidators. Unsupported/scripted clips
decline the complete query, preserving the existing script fallback. The
`--ei-script-direct-pose` diagnostic also keeps that loop. Clip choice, blend
weights, gait timing, movement, pose application and shadow updates are unchanged.

The first experiment used dynamic engine calls and was slightly slower than
script (roughly 115 versus 111 ms for 600 samples). Typed calls alone took
about 100 versus 112 ms. Reusing unchanged track metadata reduces the final
isolated fixture to **18.1–18.2 versus 110.6–110.8 ms for 600 samples**. These
are sampling timings, not whole-game FPS. The rejected experiments and raw
logs are retained in [the checks receipt](direct-pose-checks.json).

GPU Lab heavy job `3912cd1d4dea40ff` compares script/native sampling in the
same instrumented export, save and fixed Dar route. Both runs pass **54 checks**,
reach all four waypoints without blocked frames or reroutes, and retain the
same 334 actors, options hash and 1920×1080 window. Standard Very High graphics,
mirror water, soft ground and volume clouds remain enabled; PT, reconstruction
and frame generation remain disabled. No CPU builds, other checks or image
encoding run during these measurements.

| Walking leg | Script sample ms/frame | Native sample ms/frame | Script full pose ms/frame | Native full pose ms/frame |
|---|---:|---:|---:|---:|
| 0 | 0.331 | 0.091 | 0.483 | 0.255 |
| 1 | 0.334 | 0.087 | 0.487 | 0.242 |
| 2 | 0.333 | 0.090 | 0.486 | 0.252 |
| 3 | 0.347 | 0.094 | 0.509 | 0.262 |

Weighted by each run's walking frames, sampling takes **0.336 → 0.090 ms/frame**
and the whole pose callback **0.490 → 0.252 ms/frame**. This demonstrates about
0.24 ms/frame less CPU work in this path. Scopes are inclusive and must not be
added. This instrumented pair does not establish an additional whole-game FPS
percentage. The implementation is shared by direct controls in other zones,
including third-person controls, with benefits depending on active pose work.
See [the matched comparison](dar-pose-comparison.json) and compressed raw
scope captures and route logs.

The registered `direct_pose_native` test passes **7,470 checks** on Linux and
Windows under Wine. It compares exact values and key order across all four
quaternion conventions, loop/interpolation modes, authored actions, duplicate
tracks, live track edits/reordering, renames/reparenting, clip replacement,
empty/oversized/scripted animations, cache eviction, resource/helper lifetime,
and script fallback. The prior library fails the availability contract
(one check, one failure). Related gait continuity (1,929), actor picking (1,403)
and star particles (17,473) pass on both platforms; the latter two also run
through the registered Linux runner. Linux rendered checks pass first-person
shadows (28, zero differing shadow pixels), sustained downward running (28),
and Ingos dialogue/footprints/casting (57). The virtual monitor's existing
missing-EDID diagnostic is retained separately from game failures.

The first expanded test incorrectly requested `track_move_down(0)`, which
attempts index -1 in this engine. The fixture now moves valid index 3 and keeps
the same immediate-result comparison. Its initial failure log is retained;
no animation engine guard or production behavior was changed for that setup
error. All runtime scripts and native libraries match the final export
snapshot. Linux, Windows and Android ARM64 libraries are rebuilt with the
expanded `Animation` binding profile; Android was not device-executed. See
[registered results](direct-pose-registered.json) and
[source/build provenance](direct-pose-provenance.json).

Original-code comparison confirms current translation/quaternion key
interpolation at `0x50acd0` and authored parent composition at `0x50c230`;
see [the source receipt](direct-pose-original-code.json). This helper retains
the remake's existing EIAnim conventions and engine interpolation. The
direct-control lower/upper-body blend is a remake feature with no equivalent
original-game Wine fixture. The Wine checks above run the remake; original
animation timing and original Dar FPS equivalence remain unmeasured.

The new profile also separates vegetation interaction work: contact collection
costs approximately 0.13–0.23 ms/frame, versus 0.05–0.08 for history/stamping.
Ground-mark processing and delayed first-visible mirror preparation remain
other targets. None of those paths is changed by this animation batch.

## Vegetation contact collection

On integrated source `fa5c65e8`, `VegetationContactKernel` batches the existing
grass-pressure contact collector. It reads current visibility, interpolated
roots and mesh bounds, orders candidates by distance and instance ID, and
preserves the nearest-32 budget **before** terrain/height admission. Terrain
queries, the pressure texture, history, recovery and stamping are unchanged.
The helper retains no actors, geometry or contact results. Only immutable
property/method names are reused. Custom actors, models, meshes, terrain
collectors and pressure owners retain the complete scalar path; older native
libraries and `--ei-script-vegetation-contacts` do likewise. The scalar body
is identical to the baseline collector.

The first native experiment improved an isolated crowd fixture but did not
establish a Dar gain: its separately profiled native pass was slower. Those
two 54-check route runs and their raw scopes are retained as a rejected
experiment. Caching the immutable names removed repeated name interning.
The final implementation was then measured against the script collector in
the **same live scene**, without awaiting frames between timed blocks.

GPU Lab heavy job `3b580ecebd7c49ca` completes the standard Dar route and
performs script/native/native/script blocks of 300 queries at each of three
focus positions. The scene has 334 actors, 34 visible actors, and 4–5 admitted
contacts. Exact ordered contacts are checked before and after every block.
All **82 checks pass**. No CPU builds or other checks run during measurement.
The microbenchmark runs after the timed traversal phases.

| Focus offset | Script µs/query | Native µs/query | CPU time saved |
|---|---:|---:|---:|
| (0, 0) | 249.07 | 216.49 | 13.08% |
| (5, 0) | 200.82 | 178.22 | 11.25% |
| (0, 5) | 246.35 | 216.86 | 11.97% |

This saves **23–33 µs per contact query**, not per rendered frame. It is a
small shared-path improvement and does **not** establish an additional
whole-game FPS gain. The authored crowd fixture takes 108.2–109.7 ms in script
versus 69.8–70.1 ms native for 240 queries; outside-focus and hidden-actor
fixtures also improve. See [the live measurement](vegetation-contacts/dar-live-micro.json)
and [raw check summaries](vegetation-contacts/checks.json).

The registered native regression passes **1,027 checks** on Linux and Windows
under Wine. It covers exact contact/key order, budget boundaries, live poses,
visibility, geometry replacement, interpolation, figure rebuilding and complete
fallback. The old library fails the availability contract (one check, one
failure). Related animation sampling (7,470) and actor bounds (1,403) pass on
both platforms, and vegetation preparation (124) passes through the Linux
runner. Linux, Windows and Android ARM64 libraries were rebuilt; Android was
not device-executed. All 461 runtime files compared with the final export
snapshot match. See [build/source provenance](vegetation-contacts/provenance.json)
and [registered headless results](vegetation-contacts/vegetation-contacts-registered.json).

The existing rendered test initially fails its immediate airborne assertion
on **all three** controls: pre-change pack, new native pack, and new pack with
scalar collection. The engine's SceneTreeFTI path returns the last submitted
transform until the next draw. A diagnostic confirms that both collectors see
the grounded pose before drawing and reject the lifted pose after drawing.
The maintained test now verifies both stages, retains the airborne exclusion
assertion, and adds native/scalar equality and landing checks. It passes
**47 checks** on both the pre-change and new packs, with zero differences for
empty/off/restored pressure, paused wind, and forced shadow refresh. The
initial failures remain archived. See [the diagnostic](vegetation-contacts/airborne-diagnostic.json),
[updated baseline](vegetation-contacts/vegetation-contacts-rendered-before-updated-fixture.json)
and [updated native result](vegetation-contacts/vegetation-contacts-rendered-registered.json).

Original-game comparison is inapplicable to this specific collector: commit
`8f3b93d5` introduced the remake's optional grass-pressure texture and bounded
history. There is no corresponding original-game Wine fixture. Validation
therefore compares the retained remake collector exactly; the Wine checks
above execute the remake. Original Dar runtime/FPS equivalence remains
unmeasured. Ground-mark processing and first-visible mirror preparation remain
separate investigation targets.

## Foot-contact geometry

On integrated source `b1cbb922`, ground marks still spend about 0.8–1.2 ms/frame
in Dar. Part of that is the repeated transformation of sole vertices and
reduction of the lowest 3.5 cm band into contact bounds. `GroundContactKernel`
batches that calculation without retaining geometry, poses or nodes. Current
rigid and welded meshes, transforms, child order and visibility rules stay live.
Authored coarse bounds, vertex acquisition, final terrain admission, animation
events, blood pickup, mark lifetime and snow-contact history remain in script.
Custom part/mesh/collector scripts, older libraries and the diagnostic
`--ei-script-ground-contact` retain the scalar path.

GPU Lab heavy job `335b5b3b73064422` compares the **untouched previous remake
method** from `b1cbb922` against the native implementation in one live Dar scene.
The reference collector shares the same world and vertex cache. Four synchronous
legacy/native/native/legacy blocks each make 10,000 queries over 50 actual feet;
48 contacts are admitted. Exact dictionaries are checked before and after
every block. All **461 route/comparison checks pass**. No own CPU builds or
other tests run during this measurement, which follows the timed route phases.

| Implementation | First block µs/query | Second block µs/query | Mean µs/query |
|---|---:|---:|---:|
| Previous method | 7.450 | 7.406 | 7.428 |
| Native geometry | 4.584 | 4.649 | 4.616 |

The saving is **2.81 µs per query, or 37.85% of this callback's CPU time**.
It is not a whole-game FPS percentage. See [the exact baseline comparison](ground-contact/dar-legacy-micro.json),
including its source hash and unchanged method body. An earlier same-scene
comparison against the refactored scalar fallback passes 541 checks over
60 feet and measures 7.819 → 4.645 µs/query. The smaller untouched-baseline
result above is the primary performance claim; the two live scenes have
different visible actor counts and are not compared against each other.

Heavy job `17347eedf3764ea5` also runs the fixed standard-rendering route with
script/native geometry in one instrumented export. Both pass **54 checks**.
Weighted contact scopes measure 12.20 → 9.06 µs/call, while native runs have
no calls to the scalar geometry fallback. Observed contact cost is
0.183 → 0.110 ms/frame, but contact counts differ with live actor movement;
that entire difference is not attributed to this change. The shared helper
also serves other zones and Arena. Its benefit depends on active foot queries.
See [the per-leg scopes](ground-contact/dar-profile-comparison.json).

The new registered exact regression passes **2,086 checks** on Linux and
Windows under Wine. It includes synthetic and authored animated feet, rigid
and smoothed figures, live transforms/visibility, welded meshes, sole-band
and extent boundaries, terrain rejection order, and complete custom/missing
library fallback. The old library fails its availability contract (one check,
one failure). The first implementation incorrectly declined ordinary
`EIAnimPart` nodes; the authored fixture caught 576 failures. Exact support for
that class was added while preserving fallback for its custom subclasses.
That initial failure log remains archived.

Related vegetation contacts (1,027), direct pose (7,470) and actor bounds
(1,403) pass on both platforms. Rendered running trails pass **14 checks each
on Vulkan and OpenGL**, producing 93 marks each; Ingos contacts, snow and
figure rebuilding pass **57**; Arena ground ink passes **5**. The registered
OpenGL receiver/lifecycle fixture passes **13**, and animated blood projection
passes **24**. Existing virtual-monitor diagnostics are retained in the logs.
See [check summaries](ground-contact/checks.json),
[registered headless results](ground-contact/ground-contact-registered.json),
and [registered rendered results](ground-contact/ground-contact-rendered-registered.json).

All 461 compared runtime files match the final export snapshot. Linux,
Windows and Android ARM64 libraries were rebuilt; Android was not executed
on a device. [Provenance](ground-contact/provenance.json) records the source,
build and pack hashes. No player-facing text or option was added.

Original-code comparison identifies authored frame/part selection at
`0x534b60` and ground-table/blood pickup at `0x56d150`. The original uses part
extents; the remake's rendered-sole reduction and soft-ground interaction
have no identical original-game Wine fixture. Those original-derived event
and lifetime paths are unchanged. The Wine checks above execute the remake;
this does not establish original Dar FPS or original foot-contact equivalence.
Surface projection, mark ageing and first-visible mirror preparation remain
separate investigation targets.

## Ground-mark surface projection in native code

The Dar profile after the foot-contact pass still spent about 0.10 ms per
walking frame in `GroundMarkProjection.place`, roughly 0.4 ms whenever it
created or rebuilt a mark. Its ordered subdivision and clipping loop now runs
as one native batch over the current terrain and receiving-floor triangles.
The five output channels retain the previous vertex order and exact values.
Receiver discovery, material updates, animated blood-patch reuse, visibility
and lifetime remain in script. The helper retains no scene or geometry cache.
Derived projectors, unsupported inputs, older libraries and the diagnostic
`--ei-script-mark-projection` keep the complete scalar path.

GPU Lab heavy job `d4145b84f5574445` compares the **untouched `place()` from
`3c0e375d`** with the native implementation in one live Dar scene. All four
legacy/native/native/legacy blocks use the same 32 actual footprints, with
1,974 output vertices and soft ground enabled. Each block performs 1,280
forced rebuilds. Exact positions, normals, both UV channels and colors are
checked before and after every block. All **317 route/comparison checks pass**.
No own CPU builds or other tests run during the measurements.

| Implementation | First block µs/rebuild | Second block µs/rebuild | Mean µs/rebuild |
|---|---:|---:|---:|
| Previous method | 351.08 | 342.90 | 346.99 |
| Native clipping | 105.82 | 105.65 | 105.73 |

This saves **241.26 µs per rebuild, or 69.53% of the callback's CPU time**.
Ordinary animated blood already reuses its receiving patch; this percentage
is not a whole-game FPS gain. The shared projector is used in campaign zones
with footprints, blood and scorch marks. Arena retains its existing ink path.
See [the exact baseline comparison](mark-projection/dar-legacy-micro.json).

The same heavy job also profiles the fixed route with scalar/native clipping
in one instrumented export; both runs pass **54 checks**. Projection scopes
measure **441.05 → 164.79 µs per call** and **0.103 → 0.047 ms per walking frame**.
The runs generate 478 versus 610 projection calls over 2,052 versus 2,127 frames,
so live actor/mark variation prevents attributing the entire frame-time change
to this helper. The full ground-mark callback measures 0.841 → 0.813 ms/frame.
See [the per-leg scopes](mark-projection/dar-profile-comparison.json); nested
scopes must not be added together.

The new registered regression passes **1,338 checks** on Linux and Windows
under Wine. An independent copy of the previous clipping routine checks
seeded rotated triangles, subdivision depths, clipping boundaries, degenerate
receivers and all five ordered geometry channels. Live authored terrain,
raised/moving/replaced/hidden floors, terrain edits, animated blood patches,
custom triangle hooks and full missing/declined-helper fallback also pass.
The old library fails the new availability contract. The first test mistakenly
retained shared packed arrays, which the next `place()` cleared; duplicating
the snapshots fixed its 145 failures without changing native output. Both
initial failure logs are archived with the accepted results.

Related foot-contact (2,086), vegetation-contact (1,027) and direct-pose (7,470)
checks pass on both platforms. Rendered running trails pass **14 checks each
on Vulkan and OpenGL**, producing 93 marks each. The moving-camera terrain
sweep passes **687**; floor/mark lifecycle passes **13 per renderer**; animated
blood image comparisons pass **24 per renderer**. Captures show the running
trail, raised bridge and blood patch. Virtual-monitor and Compatibility-AA
messages are existing test-environment diagnostics. See
[check summaries](mark-projection/checks.json) and the
[registered results](mark-projection/mark-projection-registered.json).

Linux, Windows and Android ARM64 helpers were rebuilt from the same source;
Android was not executed on a device. The final runtime files are compared
against the exported snapshot in [provenance](mark-projection/provenance.json).
No player-visible option or text was added.

Original-code comparison identifies footprint atlas/orientation construction
at `0x6cfb60`, blood atlas/growth/rotation at `0x6cf620`, and growth/rotation/fade
updates at `0x6cf9e0`. Those original-derived behaviors remain unchanged.
The [existing original GOG 1.06 Wine blood comparison](../outstanding-issues-2026-10-23/README.md)
records visible ground pigment and reload behavior. This pass does not repeat
that fixture: the modern terrain/floor mesh and soft-ground clipping API being
optimized is remake-specific, and an identical original geometry fixture is
not available. The exact geometry comparison is against the previous remake;
Windows/Wine checks here execute the remake, with no original Dar FPS claim.

## Remaining Dar animation cost after projection batching

A private diagnostic export splits `anim_flush` around its existing engine
advance and visible root-composition calls. GPU Lab heavy job
`83ff591c2179484f` passes **54 route checks**, with 2,079 walking frames and
334 actors. No gameplay code or animation-call order changes in this probe.

| Inclusive scope | ms/walking frame | calls/frame |
|---|---:|---:|
| Actor native-frame presentation | 1.695 | 81.40 |
| Animation flush | 0.835 | 44.67 |
| Visible key advancement and setters | 0.325 | 15.98 |
| Visible pose composition | 0.317 | 15.98 |
| Hidden timeline advancement | 0.079 | 26.54 |
| Materializing a pending pose | 0.005 | 0.10 |
| Unit sound traversal | 0.275 | 1.00 |

These scopes overlap; they are not added together. This single instrumented
route identifies remaining work and makes no additional FPS claim. Visible
pose composition and the sound traversal are now stronger candidates than
further mark-projection work. Original `0x50c230` composes each part from its
parent and recursively updates children; any replacement must preserve the
existing key order, same-frame edits, dirty propagation and custom-part hooks.
Mark ageing and delayed first-visible mirror preparation remain open too.
See [scope totals](actor-parts/actor-parts-profile-summary.json) and
[diagnostic provenance](actor-parts/provenance.json). No animation or sound
behavior changed in this profiling pass.
