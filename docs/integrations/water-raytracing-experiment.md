# Water ray-tracing experiment

This experimental feature adds **Options → Graphics → Water → Water reflections →
Ray traced (test)**. It traces hardware rays with Direct3D 12 or Vulkan into nearby terrain,
objects and animated creatures, then feeds the result into the existing water tint,
distortion and Fresnel shading. It is an optional fourth choice; defaults,
automatic detection and all graphics presets continue to use existing modes.
The label, choices and help are available in English, Russian and German.

The [scene lighting experiment](scene-raytracing-experiment.md) adds
separate main-view RT shadows and one-bounce diffuse GI using this backend.
Its controls, quality budget and output textures are independent of water RT.

## API support

Since **1.24.0**, the Windows executable also supports DXR. 1.23.0 supported
this experiment only with **Forward+ (Vulkan)** and used Mirror in Direct3D 12.

Select **Forward+ (Direct3D 12)** under Screen settings, then **Graphics → Water →
Water reflections → Ray traced (test)**. DX12 is the primary Windows path;
Vulkan remains supported. Both need a GPU and driver with hardware ray tracing.
FSR frame generation still requires DX12. macOS, Android, browser and unqualified
engines retain their established reflection paths.

## Local development build

Run `local/scratchpad/water-raytracing-20261021/run-water-raytracing.sh` from
the EI workspace. This opens the experiment with ray-traced water selected.
The launcher creates a separate profile with a free cursor, FPS visible and all
audio muted. Its saves and settings belong to the experiment. The normal game
profile is not imported. Compare **Mirror** and **Ray traced (test)** in the
water options while looking across a river. Perspective and orthographic cameras
are supported.

The generic launcher is `tools/experiments/launch_water_raytrace.py`:

```sh
python3 tools/experiments/launch_water_raytrace.py \
  --engine /absolute/build/godot-water-rt.x86_64 \
  --ei-path /absolute/EvilIslands \
  --profile /absolute/water-rt-experiment-profile
```

Keep the matching `godot-water-rt.pck` and `src/native/bin` beside the executable.
This launcher retains the isolated Linux development profile. The historical
measurements below describe the experiment before its integration into 1.23.0.

## Scope and limits

- One reflected view of one selected water level, in perspective or
  orthographic cameras. The water shader approximates waves through texture
  distortion; rays do not intersect a fully displaced water surface.
- A 96 m scene snapshot includes terrain, object meshes and creature parts.
  Rigid meshes share geometry; each instance receives current transforms and
  visibility. Original articulated animation and both absolute and relative
  blend shapes update the reflection. Changed morph geometry rebuilds only
  its own acceleration structure. Hidden and invisible units are masked out.
- Moving more than 16 m or changing pools rebuilds the snapshot. A once-per-second
  membership check detects spawned, removed and replaced meshes or materials.
  It also detects edits to supported tint, emission and transparency properties
  on an existing material resource.
  Deleted or hidden instances disappear immediately. Mirror remains visible
  during extraction and GPU preparation.
- Direct sunlight and up to four nearby point lights cast traced hard shadows
  in the reflection. Local-light position, colour and energy update each frame;
  nearby-light membership refreshes once per second. Alpha-tested textures
  preserve foliage silhouettes in both primary rays and shadow rays. Texture
  mipmaps use the projected subpixel footprint on each hit triangle. The
  existing Texture filtering option also controls RT anisotropic filtering.
- Ambient light, material diffuse/emissive properties, local lights and depth
  fog approximate the game's raster materials. This is one reflection bounce
  with direct-light shadows; it does not add global illumination or multiple
  reflection bounces. Mirror and RT are not equal-quality rendering paths.
- Standard materials support opaque surfaces and alpha scissor with their
  authored threshold. Opaque surfaces ignore texture/material alpha. Tint
  affects ambient as well as direct light; solid-colour emission is independent
  of albedo and retains HDR energy. Triangle ArrayMeshes and procedural
  PrimitiveMeshes are supported; point meshes have no reflected surface.
- Particles, shader-only wind, procedural ground effects, custom vertex-shader
  deformations, blended/hashed transparency, textured emission, custom UV
  transforms and normal maps are omitted. Texture pixels are
  snapshots: replacing a texture resource refreshes it, but in-place texture
  painting and mesh edits require a scene rebuild. Lighting and camera-specific
  body shaders are not reproduced exactly.
