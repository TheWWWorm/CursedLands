# Path-traced lighting

The development build adds an optional multi-bounce lighting mode for nearby
terrain, objects and characters. It traces direct shadows, diffuse colour
transport and rough glossy reflections through two or four surface bounces.
It is a bounded lighting prototype: the main view still uses raster visibility,
material composition, sky, fog, water and particles. It is not a replacement
for the complete renderer. These notes describe the current development branch;
individual validation reports identify the source and builds they qualify.

## Controls

Open **Options → Graphics → Lighting and shadows → Ray-traced lighting**.

- **Path tracing (test):** Off, 2 bounces or 4 bounces. Off is the default.
- **RT lighting quality:** Low traces at 50% of the 3D render width and height
  with one path sample per pixel; Medium uses 75% and two samples; High uses
  100% and four samples. Medium is the default. Path tracing follows the
  viewport's applied Render scale or FSR resolution, so upscaling reduces
  tracing and reconstruction work too. The separate scene RT mode retains
  window-relative quality. Water reflection quality remains independent.
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

Camera recentering builds at most one replacement scene while the current
scene continues rendering. The controller promotes it only after its first
ray pass, reconstruction and history copies succeed at the requested size,
then retires the old device. Movement beyond the candidate region cancels
the outdated build. Deferred callbacks carry the device identity so a retired
build cannot reactivate lighting or overwrite its successor's statistics.
Incompatible material/topology changes still use conventional lighting during
replacement rather than continuing to shade an outdated scene.

Transient pipeline failures retry with increasing delays, capped at 30 seconds.
An unchanged over-budget scene retains only a lightweight source watch and
does not repeatedly repack; movement or changed source membership allows
recovery without toggling an option. A failed recenter keeps the usable current
device. Quality/renderer changes clear the failure state.

Image and descriptor allocation is transactional. A resize publishes new
backing images only after a complete render; four previous output images stay
alive until then. Frame/morph uploads and history copies are checked, failed
frames invalidate history, and failures notify the controller to restore
conventional lighting. This does not establish recovery from a lost physical
GPU or an operating-system driver reset.

Published-output readiness is separate from temporal-history confidence.
Sampler, pipeline, resize and emitter changes can reset history while the last
complete image remains display-ready. This keeps the controller updating camera
projection globals when the separate render thread is between those operations.

Queued build, render and disposal callbacks bind their device owner explicitly,
and deferred notifications retain it until delivery. Ordinary method callables
and signal values only identify their targets; they do not retain `RefCounted`
objects. The shared water controller uses the same retained dispatch. A native
lifecycle regression drops the final main-thread owner while the render queue
is blocked, then verifies resource disposal and final release after delivery.

