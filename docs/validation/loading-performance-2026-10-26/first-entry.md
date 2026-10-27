# First-entry loading follow-up, 2026-10-27

This pass starts from the earlier local loading fixes and targets entering a
save after restarting the application. It retains the earlier terrain-colour,
authority-worker, cliff and PT/NRD improvements. No remote update or release
is part of this work.

## Profiling and changes

Instrumented fresh-process Foothills loading identified two remaining costs.
With warm driver/application caches, the client zone handler took 8.76 seconds:
world construction took 3.89 seconds, actor spawning 1.73 seconds, and material
preparation 3.06 seconds, including terrain colour preparation. These scopes
overlap; they must not be added to estimate total loading time. The worker's
load-state scope was 3.41 seconds. Instrumented timings diagnose the work; the
performance comparisons use uninstrumented exports.

Forward+ material preparation now admits up to 16 zero-area representatives
per batch. Each batch still receives four completed settling draws before
its materials are acknowledged. Every required material, vertex format,
lighting state and reflection representative remains in the preparation set.
Compatibility and Mobile keep their existing two-material policy, including
Compatibility's time budget. Arena preparation keeps its existing policy.
The regression's 45-material set requires **14 full scene draws instead of 94**;
revealing its actual stationary/moving source meshes adds no draw pipelines.

Cliff and snow preparation can now survive an application restart. The cache
stores only serialized derived fields and geometry, with new GPU textures
created from retained source pixels when read. It never persists GPU handles,
materials, nodes, world state or mutable snow-deformation history. Both the
geometry owners and lazy deformation caches remain private to the new world.
Cache accounting uses existing CPU pixel arrays, removing three GPU readbacks
from the first construction.

The identity covers the actual map arrays, source sector attributes, original
artwork, dimensions and an explicit algorithm/schema revision. The checksum
also binds each file to that identity. Truncated, corrupt, wrongly named,
obsolete or oversized records fall back to normal construction. Writes use
per-process staging and atomic rename; verified abandoned staging is removed
without deleting another live process's write. On platforms where a foreign
PID cannot be checked safely, its staging is retained. Committed entries are limited to
eight files and 128 MiB, including old schema versions. The previous in-memory
limit remains two entries and 64 MiB of combined serialized and image payload.
The first visit to uncached terrain still constructs it normally.

## Measurement protocol

The final comparison uses the same qualified Linux executable, renderer,
settings, saves and automatically assigned GPU for both packs in one serial
GPU Lab heavy job. Each measured first-save case starts a new application and
authority worker. Both variants are prepared before measurement, and the four
samples per case use before/after/after/before order. The unchanged comparator
is the result of the previous loading pass, so reductions are additional to
that work. Initial inline entries and cache-seeding runs are excluded.

Settings are High, 2880×1800 actual output, balanced two-bounce PT with NRD,
SHaRC/ReSTIR/refraction/RR disabled, and a 30 FPS settle limit. A load is complete
only after the normal loading and compilation covers close and PT has published
an active frame. Raster uses the same protocol with PT disabled.

The verified RTX 3090 Ti comparison produced these median first-save timings
(two fresh launches per build and case):

| Area and renderer | Previous local fixes | This pass | Additional reduction |
| --- | ---: | ---: | ---: |
| Foothills, PT | 18.000 s | 16.275 s | 9.6% |
| Ingos, PT | 27.566 s | 21.390 s | 22.4% |
| Suslanger, PT | 22.213 s | 20.918 s | 5.8% |
| Foothills, raster | 15.505 s | 13.501 s | 12.9% |

All sixteen measured launches completed normally. These are small, controlled
samples with warmed driver/application and derived-data caches, not a guarantee
for other hardware or a newly installed game. A cache miss still builds the
terrain. The timings are additional to the previous pass; they should not be
combined with its independently measured percentages. The earlier exploratory
comparison overlapped subsequent build/functional work and is excluded.

Raw timings, build/save hashes, GPU job records and assertion totals are retained
in `local/validation/loading-first-entry-20261027/` in the workspace.

## Regression and reference scope

`terrain_cliff_disk` and its rendered counterpart clear all in-process entries
before restoring exact rock and snow geometry. They check new GPU texture
pixels, isolated owners, changed input rejection, key binding, malformed-file
fallback, neutral terrain, byte/file limits and abandoned write cleanup.
`shader_warmup_loading` observes completed draws on the actual rendering thread,
checks progress ordering under the loading cover, and reveals real source
meshes without new pipeline compilation. Both tests fail against the previous
loading build. The disk-cache negative control constructs real terrain, drops
the old process-local cache, and observes the unwanted rebuild; it does not fail
merely because the old build lacks a new helper. The first draw-counter prototype used queued main-thread signals
and reported zero synchronous draws on both builds; the corrected test uses a
mutex-protected compositor callback. That prototype is not acceptance evidence.

The existing live compilation fixture's per-advance count bound now follows
the renderer's batch size. Its intermediate screenshot observes the preceding
presented batch when the next batch completes, instead of assuming that four
completed materials necessarily means two batches. The exact pixel assertion,
completed-draw ordering and full-list completion requirements remain intact.

The integrated acceptance set has **765 passing assertions across 21 registered
cases**, plus 11 Python runner checks. Seventeen cases use the final2 pack;
the final3 pack changes only detection of foreign staging-file writers and
repeats both persistent-cache modes, in-process reuse and material warm-up.
The strengthened foreign-writer fixture fails against final2 and passes against
final3. Inspection of the engine's process API and the existing crash-report
helper established that `OS.is_process_running` only recognizes child processes.
The cache now checks accessible `/proc` data and preserves unknown ownership.

Additional water-preparation qualification passes 68 assertions. The arena
qualification passes 27 on retry, with its first-image pixel failure retained
from both the unchanged and modified builds under the same harness. Its failed
capture contains the preceding arena frame; no arena assertion was changed.
The older live-preparation fixture completes 42 checks on both builds with the
same two failing immediate-message assertions for FSR2 and terrain settings.
They conflict with the existing 500 ms display delay introduced by `89d03aa8`;
those assertions remain unchanged and are not counted as passing acceptance.

The original-game comparison remains the first pass's retained Foothills save
load under Wine 11.20 and original server/map/save-loader inspection. Godot
pipeline preparation and remake cliff/snow geometry have no original renderer
equivalent, so this pass compares exact uncached/cached remake output. It does
not claim original-game timing parity, cold-driver-cache timing improvements,
or native Windows/Android qualification.

The previous pass's intermittent startup/loading stalls remain a separate
uncertainty. A stress run is diagnostic evidence, not proof that a rare stall
is fixed. The final3 pack completed **12 loads across six fresh launches** of
Foothills, Ingos and Suslanger under a debugger prepared to capture every thread
if progress stopped. No stall occurred. Debugger timings are excluded from the
performance comparison.

## Retained evidence and cleanup

The workspace evidence includes the source patch, source/pack/save hashes,
executed fixtures, profiling and launch recipes, raw logs, native-resolution
captures, unique saves, negative controls and GPU job records. The cleanup
ledger records removal of this task's generated packs, import/export staging,
duplicate fixture libraries, isolated profiles and reproducible caches after
preserving their useful artifacts. Canonical source, shared engine/reference
targets, original game assets, prior validation and other worktrees are retained.
