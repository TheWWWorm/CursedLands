# Fresh loading and the first-movement hitch

This follows the [save/wisp loading pass](../wisp-loading-2026-10-27/README.md).
The comparator is accepted local main `f455e84401c9c7ac7d7216befac55ab03fc721cc`,
including its terrain/program caches, bounded parallel preparation and real
Autochess wisp preparation. The remaining first-entry hitch was reproduced
before changing its preparation path.

## Confirmed cause

An empty-profile Ingos save load delivered a 355.560 ms frame just after reveal.
A forwarding Vulkan interposer measured 345.237 ms inside
`vkCreateGraphicsPipelines` on that same render thread. A second reproduction
with SPIR-V debugging delivered a 536.705 ms frame and spent 527.638 ms creating
the missing graphics pipeline. Cache serialization was below 9 ms in the first
trace. Instrumented/debug runs establish the cause; they are not used for the
final timing comparison.

The missing pipeline renders unbaked terrain in the main viewport's depth-only
pass. PT GI disables SSAO when its output becomes ready. That changes the main
depth framebuffer after the earlier SSAO depth/normal preparation. The same
shader had been drawn in shadow and multisampled water-reflection passes, but
those have different framebuffer formats and do not prepare this main pass.
Newly revealed ground could therefore block the render thread during movement.
The captured vertex/fragment module hashes are `c2143262db4194d0` and
`2362514ef3f85716`; their debug sources and raw timing records are retained.

## Changes

Preparation now completes both relevant main-depth states under the existing
loading cover when SSAO and RT/PT GI are requested. Both forced and deferred
paths restore the live environment, including cancellation. The prepared key
covers the pair across PT activation and subsequent save loads, so reloads
reuse completed work. All four settling draws remain for each state. No work
is scheduled for the first movement to finish this preparation.

Fresh terrain selects its complete land and water programs after building the
needed fields. It no longer creates intermediate shaders that the selected
settings will immediately replace. The real-map regression checks all 16 water
option combinations against the previous final shader composition, preserving
currents, wakes, sampler bindings and terrain/navigation data.

A warmup mesh now contains one collapsed primitive with the original vertex
layout instead of copying and drawing an entire terrain mesh. Custom channels,
compression, indices, bones and primitive type are preserved; the authored
source mesh remains untouched.

The existing four-thread desktop pool used the default 0.3 background ratio,
which rounded down to one background worker. A trace found 26.305 seconds of
late graphics-pipeline compilation on that single worker. A 0.5 ratio permits
two independent background jobs and leaves two workers available for urgent
work. The total pool size and the existing two-job terrain-streaming limit are
unchanged. This setting applies to Linux and Windows; measured performance
below is Linux/Vulkan only.

## Validation method

Each comparison uses frozen production before/after packs with the
same qualified Linux executable (SHA-256
`900844d32a705b811a2b940b26e813defcae21f3763687aeb9c8eb99c896ebfa`). Each application
gets an empty isolated profile and the same retained save and High settings.
Both use the same built-in RT profiling flag; neither uses the diagnostic
interposer or instrumented GDScript sources for acceptance timing.
Application shader/terrain caches are empty; system/driver caches are not
forcibly cleared.
A single GPU Lab heavy job runs the cases serially on one automatically
assigned RTX 3090 Ti. It covers Ingos, the Foothills, a river area and a raster
control at 1920×1080, uncapped, without upscalers or frame generation.

`tools/benchmarks/post_load_traversal.gd` records from the first uncovered frame,
with immediate authority-controlled movement and camera panning. There is no
discarded settling window. Each application loads twice; the complete suite
includes 16 loads and 56 phases, live AI, world-time advancement, terrain
streaming, PT recentering and repeated visits. Timings include actual frame
intervals and pipeline counters, not just script return times. App-start-to-
reveal times also include work before the save-load call.

## Initial matched results on `f455e844`

| Area / renderer | Fresh load before → after | Reload before → after | Post-load p99 before → after | Worst frame before → after |
| --- | ---: | ---: | ---: | ---: |
| Ingos / PT | 75.783 → 67.874 s | 11.554 → 11.716 s | 26.809 → 28.548 ms | 74.935 → 62.982 ms |
| Foothills / PT | 60.442 → 57.968 s | 6.675 → 6.782 s | 25.949 → 25.804 ms | 75.140 → 61.806 ms |
| Suslanger / PT | 71.223 → 60.528 s | 12.415 → 11.392 s | 25.038 → 23.218 ms | 76.929 → 91.802 ms |
| Ingos / raster | 58.433 → 49.154 s | 10.823 → 11.077 s | 7.177 → 7.508 ms | 39.630 → 42.110 ms |

