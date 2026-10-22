# Path-traced lighting prototype (experimental)

Since 1.24.0, the Windows and Linux builds add an optional multi-bounce lighting mode for nearby
terrain, objects and characters. It traces direct shadows, diffuse colour
transport and rough glossy reflections through two or four surface bounces.
It is a bounded lighting prototype: the main view still uses raster visibility,
material composition, sky, fog, water and particles. It is not a replacement
for the complete renderer. It first shipped in 1.24.0.

## Controls

Open **Options → Graphics → Lighting and shadows → Ray-traced lighting**.

- **Path tracing (test):** Off, 2 bounces or 4 bounces. Off is the default.
- **RT lighting quality:** Low traces at 50% of the window width and height
  with one path sample per pixel; Medium uses 75% and two samples; High uses
  100% and four samples. Medium is the default. This is independent of water
  reflection quality and the internal FSR/render scale.
- **Path accumulation:** Responsive uses a short filtered history for play.
  Still scene averages up to 256 frames for static comparisons. Moving the
  camera, changing projection/lighting or updating geometry restarts the
  progressive accumulation. Moving scenes can remain noisy.

Path tracing replaces the separate RT shadows and RT indirect-light controls
while active. Their saved settings are preserved; they resume when path
tracing is disabled. All controls use Apply/Cancel and persist to the profile.
Labels, choices and help are available in English, Russian and German.
SSAO and contact-shadow blobs are suppressed while traced lighting is active;
their saved preferences are restored when it stops.