- The development target scales both viewport dimensions by the selected
  RT quality: Low 50%, Medium 75%, High 100% (default), with no fixed pixel cap.
  Four fixed subpixel rays per output pixel
  smooth geometry and alpha-tested foliage edges without temporal history.
  The HDR output carries premultiplied coverage through bilinear filtering,
  matching the water compositor and avoiding bright edge halos. This costs
  more than 1.23.0's half-resolution, single-sample RT; it is not a free FPS gain.
- Budgets are 320,000 unique triangles, 4,096 instances and 192
  texture layers at 512 × 512 with mipmaps. CPU extraction is staged, although
  an individual mesh or GPU build can hitch. Texture and acceleration-structure
  memory is additional to the ordinary scene; each moving instance also adds
  CPU bookkeeping and can require a top-level acceleration-structure rebuild.
- Unsupported hardware, an unqualified engine, exceeded budgets and backend
  failures retain the established fallback. Forward+ uses Mirror; other
  renderers retain their existing water fallback. Selecting Mirror or Off
  releases the experiment's GPU resources. Presets and normal defaults are
  unchanged.

The planar viewport stays available during preparation and stops drawing when
hardware RT becomes active. The fallback avoids a blank river while a new
snapshot is prepared; it can still cause a visible lighting transition.

## Engine requirement

Use the pinned Godot 4.7 source and sixteen common patches documented in
[`engine_patches/godot-4.7/README.md`](../../engine_patches/godot-4.7/README.md).
Apply `water-raytracing-uniform-stages.patch` for Vulkan. For Windows DX12 also
apply `water-raytracing-d3d12.patch`, after `experimental-fsr.patch` when using
FSR. Rebuild the Windows release template and export the executable with it;
replacing the game pack alone cannot add the DXR backend. Keep the existing
Agility/FSR runtime dependencies and native extensions beside the executable.

The DX12 patch implements acceleration structures, shader tables, DXR pipeline
creation and ray dispatch through the existing RenderingDevice command graph.
It handles both legacy and enhanced barriers and clears new storage textures
before ray dispatch. The runtime checks `ei_d3d12_raytracing`, the hardware DXR
tier and shader model; Vulkan checks `ei_raytracing_uniform_stages`. Both also
require Forward+ and `SUPPORTS_RAYTRACING_PIPELINE`. Unqualified engines fall back.

Godot's pinned NIR translator does not compile ray-tracing shader stages. The
new `shader_create_from_spirv_and_dxil` API imports native DXIL libraries with
matching SPIR-V reflection. This experiment uses one HLSL source,
`game/src/game/fx/shaders/water_raytrace.hlsl`, compiled to both formats with
[Microsoft DXC v1.9.2609](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.9.2609).
The API supports the water binding layout, no specialization/push/dynamic
constants, payloads up to 128 bytes and attributes up to 32 bytes. It does not
provide general GLSL-to-DXR translation or ray queries.

```sh
python3 tools/build_water_rt_shaders.py --dxc /path/to/dxc
python3 tools/build_water_rt_shaders.py --check
python3 tools/build_water_rt_shaders.py --check --dxc /path/to/dxc
```

The manifest pins source/builder/compiler/output hashes. `--check` verifies every stage;
with DXC it reproduces all eight binaries without replacing them. Export presets
include `.dxil` and `.spv`. The game loads these binaries at runtime, so this
change adds no runtime DXC dependency. CPU scene extraction, materials, animation
and shading are shared by DX12 and Vulkan.

## Validation

The local evidence is in `docs/validation/water-raytracing-2026-10-21.json` and
the matching scratch directory. It includes GPU readbacks for nearest hits,
texture access, alpha rejection, misses, water clipping, resizing and cleanup;
real river views; camera and option transitions; and EN/RU/DE option/help
captures. See the evidence for exact results and unqualified platforms.

The initial frame timings are whole-frame wall times on a shared development
machine. The follow-up below also measures the GPU reflection pass separately.
Those historical results use the older, lower-resolution RT settings. They do
not describe the new four-sample path. Compare reflection GPU time and whole-frame
time separately: a CPU-limited scene may keep the same FPS even if RT uses less
GPU time. RT and Mirror still differ in material fidelity.

