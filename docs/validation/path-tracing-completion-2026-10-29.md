# Path-tracing optimization completion — 29 October 2026

The starting source was local `main` at `4dd0f838`, including the 21 unpublished
commits after the 1.35.0 release. The earlier measurements remain in
[the performance record](object-materials-2026-10-28.md). This pass reviews that
work, completes the interrupted regression run, and checks another emitter
optimization without changing the accepted rendering tradeoffs.

## Confirmed controller-cache regression

`RenderingServer` shader globals belong to the process, but the new
`SceneRaytrace._global_values` cache belonged to each controller. After another
controller wrote those globals or released its state, the first controller
could skip republishing its unchanged values. The actual shader then retained
the other controller's values, including disabled PT flags.

The cache now shares the lifetime and scope of the shader globals. A release
invalidates the shared cache. `path_trace_global_cache` renders a small shader
that reads both a scalar and a vector global, exchanges writes between two
controllers, retires the second, and releases/restarts the first. It fails two
of six checks on the handoff PCK and passes all six on the fixed PCK. The test
is registered in `tools/regressions.json`.

Original-game comparison is inapplicable: the original renderer has neither
the remake's path tracer nor this controller/global cache. No original Wine
run was performed. Validation uses the real remake RenderingServer on native
Windows, with the original base-game and LiA data read only.

## Emitter shortcut trial — reverted

The trial bypassed vertex attributes, UV interpolation and mip calculations
when an emitter had opaque, constant linear emission. Textured and cutout
materials retained the existing path. Both the ordinary sampler and the
separate ReSTIR direct-light pass were rebuilt for DXIL and SPIR-V.

The frozen-river benchmark ran exclusively on the RTX 4090 Laptop through
D3D12, 1280×720 output, Low, two continuation bounces, uncapped, with
`--ei-pt-tuning`. Packs ran in A–B–B–A order, with two measurement rounds per
process. Medians of the four ray-stage block medians per configuration:

| Emissive boxes | ReSTIR | Handoff | Trial | Difference |
| ---: | :---: | ---: | ---: | ---: |
| 0 | Off | 0.428 ms | 0.425 ms | −0.6% |
| 8 | Off | 0.785 ms | 0.788 ms | +0.3% |
| 32 | Off | 0.883 ms | 0.882 ms | −0.1% |
| 8 | On | 0.916 ms | 0.922 ms | +0.7% |
| 32 | On | 1.013 ms | 1.010 ms | −0.3% |

There is no repeatable gain. The trial was reverted, including every shader
binary and build manifest; the final shaders are byte-identical to the
handoff. Source patch, individual block measurements and commands are retained
with the evidence. No benchmark sample was dropped.

The additional material coverage remains: `path_trace_emitters` now checks
opaque constant emission against independent area quadrature with a dark
diffuse texture, and checks opaque textured emission separately. Its existing
cutout, placement, proposal fallback and glossy-MIS checks remain intact. The
fixture is now registered and passes 42 checks on the final shader set.

## Review and runtime qualification

- The separate DI pass's miss path clears both the surface/reservoir record
  and all output signals before returning; valid hits finish their ambient
  floor and direction moments in the DI pass.
- RR writes to the published image handles. Same-size mode changes rebuild
  the ray bindings, and presentation adoption binds the adopted images. The
  separate DI binding cache follows the ray-set handle and shader variant.
- Transmission reuse is invalidated by camera/projection/trace changes,
  scene changes and the controller's history-reset flag. Invalid dielectric
  paths retain their kind so they are retraced. The live fixture completed
  all 25 checks, including 1440p/4K resize and actual DLSS RR, on the handoff
  build; the earlier silent exit was not reproduced. Its historical cause is
  still unknown.
- The pinned native NRD planner was exercised for 180 frames in each mode,
  alternating history resets and lighting limits. Radiance mode used 34 plan
  keys and directional mode 40, both below the 64-plan limit, with zero
  duplicate pipeline/resource keys within any frame. Rebinding changes the
  application pack/resolve boundary; internal pools remain owned by NRD.
- The pinned DXC 1.9.2609 toolchain reproduced all 48 ordinary PT, 20 RTXDI
  and 13 SHaRC shader binaries. The final checked-in manifests pass their
  verification commands. No new shader code is retained.

The runtime is the published 1.35.0 Windows package, using D3D12 on an RTX
4090 Laptop GPU with NVIDIA driver 616.64. Its archive SHA-256 is
`2cf3d8ba716a82d206e4e98c1cf641906d2018fd03f7b83be2d320aa4e72c816`;
the executable is `73dbbcdb7a74805d4104d058fa7352f5c83b7e1fe784a52a9f69c5575ded79c1`.
The original release PCK used for controls is
`e1656be7a11cacd1a418fc5ee6f3fadcca026c055b971f2816dda20a382ea1de`.
Each launch uses an isolated profile, free cursor, FPS display and muted audio.

