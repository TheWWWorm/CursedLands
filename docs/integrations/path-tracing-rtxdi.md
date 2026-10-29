# Optional RTXDI direct lighting

The current player presets manage this setting. The individual control below
is available for renderer diagnostics with `-- --ei-pt-tuning`; see the
[player preset and tuning contract](path-tracing-experiment.md#controls).

**Remake → Ray tracing / Path tracing → ReSTIR direct lighting** enables
NVIDIA RTXDI 3.1.0 in the main path-traced view. It defaults to Off and requires
Responsive accumulation. Labels, choices, help and attribution are translated
into English, Russian and German. Still accumulation restores the existing
reference sampler and releases the optional reservoirs. Water retains its own
lighting and denoising.

The implementation uses the unmodified RTXDI shader library. This is direct
light resampling, not ReSTIR GI or a replacement for path continuation. It is
compatible with radiance NRD, directional NRD, SHaRC and DLSS Ray Reconstruction.

## Sampling and history

Managed presets use the existing summed-light estimator when the scene has at
most four local lights and no registered emissive triangles. That estimator
evaluates every light exactly with one shadow ray each; from five lights it
would draw four stratified proposals per frame, and the separate ReSTIR pass
with one shadow ray and temporal reuse measured cheaper than those four rays,
so five or more lights or any registered emitter activate RTXDI; its shader
variants are prepared in
advance. The diagnostic `--ei-pt-tuning` mode continues to honor the explicit
RTXDI switch. Bounce count, resolution and reconstruction settings are unchanged.

Each primary receiver generates 8 candidates (the RTXDI library default;
sixteen measured about 0.25 ms more per frame at 1280×720 with no visible
gain over the temporal reservoir) from the existing local-light
table and registered emissive triangles. Local lights use a uniform proposal;
emissive triangles use the existing power distribution. When both are present,
each family receives half the proposal probability. Triangle sampling includes
the area-to-solid-angle Jacobian and actual textured emission. The target is
the luminance of the material's diffuse plus specular response.

The resampling runs in its own ray-generation pass after the path pass: the
path program stores the visible surface (position, normals, albedo and
material, the exact self-intersection offset and the placement id) and
publishes its path terms with raw direction moments; the direct-light pass
loads that surface, resamples, traces one visibility ray, adds the light,
applies the authored ambient floor and encodes the moments. Fusing the
resampling into the path program had cost the whole frame its occupancy.
`RTXDI_DISpatioTemporalResampling` merges the fresh reservoir with nearby
reservoirs from the previous frame. It never reads another pixel's writes from
the current dispatch. The SDK's BASIC correction reevaluates sample targets
at neighboring surfaces. This mode is approximate; it is not advertised as an
unbiased reference renderer. Depth, normal and material checks reject unrelated
surfaces. Permuted temporal sampling and an eight-pixel spatial neighborhood reduce
correlation. Each frame resamples two spatial neighbours (eight after a
disocclusion); the temporal reservoir carries most of the effective sample
count, and on the river each further neighbour cost about a quarter of a
millisecond at 1280×720. The diagnostic `--ei-pt-di-tuning=spatial,boost,
permutation,bias` and `--ei-pt-di-candidates=N` overrides exist for
measurements. Light records are read from storage-buffer copies of the
current and previous frame blocks: the resampling gathers them with per-lane
indices, which a constant buffer would serialise across the wave. History is
limited to eight candidate batches per reused reservoir,
or four with RR. Final RR shading mixes in the fresh estimate with probability
one quarter; this is a simple estimator mixture, not NVIDIA's separate path
stagnancy algorithm.

Every selected sample receives a new visibility ray against current geometry.
No previous-frame shadow result is reused. Sunlight is sampled separately, and
later path vertices keep their existing direct-light and MIS estimators. First
continuation hits on registered emitters are assigned exclusively to RTXDI's
next-event estimate, preventing duplicate energy. Emitters outside the bounded
table retain BSDF sampling support.

Previous surface positions and material data are private to each device. Motion
uses the existing instance motion records and the actual previous rendered
camera, including RR jitter. Camera cuts, resized targets, scene generations,
abrupt light changes, light membership changes and emitter-table revisions
discard history. Gradual local-light intensity changes can retain samples;
the old frame's light parameters remain available for proposal reevaluation.

## Resources and fallback

Two arrays of 24-byte SDK reservoirs and two arrays of 32-byte surface records
use 112 bytes per pixel, padded to 16×16 blocks. A 1920×1080 PT input therefore
uses about 223 MiB, plus small constants and neighbor offsets. This is the PT
input size, which may be smaller than the displayed window. Scene handoff can
briefly retain two generations. Off allocates none of these buffers.

Private buffers and descriptors are rebuilt on resize and released on Off or
device teardown. Public lighting texture handles retain their existing lifetime
contract. Failed optional allocation, shader setup or preparation returns to
ordinary PT and suppresses repeated attempts until the option is toggled.
SHaRC update and query passes use the appropriate separate descriptors.

ReSTIR can still produce correlated noise, lag around changing illumination
and poor convergence for small or mostly occluded emitters. A fresh shadow ray
avoids cached visibility errors but does not make light selection aware of
every occluder. This integration does not establish a universal speed or
quality improvement. Large light counts, image size and reconstruction mode
affect the tradeoff.

## Source and reproducible builds

RTXDI [3.1.0](https://github.com/NVIDIA-RTX/RTXDI/releases/tag/v3.1.0) selects
the library revision
[`f12037fa8e97ebc08e9e3edfd2de528ed1772a4b`](https://github.com/NVIDIA-RTX/RTXDI-Library/tree/f12037fa8e97ebc08e9e3edfd2de528ed1772a4b).
The integration follows its
[application bridge](https://github.com/NVIDIA-RTX/RTXDI/blob/v3.1.0/Doc/RtxdiApplicationBridge.md)
and [integration guide](https://github.com/NVIDIA-RTX/RTXDI/blob/v3.1.0/Doc/Integration.md).
The pristine external headers and license are hashed in
`engine_patches/rtxdi-sdk.json`; they are not vendored into application source.
Compiled shaders and the complete `RTXDI_NOTICES.txt` carry the separate NVIDIA
RTX SDKs license. Desktop packaging copies the notice into `licenses/NVIDIA/RTXDI`.

```sh
python3 tools/build_path_rtxdi.py --sdk /path/to/RTXDI-Library \
  --sharc-sdk /path/to/SHARC --dxc /path/to/dxc
python3 tools/build_path_rtxdi.py --check
# Reproduce and compare the packaged programs without replacing them:
python3 tools/build_path_rtxdi.py --check --sdk /path/to/RTXDI-Library \
  --sharc-sdk /path/to/SHARC --dxc /path/to/dxc
```

Eight ray-generation variants cover emissive tables, deep paths and SHaRC;
each has native DXIL and SPIR-V. The manifest hashes source, builder, SDK pin,
compiler, notice and all sixteen programs. Shared closest-hit and miss programs
retain the existing material and payload ABI. No engine or payload extension is
required for RTXDI.

The original game has no hardware path tracer or reservoir sampler. Its Wine
renderer cannot provide a direct reference for this new algorithm. Independent
summed-light renders, existing MIS transport and the related renderer regressions
provide the relevant controls; original-game parity is not claimed.
