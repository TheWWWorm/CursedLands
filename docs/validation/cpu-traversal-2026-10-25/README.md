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

The first movement produces a roughly 1.4-second cold shader/renderer hitch in
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
from **15.17 to 12.86 ms**. Including the cold movement hitch, median FPS rises
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
and Android device execution remain unmeasured. The existing cold movement
hitch remains visible in the full-window timelines.

All work is isolated on `perf/cpu-traversal-20261025`, starting from local main.
The separate weather fix must be integrated alongside this work before a
release is qualified. No public release, player profile or remote main was
changed. Local benchmark recipes and fixed fixture paths are retained under
[recipes](recipes); source/artifact and external fixture hashes are in
[provenance](provenance.json).
