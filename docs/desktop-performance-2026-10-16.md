# Desktop follow-up: Android Vulkan optimizations

The shared caches reduce the cost of unchanged particle-material and original
point-light updates on desktop. The on-screen comparisons below do **not**
establish an overall desktop FPS improvement or regression: repeated runs of
the same build vary substantially, and other desktop graphics workloads remain
active. The Android result must not be generalized into a desktop FPS claim.

This follows the [Android Original-quality investigation](android-vulkan-original-performance-2026-10-16.md).
The [machine-readable record](desktop-performance-2026-10-16.json) contains all
eight completed on-screen runs, settings, frame-time distributions, telemetry,
build identities and raw-artifact hashes, including unfavorable results.

## Matched desktop runs

Ubuntu 24.04.5 LTS, Ryzen 9 5950X, RTX 3090, NVIDIA 580.178.04,
Forward+/Vulkan. VSync and the frame cap are disabled. These are uncapped frame
callback rates, not monitor presentation rates.

The control uses the exact published 1.8.0 Linux pack. The candidate pack is
exported from `b4c26eb48bb6e6e4e3a52fbb6bddd86319368018`, including the terrain
changes in `2763071c`. Both use the **same published Linux executable and native
extensions**. The new native Mobile-renderer patch is not part of this desktop
runtime. The published pack's game source tree matches baseline `9da07801`.

Both load Gipat `gz1g`, with 48 units and 730 objects. The existing
`tools/benchmarks/map_pan.gd` holds world/session physics and moves the camera
along the same wall-clock route while production rendering, effects and HUD
remain active. Each run has 12 seconds of warm-up, then three eight-second
phases, with image readbacks outside the measurement windows. Render scale is
1.0. Options, viewport dimensions and population match across the builds.
Profiles are isolated from the player's settings and saves.

Original runs use published/candidate/candidate/published order; High uses
candidate/published/published/candidate. An interrupted Original candidate run
was retried; incomplete output is excluded. The separate arena game had been
closed before these runs, but other desktop GPU activity continued. No other
application was suspended or closed by the benchmark.

Each cell is the **range of two complete runs**, not a confidence interval:

| Preset and render resolution | Phase | Published FPS | Candidate FPS |
| --- | --- | ---: | ---: |
| Original, 1920×1080 | Stationary | 482.6–567.7 | 354.0–355.0 |
| Original, 1920×1080 | First pan | 144.1–551.4 | 289.0–380.4 |
| Original, 1920×1080 | Repeat pan | 134.1–576.7 | 321.3–475.9 |
| High, 2560×1440 | Stationary | 44.3–69.3 | 48.0–80.4 |
| High, 2560×1440 | First pan | 48.7–62.4 | 53.3–67.5 |
| High, 2560×1440 | Repeat pan | 48.9–64.1 | 47.8–66.0 |

High repeat pans compile no new draw pipelines. The first High stationary run
for each build still compiles 36/38 pipelines; the later stationary repetitions
compile none. Those startup transients are retained in the results. GPU and
render-thread timings in these on-screen runs are single end-of-phase samples,
not whole-phase distributions.

The overlapping pan ranges and large unchanged-build variation make a combined
percentage misleading. In particular, the second Original published run drops
from 483 FPS stationary to 134 FPS on its repeated pan, while the first published
repeat pan reaches 577 FPS. This cannot support attributing a small difference
to the code changes.

## Rendering cost on the second GPU

A separate diagnostic uses the RTX 3090 Ti and renders the same full-size
viewports with `RenderingServer.force_draw(false, delta)`, excluding the final
screen blit and buffer presentation. Each measured iteration waits for
`frame_post_draw` and reads GPU/render-thread timestamps. This avoids presenting
each frame through the busy display GPU, but adds synchronization overhead.
**Its callback rate is not gameplay FPS.** The exact executable GDScript is
included in the JSON, with full-line comments removed from the adapted harness.