Fresh entry improves by 4.1–15.9% in this batch. App-start-to-first-reveal,
which includes work before the save-load call, improves by 3.5–14.6%. The
earlier large reload improvements remain: this additional change leaves
Ingos/Foothills reloads within 0.26 seconds of the comparator and reduces
Suslanger reload by 1.02 seconds. The depth-pair key reuses the previous full
preparation; reloads prepare only four or six new representatives.

Every candidate route has **zero new draw, surface, mesh or specialization
pipelines**, on first entry and after reload. The unchanged PT routes create
five, six and five draw pipelines after first entry. Neither build needs new
pipelines after reload. All 56 phases complete with live simulation and no
reappearing loading cover. No measured frame exceeds 100 ms on either build;
the candidate maximum is 91.802 ms. Total measured gameplay is about 8.3
minutes across both builds.

These are live routes with one matched run per case, not a statistical
guarantee of identical frame pacing. Ingos PT initially has a 1.739 ms higher
p99; Foothills is nearly unchanged and Suslanger improves by 1.820 ms. Raster
p99 differs by 0.331 ms. Individual non-compilation spikes remain, including
a 91.802 ms candidate river frame versus 76.929 ms before. The zero-pipeline
results establish that the eliminated preparation work was not deferred into
these routes; they do not establish that every future frame is faster.

A reversed-order Ingos repeat on the same RTX 3090 Ti again completes both
loads and all phases. Fresh loading is 77.077 → 64.286 seconds; reload is
12.054 → 11.490 seconds. Maximum frame time is 77.623 → 62.106 ms, and candidate
pipeline deltas remain zero. Its p95 is 12.738 → 12.979 ms and p99 is
26.049 → 29.399 ms. This retains the small tail difference instead of calling
all gameplay frame times unchanged. An identical-pack worker-budget comparison
below checks whether it follows the extra background worker.

The worker isolation keeps the exact same candidate pack and changes only the
background ratio via an adjacent `override.cfg`. The existing pool regression
confirms that the control admits one background task. On the same GPU, one →
two background workers gives fresh loading of 77.083 → 68.466 seconds, p95 of
11.895 → 12.239 ms, p99 of 26.822 → 25.740 ms and maxima of 58.906 → 61.245 ms.
Both runs retain zero new pipelines during play. This comparison does not
reproduce a penalty from the second background worker. Candidate Ingos p99
ranges from 25.740 to 29.399 ms across its three full runs; the results do not
support a blanket claim of identical frame pacing. The accepted configuration
remains four workers total with two available for background work.

Across the full comparison, reverse-order pair and worker isolation, **84
complete phases and about 12.4 minutes of live gameplay** are retained. Every
candidate phase has zero growth in the four monitored pipeline counters and
no frame over 100 ms. The identified
345–528 ms render-thread compilation is prepared during loading. Ordinary
simulation/streaming variation remains visible in the evidence.

## Regression scope and retained failures

The first four new registered regressions fail against the unchanged pack for the
intended defects: 20 oversized representative meshes, unnecessary water
program creation, two missing depth pipelines (forced and deferred), and a
single background worker. The changed pack passes **9,621 assertions across
25 distinct registered cases**, plus 11 Python runner tests. The acceptance index includes the related
terrain, water, loading, wisp/Autochess and PT lifecycle checks, without counting
reruns twice.

The existing caustic soft-ground fixture searched tropical zone15 for a dry
footprint after deformation became snow-only. Both packs found zero eligible
sectors. Its fixture now uses zone11's authored snow beside water, without
changing ground types or weakening image, binding, clock or option-lifecycle
assertions. Both builds are checked with this corrected fixture.

The existing first-person river-route fixture can become surrounded by live
actors. Both builds failed to find its fourth target, with the same terrain
navigation digest and actor-blocker rejections. A diagnostic candidate rerun
passes all 50 unchanged assertions. The initial failures are retained separately
from performance acceptance; terrain parity and the matched live routes provide
additional checks. A GPU process also spun before Vulkan initialization and
before test execution; its incomplete run and fresh-profile retry are retained.
No GPU/display settings were changed to recover it.

The original game has no Godot worker pool, Vulkan pipeline preparation,
SSAO-to-PT handoff or Autochess mode, so a new original-game timing run cannot
exercise these defects. The earlier loading investigation retains its original
map/save-loader inspection and Wine load comparison; the wisp pass retains
native animation/callback evidence. Authored data and simulation behavior are
covered by the related regressions. No Windows, Android, original-renderer
parity or complete-campaign hitch-free claim is made.