## DX12 and reflection clarity (1.24.0)

DX12 is the primary Windows development target. The shared shader uses four
spatial samples per reflection pixel at every quality level. Graphics → Water →
RT reflection quality (`q_water_rt_quality`) offers Low (50 %), Medium (75 %)
and High (100 %, default), scaling both dimensions of the game viewport.
High has no fixed 1920-pixel cap: a 3840 × 2160 viewport gets a 3840 × 2160
reflection. The setting is separate from render scale/FSR and does not change
Mirror. Graphics presets and automatic detection preserve the chosen RT quality.
The control is disabled unless water effects and Ray traced (test) are selected.
It applies on confirmation without a restart and persists in the player profile.
The [quality-options validation](../validation/water-rt-quality-options-2026-10-22.json)
records live tier switches and 4K GPU targets on DX12/Wine and Vulkan, saved
settings, and EN/RU/DE layouts. `tools/tests/water_raytrace_options.gd` exercises
the actual settings screen and controller; the GPU quality fixture covers
standard, ultrawide, portrait and odd viewport sizes.

The 1.23.0 target used one sample and half the width/height. Ray hits, cutout
foliage, direct-light shadows, live poses/material edits, and the Mirror fallback
remain supported.
Premultiplied coverage also fixes the old mismatch at filtered/fading edges.
Resizing replaces the backing GPU texture without invalidating the texture
already bound by the water material, avoiding a blank reflection during handoff.

The following measurements predate the quality selector and use the equivalent
High budget at 1280 × 720. On the RTX 3090 test host through Wine/VKD3D-Proton,
comparing 4-sample RT with 2x-MSAA Mirror at **1280 × 720**, with one original
animated character, the integration build's median of three interleaved round
medians was:

| Measurement | RT | Mirror |
| --- | ---: | ---: |
| Reflection GPU time | 0.67 ms | 0.63 ms |
| Whole-frame wall time | 9.72 ms | 12.53 ms |
| Corresponding rendered frame rate | 103 FPS | 80 FPS |

The added samples spend GPU time on clarity. This run does **not** establish
that the RT GPU pass is cheaper than Mirror: its lower CPU submission cost
helped the whole frame despite a slightly higher GPU cost. This is one river
scene on a shared development machine, not a general FPS guarantee. An earlier
session with the same sampling settings measured 84/79 FPS and 0.73/0.63 ms
for RT/Mirror; both raw sessions are retained in the evidence. Materials
still differ; particles, shader wind and the other omissions above remain.

The GPU quality fixture compares silhouettes and cutout edges against a
64-sample reference. Four samples reduced coverage error by 57–67% compared
with one sample, preserved opaque interior colour, and produced deterministic
pixels without temporal history. The FSR fixture verifies real SDK counts,
including 90 generated frames and about 180 presentations per 90 rendered
frames, mode switches, resize and pause/resume. First-use shader preparation
must finish before frame generation and its additional FPS line become active.

Useful fixtures under `tools/tests/`: `water_raytrace_quality.gd`,
`water_raytrace_quality_scene.gd`, `water_raytrace_fsr.gd`, and
`water_raytrace_dynamic_performance.gd`, alongside the existing device,
lighting, material, live-scene, first-person and artifact regressions. Evidence
is recorded in [the DX12 validation bundle](../validation/water-dx12-2026-10-21/summary.json).
The final Vulkan device, lighting and quality fixtures have no API validation
errors with Khronos validation layers 1.4.363.0. This caught and corrected a
missing vertex-buffer address flag and an unused ray-query capability emitted
by DXC. DX12 readbacks pass, but Wine/VKD3D still produces startup shader
diagnostics also seen with the published engine, plus acceleration-structure
range diagnostics consistent with its oversized shared-buffer views. Those
messages and the source-based attribution are retained in the evidence; this
is not a clean native D3D12 debug-layer result. Native Windows and other GPU
vendors remain unqualified.

## Texture filtering follow-up (1.24.0)

The earlier RT shader estimated one mip level from triangle edge lengths.
It could blur detail that should remain visible, especially with stretched
UVs or angled surfaces, and equivalent triangle diagonals could choose different
levels. The closest-hit shader now derives UV gradients from the projected
subpixel footprint on the hit plane. It accounts for perspective/orthographic
cameras, both texture axes, instance scale and the reflection's actual size.
Each of the four spatial samples filters its own subpixel footprint.

