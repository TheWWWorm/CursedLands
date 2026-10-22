# Path-traced lighting prototype (unreleased)

The development build adds an optional multi-bounce lighting mode for nearby
terrain, objects and characters. It traces direct shadows, diffuse colour
transport and rough glossy reflections through two or four surface bounces.
It is a bounded lighting prototype: the main view still uses raster visibility,
material composition, sky, fog, water and particles. It is not a replacement
for the complete renderer and is not included in published 1.23.0.

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
sampled with a shared mixture PDF. The bounce count bounds work; there is no
Russian roulette or light reservoir sampling. Geometric normals offset rays
outside the actual triangles, while interpolated normals shade the surfaces.

Primary diffuse illumination and glossy radiance are stored separately. The
diffuse signal excludes the primary albedo so the main material retains its
original texture detail after reconstruction. Subsequent hits include their
albedo. Existing remake surface profiles and StandardMaterial roughness,
metallic and specular values supply a compact material description; original
assets without a profile default to rough dielectric surfaces. This does not
reproduce full PBR texture sets or procedurally modified materials.

`path_trace_filter.glsl` uses normal/depth/plane/material rejection, a 5×5
diffuse filter and a smaller 3×3 glossy filter. Responsive mode reprojects up
to eight history frames with neighbourhood clamping. Still scene skips the
spatial blur and progressively averages matching pixels, up to 256 frames.
It is a custom prototype filter, not NRD, DLSS Ray Reconstruction or another
production denoiser. History is reset on mode, resolution and scene changes;
light changes invalidate both accumulation modes.

The material integration replaces supported nearby lighting and fades back to
conventional illumination between 60 and 72 m from the scene snapshot centre.
World geometry is gathered within 96 m, with the existing budgets of 320,000
unique triangles, 4,096 instances and 192 texture layers of 512×512.
Characters' supported articulated and morph animation updates live.

## Limits and qualification

- The original assets were authored for a different lighting model. Some
  rooms have no physical light source and can become very dark. Relighting
  and better material data are needed for consistent campaign presentation.
- Water retains its separate reflection renderer. Water refraction, glass,
  volumetric paths, particles, shader-only vegetation motion, full textured
  emission and normal/roughness maps are not part of the path integrator.
- There are no object motion vectors, spatial light cache, emissive-light
  importance sampling or production denoiser. Small emissive sources and
  glossy paths can be noisy. Still scene is useful for comparisons, not for
  hiding noise during active gameplay.
- Primary ray samples use pixel centres. The raster view supplies silhouette
  antialiasing; the prototype does not provide supersampled path-traced
  geometry edges. Thin geometry, normals and receiver mismatches can expose
  conventional-lighting seams. Missing geometry outside the bounded scene
  can produce light leaks or different distant reflections.
- The twelve RGBA16F images use about 96 bytes per tracing pixel: approximately
  84 MiB at 1280×720 High and 759 MiB at 3840×2160 High, before scene textures
  and acceleration structures. Water tracing has separate resources.

See the [validation report](../validation/path-tracing-2026-10-22/README.md)
for actual outdoor/cave captures, timings, frame-generation checks and known
API diagnostics. DX12 tests here use the Windows build through Wine/VKD3D;
native Windows and other GPU vendors still require qualification.

## Rebuild and checks

All four stages are checked in as matching DXIL and SPIR-V binaries. Manifests
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
| `path_trace_live.gd` | Outdoor material integration, responsive reprojection, still accumulation, camera reset, quality resizing and conventional restoration |
| `path_trace_cave.gd` | Cave sky exclusion, two/four bounces, changing light colour, animated actor and history invalidation |
| `path_trace_materials.gd` | Actual compilation/draw of 144 world material variants |
| `path_trace_fsr.gd` | Production frame generation and measured FPS HUD alongside water and path tracing, resize and pause/resume |
| `path_trace_performance.gd` | Separate ray-pass GPU, controller CPU and whole-frame timing against conventional and one-bounce RT lighting |
| `scene_raytrace_options.gd` | Shared RT/PT settings, persistence, supported/unsupported controls, EN/RU/DE labels, choices and help |
| `scene_raytrace_fallback.gd` | Saved experimental settings on unsupported renderers |
