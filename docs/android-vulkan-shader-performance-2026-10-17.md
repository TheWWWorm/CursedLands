# Android Vulkan: additional shader work

Android Mobile now skips fog calculations for pixels where both distance fog
and border fog contribute exactly zero. Detailed materials also use an internal
uniform bound for their four-light loops, keeping the bound out of compile-time
specialization. The light count, selection, order, byte packing, overflow-light
matching and shading equations are unchanged. Original materials retain their
previous light-loop form.

The fog shortcut tests the map's complete clear rectangle, including the extra
one-metre border band. Partially fogged, fully fogged and out-of-map pixels keep
the existing calculation. Fog RGB is multiplied by its alpha at every consumer;
returning zero RGB when alpha is zero preserves the final colour. The shortcut
also avoids the unused colour conversion when border fog is disabled.

Both changes are enabled only on Android's Mobile renderer. Desktop, Forward+
and Compatibility keep their previous default shader sources. No graphics
preset, resolution, render scale, sample count, simulation rule or player-facing
option changes. This pass adds no persistent cache or per-frame uploads.

## Matched device measurements

These are additional gains over the already-optimized game at `572a8fb9`,
including the earlier [terrain cache](android-vulkan-performance-2026-10-16.md)
and [Mobile engine work](android-vulkan-original-performance-2026-10-16.md).
The baseline is that previous private QA APK, not published 1.8.0. Both APKs
contain identical native libraries. Among 796 tracked game files, only
`src/game/gfx.gd` differs between the staged builds.

Retroid Pocket 5, Android 13/API 33, Adreno 650, Mobile/Vulkan, 1920×1080,
render scale 1.0. Medium is the unchanged preset id 3. Gipat (`gz1g`) contains
48 units and 730 objects; Ingos (`gz11k`) contains 234 units and 2,078 objects.
The held benchmark keeps rendering, effects and HUD active while holding world
simulation and following a wall-clock camera route. It warms for 25 seconds,
then measures three ten-second phases on Gipat or eight-second phases on Ingos.

| Medium held route | Before FPS | After FPS | Before mean / p95 ms | After mean / p95 ms | FPS gain |
| --- | ---: | ---: | ---: | ---: | ---: |
| Gipat stationary | 11.58 | 12.36 | 86.32 / 88.59 | 80.88 / 83.10 | 6.7% |
| Gipat first pan | 10.83 | 11.66 | 92.30 / 111.20 | 85.78 / 100.42 | 7.6% |
| Gipat repeat pan | 10.75 | 11.59 | 93.01 / 108.89 | 86.27 / 101.96 | 7.8% |
| Ingos stationary | 11.66 | 12.51 | 85.75 / 87.68 | 79.93 / 81.64 | 7.3% |
| Ingos first pan | 9.85 | 10.27 | 101.53 / 111.63 | 97.40 / 106.10 | 4.2% |
| Ingos repeat pan | 9.79 | 10.26 | 102.16 / 115.46 | 97.43 / 107.73 | 4.9% |

Reinstalling the baseline and candidate and repeating the complete Gipat route
gives **11.65 / 10.85 / 10.79 FPS** before and **12.32 / 11.68 / 11.61 FPS**
after: a repeat gain of 5.7–7.7%. The second candidate's mean frame times are
81.17 / 85.63 / 86.14 ms, versus 85.82 / 92.20 / 92.67 ms before.

The first Gipat pan compiles two draw pipelines on both builds; the repeat pan
compiles none. The candidate's first-pan maximum is 125.58 ms versus 118.30 ms
for the baseline, despite better mean and p95 times. These measurements do not
establish that every individual hitch is shorter.

Original quality (preset id 1) averages 60.00–60.02 FPS on both builds over the
same three Gipat phases. Its p95 callback intervals change from
17.43 / 17.40 / 17.43 ms to 17.32 / 17.35 / 17.39 ms. One candidate repeat-pan
interval is 30.38 ms; its mean remains 16.66 ms. This is a 60 Hz FIFO device,
so this pass does not demonstrate an Original-preset FPS increase or an uncapped
throughput estimate. The request to disable VSync emits the same unsupported
mode warning on both builds and falls back to enabled VSync.

`map_pan_live.gd` keeps world/session physics and the production camera
controller active. Medium, Gipat, 20-second warm-up and ten-second phases:

| Live route | Before FPS | After FPS | Before mean / p95 ms | After mean / p95 ms |
| --- | ---: | ---: | ---: | ---: |
| Stationary | 11.88 | 12.60 | 84.17 / 86.25 | 79.38 / 81.94 |
| First pan | 11.71 | 12.58 | 85.39 / 97.93 | 79.46 / 92.72 |
| Repeat pan | 11.66 | 12.53 | 85.78 / 99.33 | 79.83 / 93.73 |