The existing **Graphics → World and textures → Texture filtering** setting
now applies to RT: Off retains trilinear mip filtering, and 2×/4×/8×/16× select
anisotropic filtering. Switching it updates the sampler without rebuilding
the reflection scene or its output texture. RT resolution quality remains
independent. This improves reflected texture detail; it does not add missing
material effects or change the fixed four-sample silhouette antialiasing.

`tools/tests/water_raytrace_filtering.gd` checks real GPU pixels on an anisotropic
striped surface, including perspective and orthographic cameras, nonuniform
instance scale, both triangulations and live filtering changes. The previous
shader fails the eight resolvable-stripe contrast cases. The updated shader
passes all 69 checks on DX12/Wine and Vulkan: wide stripes remain distinct
while single-texel stripes remain filtered. The real-river fixture is
`tools/tests/water_raytrace_filtering_scene.gd`.

On the RTX 3090 through Wine/VKD3D, the same moving-character river benchmark
at 1280 × 720, High and four samples per pixel measured approximately **0.66 ms**
for the RT GPU pass both before and after this filtering change (0.655 and
0.662 ms, medians of three round medians). Mirror measured 0.535 ms in both
runs. Whole-frame timings varied between sessions and are retained in the
evidence; they do not establish an FPS improvement from filtering. This one
scene does not establish the cost on other GPUs or texture-heavy scenes.

See the [filtering validation bundle](../validation/water-rt-filtering-2026-10-22/summary.json)
for screenshots, measurements and the regression checks after merging
`feature/autochess-rank-variants-20261021` through `c1f094ae`. These changes are
included in 1.24.0; native Windows qualification remains outstanding. The DX12 river
fixture passed its rendering assertions, then reproduced the previously
recorded Wine shutdown page fault after the game's clean-exit message. This
change does not resolve that existing shutdown issue.

## Cyan water triangle follow-up

The reported cyan wedge at the `gz3g` river bank also occurred in Off and Mirror.
The translucent river mesh contains overlapping slopes. Godot reverses normals
on back-facing triangles; the enhanced water shader clamped their negative
view cosine to zero and therefore calculated 100% sky reflection. Using the
absolute cosine evaluates Fresnel on both sides without removing those faces
or changing the original water mode.

`tools/tests/water_raytrace_artifact.gd` reproduces the exact camera and checks
Off, Mirror and hardware RT, plus two nearby RT camera turns. A negative control
restores the signed cosine and reproduces the wedge in every case. All 19
checks pass; the sampled front-facing water has zero image difference. Before
and after images and the pixel measurements are in
`docs/validation/water-raytracing-followup-2026-10-21/`.

## Initial prototype reflection cost (historical)

Before animated instances and traced shadows were added, on the RTX 3090 at
1280 × 720, three interleaved rounds of 90 samples at the
same frozen river camera produced these reflection-pass GPU median ranges:

| Mode | Reflection target | GPU pass | Whole-frame FPS¹ |
| --- | --- | --- | --- |
| Normal Mirror | 1280 × 720, 2× MSAA | 0.37–0.58 ms | 18.0 |
| Ray traced (test) | 640 × 360, one ray/pixel | 0.05–0.10 ms | 17.5 |
| Diagnostic Mirror | 640 × 360, no MSAA | 0.25–0.45 ms | — |

¹ Reciprocal of the median of three round-median wall times. This shared
machine had substantial concurrent work: an earlier run measured about 24 FPS
in both normal modes. The measurements establish a cheaper RT GPU pass for
this scene, but do not establish an overall frame-rate gain. RT has one quarter
of normal Mirror's pixels and simpler static-scene shading; even the matched
resolution diagnostic is not a quality-matched comparison.

The diagnostic Mirror controller is paused at its frozen camera after setting
the smaller target once, so it cannot repeatedly resize the target back to the
normal size. Only its GPU pass timing is used for comparison. The two normal
modes retain their production controllers. RT GPU timestamps bracket its queued
render-thread work; Mirror uses the engine's measured viewport GPU time.