## Integration and a second traversal failure

Local main advanced during this work to
`34a17e14fd016479a4a7520564d13dcd2072a858`, integrating the accepted Foothills,
foliage, cliff, figure/PT, water and Autochess fixes. Those changes are preserved.
The loading patch's three production files are unchanged; fresh frozen packs
compare this updated main with and without the loading patch. The combined
GDScript/project fingerprint is
`c1d1837f5e9157f2105185c1cd2f9b4d55c07befff97476b3b68c7ddddd1a229`.
These production packs have no extra diagnostic helper or interposer.

This intermediate integrated run completes 16 loads and 56 live phases. Its 25 passing
registered cases contain **9,622 assertions**, plus 11 Python runner tests.
All four new tests also fail against unchanged `34a17e14` for the intended
defects; the passing index excludes the existing failures described below.

| Area / renderer | Fresh load before → after | Reload before → after | Post-load p99 before → after | Worst frame before → after |
| --- | ---: | ---: | ---: | ---: |
| Ingos / PT | 74.994 → 66.192 s | 12.360 → 11.954 s | 29.012 → 29.113 ms | 357.498 → 65.411 ms |
| Foothills / PT | 59.826 → 55.362 s | 6.612 → 6.303 s | 24.945 → 25.198 ms | 88.137 → 234.599 ms |
| Suslanger / PT | 57.407 → 54.492 s | 11.214 → 11.244 s | 23.563 → 22.883 ms | 69.580 → 269.834 ms |
| Ingos / raster | 54.714 → 45.268 s | 10.821 → 10.749 s | 8.383 → 9.107 ms | 40.880 → 46.730 ms |

Fresh loading improves by 5.1–17.3%; app-start-to-reveal improves by 4.5–15.0%.
Reload times stay within 0.41 seconds of the comparator. All candidate phases
again create zero draw/surface/mesh/specialization pipelines. The unchanged
PT routes create five, six and four draw pipelines on first entry. Ingos
reproduces a 357.498 ms baseline spike; its candidate maximum is 65.411 ms.

The candidate Foothills and Suslanger runs nevertheless record one 234.599 ms
and one 269.834 ms frame during the first pan after reloading. These spikes
have no new pipeline counters, and both occur while PT rebuilding and terrain
jobs are active. They are retained in the intermediate results. Their timing
requires separate diagnosis; zero pipeline counts alone are not proof that
all runtime stalls have disappeared.

The native trace reproduced the Suslanger spike at 268.820 ms, outside the
measured Vulkan calls. Broad script timing and native-wait instrumentation
changed scheduling enough that their repeats did not reproduce it. A narrow
bake probe measured individual native terrain bakes at 250–280 ms. Godot's
render worker can cooperatively execute ordinary pool tasks while waiting;
low priority does not exclude a task from that worker.

The new deterministic `terrain_color_render_thread` regression occupies the
other pool workers, queues actual cache jobs with a controlled slow field,
and makes the real render worker wait for a continuation. The intermediate
candidate runs both bakes on the render worker (thread 5), failing the
isolation assertion. This reproduces the hazardous execution path without
relying on a statistical frame-time threshold.

Runtime terrain bakes now use dedicated low-priority threads, still capped at
two jobs and one upload per frame. They cannot be taken by the render worker.
Loading preparation keeps its bounded high-priority pool jobs, all joined
under the cover. Completion, teardown and thread-start failure preserve the
original unbaked material and exact image results. No extra work is delayed
until first movement. A related historical priority comment was clarified.

The final combined source fingerprint is
`44d05ee80d5f98001ba53b6acdaba615cf673fb20fc23b549aef7cc5e2849d21`;
its production PCK is
`9723f7744f69922090ca35cb6c5799a8bc290a5047c300f6d4ad9b8690de954b`.

The final registered suite passes **9,629 assertions across 26 cases**, plus
11 Python runner tests. The worker-isolation regression fails on both unchanged
main and the intermediate candidate, and passes after the runtime change.
Native terrain loading, image parity, cache lifecycle, save reuse, water,
foliage, wisp/Autochess and the earlier shader regressions were rerun on this
final pack. The two inherited cliff failures remain identical.

One PT camera test terminated with Vulkan device loss and NVIDIA Xid 109
(context-switch timeout), followed by a driver-library fault. Terrain detail
was disabled in that fixture, so the new runtime bake threads were inactive.
The unchanged main control and two fresh-profile final-pack retries all pass
14 assertions when run serially. The failed run and kernel evidence are
retained; no device/display reset, permission change or assertion change was
used. This is not counted as an uninterrupted all-green suite.

