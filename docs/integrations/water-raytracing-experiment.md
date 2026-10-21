# Water ray-tracing experiment

This local prototype adds **Options → Graphics → Water → Water reflections →
Ray traced (test)**. It traces actual Vulkan hardware rays into nearby terrain
and static objects, then feeds the result into the existing water tint,
distortion and Fresnel shading. It is an optional fourth choice; defaults,
automatic detection and all graphics presets continue to use existing modes.
The label, choices and help are available in English, Russian and German.

## Try the local build

Run `local/scratchpad/water-raytracing-20261021/run-water-raytracing.sh` from
the EI workspace. This opens the experiment with ray-traced water selected.
The launcher creates a separate profile with a free cursor, FPS visible and all
audio muted. Its saves and settings belong to the experiment. The normal game
profile is not imported. Compare **Mirror** and **Ray traced (test)** in the
water options while looking across a river in a perspective camera mode.

The generic launcher is `tools/experiments/launch_water_raytrace.py`:

```sh
python3 tools/experiments/launch_water_raytrace.py \
  --engine /absolute/build/godot-water-rt.x86_64 \
  --ei-path /absolute/EvilIslands \
  --profile /absolute/water-rt-experiment-profile
```

Keep the matching `godot-water-rt.pck` and `src/native/bin` beside the executable.
This is a separate Linux experiment, not a published release or a replacement
for the normal executable. No release version or published artifact is changed.

## Scope and limits

- One reflection bounce from one selected water level, using a perspective
  camera. The existing water shader approximates waves through texture
  distortion; rays do not intersect a fully displaced water surface.
- An 80 m snapshot of nearby terrain and static object meshes. Camera motion
  updates rays every frame; moving more than 16 m or changing pools rebuilds
  the snapshot. Removed or moved static objects can remain in it until a rebuild.
- Alpha-tested texture cutouts preserve foliage silhouettes. Animated units,
  foliage motion, particles, procedural ground effects, local lights and
  reflected shadows are not reproduced. Lighting uses material properties,
  ambient light, sunlight and depth fog; it is an approximation of the raster
  materials, not a full path-traced lighting system.
- Half the display width and height, capped at 960 pixels on the longer edge.
  Geometry is capped at 240,000 triangles and 192 texture layers at 512 × 512.
  Extraction is staged across frames, although a single mesh or GPU build can
  still cause a hitch. Texture and acceleration-structure memory is additional
  to the ordinary scene.
- Preparation, unsupported hardware, an unsupported engine, orthographic
  cameras and backend failures retain the existing reflection path. Forward+
  uses Mirror; other renderers retain their established fallback. Selecting
  Mirror or Off releases the experiment's GPU resources.

The implementation deliberately keeps the planar view available during
preparation. It disables that extra scene draw once the ray-traced texture is
ready. A planar water scene can already look very similar with Mirror; the
purpose here is to establish a working hardware tracing path and evaluate it.

## Engine requirement

Use the pinned Godot source and sixteen common patches documented in
`engine_patches/godot-4.7/README.md`, then apply
`engine_patches/godot-4.7/water-raytracing-uniform-stages.patch` and build a
Linux x86-64 release template with Vulkan enabled. Export this branch's game
PCK with the Godot 4.7 editor and include its native libraries as usual.

The patch corrects ray-tracing uniform visibility: the shader container was
combining stage enum values where stage bit masks were required. On the tested
runtime, hit shaders could not correctly read textures and buffers without
this change. The patch also exposes `ei_raytracing_uniform_stages`, checked
alongside Vulkan, Forward+ and `SUPPORTS_RAYTRACING_PIPELINE`. An ordinary
unpatched engine therefore takes the fallback instead of dispatching this
pipeline. No vendor DLL or ray-query extension is required.

## Validation

The local evidence is in `docs/validation/water-raytracing-2026-10-21.json` and
the matching scratch directory. It includes GPU readbacks for nearest hits,
texture access, alpha rejection, misses, water clipping, resizing and cleanup;
real river views; camera and option transitions; and EN/RU/DE option/help
captures. See the evidence for exact results and unqualified platforms.

Frame timings are whole-frame CPU wall times on a shared development machine,
not isolated GPU timings or a performance guarantee. The ray-traced pass draws
less detail and at a lower resolution than Mirror, so the timings are not a
quality-matched comparison.
