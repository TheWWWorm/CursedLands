# Portal presentation checkpoint — 8 October 2026

This local checkpoint reuses visible and party actor rosters for foreground UI
queries. Retroid Original-look Portal measurements rise from a median **30.26
FPS** across three controls to **33.86 FPS** across two candidate runs, a
**11.9%** increase. The first control was faster (32.18 FPS); all controls are
retained. This is useful progress, but **60 FPS at 1× is not achieved** and no
new release is published.

The user accepted 1× with Original graphics as the Retroid target. Desktop
remains at 2×. The Windows report of about 40 FPS on a 7945xh / RTX 4090 mobile
at 4K, 100% scale and maximum settings remains unresolved.

## Change and correctness

The world keeps a registry-ordered visible actor array, invalidated by registry,
actor lifetime and visibility revisions. Detached actors use the uncached path.
Cursor selection, controller targeting, enemy bars and revive overlays consume
this array. Player labels, hero lights and rumble reuse the existing party
roster. Simulation, shaders, engine and native modules are unchanged.

The roster fixture passes **634 checks on Linux and 634 on Retroid**, covering
same-frame visibility/controller changes, order, detached actors, parent
visibility, replacement, freeing and reattachment. Snapshot arrays are not
mutated under callers. Existing callback behavior is retained.

## Reproducible comparison

All runs use the same supplied 415-actor Portal save, real separated local
co-op authority, one owner, four workers, close Terror camera, normal commands
and combat, and a 60-second measurement window. Every remake graphics switch
is off through the actual Original-look preset. The viewport is 1920×1080,
render scale 0.75, Compatibility/OpenGL ES, FOV 55 and far distance 100. Actual
simulation advances 59.84–59.95 seconds in each window. This does not establish
ordinary single-player, WAN, longer play or stable frame pacing.

| Build/run | Average FPS | p95 ms | p99 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| throughput-original-1x-baseline-60-01 | 32.18 | 39.816 | 47.577 | 90.857 |
| throughput-original-1x-baseline-60-02 | 30.17 | 41.477 | 48.275 | 90.318 |
| throughput-original-1x-baseline-60-03 | 30.26 | 41.822 | 50.745 | 104.892 |
| throughput-original-1x-ui-roster-60-01 | 33.89 | 37.666 | 45.546 | 86.037 |
| throughput-original-1x-ui-roster-60-02 | 33.83 | 37.846 | 45.591 | 87.167 |

The [validation record](portal-presentation-validation.json) contains complete
effective settings, artifact hashes, run identities, checks and limitations.
The [versioned gameplay fixture](../tools/benchmarks/portal_gameplay.gd) records
frame intervals and simulated time without synchronized GPU timing reads.
See its [instructions](../tools/benchmarks/README.md#rendered-portal-gameplay).
Hidden-actor scheduling and terrain specialization require their own complete
gameplay validation before becoming accepted changes.

The subsequent [hidden presentation checkpoint](portal-hidden-presentation-checkpoint.md)
records the combined actor scheduling and terrain specialization comparison.
