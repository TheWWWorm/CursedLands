# Path tracing: material relief, receiver coverage and weather

This change builds on stable 1.27.0. It corrects diffuse reconstruction on
textured surfaces, fills small gaps in the half-resolution receiver lookup,
and shares cloud and precipitation attenuation with traced sunlight. It adds
no player options or strings. The engine is unchanged; both DXIL and SPIR-V
path-tracing binaries were rebuilt from the matching HLSL source.

## Reconstruction and continuity

The temporal and spatial filters previously treated the shading normal as a
geometric plane. Relief normals do not describe that plane: using them rejected
valid neighbours and history on flat, textured geometry. The filters now derive
a local plane from primary-ray depth, choosing the shorter valid neighbour on
each axis at silhouettes. Shading normals still weight illumination edges.
The geometric plane follows the same inverse-transpose motion transform as the
surface normal, and plane tolerances include half-float depth quantization.

Diffuse irradiance is already demodulated. Painted albedo and roughness changes
therefore no longer reject otherwise valid diffuse history. Instance identity,
metalness, depth, normal and spatial-distance checks remain. Specular radiance
retains its stricter material and angular checks. History length and filter
radius are unchanged; spatial output never feeds back into temporal history.

When the four half-resolution bilinear samples all miss, the raster receiver
searches a bounded two-texel neighbourhood. It still requires compatible normals
and the same geometric plane. This recovers narrow coverage gaps without
accepting a nearer foreground or unrelated background layer. Ordinary successful
lookups do not pay for that search. Scene radius and supported device fallback
remain unchanged.

## Lighting

Previously precipitation did not change PT sunlight or ambient energy, and
traced sunlight did not sample the cloud shadow field. A dark visible sky could
therefore sit above clear-day terrain lighting.

PT now samples the existing sheet noise or the shared volumetric attenuation
field at each sun-lit hit. The field is reused rather than integrating a cloud
volume inside every bounce. Disabling or replacing the field safely rebuilds
its descriptor, including RD's automatic invalidation of dependent uniform sets.
The volume lookup is bounded to the existing 1024-metre field and surfaces below
the cloud base; unsupported field coordinates retain unattenuated sunlight.

While PT is selected, outdoor precipitation scales authored *linear* sunlight
to 14% and ambient energy to 65% at full daytime rain. Snow uses 80% of rain's
strength. These are explicit appearance settings in code, not a calibrated
atmospheric simulation. Both traced and conventional receivers get the same
palette, so a fallback pixel cannot expose clear-day lighting in the storm.
Dry weather, night and cave palettes retain their previous values. Time-of-day
classification uses the authored sunlight before weather attenuation.

The existing precipitation cosine transition lasts twenty world ticks (1.1 s
for rain). During that transition, responsive accumulation uses the same short,
frame-time-bounded history as changing local lights. Abrupt changes still reset;
progressive accumulation requires exact lighting and cloud phase matches.

## Measurements and verification

The reference video uses 1.26.0. Measurements here compare against the newer
stable 1.27.0, which already includes earlier continuity and spatial-filter fixes.
All launches use isolated profiles, a free cursor, visible FPS and muted audio.
Rendered checks run through GPU Lab with automatic GPU selection.

Matched Gipat ruins first-person view: 1920×1080 output, Low / 50% tracing,
two bounces, fast response, FSR off. For eight held dry-day frames, sample
variance of linear diffuse luminance is averaged over 417,985 matching pixels
with depth below 55 m, depth difference below 5 cm and normal dot above 0.95:

| Measure | Stable 1.27.0 | Candidate |
| --- | ---: | ---: |
| Temporal luminance variance | 0.0000308239 | 0.0000201046 |
| Mean linear luminance | 0.384782 | 0.384581 |
| Nearby terrain receiver rejection | 353 / 131,509 | 121 / 131,490 |

That is 34.8% lower temporal variance with 0.052% lower mean brightness in this
view. Seeds are driver scheduled, so this is a scene measurement rather than a
universal quality score. Across six moving captures, the fraction retaining at
least four frames of history improves in every capture. The controlled relief
fixture changes from one-frame history and variance 0.8276 to eight-frame history
and variance 0.00415, retaining known unit illumination within 0.2%.

The half-resolution hole fixture fails its four hole cases against stable
1.27.0 and passes all 17 checks with this change. The actual camera test records
360 active frames across tactical, shoulder and eye modes with no PT dropout.
The rain-transition integration test records zero unnecessary history resets.

A GPU Lab heavy job uses old/new/new/old order on the same RTX 3090, with 80
warm-up and 240 measured frames per run. Median whole-PT GPU times are
2.419 / 2.829 / 2.828 / 2.651 ms: approximately 0.293 ms added, comparing the
means of run medians. Wall-frame medians are 4.333 / 4.876 / 4.945 / 4.513 ms.
This is a controlled 1080p scene cost, not a general FPS forecast. The timing
build precedes only the cloud sampler seam/lifetime and fog classification fixes;
those paths were disabled in the benchmark. Runtime hashes distinguish builds.

The final package checks cover cloud transport and lifetime, relief noise,
spatial edges and progressive bypass, light history, receiver holes and teardown
on native Vulkan and Windows DX12 under Wine/VKD3D. This is not native Windows
OS qualification. Glossy, motion, variance and quality checks also pass.
The paired qualification totals 625 checks. After preserving the cave's
hour-zero fog palette, the final exports pass another 68 cave/cloud/weather
checks. That last correction does not change reconstruction or outdoor paths.
Translation validation reports 3,288 entries with zero errors, and the shader
manifest check verifies all 18 binaries.

Compact results and final runtime hashes are recorded in
`../validation/path-tracing-weather-2026-10-24.json`. Complete logs, EXR buffers,
captures and superseded runs remain under
`/home/llm2x/Documents/EI/local/scratchpad/pt-quality-20261024/`.
The early receiver fixture used the wrong viewport size and later had a GDScript
type inference error; corrected negative controls and candidate runs replace
those results. An integration run exposed a cloud descriptor double-free;
the final descriptor test and cloud-mode transitions verify its correction.

## External denoiser assessment

[NVIDIA NRD](https://github.com/NVIDIA-RTX/NRD) is the best next integration
candidate for gameplay: its API-independent temporal denoisers target low-sample
lighting and use normal, roughness, depth and motion guides. Integration still
needs correctly packed diffuse/specular signals, hit distance and motion buffers,
plus an RD resource/dispatch bridge. The current corrections improve the guide
and history assumptions that such an integration would also depend on.

[Open Image Denoise](https://www.openimagedenoise.org/) supports ray-traced
images with optional albedo/normal guides and CPU/GPU execution. It is useful for
still-image reference work; it is not selected here as a temporal gameplay
replacement. Neither library is bundled or enabled by this change.

Sparse specular paths, newly revealed surfaces, bounded scene transport and
approximate dynamic terrain remain limits. A wider denoiser integration and
material calibration are still needed for larger visual improvements.