Use the qualified engine described in the
[water RT integration](water-raytracing-experiment.md#engine-requirement).
DX12 is the primary Windows path. Qualified Vulkan Forward+ also supports the
prototype. Unsupported hardware/renderers keep conventional lighting and allow
saved experimental settings to be turned off. No engine patch beyond the
existing native ray-tracing integration is required.

## Implementation

`path_trace_device.gd` reuses the scene RT acceleration structures, texture
lifetime and render-thread submission, with a separate native ray pipeline
and reconstruction shader. Switching between two and four bounces retains
the acceleration structures. Switching between scene RT and path tracing
replaces the pipeline and resets its history. Preparation failures and budget
limits fall back to conventional lighting.

`path_trace.hlsl` uses a camera visibility ray followed by up to two or four
continuation segments. At every hit, direct lighting is evaluated from the
sun and up to seven nearby point lights with traced visibility. A continuation
hit contributes emission and direct illumination; a miss contributes outdoor
sky radiance, or zero sky radiance in caves. Diffuse and GGX glossy lobes are
sampled with a shared mixture PDF. Glossy continuations use
[visible-normal GGX sampling](https://jcgt.org/published/0007/04/01/), with
Fresnel-aware lobe selection and no diffuse samples for pure metals. This
reduces grazing-angle variance without increasing the sample budget. The
bounce count bounds work; there is no
Russian roulette or light reservoir sampling. Geometric normals offset rays
outside the actual triangles, while interpolated normals shade the surfaces.

Outdoor misses now evaluate a continuous zenith/horizon/ground environment
instead of returning the same ambient colour in every direction. The palette
uses the original ambient, sunlight and visible sky colours, with restrained
sky tint and reduced daytime fill: the original renderer used ambient as a
minimum, while PT adds its transported energy to sunlight. Night retains a
stronger sky contribution. The below-horizon environment is faint because
traced terrain already supplies nearby ground bounce. Direct sunlight remains
separate; no second sun disk or extra ray is added. This is an authored
low-frequency approximation, not atmospheric scattering or a captured HDR sky.
The PT frame is 704 bytes, including three environment colours after the
previous inverse view-projection. Environment changes invalidate both temporal
modes. Caves still have a black environment; uniform-sky numerical fixtures
use the explicitly disabled directional mode.

Continuation and shadow origins use a surface-specific floating-point error
bound instead of a fixed 15 mm displacement and 2 mm minimum ray distance.
Hit positions are reconstructed from triangle barycentrics, adding the base
vertex and instance translation last. Bounds include triangle extent, object
coordinates and both instance transforms, following the
[DXR error analysis](https://developer.nvidia.com/blog/solving-self-intersection-artifacts-in-directx-raytracing/).
The displacement follows the inverse-transpose geometric normal, including
nonuniform scale and shear. Texture footprint edge lengths are transformed
without subtracting translated world vertices. The unused payload distance
field stores the bound, retaining the 96-byte payload and existing image/ray
budgets. Point-light visibility reconnects from this origin to the sampled
light and excludes only the last representable segment distance, preserving
blockers close to a lamp without shadowing geometry beyond it.

Ray decisions use per-pixel, shuffled and Owen-scrambled two-dimensional Sobol
sequences, following the [progressive padding approach](https://jcgt.org/published/0009/04/01/).
The index combines the frame number and sample within that frame. Each path
vertex gives the eight direct lights, emissive-light selection, emitter point,
BSDF lobe and BSDF direction separate fixed purpose slots. Both index shuffling
and coordinate scrambling are required: coordinate scrambling alone can leave
correlated selection/position decisions that stop converging on small emitters.
Skipped lights and terminated earlier samples do not advance another purpose's
sequence. Two-dimensional Sobol values are computed with bit operations, using
the binary Pascal transform for the second dimension. No lookup table, image
target, sample-count change or extra ray is required. The fast Owen permutation
is adapted from pbrt-v4; its attribution and Apache-2.0 license ship in
`PATH_SAMPLING_NOTICES.txt` through every export preset.

This primarily improves convergence over multiple samples and stationary
frames. A single sample still has Monte Carlo noise. The sampler does not
track a surface through camera/object motion or impose spatial blue noise;
the existing reconstruction guides remain responsible for history validation.

Emissive triangles also receive direct area sampling at each vertex that has
a remaining continuation segment. An area-times-emission proposal selects
one triangle and one point on it, then traces visibility with the same geometry
mask as continuation rays. The light and BSDF proposals are combined with the
[power heuristic](https://pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/A_Better_Path_Tracer),
including the probability of selecting the light. This reduces noise from
small glowing surfaces without counting their light twice or extending the
selected bounce limit. Narrow glossy reflections retain BSDF sampling as well.
Alpha-cutout samples contribute zero without resampling; shader emission keeps
its existing texture modulation and colour conversion. StandardMaterial
emission uses its supported constant colour and energy.

The proposal keeps up to 4,096 emitting triangles, ranked by world-space area
times estimated emission power. Textured brightness affects the sampled
radiance; the selection estimate assumes a white texture. Omitted emitters
still contribute through BSDF hits with full weight. The GPU proposal and
sparse hit lookup use 384 KiB plus a 16-byte header and four bytes per instance;
no additional screen-sized images are allocated. A path can cast at most one
additional emissive visibility ray per continuation bounce and sample. Scenes
without eligible emitters use a smaller ray-generation variant with no emitter
sampling or MIS code. It switches automatically, retaining the acceleration
structures, SBT ranges and image bindings; a previously used variant is cached.
Stable placement IDs distinguish copies
of a shared mesh, including after hiding or revealing instances. Emissive
movement, deformation and visibility changes update the proposal and reset
lighting history. Non-emissive transforms do not rebuild the proposal; known
non-emissive terrain and morph data skip emission scanning.

Primary diffuse illumination and glossy radiance are stored separately. The
diffuse signal excludes the primary albedo so the main material retains its
original texture detail after reconstruction. Subsequent hits include their
albedo. Existing remake surface profiles and StandardMaterial roughness,
metallic and specular values supply a compact material description; original
assets without a profile default to rough dielectric surfaces. This does not
reproduce full PBR texture sets or procedurally modified materials.

Enhanced terrain and identified stone/wood object profiles also supply
texture-derived relief to traced shading. The existing terrain/material options
control it; changing either rebuilds the lighting snapshot. Seven previously
unused material bits store its strength without enlarging geometry or the ray
payload. Four texture taps estimate bounded perceptual brightness slopes in a
world-space cotangent frame. UV mirroring, nonuniform instance transforms and
back faces retain their orientation. Object relief fades over 14–40 m and 1.2–4 texels
per tracing pixel; secondary ray cones contribute to minification. Degenerate
UVs and normals that would face into the geometric surface keep the original
normal. Terrain has a separate, stronger bounded slope response: its sample
spacing follows the mip footprint, and detail fades over 25–65 m and 2–8 texels
per tracing pixel. Object relief retains the narrower range above. Perturbations
are limited continuously near the geometric and viewing hemispheres to avoid
popping at grazing angles. Painted relief remains a bounded approximation,
not geometric displacement or an authored PBR normal map.

Detailed terrain also retains the raster renderer's padded sRGB atlas and its
exact authored tile identities. The hit shader applies tile rotations, edge
blends, natural pair/junction transitions, semantic roughness, macro colour and
the existing procedural detail-normal texture. Cliff eligibility, crest guards
and vertical projections follow the raster terrain shader. Cliff painted relief
uses that vertical projection; ordinary terrain keeps its compact four-tap
relief approximation. This does not reproduce every raster sharpening or relief
operation, and explicit ray-cone mip footprints approximate raster derivatives.

Tile identities come from retained terrain triangles, not world XZ: original
maps can shift their vertices. The immutable snapshot retains the atlas owner
and copies tile/transition/guard metadata, while normal and macro data join the
existing raw texture array. Terrain detail, cliff or material setting changes,
and completion of asynchronous procedural textures, rebuild the snapshot.
Separate original/detailed/transition hit variants avoid loading transition
code into scenes that do not use it. The existing sample and bounce budgets,
96-byte ray payload and screen-sized buffers stay unchanged.

The existing Leaf backlighting option now also controls thin diffuse leaf
transmission in PT. The authored foliage mask identifies leaves and bark;
texture alpha is only used for cutouts. Up to 40% of a leaf's diffuse share
crosses to the opposite hemisphere, with the reflected share reduced by the
same amount. Direct sun, point lights, emissive proposals and continuation
paths use the same BSDF and side-aware ray origins. Both hemisphere PDFs and
emissive MIS include the transmission probability. Rejected below-surface GGX
reflection samples remain rejected rather than becoming unaccounted transmission.
The model follows the cosine-weighted reflection/transmission construction in
[pbrt's diffuse transmission model](https://github.com/mmp/pbrt-v4/blob/master/src/pbrt/bxdfs.h).
It is a thin surface approximation, not volumetric subsurface scattering.
Trunks remain opaque; the mask's bark channel supplies the existing shallow
object relief when Surface materials is enabled. The shared colour array
stores mask layers as data; material flags identify them. The 96-byte payload,
frame size and sample/bounce budgets remain unchanged. Leaf setting changes
rebuild the lighting snapshot.

Raster receiver normals are aligned to the visible geometric face, matching
the ray tracer, before guide validation. This keeps back faces of two-sided
foliage and terrain on PT instead of spuriously falling back to conventional
lighting. The world-space plane/depth checks still reject unrelated surfaces.

The material guide stores albedo and an exactly representable half-float
integer containing six roughness bits and five metalness bits. This guide
quantization only controls reconstruction; the integrator retains its existing
eight-bit material values. Separate fields prevent different combinations of
roughness and fractional metalness from sharing an ambiguous summed value.

`path_trace_filter.glsl` uses normal/depth/plane/material rejection, a 5×5
diffuse filter and a smaller 3×3 glossy filter. Responsive mode reprojects up
to eight history frames with neighbourhood clamping. Four bilinear history
taps are independently checked against the receiver's world-space plane,
normal and material, with reduced history confidence on partial disocclusion.
This avoids snapping to a single pixel or unnecessarily rejecting a matching
sloped surface during camera movement. Projection changes reset history.
Glossy history has its own confidence in the existing specular alpha channel.
A roughness-dependent angular weight compares reflected viewing directions,
including normal changes, for both spatial neighbours and historical taps.
Smooth surfaces therefore reuse less radiance after the reflection direction
changes; diffuse history and broad rough lobes can continue accumulating.
Perspective views use the current/previous camera positions, while orthographic
views use their parallel directions. The new-sample weight is accumulated
explicitly to preserve precision during long glossy accumulation.

Responsive reconstruction also tracks the largest channel variance for each
lighting signal. Centred spatial moments avoid HDR cancellation, and unequal
filter weights determine the effective sample count. Reprojected variance
widens the colour-clamping envelope when a small current neighbourhood cannot
represent the expected noise distribution. Its temporal blend follows the
same surface checks and independent diffuse/glossy confidence as radiance.
A narrower temporal glossy lobe limits highlight lag under these wider bounds.
Two consecutive fully dark neighbourhoods with at least twenty valid taps
limit history to two effective frames, accelerating a disappearing noisy
signal without rejecting an isolated missing sample. Edges with insufficient
support retain the normal bounded history.

The variance history is two RG16F images, storing standard deviations so HDR
values do not overflow when their square exceeds the half-float range. A
negative sign records a fully dark current neighbourhood; the magnitude is
the standard deviation. These images resize and release with the lighting
targets. They add one small history copy, without additional rays or compute
dispatches. This is a custom variance-aware clamp, not an implementation of
the full [SVGF pipeline](https://research.nvidia.com/labs/rtr/publication/schied2017spatiotemporal/)
or NRD.
Still scene uses the identical pixel without interpolation, skips the
spatial blur and progressively averages matching pixels, up to 256 frames.
It is a custom prototype filter, not NRD, DLSS Ray Reconstruction or another
production denoiser. Mode, resolution, projection and light changes invalidate
history in both modes. Geometry updates reset Still scene; Responsive rejects
changed surfaces through the guides and neighbourhood clamp.

The material lookup also compares reconstructed positions against the raster
triangle's tangent plane, rather than comparing adjacent pixels' raw depths.
Low/Medium tracing resolutions can therefore cover steep surfaces without
borrowing lighting from a different depth layer. The additional inverse
view-projection matrices are computed on the CPU once per frame; target
allocation and texture memory are unchanged.

The material integration replaces supported nearby lighting and fades back to
conventional illumination between 60 and 72 m from the scene snapshot centre.
World geometry is gathered within 96 m, with the existing budgets of 320,000
unique triangles, 4,096 instances and 192 texture layers of 512×512.
Characters' supported articulated and morph animation updates live.

PT receiver composition retains the terrain's authored underwater depth factor
on reflected diffuse and glossy light, while preserving emission. Since the
combined lighting buffers do not retain each incident light direction, this
uses the original ambient attenuation factor, not the directional underwater
formula. It does not simulate water-volume transport on secondary paths.

## Limits and qualification

- The original assets were authored for a different lighting model. Some
  rooms have no physical light source and can become very dark. Relighting
  and better material data are needed for consistent campaign presentation.
- Water retains its separate reflection renderer. Water refraction, glass,
  volumetric paths, particles, shader-only vegetation motion, separate emission
  textures and arbitrary object normal/roughness maps are not part of the path
  integrator. Terrain uses its existing procedural detail-normal texture and
  semantic roughness.
- There are no object motion vectors, spatial light cache, light reservoirs or
  production denoiser. Many occluded lights, cutout emitters, indirect paths
  and glossy motion can remain noisy. The emitter proposal is global to the
  bounded scene, without per-receiver visibility or distance importance.
  Glossy history still reprojects the primary surface, without reflected-hit
  motion or hit-distance guides. Angular rejection reduces stale highlights
  but trades some temporal noise suppression for responsiveness; it cannot
  correctly track every moving reflected object or recover missing samples.
  The variance estimate includes spatial signal variation and can still be
  inaccurate at thin surfaces, disocclusions and very sparse samples. Clamping
  remains a biased estimator; lower variance is not proof of energy conservation.
  Still scene is useful for comparisons, not for hiding noise during gameplay.
- Primary ray samples use pixel centres. The raster view supplies silhouette
  antialiasing; the prototype does not provide supersampled path-traced
  geometry edges. Thin geometry, normals and receiver mismatches can expose
  conventional-lighting seams. Missing geometry outside the bounded scene
  can produce light leaks or different distant reflections.
- Emissive visibility still excludes the last 2 mm before its sampled target
  and does not directly sample connections shorter than 4 mm. Receiver-side
  origin bounds improve contacts, but do not remove this endpoint limitation.
  Error bounds are conservative and depend on coordinate/transform conditioning;
  very large local coordinates can still require a noticeable displacement.
  Intersection constants have been tested on RTX hardware; other vendors
  require qualification before claiming equivalent self-intersection protection.
- Twelve RGBA16F lighting/guide images plus two RG16F variance images use
  104 bytes per tracing pixel: approximately 91 MiB at 1280×720 High and
  823 MiB at 3840×2160 High, before scene textures and acceleration structures.
  Variance history accounts for 7 MiB and 63 MiB respectively. Water tracing
  has separate resources.

See the [validation report](../validation/path-tracing-2026-10-22/README.md)
for actual outdoor/cave captures, timings, frame-generation checks and known
API diagnostics. DX12 tests here use the Windows build through Wine/VKD3D;
native Windows and other GPU vendors still require qualification.
The [sampling and reconstruction follow-up](../validation/path-tracing-smoothing-2026-10-22/README.md)
records variance, subpixel history, steep-receiver coverage and before/after
GPU timings for the subsequent smoothing changes.
The [emissive sampling follow-up](../validation/path-tracing-emitters-2026-10-22/README.md)
records unfiltered small-light variance and energy, dynamic/cutout emission,
shared-mesh placement checks, API regression coverage and GPU timings.
The [glossy reconstruction follow-up](../validation/path-tracing-glossy-2026-10-22/README.md)
records moving-highlight error, independent history confidence, fractional
metalness guides, stationary variance and GPU/FG regression checks.
The [variance-clamping follow-up](../validation/path-tracing-variance-2026-10-22/README.md)
records brightness bias against analytical references, sparse coloured/HDR
signals, disappearing noisy lighting, memory cost and GPU/FG regression checks.
The [sample-distribution follow-up](../validation/path-tracing-sampling-2026-10-22/README.md)
records unfiltered convergence against independent lighting references,
per-frame quality, temporal noise, correlation checks and GPU/FG regressions.
The [contact-lighting follow-up](../validation/path-tracing-contacts-2026-10-22/README.md)
records thin shadows, indirect occlusion, nearby reflections, point-light
segments, transformed-surface precision and GPU/FG regression checks.

The [terrain material follow-up](../validation/path-tracing-terrain-materials-2026-10-22/README.md)
records raster-sampler comparisons, cliff/normal integration, matched campaign
views, Vulkan compiler compatibility and the increased GPU cost.

## Rebuild and checks

All four stages, the additional ray-generation variant and two terrain hit
variants are checked in as fourteen matching DXIL and SPIR-V binaries. Manifests
pin source, builder and binary hashes. Rebuild or reproduce with DXC 1.9.2609:

```sh
python3 tools/build_water_rt_shaders.py --shader path_trace --dxc /path/to/dxc
python3 tools/build_water_rt_shaders.py --shader path_trace --check --dxc /path/to/dxc
python3 tools/check_translations.py
```

Import the compute shader before exporting with the qualified engine template.
Use an isolated profile with a free cursor, visible FPS and muted audio.
Fixtures run through the existing `--tool` interface:

| Fixture in `tools/tests/` | Coverage |
| --- | --- |
| `path_trace_device.gd` | Additional bounce energy, emissive transport, glossy metal, accumulation, emitter removal, stable bindings, resize and teardown |
| `path_trace_alpha.gd` | Cutout alpha in primary, direct visibility and continuation rays |
| `path_trace_emitters.gd` | Raw small-light and glossy variance, area-integral energy reference, cutout/textured emission, movement/deformation, duplicate placements, visibility masks and proposal-budget fallback |
| `path_trace_emitter_live.gd` | Production scene collection, emissive terrain illumination, movement/hiding and material changes in the actual campaign |
| `path_trace_quality.gd` | Native grazing-metal variance and energy against numerical quadrature; subpixel and sloped reprojection; rejection of unrelated depth layers |
| `path_trace_glossy.gd` | Native moving highlights against their deterministic raw reference, stationary variance/energy, separate diffuse/glossy confidence, perspective/orthographic motion, material-guide aliases and progressive precision |
| `path_trace_variance.gd` | Analytical stochastic means, dark/bright outliers, colour ratios, HDR variance range, coherent/persistent dark changes, reset/depth rejection and variance-resource resize/teardown |
| `path_trace_sampling.gd` | Native unfiltered grazing-metal, disk-sun penumbra and small-emitter convergence at 1/2/4 samples; late sequence starts, repeatability, frame wrap, purpose independence, spatial error correlation and packaged attribution |
| `path_trace_contacts.gd` | Raw thin-contact shadows, sky/emissive occlusion, nearby glossy reflection, point-light endpoints and self-intersection under translation, scale, rotation, shear, mirrored instances and large local coordinates |
| `path_trace_daylight.gd` | Analytic directional-sky irradiance, isotropic fallback, bounded relief, UV/instance mirroring, degenerate UVs, distance and minification fades |
| `path_trace_daylight_live.gd` | Matched noon/evening/night river views, sky-only history reset, enhanced surface collection and conventional restoration |
| `path_trace_foliage.gd` | Leaf/bark separation, reflected/transmitted energy, uniform environment, disabled transmission, back-side blockers and emissive MIS |
| `path_trace_terrain.gd` | Traced tile rotation, pair/junction/cliff colours against the actual raster sampler; shifted tile identities, procedural normals, projected relief, semantic roughness and atlas ownership |
| `path_trace_terrain_live.gd` | Matched campaign river/cliff views, raw/filtered buffers, terrain/cliff/transition rebuilds and conventional restoration |
| `path_trace_outdoor.gd` | Matched river/grove views across noon/evening/night, authored foliage collection, leaf-only setting rebuild and conventional restoration |
| `path_trace_underwater.gd` | Production receiver composition with controlled reflected/emitted radiance and underwater depth coefficients |
| `path_trace_receivers.gd` | Rendered front/back-face steep-surface coverage and depth-edge rejection at 50/75/100% tracing resolution |
| `path_trace_live.gd` | Outdoor material integration, responsive reprojection, still accumulation, camera reset, quality resizing and conventional restoration |
| `path_trace_cave.gd` | Cave sky exclusion, two/four bounces, changing light colour, animated actor and history invalidation |
| `path_trace_materials.gd` | Actual compilation/draw of 144 world material variants |
| `path_trace_fsr.gd` | Production frame generation and measured FPS HUD alongside water and path tracing, resize and pause/resume |
| `path_trace_performance.gd` | Separate ray-pass GPU, controller CPU and whole-frame timing against conventional and one-bounce RT lighting |
| `scene_raytrace_options.gd` | Shared RT/PT settings, persistence, supported/unsupported controls, EN/RU/DE labels, choices and help |
| `scene_raytrace_fallback.gd` | Saved experimental settings on unsupported renderers |