RT preparation took 3.5–5.4 seconds from selection in the final run, during which
Mirror remains visible. This preparation and snapshot rebuild cost is excluded
from the steady-frame GPU timings. See
`docs/validation/water-raytracing-followup-2026-10-21.json` for raw data, methods,
limits and captures. The reproducible harness is
`tools/tests/water_raytrace_performance.gd`.

## Expanded scene validation

`tools/tests/water_raytrace_lighting.gd` reads back GPU pixels for instanced
transforms, alpha-aware sun and point-light shadows, light removal, orthographic
rays, both MeshInstance blend-shape modes and shadow-only visibility.
`water_raytrace_live.gd` exercises an original campaign character's movement,
walk animation, hide/show transitions and equipment replacement in a real
river scene. The existing device, river, localization and cyan-wedge regressions
remain part of validation.

The expanded implementation's measurements and captures are recorded separately
in `docs/validation/water-raytracing-comprehensive-2026-10-21.json`. The earlier
prototype's timings above do not describe the cost of this version. The static
benchmark retains live-scene polling and all new shadow rays; a second benchmark
animates and moves one original character every frame, forcing live instance
updates. Both measure reflection GPU work and whole-frame wall time separately.
The controller CPU bracket helps account for scene bookkeeping; it is not a
measurement of the entire game's CPU frame.

On the same RTX 3090, the expanded version produced these three-round results:

| Scene | Mode | Reflection GPU median range | Whole-frame FPS |
| --- | --- | --- | --- |
| Frozen river | Mirror | 0.84–1.08 ms | 25.7 |
| Frozen river | RT | 0.23–0.24 ms | 27.3 |
| Moving character | Mirror | 0.63–1.56 ms | 21.2 |
| Moving character | RT | 0.27–0.87 ms | 19.7 |

These are different-quality paths on a shared machine. The results do not
establish an overall speedup. The RT controller's CPU median was 1.69–1.74 ms
in the frozen scene and 3.13–3.68 ms with the character, compared with
0.06–0.08 ms for Mirror's controller. Mirror also has separate render-thread
scene-submission work, so these controller figures are not complete CPU costs.
The moving case includes top-level acceleration-structure rebuilds.

Cold RT preparation took 6.5–6.6 seconds in the frozen scene and 10.4–11.7
seconds with the moving character in these runs. Mirror remains visible during
preparation. The validation report contains 116 passing checks, the raw
per-round timings, and captures; the previous cyan-wedge fix remains covered.

## Scene-update optimization

The next pass moves vertex packing and live transform/visibility comparisons
into the existing native extension. Its watchers retain object IDs, check them
on the main thread and pass plain changed values to the render thread. The
original script implementation remains available on older libraries and with
`--ei-script-water-rt`. Blend-shape deformation still uses the existing script
path. The original optimization pass updated the Linux x86-64 helper binary;
release 1.23.0 also includes the updated Windows x86-64 helper.

The top-level acceleration structure now contains only visible instances.
Hidden geometry receives its own acceleration structure on first reveal and
reuses it afterward. Revealing a mesh builds its latest pose, including changes
made while hidden. A completely hidden scene still returns sky. Structures are
released in dependency order when the experiment is switched off or rebuilt.
CPU mesh data and the full vertex buffer remain allocated; this is not a
proportional reduction in total memory, and first reveal can still hitch.

In the same river/character cost fixture, 433 of 1,438 instances are active and
only 302 of 1,303 geometry structures are built. The previous build is commit
`db47adb391610ca2dfd350aa13cbbda4f0e63989`, with its own archived PCK and native
library. On the RTX 3090 at 1280 × 720:

| Measurement | Previous build | Optimized build |
| --- | --- | --- |
| RT preparation from mode selection | 3.92 s | 2.50 s |
| Scene update CPU, unchanged pose | 0.587 ms | 0.097 ms |
| Scene update CPU, moving character | 0.602 ms | 0.115 ms |
| Whole RT controller CPU, moving benchmark¹ | 2.035 ms | 0.741 ms |
| RT GPU pass, moving benchmark¹ | 0.713 ms | 0.594 ms |

The CPU-only scene probe samples 150 updates after warm-up. The moving probe
changes the same 17 articulated instances per update. Preparation is a single
mode-selection measurement after loading the map; it is not total game startup.
The optimized 640 × 360 reflection image matches the previous build exactly
in the final capture. Against the current script fallback, three pixels differ
by one 8-bit colour level; mesh, triangle and texture counts match.

