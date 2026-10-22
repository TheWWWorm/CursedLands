# Path-tracing emissive sampling validation — 2026-10-22

Unreleased follow-up to `4f701ae0`. The previous package and updated package
ran on the same RTX 3090. Windows DX12 runs used Wine/VKD3D; Vulkan runs used
the qualified native Linux engine with validation layers. These results do
not qualify native Windows or other GPU vendors.

The integrator now directly samples emissive triangles, combining these
samples with BSDF continuations through multiple importance sampling. The
bounce limit, path samples, quality resolutions and twelve image targets are
unchanged. Extra visibility rays are required when emitters are present. An
automatic smaller ray-generation variant handles scenes without emitters.
See the [integration document](../../integrations/path-tracing-experiment.md)
for the algorithm, resource budgets, material support and remaining limits.

## Quality and energy

The fixture renders 147,456 pixels at 512×288, viewing a small floor patch lit
by a 0.3×0.3 m emissive surface. There is no sun, point light or sky lighting.
These measurements use the raw integrator outputs before reconstruction;
spatial and temporal filtering cannot account for the noise reduction.
Both packages use the same geometry, view and path sample count. Variance
across the patch includes its small spatial variation as well as sampling noise.

| Receiver | Samples/pixel | Previous red variance | New red variance | Reduction |
| --- | ---: | ---: | ---: | ---: |
| Diffuse | 1 | 70.25021 | 0.000559 | 99.9992% |
| Glossy metal, roughness 0.25 | 4 | 150.99628 | 9.64614 | 93.6% |
| Same glossy metal, diagnostic stress case | 16 | 42.17531 | 6.44940 | 84.7% |

The diffuse mean is 0.67803, within 0.2% of independent midpoint area
quadrature (0.67932). The four-sample glossy mean is 6.29611 versus 6.28335
previously, a 0.2% difference. Small-light diffuse pixels below 0.0001 fall
from 99.34% to zero; four-sample glossy pixels below that threshold fall from
77.40% to zero. The extreme diffuse improvement describes this intentionally
difficult small-source fixture, not a general campaign-wide percentage.

The selected light's probability participates in both MIS weights. Tests
check duplicate placements of one mesh, non-uniform scale, posed geometry,
extinguishing and relighting, partial alpha cutouts, texture-modulated shader
emission, and occluders that do not cast conventional shadows. A deliberately
omitted emitter retains its BSDF-hit energy. A separate 4,102-triangle proposal
test verifies the 4,096-light cap and matching floating-point CDF/PMFs. The
closed diffuse room still gains energy at two and four bounces, and metals
retain their separate glossy output without a diffuse lobe.

Energy, variance and timing data:
[before](emitters-qualified-baseline-sampling/path-emitters.json),
[DX12 after](emitters-qualified-dx12-sampling/path-emitters.json),
[Vulkan after](emitters-qualified-vulkan-sampling/path-emitters.json).
Raw captures:
[diffuse before](emitters-qualified-baseline-sampling/small-emitter.png),
[diffuse after](emitters-qualified-dx12-sampling/small-emitter.png),
[glossy before](emitters-qualified-baseline-sampling/glossy-emitter-4spp.png),
[glossy after](emitters-qualified-dx12-sampling/glossy-emitter-4spp.png),
[cutout emitter](emitters-qualified-dx12-sampling/cutout-emitter.png).
These PNG previews clamp HDR values to 0–1; the energy and variance measurements
above use the original floating-point buffers, including values above one.

## GPU cost

The controlled emitter fixture also brackets the real ray pass, reconstruction
and copies with GPU timestamps. Each row has 100 measured frames after warm-up.
The sixteen-sample diagnostic exceeds the shipping High setting's four samples.

| Receiver | Samples/pixel | Previous GPU median, ms | New GPU median, ms |
| --- | ---: | ---: | ---: |
| Diffuse small-light fixture | 1 | 0.257 | 0.345 |
| Glossy small-light fixture | 4 | 0.345 | 0.703 |
| Glossy diagnostic stress case | 16 | 0.570 | 4.016 |

Emissive sampling has a measurable cost, especially for repeated glossy paths.
This is a quality improvement, not a claim that adding light samples raises
FPS. The proposal is global, without per-receiver visibility or distance
importance; many occluded emitters can waste work. The two timings alone do
not predict performance in a complex emissive campaign scene.

The frozen river benchmark contains **zero eligible emissive triangles**, so
it exercises the smaller automatic variant. It uses a 1280×720 window, hidden
units, water reflections and frame generation off, and responsive history.
Two rounds run in opposite orders with 90 measured frames per case. Ranges
contain the two median GPU times for rays, reconstruction and copies; scene
builds, acceleration-structure updates and the main raster viewport are excluded.

