# Water and glass transmission validation — 2026-10-26

The optional refraction pass runs on Vulkan and Direct3D 12. GPU readback
matches analytic Snell endpoints, Beer absorption and two-interface glass
transmission. Campaign water and explicitly authored glass render through
1440p and 4K, alongside directional NRD, RTXDI and the real DLSS RR callback.
The setting defaults to Off.

## Executed checks

| Case | API | Checks |
| --- | --- | ---: |
| `path_trace_transmission` | Vulkan + DX12 | 33 each |
| `path_trace_transmission_options` | Vulkan + DX12 | 56 each |
| `path_trace_transmission_live` | Vulkan / DX12 | 21 / 25 |
| `path_trace_transmission_fallback` | Mobile Vulkan + OpenGL | 9 each |
| `path_trace_water` | Vulkan + DX12 | 22 each |
| `path_trace_rtxdi` | Vulkan | 27 |
| `path_trace_nrd_directional` | Vulkan | 21 |
| `scene_raytrace_materials` | Vulkan | 470 |
| `water_raytrace_materials` | Vulkan | 120 |
| `path_trace_lifecycle` | Vulkan | 169 |

All **1,093 assertions pass**. The cases are registered in
`tools/regressions.json`; [results, source hashes and runtime identities](transmission-results.json)
identify the exact tested feature delta and each exported pack. These are
correctness runs, not performance benchmarks. The five component integrations
were developed on the local main baseline without publishing a release.

The optical fixture checks actual ray endpoints rather than shader text. Water
with absorption `(0.4, 0.1, 0.02)` and a two-unit-deep bed produces RGB around
`(0.219, 0.444, 0.537)`, within 0.007 vector distance of the independent Beer
calculation including radiance's relative-IOR-squared factor. It exercises
total internal reflection, exiting from inside water, opaque occlusion,
visibility, moving beds, nested-media absorption, thin panes, camera resets,
odd-size resize, Off/On and teardown. Opaque lighting and primary guides remain
identical when the optional pass is switched off.

Campaign tests verify actual finite water meshes, raster receiver matches,
explicit glass collected through the normal scene path, `SetWaterLevel`
rebuilds, and release of the previous pass on Off. Final DX12 RR output records
26 native evaluations, preset F and zero SDK errors. Both the raw optical buffer
and the displayed image are checked. Its sampled glass colour is
`(0.1176, 0.3451, 0.4588)` and the water-region mean is
`(0.2378, 0.2940, 0.3067)`.

## Failures investigated

Visual review found that the first RR campaign run's passing readback assertions
missed black displayed glass and red water. Two new displayed-image assertions
reproduce the failure: the glass pixel was `(0,0,0)` and water-region mean was
`(0.4354,0.2964,0.2046)`. The strengthened test fails both assertions against
the preceding pack; that run is retained as a negative control.

The receiver first needed the same API-to-ray clip conversion as the main PT
shader. A projection-only rebuild still failed both assertions. Inspection then
found repeated `Texture2DRD` assignments inside PRE_OPAQUE. Even assigning the
same RD RID replaces the RenderingServer texture and invalidates prepared
material bindings. Publishing only when the backing image changes resolves the
visible failure. The final unchanged regression passes both assertions, and
the [RR screenshot](transmission-refraction-rr.png) was inspected directly.

Earlier development runs exposed a null dynamic uniform helper, missing typed
metadata defaults, unshaded glass using the wrong output channel, and two test
assumptions about Still history and resource identity. The helper now creates
typed uniforms locally; ordinary materials use an empty typed metadata default;
unshaded glass writes albedo; and the fixtures explicitly select Responsive
history and test stable public resource identity with replaced private storage.
The campaign test checks displayed glass brightness to protect that correction.
No earlier regression was weakened.

One batch wrapper rejected the material suite's `checks=470 failures=0` summary
format despite a clean passing run. Its parser now recognizes that exact format;
the entire 470-check matrix was rerun successfully.

## Evidence and limits

Retained images include [Vulkan 4K](transmission-vulkan-4k.png),
[DX12 4K](transmission-dx12-4k.png),
[ordinary water](transmission-refraction-off.png),
[refracted water](transmission-refraction-water.png), and 4K option help in
[English](transmission-help-en-3840x2160.png),
[Russian](transmission-help-ru-3840x2160.png), and
[German](transmission-help-de-3840x2160.png), with matching 1440p captures.
All three languages were checked at actual 720p, 1440p and 4K window extents.
Full campaign stage data is retained for [Vulkan](transmission-vulkan-live.json)
and [DX12](transmission-dx12-live.json).

All graphical work used GPU Lab's automatic GPU assignment, isolated profiles,
muted audio, a free cursor and visible FPS. DX12 ran through the registered
GE-Proton11-11 runtime with one exclusively locked writable prefix. No adapter
capability overrides or withdrawn RTX 30 package were used. Native Windows OS,
non-NVIDIA GPUs, physical Android devices, HDR, XR and frame generation remain
unqualified. The Linux wrapper excludes only the known virtual-display EDID
`monitors` error and its exact refresh-rate stack; other engine/script errors
fail the run.

The original game has no equivalent PT optical mode. An original Wine image
cannot provide optical ground truth for this feature; the independent analytic
references and existing material/off-path regressions are the relevant controls.
The [integration guide](../../integrations/path-tracing-transmission.md) documents
the smooth-interface model, bounded medium stack, memory cost, glass authoring,
transparent reconstruction approximation and omitted caustics/rough glass.
