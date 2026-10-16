# Android Vulkan: skip unused water reflection work

Enhanced water on Android Mobile now omits its scene-reflection tracer and
screen-colour sampler when scene reflections are disabled. Shore depth,
transparency, foam, moving normals, sunlight and sky/cloud reflections retain
their existing calculations. When scene reflections are enabled, water requests
only the screen level it actually reads: every screen-colour lookup explicitly
uses mip level zero. A companion engine patch makes Mobile honor that demand:
copy level zero every time a screen consumer needs it, but generate the higher
levels only when a visible material requests mip filtering. Mip consumers,
including next-pass materials and restored MultiMeshes, keep the full chain.
The flag is reset for each render list and updated through normal material-cache
invalidation. Buffer allocation stays compatible with consumers returning.

The existing shader cache tracks the reflection setting and rebuilds retained
materials when it changes. Shader/material identities and live parameters are
preserved. Natural/Mirror switches continue to use their existing uniforms.
The change adds no per-frame uploads, time-based cache or reduced quality setting.
Desktop, Forward+ and Compatibility keep their previous default programs.

Related Android tracking: [#3](https://github.com/TheWWWorm/CursedLands/issues/3).

## Device measurements

These are incremental measurements against `be60a1c2`, after the previous
[Mobile shader pass](android-vulkan-shader-performance-2026-10-17.md), rather
than against published 1.8.0. The candidate adds the focused Mobile engine patch;
other native libraries are identical. Only `src/game/gfx.gd` and
`src/ei/terrain.gd` differ among the tracked game files in the staged builds.
Both use the same QA export preset and diagnostic startup entry point.

Retroid Pocket 5, Android 13, Adreno 650, Mobile/Vulkan, 1920×1080, render scale
1.0. The held route retains animated rendering, effects and HUD while holding
simulation. The live route also runs physics and the production camera. Options,
map populations and benchmark configurations match within each pair. GPU clocks
are not locked. Frame distributions are wall-clock callback intervals;
`TIME_PROCESS` includes GPU blocking and is not used as pure CPU time.

| Scenario | Before FPS | After FPS | Before mean / p95 ms | After mean / p95 ms | FPS change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Gipat Medium stationary | 12.33 | 12.57 | 81.10 / 83.28 | 79.54 / 81.55 | +2.0% |
| Gipat Medium first pan | 11.70 | 11.88 | 85.49 / 101.00 | 84.19 / 99.19 | +1.5% |
| Gipat Medium repeat pan | 11.60 | 11.79 | 86.20 / 100.68 | 84.79 / 98.92 | +1.7% |
| Ingos Medium stationary | 12.47 | 12.66 | 80.18 / 82.67 | 78.99 / 80.98 | +1.5% |
| Ingos Medium first pan | 10.32 | 10.39 | 96.89 / 107.53 | 96.29 / 106.74 | +0.6% |
| Ingos Medium repeat pan | 10.16 | 10.34 | 98.43 / 109.77 | 96.72 / 107.00 | +1.8% |
| Gipat reverse-order repeat stationary | 12.38 | 12.56 | 80.81 / 82.81 | 79.63 / 81.24 | +1.5% |
| Gipat reverse-order repeat first pan | 11.70 | 11.82 | 85.47 / 100.19 | 84.62 / 102.45 | +1.0% |
| Gipat reverse-order repeat repeat pan | 11.68 | 11.79 | 85.63 / 99.03 | 84.80 / 99.07 | +1.0% |

Additional Gipat cases:

| Scenario | Before FPS | After FPS | Before mean / p95 ms | After mean / p95 ms | FPS change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Medium, reflections on stationary | 10.94 | 10.98 | 91.43 / 95.27 | 91.10 / 94.27 | +0.4% |
| Medium, reflections on first pan | 10.86 | 10.86 | 92.12 / 109.86 | 92.12 / 111.30 | +0.0% |
| Medium, reflections on repeat pan | 10.87 | 10.92 | 92.01 / 109.94 | 91.61 / 110.83 | +0.4% |
| Medium, live simulation stationary | 12.63 | 12.88 | 79.20 / 81.17 | 77.66 / 79.73 | +2.0% |
| Medium, live simulation first pan | 13.03 | 12.65 | 76.73 / 88.64 | 79.05 / 89.82 | -2.9% |
| Medium, live simulation repeat pan | 13.29 | 12.74 | 75.22 / 91.03 | 78.49 / 91.43 | -4.2% |
| Medium, live reverse-order repeat stationary | 12.62 | 12.86 | 79.26 / 81.55 | 77.76 / 80.02 | +1.9% |
| Medium, live reverse-order repeat first pan | 12.64 | 12.77 | 79.11 / 90.77 | 78.29 / 90.84 | +1.0% |
| Medium, live reverse-order repeat repeat pan | 12.62 | 12.60 | 79.22 / 91.38 | 79.34 / 90.48 | -0.1% |
| Original stationary | 59.99 | 60.01 | 16.67 / 17.33 | 16.66 / 17.39 | +0.0% |
| Original first pan | 60.01 | 60.00 | 16.66 / 17.45 | 16.67 / 17.30 | -0.0% |
| Original repeat pan | 60.01 | 60.01 | 16.66 / 17.27 | 16.66 / 17.35 | -0.0% |

The reverse-order held and live repeats run candidate first, then baseline.
The live repeat was added after the first pair's moving-camera phases regressed,
to check whether that result was consistent. Original quality remains limited
by the device's 60 Hz FIFO presentation; its FPS cannot
establish an uncapped speedup. Requested disabled VSync produces the same
unsupported-mode warning in both builds.

Gipat Medium gains **1.0–2.0%** across the two held-route pairs. Ingos gains
**0.6–1.8%**. These are modest incremental reductions; the demanding native-resolution
Medium views still average roughly 10–13 FPS. With scene reflections enabled,
the measured **0.0–0.4%** difference does not establish a reliable FPS gain.

Live stationary rendering gains **1.9–2.0%** in both pairs, but live panning is
inconclusive. The first pair changes by **−2.9% / −4.2%** during the two moving
phases; the reverse-order pair changes by **+1.0% / −0.1%**. Both use the same
options and population and advance approximately 10.1–10.2 simulated seconds
per phase. Camera paths and visible surfaces differ slightly because this is
live gameplay rather than deterministic replay. These results do not establish
a consistent live-panning benefit.

Individual tail intervals are not uniformly better. Ingos's first-pan maximum
changes from **109.02 ms to 120.17 ms**, and the reflection-enabled repeat-pan
maximum changes from **119.24 ms to 143.64 ms**. The reverse-order held Gipat
first-pan p95 also changes from **100.19 ms to 102.45 ms**, despite its lower
mean. The record retains these outcomes and pipeline-compilation counts; this
pass makes no general hitch-reduction claim.

## Rendering and setting changes

The game changes passed their first checks on the prior native runtime. The
mip-demand fixture, water-reflection image comparison and water-option fixture
then passed on the final native runtime. The record identifies the engine used
for every test.

- `mobile_screen_mips.gd`: **24 checks, zero failures on each engine**, with all **12 captures pixel-identical across engines**. Mixed level-zero/higher-level consumers,
  hidden/culled/restored surfaces, live shader changes, empty/restored
  MultiMeshes and next-pass materials are compared to forced full-mip references.

- `mobile_water_options.gd`: **663 checks, zero failures**, with **132 actual
  draws** covering six water programs, scene reflections off/Natural/Mirror,
  sheet/volume cloud consumers, repeated setting changes and the dynamic
  diagnostic fallback. Existing materials retain their identities and water
  clock. Shore depth remains present; disabled scene-colour dependencies are
  removed and restored with the setting.
- `mobile_water_render.gd`: **12 full-map comparisons, zero changed pixels**, including repeated references. Nine views exercise the final game source on the prior engine; the three reflection-enabled views are repeated on the final engine. Three full 1080p views each are checked
  with scene reflections off, scene reflections on, and wet weather with cloud
  reflections/current/interaction/waves. Each candidate is compared to the
  previous program and to a repeated reference, with the entire scene and shader
  TIME frozen. This freeze applies only to correctness tests and specifically
  labelled diagnostics, not the final animated performance routes.
- `material_shader_options.gd --supported-renderer-only`: **368 checks, zero failures**, with **102 actual draw variants**.
  This uses the renderer's supported modes; the pre-existing forced-volumetric
  combinations documented in the previous report are outside this qualification.

The first option fixture incorrectly expected renderer-owned screen/depth
samplers in Godot's editable uniform list. `ShaderCompiler` explicitly excludes
those hints. The corrected fixture inspects declarations after preprocessing
using an inspection-only shader copy with ordinary samplers. GPU draws always
use the actual production shaders. No pixel tolerances were changed; the initial
failed fixture result is retained in the machine-readable record.

## Investigation

Lighting reuse across stages, conditional per-light evaluation, removing unused
vertex lighting, active-light loop bounds, terrain lookup shortcuts and direct
uniform selection were tested and rejected. Several plausible reductions made
Adreno shaders slower. Direct uniform selection initially looked faster with
animated effects, but became slower in a controlled frozen comparison and was
removed. The final change contains none of these lighting/terrain experiments.

In the frozen production comparison, disabling the unused reflection program
changes mean frame time from **77.75 ms to 75.21 ms**, with a repeated original
at **78.15 ms**. All corresponding images are pixel-identical. This diagnostic
motivated the final APK measurements above; it is not added to their gains.

The isolated mip-level test with scene reflections enabled averages
**90.60 / 90.41 ms** for two original passes and **90.41 / 90.50 ms** for two
level-zero-only passes. Images are identical. That is within timing variation;
the old Mobile renderer generated the full chain regardless of the sampler
hint. The subsequent engine patch removes that work; the final reflection-on
APK comparison above measures the combined implementation.

## Reproduction and artifacts

The internal `--ei-dynamic-mobile-water` switch restores the previous water
program and screen sampler. `--ei-dynamic-material-shader` also retains the
dynamic diagnostic path. These are developer controls, not player options.
The GPU fixtures use the existing `--tool=` entry point and, for map tests,
`--ei-path=` original-data argument. The full-map fixture accepts `extra_options`
and `wet_weather` properties for the additional cases.

The final isolated QA APK SHA-256 is
`d390610c39ba9cdf6b425dc383be8fc4410ba4bffc5aff78f393e9e2ccf8192e`.
Its native engine SHA-256 is
`5715b3e0ee30c9b42f724ceed1a0571d51240d6cd1d2abd6105ebe0ca44fa8bd`.
The comparison APK SHA-256 is
`34c4b08cc954a33195ebb1eff694c4149f07da6ec2e0826973db6fdbdc322431`,
with engine SHA-256
`bd398cfa7857d40bc1847af64ea18d1a8815881003e3bc7cc63ebb8e4b04e712`.

Import/export and the Android ARM64 native build pass. The source audit checks
all 17 inherited native-patch files and records the five files changed by this
patch. The patch applies after `mobile-render-work.patch`; existing Forward+
copy callers retain the original default. The native patch has been exercised
on Android Mobile, not qualified for desktop Mobile, compositor effects or XR.

Read-only samples during the comparison batch report battery temperatures of
34.5–35.0°C and thermal status 0. Observed GPU clocks are
587 MHz. Performance and fan settings were unchanged.


The [machine-readable record](android-vulkan-water-performance-2026-10-17.json)
contains exact configurations, option values, distributions, image and log hashes,
rejected diagnostics and source/build hashes. The private QA app's settings are
restored, autorun is removed and the app is stopped after testing. The normal game
and its saves are untouched. No version bump, public release or shared engine
export-template change is included. These results qualify one device; they do
not establish gains on other Android GPUs or desktop.