Both live runs advance approximately 10.1–10.2 simulated seconds per phase.
They corroborate the gain but are not deterministic replay. Frame distributions
measure wall-clock callback intervals; `TIME_PROCESS` includes GPU blocking and
is not treated as pure CPU time. End-of-phase GPU queries are samples, not
whole-run percentiles. Timing builds have no GDScript profiling wrappers.

## Investigation and retained scope

The already-optimized Medium stationary scene remains GPU-bound: its initial
profile spends approximately 54 ms in opaque rendering, 21 ms in transparent
rendering, 3.8 ms in shadows and 2.7 ms in SMAA, with about 1.2 ms of sampled
render CPU time. This pass targets shader cost rather than adding another CPU
cache to that workload.

Diagnostic removal of terrain, relief, fog and shadows helped locate costs;
those quality reductions are not part of the change. A shared terrain-trait
gather passed independent GPU comparisons and was faster on its own, but made
the combined production shaders slower than the selected light/fog pair. It
was removed. Cross-light caching, extra vertex metadata and alternative water
loops also failed to improve the selected workload and were not retained.
Individual diagnostic gains must not be added together.

## Rendering validation

All final image checks run on the final APK and physical Adreno GPU:

- `mobile_light_loop.gd`: **196 checks, zero failures**, covering zero, one,
  two, four and overflowing point lights; moved/recoloured lights; no sun;
  spot/local lights; and Original/detail transitions. All fourteen cases are
  pixel-identical between compact and original loops, as are their repeated
  reference captures.
- `mobile_clear_fog.gd`: **73,728 pixel checks, zero failures** against the
  independent original fog function. Six border/range configurations cover
  clear/partial/full fog, distance thresholds, map edges, out-of-map positions,
  small maps, disabled borders and linear/menu borders. It compares final
  blended RGB and fog alpha, and checks for non-finite values.
- `mobile_render_work.gd`: **six checks, zero failures**. Three complete 1080p
  Gipat views are pixel-identical between the old and combined new programs;
  repeated references are also identical. This includes the coast, terrain,
  scenery and a fogged map edge.
- `material_shader_options.gd --supported-renderer-only`: **368 checks, zero
  failures**, with 102 actual draw variants. Existing materials survive repeated
  detail toggles, terrain/deformation/weather changes and the dynamic diagnostic
  fallback while retaining their shader identity and parameters.

The first whole-map fixture disabled the Game parent but left the World's
independent PAUSABLE process group active. Its repeated-reference checks caught
moving water and foliage. The corrected fixture freezes every child process
group and shader TIME; the original comparison tolerances are unchanged.
This correction is confined to the image test, not the performance benchmarks.

The unrestricted material fixture deliberately forces volumetric fog, which
`Gfx.on` disables outside Forward+. Ground-contact variants with that forced
combination exceed the Adreno's 28-varying limit (29 requested) on **both** the
baseline and candidate. This is recorded separately, not counted as a pass.
The fixture's default still probes all modes; `--supported-renderer-only` opts
into the modes available to players on the current renderer.

The new fixtures require an actual Mobile renderer; their readbacks exercise
the GPU driver rather than only the shader parser. `mobile_render_work.gd`
also requires original game data. They use the existing `--tool=` entry point
and `--ei-path=` data argument. The existing held/live benchmark configuration
for Gipat Medium is:

```json
{"zone":"gz1g","preset":3,"seconds":10,"warmup":25,"width":1920,"height":1080}
```

For diagnostic controls, `--ei-expanded-mobile-lighting` restores the previous
four-light loop source, and `--ei-full-mobile-fog` restores the original fog
calculation. These are internal command-line switches, not player options.

## Artifacts and limits

The final private QA APK SHA-256 is
`34c4b08cc954a33195ebb1eff694c4149f07da6ec2e0826973db6fdbdc322431`.
The baseline APK SHA-256 is
`aafba01afb9ad776a3697bfdc6c795ead235e265405b153f5c9106ee70a18bef`.
Both contain native engine SHA-256
`bd398cfa7857d40bc1847af64ea18d1a8815881003e3bc7cc63ebb8e4b04e712`.
Import/export succeeds; this pass requires no additional engine patch.
The [machine-readable record](android-vulkan-shader-performance-2026-10-17.json)
contains configurations, identical option values, timing distributions, raw-log
hashes, source/build hashes and GPU test results.

Read-only samples during the comparison batch report battery temperatures of
33.7–34.5°C and thermal status 0. Observed GPU clocks are 587 and 670 MHz;
clocks were not locked. Device performance and fan settings were not changed.

These measurements qualify one Retroid and two maps. Medium still averages
roughly 10–13 FPS in these demanding native-resolution views. Other Android
GPUs and longer thermal runs require separate measurements; this pass makes
no additional desktop performance claim. The isolated QA package's original
settings are restored, its autorun is removed and it is stopped after testing.
The normal game and its saves are untouched. No version bump, public release
or shared export-template replacement is included.