`path_trace.hlsl` uses a camera visibility ray followed by up to two or four
continuation segments. At every hit, direct lighting is evaluated from the
sun and up to seven nearby point lights with traced visibility. A continuation
hit contributes emission and direct illumination; a miss contributes outdoor
sky radiance, or zero sky radiance in caves. Diffuse and GGX glossy lobes are
sampled with a shared mixture PDF. Glossy continuations use
[visible-normal GGX sampling](https://jcgt.org/published/0007/04/01/), with
Fresnel-aware lobe selection and no diffuse samples for pure metals. This
reduces grazing-angle variance without increasing the sample budget. The
bounce count bounds work. Four-bounce mode uses compensated Russian roulette
after its first two continuation segments; the survival floor ranges from
25% for diffuse surfaces to 75% for smooth metals. Two-bounce mode uses a
smaller shader without this tail, and `--ei-full-paths` retains the full-path
comparison. There is no light reservoir sampling. Geometric normals offset rays
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

Active PT uses a fixed AgX display profile (exposure 1.2, contrast 1.15,
white 16.29) to retain HDR flame and reflection detail. Actual output readiness
gates the profile; conventional rendering, scene RT GI and released/unsupported
PT use the original linear display at exposure 1. Canvas UI remains unchanged.
Enhanced stationary fire records also supply a finite source radius, from
0.08 to 0.24 metres according to their original light range. The existing
angular sampler uses this radius at primary and secondary hits, without extra
rays or changes to light energy/range. Disabling enhanced fire removes the
radius; spells and scene RT retain their previous source sizes. See the
[authored-lighting qualification](../validation/path-tracing-authored-lighting-2026-10-23/README.md)
for matched campaign views, display calibration and performance measurements.

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
metallic and specular values supply a compact material description. Equipped
figures also retain their composed surface maps: metal, leather, cloth and skin
regions use the original redress masks and layer order at primary and secondary
ray hits. These maps contain linear highlight/roughness/metalness data. PT reads
roughness and metalness while retaining its calibrated dielectric reflectance;
the legacy highlight channel is not treated as AO or physical reflectance.

Mapped figures use one additional filtered texture lookup in the existing
array, with no additional rays, bindings or ray payload fields. Ordinary
surfaces keep the scalar path. Material-effects settings control collection,
and replacing a surface texture invalidates the scene snapshot. The render-thread
descriptor preserves the map index alongside the existing independent foliage
mask. Original assets without a profile or map remain rough dielectrics.
This does not yet reproduce full PBR normal/emission texture sets, wounds on
secondary hits, or every procedurally modified material.
The [equipment-map qualification](../validation/path-tracing-equipment-materials-2026-10-22/README.md)
contains matched campaign captures, GPU timings and backend checks.

The first authored prop maps cover `bridge00`, `stone03` and `columnruins01`.
They pack tangent normal XY, perceptual roughness and metalness into one linear
RGBA8 texture. Both the object raster shader and PT consume the same map;
the original color atlas stays intact. A source MMP fingerprint prevents a
changed mod atlas from receiving masks authored for different UV regions.
These maps replace the four-tap brightness relief on matching props with one
filtered lookup. They do not add rays, bindings or payload fields. The bridge
grain follows its diagonal beams and other board regions; its bone ornament
stays smooth. Carved stone uses authored joints and rock uses bounded fissures.

The UV tangent frame supports mirrored UVs, nonuniform/reflected instances
and back faces. Detail fades over 24–60 m and 2–8 texels per pixel, including
secondary-ray footprints; unresolved glossy detail broadens to at least 0.65
roughness. This is a conservative fade, not a variance-prefiltered microfacet
normal distribution. The source recipes and import settings are reproducible
with `tools/build_surface_detail_maps.py` (`--check` verifies decoded pixels).
The bake uses the runtime decoder's D3D row order, row zero at V zero; flipping
an inspection preview is not a valid substitute. Height is converted to that
order before deriving normal XY. `surface_detail_inventory.gd` exports local
runtime-order previews and original mesh/UV bounds for authoring. Bone and snow
regions are checked against the original decoded color atlas as well as the
generated map.
Alpha stores metalness, so alpha-border repair, premultiplication, sRGB data
sampling and automatic normal-map compression are disabled. Do not treat these
maps as color images, ORM, or the separate equipment `surface_tex` format.
The [authored-surface qualification](../validation/path-tracing-authored-surfaces-2026-10-23/README.md)
contains matched captures, source/import checks and follow-through measurements.
The [GPU 1 control](../validation/path-tracing-gpu1-control-2026-10-23/README.md)
completes the separate unmapped-scene performance check on an RTX 3090 Ti.

Enhanced terrain and identified stone/wood object profiles also supply
texture-derived relief to traced shading when no authored map is present. The existing terrain/material options
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
completion or replacement of procedural textures, and changes to edge blending
rebuild the snapshot. Ready normal/macro texture identities are tracked as well
as their generation state, so replacing a ready texture cannot leave the old
traced material resident.
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
Rigid placements, including articulated character parts, reproject through
their previous rendered transforms. A stable placement identity rejects history
from a different object even when its depth and material match. Previous normals
follow the inverse-transpose transform, including nonuniform scale and shear.
Visibility changes and changed morph geometry reject that placement's history;
stopped placements retire their motion on the next rendered frame. Static scenes
need no transform-buffer updates. Still-scene accumulation retains its existing
reset on scene motion.

The raw diffuse alpha carries an exact FP16 placement code; two R16F history
images preserve that identity without enlarging the ray payload. A 96-byte
record per placement supplies previous position/normal transforms. The shader
uses an identity fast path for stationary placements. Rays and receiver lookup
share the unjittered camera projection; raster receivers project their world
positions into the PT image, preserving alignment with FSR's jittered samples.
The guide and reconstruction sizes follow the actual truncated 3D render size,
then the selected PT quality. Resizing invalidates history while retaining the
scene acceleration structures and public texture handles.
The [speed and motion qualification](../validation/path-tracing-speed-motion-2026-10-23/README.md)
records the measured cost reduction and moving-surface checks on GPU 1.
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
production denoiser. Mode, resolution, projection and substantial light changes
invalidate history in both modes. Geometry updates reset Still scene; Responsive rejects
changed surfaces through the guides and neighbourhood clamp.

Gentle local-light flutter now retains a short responsive history instead of
resetting every frame. The light list, positions, ranges, source sizes, hues,
sun and environment must remain unchanged; each changed light's linear peak
intensity must stay within 10% of its previous value. The history-age cap is
three at 60 Hz, 1.8 at 30 Hz and approximately 1.42 at 20 Hz. Slower frames
therefore give current illumination more weight, preserving a bounded response
time. At 60 Hz at least one third of the estimate is current, with the older
contribution decaying exponentially; this is not a literal three-frame window.
The usual guide checks still apply to both diffuse and glossy history.
Extinguished, newly lit, moved, resized, recoloured or replaced sources reset
immediately. Still scene continues to require exact lighting. The diagnostic
`--ei-strict-light-history` restores the previous reset policy without changing
the source animation. No shader, ray budget, binding or buffer was added.
The [torch-history qualification](../validation/path-tracing-torch-history-2026-10-23/README.md)
contains controlled original-torch sequences, noise/response measurements and
links to the subsequent performance measurements. Its original synchronous
capture timings remain excluded.

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
Opaque detached limbs also participate after leaving their source character.
They register through the world's explicit ray-geometry group, preserving
their original copied meshes/materials, live transforms and visibility masks
in both scene lighting and water reflections. Registration is filtered to the
current world and follows scene-tree lifetime. Whole-root admission and exit
hysteresis apply to these moving parts; particles remain on their own renderer.

A failed or empty gather can discard its packed vertices, copied textures,
placements, morph data and native watcher while retaining its lightweight
source-version snapshot. Topology-only polling does not refill packing caches.

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
- Rigid surface motion is supported; deformation motion vectors, a spatial
  light cache, light reservoirs and a production denoiser are not. Many
  occluded lights, cutout emitters, indirect paths
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
- Twelve RGBA16F lighting/guide images, two RG16F variance images and two R16F
  identity images use 108 bytes per tracing pixel: approximately 95 MiB at
  native 1280×720 High and 854 MiB at native 3840×2160 High, before scene
  textures and acceleration structures. FSR Quality's two-thirds render scale
  reduces those pixel allocations to approximately four-ninths. The motion
  buffer uses at most 384 KiB for 4,096 placements. Water tracing has separate
  resources. A recenter can temporarily retain two bounded scenes and their
  lighting targets; a resize additionally retains four previous RGBA16F output
  images until publication. Allocation failure preserves the last valid output
  long enough for the controller to retire the device safely.

See the [validation report](../validation/path-tracing-2026-10-22/README.md)
for actual outdoor/cave captures, timings, frame-generation checks and known
API diagnostics. DX12 tests here use the Windows build through Wine/VKD3D;
native Windows and other GPU vendors still require qualification.
The [recovery and sustained qualification report](../validation/path-tracing-recovery-2026-10-23/README.md)
tracks the subsequent output-lifetime, recenter/retry and live-scene hardening.
Use the repository-owned [qualification runner](../path-tracing-qualification.md)
for reproducible hardware, runtime, profile, memory and shutdown gates.
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

The four base stages, three additional ray-generation variants and two terrain
hit variants are checked in as eighteen matching DXIL and SPIR-V binaries. Manifests
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
| `path_trace_lifecycle.gd` | Transactional image/descriptor allocation, failed pipeline/upload/copy combinations, output publication, retry and repeated teardown |
| `path_trace_controller.gd` | Real recenter continuity, automatic failure recovery, cancellation, stale callbacks, disabled renderer and bounded retry delays |
| `path_trace_sustained.gd` | Repeated live quality/scale/renderer changes, two campaign zones, actor motion, generated save/load, owner retirement and warmed allocation trends |
| `path_trace_weakref_regression.gd` | Standalone CPU reproduction of coroutine temporary retention and the synchronous weak-capture lifetime guard |
| `path_trace_alpha.gd` | Cutout alpha in primary, direct visibility and continuation rays |
| `path_trace_emitters.gd` | Raw small-light and glossy variance, area-integral energy reference, cutout/textured emission, movement/deformation, duplicate placements, visibility masks and proposal-budget fallback |
| `path_trace_emitter_live.gd` | Production scene collection, emissive terrain illumination, movement/hiding and material changes in the actual campaign |
| `path_trace_detached_live.gd` | Original campaign severing, native primary-hit identities on detached meshes, transform/visibility updates and removal on expiry |
| `path_trace_topology.gd` | Whole-figure boundaries, dynamic-root lifetime/world isolation, ready terrain texture replacement, lightweight failure watches and unchanged geometry budgets |
| `path_trace_quality.gd` | Native grazing-metal variance and energy against numerical quadrature; subpixel and sloped reprojection; rejection of unrelated depth layers |
| `path_trace_motion.gd` | Rigid motion and camera reprojection, rotation/nonuniform scale, stable object identities, visibility/morph rejection, movement stopping, high instance IDs and resource lifetime |
| `path_trace_resolution.gd` | Real raster/PT dimensions, render scale, FSR jitter, native qualities, resizing, history reset, image comparison and unchanged scene RT sizing |
| `path_trace_resolution_performance.gd` | Interleaved window-resolution/render-resolution PT grids with identical raster upscaling, scene, samples and bounce count |
| `path_trace_glossy.gd` | Native moving highlights against their deterministic raw reference, stationary variance/energy, separate diffuse/glossy confidence, perspective/orthographic motion, material-guide aliases and progressive precision |
| `path_trace_variance.gd` | Analytical stochastic means, dark/bright outliers, colour ratios, HDR variance range, coherent/persistent dark changes, reset/depth rejection and variance-resource resize/teardown |
| `path_trace_sampling.gd` | Native unfiltered grazing-metal, disk-sun penumbra and small-emitter convergence at 1/2/4 samples; late sequence starts, repeatability, frame wrap, purpose independence, spatial error correlation and packaged attribution |
| `path_trace_contacts.gd` | Raw thin-contact shadows, sky/emissive occlusion, nearby glossy reflection, point-light endpoints and self-intersection under translation, scale, rotation, shear, mirrored instances and large local coordinates |
| `path_trace_daylight.gd` | Analytic directional-sky irradiance, isotropic fallback, bounded relief, UV/instance mirroring, degenerate UVs, distance and minification fades |
| `path_trace_surface_detail.gd` | Authored data import/export, source fingerprint guards, linear channels, raster/ray normal parity, mirrored UVs and instances, back faces, fallback and detail fades |
| `path_trace_surface_detail_live.gd` | Original campaign props, live map toggles through the controller, matched captures and interleaved GPU timings |
| `path_trace_daylight_live.gd` | Matched noon/evening/night river views, sky-only history reset, enhanced surface collection and conventional restoration |
| `path_trace_foliage.gd` | Leaf/bark separation, reflected/transmitted energy, uniform environment, disabled transmission, back-side blockers and emissive MIS |
| `path_trace_terrain.gd` | Traced tile rotation, pair/junction/cliff colours against the actual raster sampler; shifted tile identities, procedural normals, projected relief, semantic roughness and atlas ownership |
| `path_trace_terrain_live.gd` | Matched campaign river/cliff views, raw/filtered buffers, terrain/cliff/transition rebuilds and conventional restoration |
| `path_trace_outdoor.gd` | Matched river/grove views across noon/evening/night, authored foliage collection, leaf-only setting rebuild and conventional restoration |
| `path_trace_underwater.gd` | Production receiver composition with controlled reflected/emitted radiance and underwater depth coefficients |
| `path_trace_receivers.gd` | Rendered front/back-face steep-surface coverage and depth-edge rejection at 50/75/100% tracing resolution |
| `path_trace_live.gd` | Outdoor material integration, responsive reprojection, still accumulation, camera reset, quality resizing and conventional restoration |
| `path_trace_light_history.gd` | Controller light classification, all seven slots, frame-rate-dependent history, real GPU diffuse/glossy weighting and immediate extinction |
| `path_trace_torch_history_live.gd` | Original cave torch, paired strict/bounded histories, normalized temporal noise, brightness response and extinction at fixed update rates |
| `path_trace_light_inventory.gd` | Read-only original campaign torch locations, identifiers, strengths and cave classification |
| `path_trace_lighting.gd` | Actual-output display gating, rendered HDR ramp, unchanged Canvas UI, flame-radius handoff and option restoration; `--fallback-only` for conventional backends |
| `path_trace_lighting_live.gd` | Matched noon/dusk/night/grove/cave captures; `--pt-lighting-bench` alternates display/source profiles, `--pt-history-bench` isolates strict/bounded flutter cost |
| `path_trace_cave.gd` | Cave sky exclusion, two/four bounces, changing light colour, animated actor and history invalidation |
| `path_trace_materials.gd` | Actual compilation/draw of 144 world material variants |
| `path_trace_fsr.gd` | Production frame generation and measured FPS HUD alongside water and path tracing, resize and pause/resume |
| `path_trace_performance.gd` | Separate ray-pass GPU, controller CPU and whole-frame timing against conventional and one-bounce RT lighting |
| `scene_raytrace_options.gd` | Shared RT/PT settings, persistence, supported/unsupported controls, EN/RU/DE labels, choices and help |
| `scene_raytrace_fallback.gd` | Saved experimental settings on unsupported renderers |
