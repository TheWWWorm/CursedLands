# Ray-traced scene lighting (experimental)

Since 1.24.0, the Windows and Linux builds add optional hardware ray-traced shadows and one-bounce
diffuse global illumination to the main campaign view. Terrain, objects and
characters using the game's lit materials receive the lighting. The controls
are under **Options → Graphics → Lighting and shadows → Ray-traced lighting**:

- **RT shadows (test):** soft sunlight and shadows from up to seven nearby
  point lights. The existing object/character shadow switches still apply.
- **RT indirect light (test):** diffuse colour bounce from sunlight, nearby
  lights and emissive surfaces, plus occluded outdoor sky illumination.
- **RT lighting quality:** an independent budget for both effects.

The same page also offers a separate
[multi-bounce path-tracing prototype](path-tracing-experiment.md), which
replaces these two effects while active and preserves their saved settings.

Both effects default to Off. Quality defaults to Medium. Presets and automatic
detection preserve these choices. Apply changes without a restart; Cancel
discards pending changes. Labels, choices, help and availability explanations
are localized in English, Russian and German. An unsupported renderer prevents
enabling RT but still permits turning off a saved setting.

| Quality | Width and height relative to game window | Diffuse samples per pixel | Visibility samples per light |
| --- | ---: | ---: | ---: |
| Low | 50% | 1 | 1 |
| Medium | 75% | 2 | 2 |
| High | 100% | 4 | 4 |

The percentages apply to each dimension, not the pixel count: Low traces one
quarter of High's pixels. Resolution follows window resizing with no fixed
pixel cap, independently of internal render scale/FSR and water reflection
quality. A primary visibility ray locates the receiver for each lighting pixel.
GI samples also trace visibility from their bounce hit to contributing lights;
the table is not the total ray count.

## Rendering and fallback