## Final comparison on integrated main

The final production pack runs before the unchanged `34a17e14` control for
each case, reversing the earlier order. GPU Lab job `b1c31128cb914087` completes
all eight applications serially on the same RTX 3090 Ti with exit code zero.
Source, pack, engine and all eight native-library hashes match the frozen
inputs after the run. Neither timing pack contains the diagnostic scripts or
interposers used to investigate the second stall.

| Area / renderer | Fresh load before → after | Reload before → after | Post-load p99 before → after | Worst frame before → after |
| --- | ---: | ---: | ---: | ---: |
| Ingos / PT | 73.018 → 69.462 s | 12.181 → 11.734 s | 27.317 → 24.551 ms | 345.569 → 56.981 ms |
| Foothills / PT | 60.812 → 56.753 s | 6.656 → 6.861 s | 27.258 → 27.687 ms | 87.609 → 63.974 ms |
| Suslanger / PT | 62.767 → 59.117 s | 11.861 → 12.399 s | 23.497 → 24.384 ms | 81.402 → 76.850 ms |
| Ingos / raster | 54.953 → 46.311 s | 11.057 → 11.007 s | 8.931 → 8.105 ms | 40.874 → 47.850 ms |

Fresh loading improves by **4.9–6.7% with PT and 15.7% in the raster control**.
App-start-to-first-reveal improves by 4.6–6.1% with PT and 14.0% with raster.
Reload differences range from 0.45 seconds faster to 0.54 seconds slower;
reloads reuse the full preparation and draw only four or six new
representatives. The previously confirmed large reload improvement remains
part of both builds.

The final pair covers **16 loads, 56 live phases and 496.5 seconds of measured
gameplay**. Every final route records zero growth in the draw, surface, mesh
and specialization counters on both loads, no reappearing loading cover and
advancing simulation. Every movement leg travels more than ten world units.
The control adds four, eight and four draw/specialization pipelines after
first entry in Ingos, Foothills and Suslanger respectively. Ingos reproduces
the 345.569 ms hitch; the final build's maximum there is 56.981 ms. No final
frame exceeds 100 ms; its maximum across all four cases is 76.850 ms.
Final Ingos and Suslanger captures were also inspected after traversal.

The late terrain-worker fix removes the deterministic render-worker execution
path, and the final Foothills/Suslanger runs no longer show the intermediate
235–270 ms stalls. This is evidence against shifting those stalls into the
tested traversal routes, not a claim that every frame or every location is
faster. Foothills p99 rises by 0.429 ms and Suslanger by 0.887 ms; their mean
frame times rise by 0.419 and 0.714 ms respectively in this single matched
pair. Suslanger p95 rises by 1.309 ms. Ingos PT/raster p99 improves by 2.766 /
0.826 ms. Live simulation and scheduling vary between runs.

The four pipeline counters do not include compute pipelines. Diagnostic
Foothills traces record a roughly 33–35 ms runtime compute compilation in
both builds, so zero monitored counts must not be read as zero compilation
of every kind. The remaining small runtime variation and the limits of one
matched run per case are retained rather than hidden by a settling window.

Two related cliff checks already fail on updated main without this patch, and
fail identically with it. The Forward+ fixture selects a newly admitted site
with 16 resident sectors and completes 69 successful assertions, below its
old manifest minimum of 87. The Compatibility fixture fails its unsupported-
tile exact-pixel control. Both implementations choose the same authored site;
their raw reports, screenshots and failures are retained. These are not counted
as passing tests, and their assertions/minimums were not lowered. The new
all-effects foliage, desert rendering and weapon-pose checks are also included
in the integration run.

## Evidence and cleanup

Workspace evidence is in `local/validation/fresh-loading-hitch-20261027/`:
source/pack/engine hashes, exact executed fixtures, raw per-frame measurements,
PNG captures, Vulkan traces, negative controls and excluded exploratory runs.
Diagnostic coroutine durations include suspension and must not be summed as
CPU time. The maintenance ledger records removal of disposable exports,
profiles, reproducible caches and redundant diagnostic shader dumps while
preserving the culprit shaders, unique saves and useful validation records.
Both task scratch directories were removed after their jobs completed and
their recipes and non-cache evidence were saved. The two cleanup ledgers
record 9,323,819,018 logical bytes removed (including hardlink names, not a
physical-free-space measurement). About 480 MiB of investigation evidence is
retained. Canonical source/history, shared engines and native libraries,
original assets/saves and unrelated worktrees are preserved.
