# Cursed Lands path tracing graphics roadmap

Research date: 22 October 2026. Renderer baseline: `a56d4484`, following the
water, scene-lighting, path-tracing and performance work in the
[earlier chat](codex://threads/01a15f4b-ce2b-7c00-ad14-a51ae6834c1d).

The next substantial graphics improvement should combine richer materials and
authored lighting with motion-aware reconstruction. After that, expand light
sampling, scene coverage and water integration. Increasing bounce counts alone
would leave several visible limitations intact and consume an already expensive
GPU budget. The proposals below are implementation priorities; their speed and
image-quality gains require measurement in this game.

Implementation update, 23 October: PT now follows the applied internal render
resolution, and rigid primary surfaces retain history through their previous
transforms and stable placement identities. The
[speed and motion qualification](../validation/path-tracing-speed-motion-2026-10-23/README.md)
records matched GPU 1 measurements, native Vulkan and DX12/Wine checks, FSR
readiness, moving actors and remaining deformation/reflection limitations.

## What the Dark Souls II example demonstrates

The author's [DS2LightingEngine page](https://www.nexusmods.com/darksouls2/mods/1146)
describes native path tracing alongside area presets, dynamic lighting,
parallax, adaptive tessellation, fog, HDR and upscaling. Its credits explicitly
acknowledge NRD and NRD Sample. Hardware ray-traced sun shadows remain a separate
choice. The useful comparison is therefore an integrated visual overhaul;
the public description does not establish that every effect uses path tracing.

For Cursed Lands, the transferable lesson is to improve the scene being lit,
its light sources and its temporal presentation together. A convincing torchlit
room needs suitable stone, a credible flame and readable exposure as well as
correct light transport.

## Current capabilities and remaining gaps

The source at the baseline commit is more current than some overview prose in
[the integration notes](path-tracing-experiment.md). In particular, compensated
Russian roulette for deeper paths is already implemented.

| Area | Already present | Remaining opportunity |
| --- | --- | --- |
| Transport | Hardware DX12/Vulkan rays; two/four continuation bounces; diffuse and GGX glossy transport; thin leaf transmission | Dielectric refraction, participating media and broader material models |
| Sampling | Owen-scrambled Sobol sampling, visible-normal GGX, emissive next-event estimation with MIS, compensated deep-path termination | Spatially informed light selection, reservoirs and radiance caching |
| Materials | Albedo, compact roughness/metalness/specular profiles, detailed terrain transitions, procedural terrain normals, bounded texture-derived relief | Authored object normal/roughness/emission maps and consistent material data across renderers |
| Lighting | Sun and up to seven selected local point lights; proposals for up to 4,096 emissive triangles | More light types and lights chosen by their contribution to each receiver |
| Reconstruction | Separate diffuse/glossy channels, variance-aware history, camera and rigid-object reprojection, stable surface identities, angular glossy rejection | Deformation motion, reflected-hit guides and production reconstruction |
| Coverage | 96 m scene snapshot; PT receivers fade to conventional lighting at 60–72 m | Persistent regional geometry and distant occluders/reflections |
| Animation | Articulated transforms, visibility changes and supported morphs update | Shader-only vegetation deformation and consistent previous-frame geometry |
| Water and atmosphere | Separate water reflections, sky, fog and particles | Shared illumination, reflection/refraction transport and consistent atmospheric attenuation |

Material collection currently resizes ordinary snapshot textures to 512×512,
with 192 layers, 320,000 unique triangles and 4,096 instances. Detailed terrain
also borrows its existing raster atlas, so the 512 limit does not describe every
terrain texture. Exceeding scene budgets falls back to conventional lighting.

The existing [river](../validation/path-tracing-shader-optimization-2026-10-22/river-noon.png)
and [cliff](../validation/path-tracing-shader-optimization-2026-10-22/cliff-noon.png)
captures show angular bank and cliff silhouettes. Normal shading can enrich
their surfaces, but silhouette improvements require geometry. These are
controlled captures with several optional effects disabled, not evidence that
those effects are absent from the game.

## Priority and expected visible benefit

Effort is relative implementation scope, not a delivery estimate.

| Priority | Work | Expected visible benefit | Main cost or dependency |
| --- | --- | --- | --- |
| First | Motion guides, reconstruction and tracing-resolution control | Cleaner moving characters, more stable foliage and reflections, better detail at a practical ray budget | Substantial renderer integration; denoiser overhead must be recovered elsewhere |
| First | Material maps and a representative area lighting pass | Distinct stone, bark, leather and metal; convincing torchlight and wet surfaces | Asset authoring, material parity and texture bandwidth |
| Next | Receiver-aware light sampling and RTXDI/ReSTIR DI evaluation | More useful lights and small emitters with less noise | Light registry, reservoirs and temporal validation |
| Next | World-space radiance cache experiment | More stable indirect light and reduced deep-path work | Memory, cache update cost and responsiveness |
| Next | Persistent scene coverage and shared ray scene | Fewer boundary changes, missing reflections and occlusion leaks | Streaming, acceleration-structure ownership and budgets |
| Then | Water transport and atmosphere integration | Lit objects reflected consistently; credible shallow water, haze and beams | Transparency, medium handling and reconstruction |
| Later | Selected geometry upgrades and advanced transport | Better close-up silhouettes, special glass/skin/caustic effects | Content and potentially high tracing cost |

## Reconstruction and practical rendering resolution

The filter now reprojects rigid surfaces through their previous transforms and
camera, with stable surface identity. Changed morph geometry rejects history;
deformation motion still needs previous surface data consistent with the visible
surface. Add separate diffuse/specular hit-distance guides. Handle reflection
motion separately where possible; primary
surface motion cannot describe every moving object seen in a reflection.

[NRD](https://github.com/NVIDIA-RTX/NRD#inputs) supplies temporal diffuse/specular
denoisers using motion, normal, roughness, depth and hit-distance information.
It supports integration through engine compute dispatches or a native API
bridge. Evaluate REBLUR and RELAX against our custom filter using the same
animated scenes. Its documented scope is opaque surface signals, so water and
fog still need deliberate treatment.

The new guide contract must cover orthographic and perspective cameras, jitter,
disocclusion, teleports, exposure changes and resizing. Extracting suitable data
from Godot's existing motion pass may help, but its resolution, material coverage
and deformation behavior must match the PT inputs. Add diagnostic displays for
these guides before tuning the denoiser.

The window-relative PT resolution issue is addressed: `scene_raytrace.gd` now
uses the viewport's applied scale and Godot's truncated internal size before
applying PT quality to rays, guides and reconstruction. Raster receivers project
world positions into the unjittered PT lattice. Compositor checks verify actual
raster/PT dimensions and temporal jitter through scale and FSR changes. Native
render scale retains the original PT sizes; scene RT remains window-relative.

Optional [DLSS Ray Reconstruction](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_RR.md)
can use the same groundwork. Its inputs include noisy color, diffuse/specular
albedo, normals/roughness, depth, dense motion and either specular motion or
hit distance. It needs integration before final display composition; applying
it to a finished, already denoised screenshot is not an equivalent path.
Choose the reconstruction branch explicitly to avoid redundant denoising or
upscaling. Preserve an independently qualified non-DLSS route.

The current reconstruction pass costs approximately 0.185 ms at Medium and
0.314 ms at High in the saved experiment. A more sophisticated denoiser is a
quality investment. Its performance case is to permit fewer samples or fewer
tracing pixels at acceptable moving-image quality. Compare those complete
configurations, including the added guides and denoiser cost.

## Material and lighting work that makes path tracing visible

The [focused material and lighting research](path-tracing-materials-and-lighting-research-2026-10-22.md)
audits existing equipment masks, original texture assets and light behavior,
and proposes an authoring format and representative area pilot.

Introduce a shared material description for raster and ray hits: base color,
normal, roughness, metalness/specular, emissive texture and alpha behavior, with
room for transmission and thickness. Preserve tangents, UV transforms, color
space and mip selection consistently. Keep the existing terrain atlas fidelity
and leaf/bark separation when extending the representation.

Start with a small authored library: dry and wet rock, soil, grass, bark, wood,
leather and metal. Original art can contain painted light and shadow; review it
before treating brightness as height or lighting-free albedo. Automatically
derived normals can remain a fallback, while close-up surfaces receive authored
maps. Higher texture resolution should be allocated by material and view need,
instead of uniformly enlarging the whole snapshot array.

Investigate precomputed material textures for expensive static terrain
operations. Cache appropriate color/normal/roughness fields and invalidate them
when the corresponding terrain or material changes. Keep view-dependent relief
and filtering separate. This is a new experiment with a memory/bandwidth tradeoff;
the previous per-triangle footprint cache was slower and should not be repeated
without a changed hypothesis.

Build a lighting demonstration in one outdoor area and one cave/interior.
Place coherent light sources at existing lamps, fire and emissive objects;
preserve the intended palette and readable routes. The current local-light
attenuation is an authored finite-range curve, so physical units and inverse
square falloff require coordinated light-intensity migration, not a shader-only
replacement. A room with no source cannot acquire convincing indirect light
through extra bounces.

Use consistent exposure and highlight handling across sky, surfaces, water and
fog. Preserve atmosphere deliberately; crushing shadows to make comparisons
look dramatic would obscure whether light transport actually improved.

## More lights with a better sampling strategy

Implementation update, 28 October: continuation vertices now draw one local
light per bounce in proportion to its reach; see
[the performance plan](path-tracing-performance-plan-2026-10-28.md).

The current loop evaluates the sun and each eligible selected point light at
every path vertex. The seven local lights are selected around the camera, while
the emissive proposal uses scene-wide area times estimated emission power.
Neither selection models each receiver's likely contribution well.

Create a stable light registry covering supported analytic lights and emissive
triangles. Start with a receiver-aware spatial proposal and compare it with
[RTXDI](https://github.com/NVIDIA-RTX/RTXDI#introduction) ReSTIR DI, which reuses
light candidates across space and time. The current SDK also offers ReSTIR GI
and PT; DI is the narrower first integration for our light-loop bottleneck.

Give sun and environment lighting explicit sampling rules, maintain correct
PDF/MIS weights, and avoid representing the same flame twice as both an emitter
and an additive proxy lamp. Stable IDs, moving-light rejection, visibility
revalidation and a long-accumulation reference are required. Raising the
seven-light cap while retaining the full loop would expand cost directly.

The river timing scene contains little local-light complexity. Measure this
work in a room with many occluded lamps and small emitters as well as outdoors;
there is no basis yet for promising a river FPS gain from reservoirs.

## Reusing indirect light in world space

[SHaRC](https://github.com/NVIDIA-RTX/SHARC/blob/main/docs/Integration.md) is a
shader-based radiance cache with update, resolve and query stages. A successful
query can terminate an eligible continuation path. Its current guide describes
native FP16 requirements and a default 2²²-entry allocation totaling 160 MiB,
before optional directional data or other resources.

Prototype cache use after the first visible surface, initially for diffuse and
broad glossy transport. Preserve explicitly traced sharp reflections and close
contacts. Cache misses must continue tracing. Test torches, transient spell
lights, doors, moving units and day/night transitions for stale illumination,
and expose cache occupancy and hit rates during development.

This adds an approximation and substantial resources. Retain an uncached
reference and judge both response time and energy error. Compare its total
update/resolve/query cost with today's compensated deep paths before adopting
it. A learned radiance cache is a separate, more involved option; it is not a
prerequisite for this experiment.

## Scene coverage and acceleration structures

Replace repeated bounded snapshots with persistent regional scene data. Keep
detailed nearby geometry and cheaper distant occluders where their shadows or
reflections matter. Include offscreen contributors: camera visibility alone is
not sufficient for tracing. Stream and retire regions with hysteresis to avoid
repeated rebuilds around the current 16 m movement threshold.

Water and scene lighting currently own separate device/snapshot paths. Evaluate
shared geometry, materials and acceleration structures with distinct ray masks
and output resources. Define ownership and synchronization before attempting
sharing; their collection and visibility requirements differ.

The existing code already shares repeated meshes, creates BLASes lazily and
marks opaque geometry to skip alpha any-hit work. Remaining experiments include
static BLAS compaction, pooling, TLAS build preferences and dynamic BLAS
update/refit support. The source currently rebuilds changed morph BLASes and
the affected TLAS. Compare rebuild/update quality and total frame cost rather
than assuming a refit is always faster. NVIDIA's
[acceleration-structure guidance](https://developer.nvidia.com/blog/best-practices-using-nvidia-rtx-ray-tracing/)
provides the relevant tradeoffs.

Match shader-driven vegetation positions between raster visibility, tracing
and motion guides. Improving leaf transmission is already done; moving leaf
geometry is a separate missing capability.

## Water and atmosphere as part of the same lighting system

First make reflected surfaces use the same material and illumination model as
their direct view. The current water tracer shades one reflected view with
direct light and ambient approximations; it does not inherit the full PT
transport of the main scene. Its wave appearance also comes from distortion,
not intersections with a fully displaced water surface.

Then add a controlled water interface with consistent wave normals, Fresnel
reflection/refraction and absorption over traveled distance. Support entering
and leaving water without counting the interface twice. Multiple water levels,
underwater views and reflection motion belong in its acceptance cases.
[Dielectric BSDFs](https://pbr-book.org/4ed/Reflection_Models/Dielectric_BSDF)
provide the interface model; [volume transport](https://pbr-book.org/4ed/Volume_Scattering)
provides the attenuation/scattering model. Water caustics need a dedicated
sampling strategy and can follow later.

For atmosphere, share the sky/environment source between visible sky and
traced illumination. The current directional palette is intentionally
low-frequency. A richer environment needs importance sampling and consistent
sun handling. Extend fog with compatible light and shadow data, and apply
appropriate attenuation along reflected/refracted paths. A practical initial
version can retain rasterized volumetric integration; full multiple scattering
is a separate cost decision.

Keep particles and transparent effects explicit in the composition design.
Fire may contribute through a controlled emitter representation while its
visible particle animation remains rasterized. That approximation should be
documented and tested for double-counted light and missing reflections.

## Scope of a complete renderer

Raster primary visibility is compatible with extensive path-traced lighting.
The more consequential current limits are missing material/transport features
and bounded scene coverage. Retaining raster visibility is a reasonable
production route if those systems share consistent data.

A pure camera-ray renderer would additionally need complete visible geometry,
matched transparency and deformation, jittered primary sampling and a new
composition contract for water, atmosphere and effects. Treat that as a later
architecture milestone. [RTXPT](https://github.com/NVIDIA-RTX/RTXPT#features)
is a useful reference for a pure tracer with DX12/Vulkan backends, analytic and
emissive lights, volumes and nested dielectrics. Its sample is a reference for
individual systems, not a drop-in Godot renderer.

Selective mesh refinement can improve prominent banks, rocks and props without
changing collision or authored gameplay placement. The corresponding tracing
geometry must follow the visible geometry. Simply subdividing a planar face
does not improve its silhouette; displacement or remodeled shape is needed.
Prioritize these assets before expensive general caustics, full volumetric
multiple scattering or large increases in path depth. Feature-dependent SER
and opacity-micromap work should follow capability checks and profiling rather
than becoming a prerequisite for the current DX12/Vulkan path.

## Performance baseline and acceptance

The [latest saved comparison](../validation/path-tracing-shader-optimization-2026-10-22/README.md)
uses an RTX 3090 at 1280×720, DX12 through Wine/VKD3D. Four-bounce PT costs
5.479 ms at Medium and 20.972 ms at High, including reconstruction and history
copies, with acceleration-structure updates outside that bracket. Whole-frame
times are 8.075 and 23.223 ms respectively. Units, water reflections, frame
generation, wind and grass were disabled for these controlled timings; they
are not full-game or native-Windows performance promises.

High uses full dimensions with four path samples; Medium uses 75% dimensions
with two. That is about 3.56 times as many path samples before differences in
shader behavior. These coupled settings make increasing quality expensive.
Separate resolution, sampling and reconstruction quality during experiments so
their individual contributions can be assessed.

The current lighting/guide history uses 104 bytes per tracing pixel, about
91 MiB at 720p and 823 MiB at 4K, before scene textures, acceleration structures
and water resources. New guides, reservoirs and caches need an explicit memory
budget and transient-resource reuse.

Use one matched acceptance route containing river banks, a forest, a cave with
several sources and moving characters. Add stress cases for thin foliage,
offscreen lights, reflective metal, emissive removal, camera disocclusion,
scene streaming and multiple water levels. Compare moving clips as well as
stationary references.

For each change record tracing, reconstruction, scene-update and whole-frame
times, frame-time tails and peak VRAM. Compare at equal output resolution and
also at comparable moving-image quality. Use alternating same-process runs
where possible. Report rendered FPS separately from generated presentations;
frame generation does not establish a lower tracing cost.

Start with the existing RTX 3090 and extend qualification to native Windows,
native Vulkan and other supported vendors before wider claims. Keep the
existing Wine shutdown limitation separate from visual/behavior assertions.
Development profiles must retain a free cursor, visible FPS and muted audio.
Any new settings must ship with EN/RU/DE labels, choices and help together.

## Suggested first implementation milestone

Implement the common motion/hit-distance guide contract and configurable PT
internal resolution, then compare NRD against the present filter. Alongside
that renderer work, author one small material set and relight the representative
river/cave pair. Judge the combined result at the existing rendered-frame
budget. This produces both a visible demonstration and a sound basis for
many-light sampling, caching and water integration.

Useful source entry points are
[`scene_raytrace.gd`](../../game/src/game/fx/scene_raytrace.gd),
[`path_trace.hlsl`](../../game/src/game/fx/shaders/path_trace.hlsl),
[`path_trace_filter.glsl`](../../game/src/game/fx/shaders/path_trace_filter.glsl),
[`water_raytrace_scene.gd`](../../game/src/game/fx/water_raytrace_scene.gd),
[`water_raytrace_device.gd`](../../game/src/game/fx/water_raytrace_device.gd),
[`path_trace_emitters.gd`](../../game/src/game/fx/path_trace_emitters.gd),
[`path_trace_terrain.gd`](../../game/src/game/fx/path_trace_terrain.gd) and the
[custom engine integration](../../engine_patches/godot-4.7/README.md).
