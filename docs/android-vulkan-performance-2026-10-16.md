# Android Vulkan terrain performance

The Mobile renderer now shares the expanded terrain sampler across the centre
colour and four relief samples. Android Mobile also uses the existing bounded
terrain colour cache. Immutable atlas colour blending is baked once for resident
sectors; lighting, weather, sharpening, normals and water levels remain live.
No graphics option, preset, resolution or simulation rule changes.

The cache retains its 128 MiB resident image-data budget, two worker jobs and
one texture upload per frame. Vulkan baking uses linear colour interpolation
and sRGB output. Sectors with pending or installed footprints suspend their
cache override so the live deformation material remains visible. Expiry restores
the resident material without rebaking; eviction and late uploads also respect
the deformation owner. The Compatibility cache's soft-ground restriction remains.
Forward+ retains its existing shader path.

## Measurements

Retroid Pocket 5, Android 13, Adreno 650, Mobile/Vulkan, 1920×1080, render scale
1.0, Medium preset. Private builds use the native libraries from stable 1.8.0
(`9da07801` source base). The normal installed game and its saves were not edited.
Final timing builds have no per-frame GDScript profiling wrappers.

The held-simulation route in `tools/benchmarks/map_pan.gd` keeps the authored
population and follows wall-clock camera positions. Presentation, effects and
HUD remain active. Each phase lasts 12 seconds after 12 seconds of warm-up.
The device falls back to enabled VSync when disabled VSync is requested; these
measurements are far below its 60 Hz cap.

| Held route | Baseline FPS | Candidate FPS | Baseline mean / p95 ms | Candidate mean / p95 ms |
| --- | ---: | ---: | ---: | ---: |
| Stationary Gipat coast | 2.84 | 10.93 | 351.98 / 356.49 | 91.46 / 93.35 |
| First pan | 2.67 | 9.95 | 374.88 / 406.92 | 100.55 / 117.21 |
| Repeat pan | 2.67 | 9.92 | 374.73 / 405.20 | 100.80 / 117.80 |

A second candidate run, after the clean baseline control, measured **10.96 /
9.94 / 9.96 FPS** for the same three phases.

That is about 74% less mean frame time. The stationary GPU query fell from
352.05 to 88.98 ms. CPU callback profiling and land-removal diagnostics identified
terrain shading as the dominant cost: removing land reduced the original GPU
query to about 43 ms, while removing water alone left about 330 ms.

A same-process control with the new sampler measured about 6.2 FPS without the
colour cache and 10.9–11.0 FPS with it. Returning to the uncached path returned to
6.2 FPS. Vertex metadata caching, a four-tap-only loop and nested corner loops
were rejected after device measurements. Looping the already-small baked sampler
also regressed; that shader retains its original call sites.

`map_pan_live.gd`, with world/session physics and the production camera controller
active, measured 2.69–2.76 FPS before and 10.42–11.04 FPS after. This corroborates
the improvement but is not deterministic replay: the baseline advances only
7.7–8.0 simulated seconds per ten-second window, while the candidate advances
about 10.1–10.2 seconds. These live workloads must not be treated as identical.

## Rendering and regression checks

The five independent atlas-sampling call sites also produced darker terrain on
the Adreno than on the desktop Mobile renderer. The compact shader preserves
the original coordinates, gradients, centre traits and four relief taps. The
exact driver mechanism has not been established.

A clean 1.8.0 Linux runtime and RTX 3090 provide the colour reference, not a
desktop performance claim. In a fixed terrain crop, mean absolute RGB byte
differences from that reference changed from **17.91 / 25.89 / 5.09** for the old
Android path to **2.00 / 2.45 / 1.08** for the candidate. Desktop original versus
compact differs by **0.44 / 0.62 / 0.18**. Live foliage/shadows and filtered baked
textures prevent these scene comparisons from being bitwise comparisons. The
candidate's cached/uncached terrain control averages less than one byte per
channel in the same crop.

- 17,966 terrain-sector checks pass on Linux and physical Android, including
  actual native deformation, cache suspension, late upload, eviction, material
  refresh, expiry and restoration.
- 3,300 native terrain-colour checks pass, including rotations, gutters, shared
  borders, linear interpolation, sRGB encoding and worker-owned image data.
- Eight existing soft-ground material-copy checks pass.
- 96 GPU sampler checks pass on Android Mobile, desktop Mobile and desktop
  Compatibility. They compare every output against independent original calls,
  including edge overshoot, centre clamping and disabled relief.
- 14 real-map cache lifecycle checks pass on Android in the authored Ingos map:
  cached snow, a visible native footprint, expiry, detail off/on, Natural terrain
  and complete cache cleanup. Captures wait for new camera shadow cascades to
  settle before comparison.
- 14 composed shader variants draw/read back on Android Mobile.

## Scope and reproduction

This remains a slow scene at roughly ten FPS. Large views, cache misses and
remaining live terrain/water shading still cost substantial GPU time. Only one
Android device was measured. Related investigation: [issue #3](https://github.com/TheWWWorm/CursedLands/issues/3).
The Adreno 840 from that issue was not available, and this does not establish a
fix for its separate OpenGL driver crash.

Run the existing held/live benchmark tools with a configuration containing
`zone: gz1g`, `preset: 3`, `width: 1920`, `height: 1080`, `seconds: 12` and
`warmup: 12`. On desktop, `--ei-baked-terrain` enables the otherwise Android-only
cache for validation. `terrain_sampling.gd` requires an actual renderer;
`terrain_color_lifecycle.gd` requires Mobile and the original game data.

Private Android validation used a separate package and an external test-tool
bootstrap. Autorun is removed and that package is stopped after each run. No
public release or version bump is part of this change. Machine-readable results
and build hashes are in [the measurement record](android-vulkan-performance-2026-10-16.json).
