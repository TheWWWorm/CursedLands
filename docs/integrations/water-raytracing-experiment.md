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

The initial frame timings are whole-frame wall times on a shared development
machine. The follow-up below also measures the GPU reflection pass separately.
Neither is a performance guarantee: RT draws less detail and at a lower
resolution than normal Mirror, so this is not a quality-matched comparison.

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

## Measured reflection cost

On the RTX 3090 at 1280 × 720, three interleaved rounds of 90 samples at the
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
