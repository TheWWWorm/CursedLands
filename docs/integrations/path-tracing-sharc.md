# Optional SHaRC indirect lighting

Added on 25 October 2026, starting from local integration `2a912713` and
retaining the sparse scene-upload change `2a7cd054`.

**Remake → Raytracing / Path tracing → SHaRC indirect lighting** enables
NVIDIA SHaRC 1.8.3 for Responsive PT. It defaults to Off. The label, choices,
help and SDK credit are translated into English, Russian and German. Still
scene accumulation bypasses the cache and releases its buffers.

SHaRC is an approximate world-space radiance cache. It shares indirect light
between nearby surfaces and can terminate eligible paths early. Its update
paths also carry lighting beyond the selected two/four-bounce query budget.
This changes the estimator; it is not an unbiased replacement for the bounded
reference renderer, nor a guaranteed performance improvement. NRD remains the
reconstruction stage. This change adds no asynchronous reconstruction or DLSS
Ray Reconstruction integration.

## Integration

Each scene generation owns a cache with 1,048,576 entries: 8-byte spatial keys,
16-byte accumulation records, 16-byte resolved records and 4-byte locks.
These buffers occupy 44 MiB, plus small constants/counters and shader resources.
A scene handoff can briefly retain two caches. Caches are never transferred
between scene generations; the existing validated NRD history handoff remains.

The render thread runs these passes in order:

1. Trace one jittered update path per 4×4 tile of the PT image, with up to
   eight segments and existing BSDF, terrain, emitter, sun, sky and local-light
   evaluation. Updates do not resample old cached radiance.
2. Resolve the cache, with at most eight history frames, the existing shorter
   history limit during gradual light changes, and an eight-frame stale limit.
3. Trace the regular image. Only sufficiently rough, nonmetallic indirect
   transport can query the cache, and the last segment must exceed the cache
   voxel size. Thin foliage and sharp/glossy transport retain explicit tracing.
   Missed queries continue the existing integrator.
4. Run the existing NRD and direct-light reconstruction/presentation passes.

Primary direct lighting and NRD's first-hit distances remain explicit. Emission
is separated from cached radiance and evaluated with the current MIS weight
once on a successful query. Material demodulation uses an albedo floor of 0.05;
scene scale is 128. The implementation uses SHaRC's 32-bit lock fallback for
64-bit keys, so it does not require 64-bit atomics. Native fp16 arithmetic and
16-bit storage are checked before allocation.

Moved/masked instances, deformations, abrupt lighting changes, camera cuts,
resizing and other existing history resets clear cached radiance. Identical
instance transforms do not clear it. Conservative whole-cache invalidation
avoids stale blockers/light, but reduces usefulness in animated crowds. Small
lighting changes retain the existing short response window, so approximate
indirect light may still lag slightly. Thin-wall leaks and spatial bias remain
inherent limitations of radiance caching.

Off does not allocate cache buffers. Failed setup or an optional update pass
returns to ordinary PT, releases partial resources and suppresses per-frame
retries. Switching the option off/on permits a new attempt. Query/update shaders
have separate shader binding tables and descriptors; outputs retain their
existing stable handles.

## Shader builds and backend compatibility