Use the qualified Godot 4.7 engine and native extensions documented in the
[water RT integration](water-raytracing-experiment.md#engine-requirement).
The same engine supports the new shaders without an additional engine patch.
DX12 is the primary Windows development path; Vulkan Forward+ also works on
qualified hardware. Compatibility/OpenGL, unqualified engines and non-RT GPUs
keep conventional lighting. These changes first shipped in 1.24.0.

`scene_raytrace.gd` gathers a 96 m scene around the active camera, including
ceilings and underground geometry. It shares the water experiment's material,
mesh, animation and acceleration-structure handling but keeps separate scene
and lighting resources. Primary receivers, shadow casters and indirect-light
surfaces have separate ray masks. Original articulated animation, supported
morphs, transforms and visibility update live. Membership/material changes are
checked once per second; moving 16 m recenters the snapshot.

`scene_raytrace.hlsl` traces soft direct visibility and one cosine-weighted
diffuse bounce. Each bounce evaluates direct sunlight and up to seven selected
local lights with occlusion, or emission. Outdoor misses receive sky radiance;
cave misses receive none. Light transforms, colours and energy update each
frame, with nearby-light membership refreshed once per second. Bounce lighting
is approximate: the shared material snapshot does not reproduce every original
material or procedural lighting effect.

`scene_raytrace_filter.glsl` filters GI over a 5×5 neighbourhood and shadow
visibility over 3×3. Normal, depth and surface-plane tests reject unrelated
surfaces. Camera reprojection retains at most eight GI history frames, with
neighbourhood clamping and shorter shadow history. Camera cuts, resizing, mode
changes and new scenes invalidate history. The four published output textures
retain stable backing allocations between resizes; GPU copies supply previous
history without invalidating every material's bindings each frame.

The main-view material integration checks world position, receiver depth and
normal before sampling. Valid receivers replace flat ambient illumination
with traced indirect light when GI is enabled. Direct light is accumulated in
linear space. RT visibility replaces supported direct shadow attenuation;
other lights retain conventional shadows. Water, mirror views and previews
retain their own lighting. RT lighting fades to conventional illumination
between 60 and 72 m from the snapshot centre. Conventional lighting also stays
live during preparation, after allocation/build failure and when budgets are
exceeded. Disabling both effects releases the RT resources and restores the
original material path.

While GI is active, screen-space ambient occlusion and contact-shadow blobs are
suppressed to avoid applying ambient darkness twice. Their saved preferences
are preserved and restored when GI stops. Conventional shadow maps remain
available for fallback receivers, so RT adds work rather than eliminating all
existing shadow rendering.

## Limits and cost

This mode is an experimental one-bounce GI implementation. It does not provide
multi-bounce path tracing, a world-space irradiance cache, ray-traced specular
lighting or production-quality denoising. Moving lighting can be noisy or lag
briefly; reprojection has no per-object motion vectors. Geometry and material
differences can cause visible transitions to fallback, particularly at thin
surfaces and silhouettes. Cavities with no directly illuminated or emissive
bounce source can be very dark.

The geometry budget is 320,000 unique triangles, 4,096 instances and 192 texture
layers of 512×512 with mipmaps. Shader-only wind, custom vertex deformations,
particles, blended/hashed transparency, textured emission and full normal/UV
material reproduction retain the water experiment's limitations. Standard
materials can participate in ray intersections and bounce/caster geometry;
receiving the result is implemented in the game's Gfx material pipeline.
Only seven nearby point lights participate in traced lighting at once. Selection
changes and missing distant occluders can change the result.

The twelve RGBA16F lighting images use about 96 bytes per output pixel: roughly
84 MiB at 1280×720 High and 759 MiB at 3840×2160 High, before material textures
and acceleration structures. Water RT has its own additional resources. Initial
scene extraction, GPU builds, first-use shaders and large scene changes may
hitch. High resolution and several overlapping local lights increase GPU cost.

On an RTX 3090, a frozen 1280×720 river test through DX12/Wine measured the
combined shadows+GI dispatch, reconstruction and history copies at about
**0.20 ms Low, 0.52 ms Medium and 1.55 ms High**. Whole-frame Low was
**4.16–4.62 ms**, versus **2.94–2.98 ms** with conventional lighting. The RT
timestamp excludes acceleration-structure updates; whole-frame time includes
CPU work and is not derived from that timestamp. These are two short interleaved
rounds with units hidden and water reflections off, not gameplay FPS guarantees
or native Windows performance results. See the
[validation report](../validation/scene-rt-2026-10-22/README.md) for methodology,
Vulkan results and API diagnostics.

## Shader builds and tests

The one HLSL source is compiled to four native DXIL libraries and four SPIR-V
stages. Runtime compilation with DXC is unnecessary. The manifest pins source,
builder and output hashes. With Microsoft DXC 1.9.2609:

```sh
python3 tools/build_water_rt_shaders.py --shader scene_raytrace --dxc /path/to/dxc
python3 tools/build_water_rt_shaders.py --shader scene_raytrace --check --dxc /path/to/dxc
python3 tools/build_water_rt_shaders.py --shader water_raytrace --check --dxc /path/to/dxc
python3 tools/check_translations.py
```

Export with the qualified matching template after importing the compute shader.
Run GPU fixtures in an isolated profile with a free cursor, FPS visible and all
audio muted. Test files are supplied through the existing `--tool` interface:

| Fixture in `tools/tests/` | Coverage |
| --- | --- |
| `scene_raytrace_device.gd` | GPU readbacks, direct shadows, emissive and diffuse colour bounce, all seven point-light channels, finite rays, moving casters, resource lifetime |
| `scene_raytrace_alpha.gd` | Opaque and cutout geometry in primary, shadow and GI rays |
| `scene_raytrace_live.gd` | Actual river materials, quality targets, setting transitions, exact conventional restoration |
| `scene_raytrace_cave.gd` | Cave sky exclusion, changing light colour, animated character, ambient-effect restoration |
| `scene_raytrace_materials.gd` | 144 rendered world-material variants and conventional fallback |
| `scene_raytrace_options.gd` | Apply/Cancel/persistence, supported and unsupported renderers, EN/RU/DE labels/choices/help at 1280×720 and 800×600 |
| `scene_raytrace_fallback.gd` | Conventional baseline and unsupported-renderer behaviour |
| `scene_raytrace_fsr.gd` | Production FSR frame generation, rendered/presented FPS text, simultaneous water and scene RT, resize, pause/resume |
| `scene_raytrace_performance.gd` | Two interleaved rounds with separate RT GPU, controller CPU and whole-frame timing |