¹ Median of three round medians, using the interleaved moving-character fixture
with 90 frames per case. The full controller bracket includes more work than
the isolated scene probe. These new baseline and optimized runs were collected
together; do not compare their absolute FPS with the earlier, more heavily
loaded session. Baseline RT/Mirror measured 30.5/32.1 FPS; optimized RT/Mirror
measured 32.3/32.2 FPS. Shared-machine variation and different reflection quality
remain: this establishes lower reflection overhead, not a reliable overall FPS
advantage over Mirror. Normal Mirror still uses 1280 × 720 and 2× MSAA; RT uses
640 × 360 with approximate materials and traced direct-light shadows.

`docs/validation/water-raytracing-optimization-2026-10-21.json` records the
175 passing functional checks, native/script and image comparisons, raw timing
rounds, binary/source hashes and qualification limits. The GPU tests now also
cover empty scenes and hidden-pose updates before a first reveal. The live
character, equipment refresh, camera, fallback, cyan-wedge and EN/RU/DE checks
remain passing. The 49 native parity checks also pass with the extension
translation unit instrumented by AddressSanitizer and UndefinedBehaviorSanitizer.
That CPU check uses software OpenGL and a private loader adapter; it does not
establish sanitizer coverage of the engine or Vulkan driver.

## Material handling and opaque rays

Each geometry now carries its material cutoff and shading type. Terrain and
opaque materials ignore alpha, while alpha-scissor materials use their authored
threshold for both reflection and shadow rays. Fully opaque geometry is marked
opaque in its acceleration structure, avoiding unnecessary any-hit shader
invocations. Foliage keeps alpha testing. The diagnostic command-line switch
`--ei-water-rt-force-anyhit` disables only this optimization for comparison.

Standard material tint now affects ambient light as well as direct light.
Solid-colour emission is independent of the albedo texture and retains values
above one in the HDR reflection. Blended, hashed and depth-prepass transparency
are omitted instead of being treated as solid cutout surfaces. The reflection
still approximates lighting and does not implement the full raster material.

The scene poll detects changes to supported material values even when the
resource ID stays the same, then rebuilds under the existing Mirror fallback.
Procedural triangle meshes are also included. GPU teardown owns its copied
geometry descriptors and no longer clears the CPU scene's array.

`tools/tests/water_raytrace_materials.gd` checks colour, alpha, HDR emission,
shadows, terrain and cleanup using actual GPU readbacks with the opaque flags
enabled and disabled. It passes through both the native and script packing
paths. `water_raytrace_material_live.gd` adds a procedural probe to the real
river and verifies red-to-green emission, transparency and threshold edits on
the same material resource, plus Mirror continuity while rebuilding.

The full pass has 431 successful assertions, including existing animation,
visibility, camera, fallback, cyan-wedge and EN/RU/DE regressions. Engine and
native binaries are unchanged. Evidence and source/binary hashes are recorded
in `docs/validation/water-raytracing-materials-2026-10-21.json`.

Three interleaved moving-character rounds on the RTX 3090 produced these
medians of round medians. Each variant uses the same scene and renderer; the
last two use the exact same PCK with only the opaque flag switch changed.

| Variant | RT GPU pass | RT controller CPU | RT / Mirror FPS |
| --- | --- | --- | --- |
| Previous build `4745d931` | 0.582 ms | 0.748 ms | 33.2 / 31.6 |
| Material handling, opaque flags enabled | 0.582 ms | 0.754 ms | 31.8 / 30.6 |
| Same build, opaque flags disabled | 0.580 ms | 0.761 ms | 32.3 / 31.7 |

The material fixes retain essentially the same reflection-pass cost. Skipping
opaque any-hit work does not produce a measurable timing benefit in this
fixture, and whole-frame variation does not establish an FPS improvement.
Mirror and RT still differ in resolution, antialiasing and material fidelity.
The fixed river reflection matches the prior build exactly; disabling the
opaque flags changes five of 230,400 RGB pixels by one 8-bit channel value.
Preparation in the separate cost probe was 2.71 / 2.56 / 2.63 seconds respectively,
with Mirror visible during each build. There are 751 opaque geometry descriptors
among 1,303 total; that includes hidden geometry and is not an active BLAS count.