The external SDK is pinned to
[`4e21b585c33c83d723ca9a1e11bbb1090d145793`](https://github.com/NVIDIA-RTX/SHARC/tree/4e21b585c33c83d723ca9a1e11bbb1090d145793).
Headers are not vendored or modified. They are covered by the NVIDIA RTX SDKs
license, separately from application source. Compiled programs, complete
`SHARC_NOTICES.txt`, package-license copying and an in-game credit are included.

```sh
python3 tools/build_path_sharc.py --sdk /path/to/pinned/SHARC --dxc /path/to/dxc
python3 tools/build_path_sharc.py --check
# Reproduce binaries without replacing them:
python3 tools/build_path_sharc.py --check --sdk /path/to/pinned/SHARC --dxc /path/to/dxc
python3 tools/build_water_rt_shaders.py --shader path_trace --check
```

`path_trace_sharc_build.json` hashes the adapter, builder, pristine pinned SDK
files, license, compiler and all 13 runtime binaries. Ray-tracing libraries use
native DXIL on DX12 and SPIR-V on Vulkan. The resolve compute shader uses
`shader_create_from_spirv` on both backends, as NRD does. The engine's direct
DXIL entry point accepts only ray-tracing stages.

A default-true specialization guard preserves the resolve program through
Godot 4.7's re-spirv optimizer, matching the existing NRD workaround. An
unguarded program passed SPIR-V validation but crashed the NVIDIA Vulkan
pipeline compiler after the engine rewrite; a debugger isolated the failure
to compute pipeline creation. The final guarded program and the complete
update/resolve/query sequence pass on native Vulkan and DX12 through Wine.

## Measured cost

The table below records the initial SHaRC integration, before the subsequent
cave-wall material correction. The final combined change has additional wall
sampling work; its measurements are recorded in the
[cave-wall validation report](../validation/cave-wall-2026-10-25/README.md).

These are static campaign comparisons at a 1920×1080 window, with actor
animations paused, in GPU Lab heavy jobs. Each result averages two block
medians from Off/On/On/Off order (40 warm-up and 120 measured frames per block).
Low traces at 50% resolution and one sample/pixel; High traces at 100% and four.
The measurements include cache updates, resolve, tracing and reconstruction.
They are PT-pass GPU times, not general game-FPS promises.

| Scene / quality / GPU | Bounces | Off | SHaRC On | PT GPU change |
| --- | ---: | ---: | ---: | ---: |
| Outdoor / Low / RTX 3090 | 2 | 1.430 ms | 1.877 ms | +31.3% |
| Outdoor / Low / RTX 3090 | 4 | 1.606 ms | 2.050 ms | +27.6% |
| Cave / Low / RTX 3090 | 2 | 4.144 ms | 4.686 ms | +13.1% |
| Cave / Low / RTX 3090 | 4 | 4.727 ms | 5.406 ms | +14.4% |
| Outdoor / High / RTX 3090 Ti | 2 | 15.564 ms | 16.756 ms | +7.7% |
| Outdoor / High / RTX 3090 Ti | 4 | 17.367 ms | 17.517 ms | +0.9% |
| Cave / High / RTX 3090 | 2 | 102.601 ms | 73.946 ms | -27.9% |
| Cave / High / RTX 3090 | 4 | 110.545 ms | 76.815 ms | -30.5% |

High-quality cave rendering benefits substantially; Low quality does not
amortize the extra cache work, and the outdoor High four-bounce result is
approximately break-even. This is why the option remains Off by default.
These captures exercise static scenes; frequent geometry/light invalidation
can reduce the benefit further.

## Validation

`path_trace_sharc` is a registered GPU regression. Its 25 assertions exercise
real cache writes and query hits, coloured emissive transport, NRD, persistent
history, stable targets, odd-size resizing, moving blockers, unchanged
transforms, extinguished emission, accumulation switches, allocation/update failure, packaged credit/license,
retry suppression and teardown. Both Vulkan and DX12/Wine pass.

`path_trace_sharc_live` is registered for the real campaign. Outdoor Ingos and
Gipath cave runs each pass 18 assertions covering terrain/material variants,
actual cache hits, the two/four-bounce switches, red/blue moving local lights,
light removal, Still/Responsive switches, streamed scene replacement, NRD,
Off and leaving PT. The settings fixture passes 423 assertions, including
translated help at 800×600 and 1280×720; German and Russian captures were also
visually checked.

The original game has no hardware path tracer, NRD or SHaRC cache. Comparing
this new renderer feature with original gameplay under Wine would not establish
cache correctness. Instead, the reference is the same remake renderer with
SHaRC disabled, supported by actual Vulkan and DX12/Wine GPU readback and
campaign captures. Original-game visual parity is not claimed.

1125 passing GPU assertions include the four benchmarks and related
motion, sparse-upload, lifecycle, glossy, emitter, foliage, terrain, NRD,
first-person illumination, water and scene-device checks. CPU qualification
tests pass 24 checks; translations report zero errors. All 31 shader binaries
reproduce, and all 16 SPIR-V modules validate.

Timing results and regression receipts are recorded in
[the validation summary](../validation/sharc-2026-10-25/summary.json).
