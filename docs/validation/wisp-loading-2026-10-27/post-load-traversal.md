# Frame pacing after loading

The full loading change was compared with local main at `9cacce1a` using the same
qualified Linux executable, RTX 3090 and Vulkan. One serial GPU Lab heavy job ran
eight fresh applications and sixteen ordinary solo-worker loads. Four matched
cases cover Foothills, Ingos and Suslanger with balanced PT/NRD, plus Foothills
with raster rendering. High quality, actual 1920×1080 output, no upscaler/frame
generation, disabled VSync and an unlimited frame rate are identical between
builds. Application profiles are isolated; the system driver cache is not reset.

Every load immediately begins real unit movement, then a return leg and camera
panning. The first load also repeats its pan. There is no post-load warm-up or
discarded settling window. Measurements span **56 valid gameplay phases and
about 14.4 minutes of active play**, including camera extents over 180 metres,
new terrain pages and live PT region replacement. All characters survive and
simulation advances. No loading/compilation cover reappears during play.

## Results

Frame percentiles below include all measured movement and panning after both
loads. The worst frame and the count over 100 ms are retained to expose outliers.
Each row has one full matched run per build; these are observations from a live
workload, not statistical proof of identical performance on other machines.

| Area / renderer | Reload before → after | Post-load p99 before → after | Worst frame before → after | Frames over 100 ms before → after |
| --- | ---: | ---: | ---: | ---: |
| Foothills / PT | 10.703 → 6.329 s | 27.692 → 28.342 ms | 75.135 → 84.709 ms | 0 → 0 |
| Ingos / PT | 18.955 → 11.948 s | 25.765 → 27.429 ms | 72.837 → 309.968 ms | 0 → 1 |
| Suslanger / PT | 14.310 → 10.769 s | 28.816 → 28.358 ms | 263.809 → 81.888 ms | 1 → 0 |
| Foothills / raster | 9.449 → 5.673 s | 11.229 → 11.050 ms | 40.087 → 27.058 ms | 0 → 0 |

Reload reductions are 25–41%. First entry with an empty application profile
remained expensive in this batch: 54.170 → 55.059 s in Foothills PT,
68.709 → 73.230 s in Ingos PT, 56.269 → 58.552 s in Suslanger PT, and
38.129 → 39.605 s in raster. These fresh-profile results do not establish a
cold-start speedup. The earlier first-entry report separately measures repeated
application starts with warmed caches. The wisp fix adds required preparation
to the first loading screen; it is reused afterward.

The timing review flagged the 310 ms Ingos first-movement frame instead of
treating the close percentiles as sufficient. A focused reversed-order repeat
compares unchanged main, the preceding loading-only build, and the complete
wisp build. On an automatically assigned RTX 3090 Ti, its five fresh starts
produced these first-movement maxima, in execution order:

| Build | First-movement maximum |
| --- | ---: |
| Unchanged main | 44.965 ms |
| Complete change | 21.419 ms |
| Previous loading passes, before wisp preparation | 26.684 ms |
| Complete change | 20.239 ms |
| Unchanged main | 320.881 ms |

The last unchanged-main run reproduces the same class of first-movement spike.
This establishes that the hitch can occur without the loading changes; it does
not identify or fix its underlying cause. The original 309.968 ms observation
remains in the changed build's report. The repeat adds no post-load settling
delay and does not discard its first frame intervals. A device-specific pair
on the RTX 3090 used for the full comparison produced first-movement maxima of
26.278 ms on unchanged main and 317.449 ms on the complete change. The outlier
therefore remains reproducible in the changed build on that device. These
small samples do not establish an unchanged frequency of this intermittent
hitch, even though its existence on unchanged main is confirmed.

The first Foothills traversal p99 is 27.643 → 27.639 ms; after reload it is
19.280 → 18.553 ms. Both builds still compile a small number of ordinary
first-movement pipelines. The full change does not increase their count in
the measured Foothills route, and neither build creates new draw, surface,
mesh or specialization pipelines on the corresponding post-reload route.
Terrain jobs and PT region replacement continue through the normal streaming
paths. Their remaining frame spikes are part of this report, not silently
removed from its distributions.

Isolating movement and panning **after the second load**, where reuse produces
the largest loading savings, gives the following results. Every phase has zero
new draw, surface, mesh or specialization pipelines, and neither build has a
frame over 100 ms in this subset. This is direct evidence against moving the
saved preparation cost into the subsequent measured gameplay.

| Area / renderer | Post-reload p99 before → after | Worst frame before → after |
| --- | ---: | ---: |
| Foothills / PT | 25.582 → 27.114 ms | 62.976 → 58.703 ms |
| Ingos / PT | 21.883 → 23.881 ms | 62.836 → 58.654 ms |
| Suslanger / PT | 28.462 → 24.694 ms | 70.479 → 81.888 ms |
| Foothills / raster | 10.245 → 9.966 ms | 15.623 → 17.007 ms |

A further RTX 3090 diagnostic isolates the initial Ingos spike. The changed
build still produces it while stationary (321.212 ms) and when a move goes
directly to the authority without the local acknowledgement (326.892 ms).
A subsequent ordinary-move run peaks at 29.850 ms during first movement.
The command calls themselves take at most 0.146 ms. The stationary stall has
no pending terrain jobs or PT region rebuild. This rules out traversal and
the acknowledgement call as necessary triggers in these runs; it does not
identify the remaining first-frame work or establish its rate of occurrence.

## Functional traversal qualification

Both registered first-person PT/NRD routes complete 50 checks. The river route
initially stopped after two or three legs because its live route chooser found
no admissible next target; unchanged main completed the route. A diagnostic
repeat on the changed build completes all four legs with the original
assertions and route filters. Added records retain terrain, exit and actor
rejections, start-cell passability and a navigation-grid digest. Even its
successful run encounters nearby actors that prevent attempted reroutes.
The original build also completes the diagnostic route, with an identical
terrain-grid digest at every leg. This is consistent with a timing-sensitive
live-route fixture; the earlier failures predate the rejection diagnostics,
so their precise rejected-target causes cannot be recovered. They are not
counted as passes or silently retried away. No navigation or route-selection
behavior was changed.

The authority terrain regression now includes the river's `zone7`. All 152
checks across four maps pass: authored terrain and water data, object floors,
navigation inputs, and all eight movement-class passability/cost arrays are
identical between presentation and simulation-only worlds. This directly
checks the loading optimization that could otherwise affect traversal.

## Reproduction and evidence

Use `tools/benchmarks/post_load_traversal.gd`; its configuration and protocol are
documented in `tools/benchmarks/README.md`. The retained reference saves contain
ordinary level-15 attributes and authored armour so the hero survives the same
route on both builds. Enemy AI, damage, collisions, movement, physics and world
simulation remain active. The initial unarmoured pilot paused after a death
and is excluded. The seed generator's first release-mode attempt placed the
save call inside an assertion and wrote no files; it was corrected before any
matched traversal run. The wisp measurements from that earlier job remain valid.

The workspace evidence directory `local/validation/wisp-loading-20261027/`
contains `frame-summary.json`, `traversal-summary.json`, `gameplay-provenance.json`,
all per-frame timelines and screenshots, source/pack/save hashes, GPU job records
and the exact launch and fixture recipes. First-movement isolation uses a
shorter copy of the same fixture and is labelled separately. Native Windows,
Android, multiplayer latency and every possible route are outside this measured
scope.