There is one pair per preset: published/candidate at Original, then
candidate/published at High. The repeated camera pan gives:

| Render resolution and preset | Published mean GPU ms | Candidate mean GPU ms |
| --- | ---: | ---: |
| 1920×1080 Original | 0.6585 | 0.6553 |
| 2560×1440 High | 5.8992 | 5.8092 |

These are small differences, approximately 0.5% and 1.5%. Clocks and temperatures
are not fixed, and there is only one pair at each setting, so this does not
establish a small GPU improvement. It provides no evidence of a large rendering
gain on desktop Forward+. All four diagnostic runs exit cleanly, render at the
requested dimensions and return nonzero GPU timings. Recorded process samples
show no other active GPU work on this second GPU; unavailable utilization
samples are not treated as zero.

## Shared CPU cache measurements

`tools/benchmarks/shared_render_cache.gd` exercises four existing particle
materials and six original point lights with unchanged values. Each case warms
up for 1,000 calls and records nine batches of 5,000 calls. The same release
runtime runs headlessly with the dummy renderer; these measurements exclude
native GPU rendering and are **not whole-frame speedups**. Two executions per
build reverse order on repetition.

| Operation | Published µs/call | Candidate µs/call | Cost reduction |
| --- | ---: | ---: | ---: |
| Four unchanged particle materials | 3.2282 | 2.6489 | 17.9% |
| Six unchanged original point lights | 13.2211 | 8.2439 | 37.6% |

Values are medians of the two run medians. Together these fixtures save about
5.56 microseconds per pair of calls. They confirm the shared CPU work is
cheaper, but their percentages cannot be applied to total game FPS.

## Rendering checks and scope

The candidate passes **106 particle checks, zero failures**, using the shipping
Linux runtime with Forward+/Vulkan on the RTX 3090 Ti. This includes real GPU
pixel comparisons for eight shader variants, soft particles off/on/off,
empty-to-visible transitions, stable shader identity and new-material cache
invalidation. It exits cleanly. Using the shipping Linux runtime avoids the
shutdown failure seen in the earlier fixture run with the official engine.

The candidate imports and exports successfully, and all eight completed
on-screen runs exit cleanly without script, shader or runtime errors. The
shipping runtime's separate-render-thread experimental warning remains.

The findings apply to this Linux Forward+ host and route. They do not measure
Windows, macOS, integrated GPUs, desktop Mobile rendering, a live combat replay
or long thermal sessions. The Mobile-only terrain and native light/pass/sky
optimizations do not provide evidence of a Forward+ desktop gain. No production
code, quality preset, release version or published artifact changes in this
follow-up.

## Reproduction

Use the published 1.8.0 Linux runtime and native libraries for both packs. Build
the candidate release pack from `b4c26eb4`. Supply original game data through
`--ei-path`, and give each build/preset/resolution its own `XDG_DATA_HOME`,
`XDG_CACHE_HOME` and `XDG_CONFIG_HOME`. Do not benchmark both builds concurrently.

Run `CursedLands.x86_64` with `--rendering-method forward_plus`,
`--rendering-driver vulkan`, the display GPU index, and `--audio-driver Dummy`.
After `--`, supply `--tool=/absolute/path/to/tools/benchmarks/map_pan.gd` and
`--pan-config=/absolute/path/to/config.json`, plus the original-data path.

```json
{"zone":"gz1g","preset":1,"seconds":8,"warmup":12,"width":1920,"height":1080}
```

For High, use preset 4 and 2560×1440. For the CPU diagnostic use `--headless`
and `--tool=/absolute/path/to/tools/benchmarks/shared_render_cache.gd`; its
result is saved as `user://shared-cpu-probe.json`.

Earlier setup probes with concurrent gaming load or cross-GPU PRIME
presentation are excluded from the on-screen comparison. Their reasons are
recorded in the JSON. No zero-valued unavailable GPU query is interpreted as
zero rendering cost.