| Mode | Previous RT pass, ms | New RT pass, ms |
| --- | ---: | ---: |
| 2 bounces, Low | 0.455–0.462 | 0.458–0.460 |
| 2 bounces, Medium | 2.273–2.277 | 2.317–2.463 |
| 2 bounces, High | 9.737–9.911 | 9.876–9.924 |
| 4 bounces, Low | 0.604–0.609 | 0.603–0.606 |
| 4 bounces, Medium | 3.048–3.391 | 3.179–3.366 |
| 4 bounces, High | 11.943–12.186 | 12.088–12.184 |

These GPU timings remain close to the previous build. Whole-frame timings
vary with CPU and scheduling load on the shared host and do not establish a
general FPS change. Other running work was left untouched. Full distributions:
[previous](emission-baseline-dx12-performance/path-performance.json),
[updated](emitters-final-dx12-performance/path-performance.json).

## Campaign integration and regression coverage

The production scene collector was tested with a temporary emissive box
attached to a real river-bank object. Revealing its twelve triangles switches
the existing device to emitter sampling and lights the actual terrain.
Movement updates its placement; hiding it clears the light and selects the
smaller pipeline. Changing the material's emission triggers a fresh snapshot
with the correct emission metadata. The test object is fixture-only; campaign
content and saved player preferences were not modified.

[Hidden](emitters-final-dx12-campaign-emitter/campaign-emitter-hidden.png),
[emitting](emitters-final-dx12-campaign-emitter/campaign-emitter-lit.png),
[restored](emitters-final-dx12-campaign-emitter/campaign-emitter-restored.png),
[results](emitters-final-dx12-campaign-emitter/path-emitter-live.json).

The updated build passed **286 assertions across 13 recorded runs**, covering:

- Native DXIL and SPIR-V emitter sampling, energy, alpha, textures, occlusion,
  deformation, visibility, duplicate placements and proposal fallback.
- Automatic pipeline switching while retaining the TLAS, SBT ranges and
  stable texture bindings; hidden/camera-only animation preserves history.
- Existing multi-bounce room, grazing GGX, temporal reconstruction, resize,
  teardown, water-RT and one-bounce scene-RT regressions.
- Outdoor and cave rendering, changing lights, character updates, camera and
  projection changes, and restoring conventional rendering.
- Production FSR frame generation with path lighting and water reflections,
  including resize, pause/resume and both measured FPS lines.

The FG run generated 90 frames over its 90-frame sampling interval and observed
180 presents. Its first capture shows **99 FPS rendered / 198 FPS presented**;
these are observations from this run, not promised gameplay rates.
[FG results](emitters-final-dx12-path_trace_fsr/rt-fsr.json),
[HUD](emitters-final-dx12-path_trace_fsr/rt-and-fg.png),
[resized HUD](emitters-final-dx12-path_trace_fsr/rt-and-fg-resized.png).
Additional captures:
[river](emitters-final-dx12-path_trace_live/river-path-4-still.png),
[cave](emitters-final-dx12-path_trace_cave/cave-path-4-still.png).

All runs used isolated profiles, a free cursor, visible FPS and muted audio.
No player-facing text or options changed. Translation validation passed all
3,042 remake entries and dynamic-key coverage. All ten path binaries and both
unchanged eight-binary water/scene families reproduce with DXC 1.9.2609.5.
The latter manifests changed only to pin the updated builder. Production
source hashes match the exported runtime. Windows was exported with the
qualified template and approved icon; the EXE is byte-identical to the
previously icon-qualified export. Package/source hashes are in
[build.json](build.json); fixture hashes and per-run counts are in
[summary.json](summary.json).

## Diagnostics and limits

The two recorded native Vulkan runs emitted no validation errors. Recorded
updated runs emitted no shader compile errors, script errors or failed
assertions. Baseline DXGI/EDID/SDR warnings remain on Wine.

The previously recorded Wine shutdown fault recurred after the application's
clean-exit message in three updated runs: emitter sampling, the campaign
emitter fixture and the closed-room device fixture. It reads
`0000000241BB6030` at `00006FFFFFC81448`. The exact diagnostics are retained
beside each run. Passing in-game assertions and a zero runner exit code do
not make this clean native-Windows qualification. The final FG run did not
show that shutdown fault.

This remains bounded path-traced lighting with raster primary visibility and
separate water rendering. Material authoring, moving glossy history,
occluded lights, thin geometry, particles, transmission and content outside
the bounded snapshot still limit the result. No release was published.