## Final regression results

The final PCK is
`1dd33ea0380c45c8e56c6f6b5ccd5a0e6e233b1f6bcc9c29ccec73f455085ef3`.
All 80 registered rendered PT cases were exercised with the Windows harness:
71 passed and nine failed. All six registered headless PT cases passed through
`tools/check_regressions.py` (288 checks). No failing assertion was waived,
weakened or counted as passing because it also failed on the published build.
The rendered harness requires a unique summary, the registered minimum check
count, exit code zero and no error/failure lines. All 86 registered PT case IDs
are accounted for in the final results.

The new global-cache test passed 6/6 and the registered emitter test passed
42/42. Live transmission passed 25/25 again on the final PCK, including actual
RR and 1440p/4K resize. The 4K river, desert and cave RR/FG traversals each passed
49/49. Controller recovery, retirement, RR guides/presentation, NRD, ReSTIR,
SHaRC, topology/pose updates, terrain lighting and resource/upload staging
passed their registered checks.

The initial `rr_unavailable` launch incorrectly included the complete RR
runtime. Its failure remains in the historical results. Repeating the contract
with only `sl.dlss_d.dll` and `nvngx_dlssd.dll` omitted from an isolated runtime
mirror passed 7/7, preserving real DLSS SR and falling back to selected NRD.
The original release runtime and all other mirrors remained intact.

Published 1.35.0 controls use the same engine, fixtures and isolated settings.
Case names below omit the `path_trace_` prefix:

| Cases | Final result | Published control |
| --- | --- | --- |
| `travel_night`, `travel_rr`, `travel_rr_night` | Late snapshot promotion/coverage and night colour shift; RR cases also report a 2560×1514 window instead of the requested output | Same failures; night promotion at frames 76/67 versus final 71/62, with colour shift approximately 0.148 in both builds |
| `water_options`, `rr_options` | All 28/50 assertions pass, but each emits 19 Windows display-query errors (`screen_count = 0`) | Same assertions and errors |
| `rtxdi_options`, `transmission_options` | Three initial 1280×720 extent failures, one per language; remaining help/localization and higher-resolution checks pass | Same three failures per fixture |
| `zone_traversal_river` | Route selection finds no admissible next leg; final run stops at leg 2 (35 checks) | Passes 50/50; a diagnostic repeat on the final build also passes all 50 original assertions |
| `rr_traversal_snow` | PT/RR remain active at 3840×2160; three FG presentation-count checks fail with one SDK present per game present | Passes 49/49; an unchanged repeat on the final build also passes 49/49 |

The handoff run also exhausted river route candidates, at leg 3. Its route
diagnostics and the final run show valid starting terrain cells, identical
terrain digests, and all 160 candidates rejected by terrain, exit or actor
constraints. Navigation code and the traversal fixture are unchanged from
1.35.0. This is retained as a failure, not converted into a shorter passing route.

The navigation diagnostic adds only a read-only dump after the original route
assertion fails. Its successful repeat never entered that branch. The runs
reach the first recorded phase at different simulation times (6.435 seconds
on the failing final run versus 8.085 on the published control), and moving
actors produce different route choices. Timing-dependent fixture selection is
an inference supported by those observations, not a confirmed game-navigation
regression. The original failed runs, successful controls and repeat remain
available together.

The snow FG failure also remains recorded as intermittent: native status
reported RR and FG active with no SDK error, but the initial presentation ratio
was 1:1; both subsequent runs satisfy the original presentation-count checks.
Its underlying cause was not isolated. The primary result remains 71/80;
two more cases pass on repeat, while seven failures reproduce on 1.35.0.

## Evidence and scope

Evidence is under `C:/web/local/validation/pt-finish-2026-10-29`, with the
workspace map and cleanup record in
`C:/web/local/maintenance/pt-finish-2026-10-29.md`. Native Windows substitutes
for the Linux GPU Lab workflow on this workstation; no Wine prefixes were
created. Vulkan runtime behavior and other GPU families were not tested here.
No push, tag, publication or release asset was requested or produced.
Superseded test packs and SDK download staging are removed after their hashes
and results are preserved. Verified toolchains/reference assets remain under
`local/runtime/`. Automatic approval review blocked bulk harness cleanup with
the stated reason "blocked by policy"; the maintenance record identifies the
retained staging and its size.
