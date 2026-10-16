# Android Vulkan: Original quality

The Mobile renderer avoids repeated light evaluation and rendering work with
no visible consumer. Particle materials omit their depth dependency when both
soft particles and through-obstacle display are inactive. Stable particle
options and original point-light uniforms are uploaded only when they change.
Empty instances no longer split the Mobile render pass just because their
materials declare depth/screen inputs. The sky can defer unused radiance
updates, and the directional shadow shader shares its repeated PCF call site.
Android Vulkan uses FIFO presentation without the additional Swappy pacing
layer. No quality preset, render scale, shadow resolution, filter sample count,
simulation rule or player-facing option changes.

Related investigation: [issue #3](https://github.com/TheWWWorm/CursedLands/issues/3).
The earlier [terrain work](android-vulkan-performance-2026-10-16.md) is retained.
Its Medium-preset measurements are separate from the Original-preset results
below.

## Device measurements

Retroid Pocket 5, Android 13/API 33, Adreno 650, **Mobile/Vulkan**, 1920×1080,
render scale 1.0, the unchanged `GfxPresets.ORIGINAL` values (preset id 1).
Both builds use the authored Gipat coast map `gz1g`, with 48 units and 730
objects. Final builds contain no per-frame GDScript profiling wrappers.
The published control is stable 1.8.0, source `9da07801`, with its shipping
native libraries. The final candidate includes the prior terrain commit
`2763071c` and the game/native changes documented here.

`tools/benchmarks/map_pan.gd` holds simulation while keeping rendering, effects
and HUD active. Both matched runs use 18 seconds of warm-up and three
15-second measurement phases, following the same wall-clock camera route.

| Held route | Published FPS | Final FPS | Published mean / p95 ms | Final mean / p95 ms |
| --- | ---: | ---: | ---: | ---: |
| Stationary | 60.006 | 60.007 | 16.665 / 16.826 | 16.665 / 17.339 |
| First pan | 50.618 | 60.009 | 19.756 / 34.058 | 16.664 / 17.390 |
| Repeat pan | 50.615 | 59.999 | 19.757 / 34.051 | 16.667 / 17.356 |

The pans improve by approximately 18.5% in average FPS, with their p95 frame
time nearly halved. The final held route has no measured frame over 25 ms.
Its end-of-phase GPU queries are 12.26 / 12.36 / 12.34 ms. These queries are
samples, not whole-run GPU percentiles or an uncapped FPS measurement.

`map_pan_live.gd` keeps world/session physics and the production camera
controller active, including smoothing, ground clearance and scenery fading:

| Live route | Final FPS | Mean / p95 ms | Simulated seconds |
| --- | ---: | ---: | ---: |
| Stationary | 60.006 | 16.665 / 17.710 | 15.015 |
| First pan | 59.998 | 16.667 / 18.332 | 15.015 |
| Repeat pan | 60.005 | 16.665 / 19.280 | 15.015 |

The live repeat phase has two CPU frame-callback intervals over 25 ms
(35.551 and 25.701 ms); its average remains 60 FPS. Live simulation is not a
deterministic replay, so it is corroborating evidence rather than a matched
before/after workload.

The display exposes a 60 Hz FIFO swapchain; a request to disable VSync falls
back to enabled VSync. SurfaceFlinger actual-present timestamps independently
show 60.005 FPS in every sampled final held/live phase, with zero intervals over
25 ms. Final sampled presentation maxima are 16.716 ms held and 16.737 ms live.
Published pan samples contain 113 and 118 intervals over 25 ms respectively,
with p95 around 33.35 ms. Sampling uses fixed interior phase bounds and
deduplicates overlapping timestamp histories; no sample is rejected based on
frame duration. Startup and benchmark screenshot readbacks between phases are
outside those bounds. This establishes the display's 60 FPS cap on this route,
not a measured presentation rate above 60 Hz.

Battery temperature finishes at approximately 31.7°C, thermal status 0, with
the GPU reporting 587 MHz. Device performance/fan settings were not changed.

## Expensive work removed

- Original materials already include the selected four original point lights
  in their packed vertex lighting. A native, per-surface opt-in removes those
  lights from Mobile's repeated fragment light calls and shader specialization
  count. Ordinary Godot materials still receive them, including other surfaces
  of the same mesh. Enhanced local lights and overflow lights retain their
  normal paths. Selection, movement, visibility and colour remain live.
- The game opts in only with a visible, energized sun and no additional
  material highlights, foliage lighting or weather surfaces. Shadowed,
  projected, negative, distance-faded and nonzero-attenuation lights are excluded.
  Grass/solid-cover shaders retain their transmission calls. Owned flags are
  cleared on option/selection changes and game teardown; weak references do
  not keep lights alive. Native light bake mode and cull masks are unchanged.
- Mobile's half-precision light direction and attenuation could make the old
  matcher misidentify an already packed light as an overflow light and add it
  again. Normalizing the promoted direction and comparing the forward falloff
  fixes that duplicate response. The native omission is compared against this
  corrected full-light path; the change is not claimed to preserve the old
  erroneous double lighting pixel for pixel.
- A zero particle soft-distance uniform still made Godot prepare a depth
  texture. Shader variants now remove that unused declaration. Through-obstacle
  markers retain depth reads and disabled depth testing; additive blending,
  reflection markers, live soft-option changes and shader identities survive.
  Material option uploads are cached, while particle interpolation stays live.
- An empty MultiMesh cannot draw but previously contributed material flags
  that could force a depth copy and split the Mobile pass. It is now skipped
  before those flags are accumulated, after dirty instances have been updated.
- Only the game's explicitly opted-in sky defers radiance with no ambient,
  reflection, aerial-fog or shader `RADIANCE` consumer. Background and sky
  subpasses remain active. Consumers restore current radiance before use;
  ordinary sky materials keep their existing update/bake contract.
- The shadow shader shares one PCF call site between the primary and transition
  cascades and skips the second filter when its blend weight is zero. All four
  cascades, filter taps, bias, blur, fade and nonzero transition blending remain.
- Disabling Swappy removes an additional pacing bottleneck on this device.
  In an intermediate fixed-view control, the same candidate went from 43.4 to
  52.2 FPS while its GPU query remained about 17.1 ms. FIFO VSync is retained.
  The setting is read in the Android Vulkan driver, not the GLES path.

Forward+ and a separate render thread did not improve this device's measured
workload and were not selected as performance fixes. Fog-colour cache and
quality-reduction diagnostics are not included in the production change.

## Rendering and regression checks

- **106 particle checks** pass on physical Android Mobile and Compatibility:
  all eight additive/through/marker variants, soft off/on/off, visible GPU
  comparisons against the unspecialized shader, empty-to-visible transitions,
  stable shader identity and new-material/cache invalidation.
- **66 original-light checks** pass on Android Mobile using real figure and
  terrain lighting programs. They cover selection, moved/recoloured/hidden/freed
  lights, optional highlights/transmission/weather, excluded special lights,
  unchanged values and teardown. Native omission matches the corrected full
  light path within the fixture's two-byte channel tolerance.
- **17 native light checks** pass for mixed custom/ordinary surfaces, zero/one/
  multiple/all flagged lights, index reordering and opaque/transparent draws.
- **22 lazy-sky checks** pass for screen/radiance output and none/ambient/
  reflection/aerial-fog/`RADIANCE` consumer transitions, including two viewports
  sharing a sky. The existing **84 sky-subpass checks** also pass.
- **Eight paired shadow captures are byte-identical** between the shipping and
  final engines, with cascade blending off/on at four camera positions.
- The Android engine builds, the patch applies cleanly to the shipping
  fourteen-patch source tree, and its reverse applies cleanly to the built tree.
  The final game imports and exports successfully.

Particle assertions also pass on Android Forward+ (106), but that renderer
reports a Vulkan compute-pipeline startup error; it is not counted as a clean
runtime acceptance. An official desktop 4.7 Forward+ run passes the same pixel
assertions but encounters its separate-render-thread shutdown error. These
additional runs do not qualify Forward+ or a new desktop engine template.

A later [desktop follow-up](desktop-performance-2026-10-16.md) runs the particle
fixture successfully with the shipping Linux runtime and measures the shared
CPU caches. Its repeated desktop FPS tests do not establish an overall gain;
the Android FPS result above remains device- and renderer-specific.

## Builds, reproduction and limits

Apply `engine_patches/godot-4.7/mobile-render-work.patch` after the fourteen
shipping Android patches, following the [engine recipe](../engine_patches/godot-4.7/README.md).
The native capabilities gate game opt-ins; older runtimes remain supported.
Never emulate those capabilities with export feature tags. The fixture scripts
run through the existing `--tool=` entry point with original data supplied via
`--ei-path=`. For the held/live benchmarks use:

```json
{"zone":"gz1g","preset":1,"seconds":15,"warmup":18,"width":1920,"height":1080}
```

The final private QA APK SHA-256 is
`aafba01afb9ad776a3697bfdc6c795ead235e265405b153f5c9106ee70a18bef`.
Its native engine SHA-256 is
`bd398cfa7857d40bc1847af64ea18d1a8815881003e3bc7cc63ebb8e4b04e712`.
The [machine-readable record](android-vulkan-original-performance-2026-10-16.json)
contains source hashes, native build command, full timing rows, test results,
presentation sampling details and raw-log hashes.

The installed QA package is `org.cursedlands.vulkanbench`, set to Original,
Mobile/Vulkan and native resolution with automatic quality adjustment off.
Benchmark autorun is removed. The normal `org.cursedlands.engine` 1.8.0 app and
its saves remain untouched. This is a private validation build, with no version
bump, published release or shared export-template replacement.

Only this Retroid and Gipat route establish the 60 FPS result. Other maps,
longer thermal runs and other drivers require separate measurements. The
Adreno 840 from issue #3 was unavailable; this does not establish a fix for its
separate OpenGL crash. Medium and higher quality are not covered by this
60 FPS claim.
