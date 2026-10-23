# Path tracing: internal resolution and rigid motion

23 October 2026. Development checkpoint on `work/dx12-water-rt`, based on
`58ab5287d4e5217c540d58ba4b6fed55d4e6a283`. PT now follows the applied 3D render
resolution, including FSR, and reprojects rigid primary surfaces through their
previous transforms. At 2560×1440 Medium in the controlled river scene, the
internal-resolution grid reduced PT GPU time by 54–55% and total frame time by
44% on both tested backends.

## Changes

- Derive PT dimensions from the viewport's applied scale and actual truncated
  internal size, then apply Low/Medium/High quality. Rays, guides and
  reconstruction share that size. Native scale retains the original sizes;
  ordinary scene RT keeps its window-relative behavior.
- Reproject moving rigid placements, including articulated character parts,
  through previous position and inverse-transpose normal transforms. Preserve
  exact identities for all 4,096 placements to reject unrelated surfaces.
  Visibility changes and morph updates reject affected history; stopped objects
  retire their previous motion on the next rendered frame.
- Add EN/RU/DE help explaining the resolution policy. Existing option labels and
  choices retain their translations. Add native GPU motion, compositor/FSR
  resolution and matched performance fixtures.

The motion records cost 96 bytes per placement, at most 384 KiB, and are uploaded
in one bounded dirty range. Stationary scenes require no repeated motion-buffer
upload. Paired R16F identity textures add 4 bytes per tracing pixel, bringing all
PT output/guide/history images to 108 bytes per tracing pixel. The lower tracing
resolution reduces those image allocations as well as GPU work. The ray payload
and raw image formats do not grow.

## Measurement

Physical **GPU 1, NVIDIA GeForce RTX 3090 Ti**, driver **580.178.04**, on a private
GPU-backed Xorg `:97` virtual screen, 2880×1800. The desktop GPU was not used for
these tests. Native Linux uses Vulkan; the Windows executable uses DX12 through
Wine/VKD3D. This is not native-Windows qualification. GPU clocks were not locked;
per-run GPU telemetry is included. Other existing GPU processes were preserved.

Each benchmark compares two grids in the **same candidate process**, retaining
the same raster upscaler, camera, scene, samples, acceleration structures and
rigid-history implementation. The reference switch recreates the old
window-relative PT grid. The scene contains 2,171 placements, 2,035 geometries
and 149,784 unique triangles, with detailed terrain and hidden actors. PT uses
four bounces and responsive history; water reflections and frame generation are
off. Each configuration has 45 warmup frames and 120 measured frames, repeated
in reverse order. Values below are the arithmetic mean of the two block medians.

PT GPU time includes tracing, reconstruction and history copies; it excludes
acceleration-structure updates. The separately recorded main-viewport GPU time
excludes the PT pass. Total frame time is measured from consecutive frames; it
is not the sum of those GPU counters. The HUD in captures is incidental and is
not the benchmark statistic.

| Display / backend / quality | Old → new PT dimensions | PT GPU ms | Total frame ms |
| --- | --- | --- | --- |
| 1440p Vulkan, FSR 2 Quality, Medium (2 spp) | 1920×1080 → 1286×723 | 13.037 → 5.945 (−54.4%) | 14.857 → 8.256 (−44.4%) |
| 1440p DX12/Wine, FSR 3.1 Quality, Medium (2 spp) | 1920×1080 → 1280×720 | 17.111 → 7.741 (−54.8%) | 19.577 → 10.866 (−44.5%) |
| 1440p Vulkan, FSR 2 Quality, Low (1 spp) | 1280×720 → 858×482 | 2.455 → 1.165 | 5.111 → 6.476 |
| 1440p DX12/Wine, FSR 3.1 Quality, Low (1 spp) | 1280×720 → 853×480 | 3.173 → 1.603 | 7.479 → 8.436 |
| 720p Vulkan, FSR 2 Quality, Medium (2 spp) | 960×540 → 643×362 | 3.374 → 1.603 | 4.843 → 4.795 |

FSR 2 applies a 0.67 scale here; the SDK applies approximately 2/3. The compositor
fixture checks the resulting real raster dimensions. Low quality and 720p are
limited by other frame work and scheduling in this scene: reduced PT cost did
not consistently improve frame time. These are scene-specific results, not a
general gameplay FPS claim. Rigid history itself has a small cost: the separate
720p resolution-only comparison measured reconstruction around 0.189 ms versus
0.200 ms with rigid history, at the same window-relative Medium grid.

The final DX12 benchmark waits for SDK provider **3.1.5**, completed shader/context
initialization, correct viewport mode/scale and successful upscaling evaluations.
Every measured block records **120 successful SDK evaluations for 120 frames**.
The readiness wait was 940 ms with the isolated test shader cache. Earlier
`candidate-dx12-bench` and `candidate-dx12-1440` runs sampled before initialization
and are excluded from the performance claims. Their long shutdown was pending
shader work draining; both exited normally. The fixtures now fail if SDK
readiness or evaluations are missing.

Raw block values, p95 timings, stage timings, dimensions and image comparisons
are in [performance.json](performance.json) and the per-run JSON files. The
[manifest](summary.json) records the baseline, source and packaged-build hashes,
run outcomes, profile settings and local artifact directory.

## Image and motion checks

The matched Medium captures have mean absolute RGB differences of **0.00390**
(Vulkan) and **0.00370** (DX12), in display-encoded 0–1 values over the fixture's
sampled comparison region. Mean brightness changes are **+0.060%** and **+0.112%**.
The comparison excludes the FPS HUD. Visual inspection found no new obvious
receiver seams or broad lighting shift; this does not establish equivalence for
every scene or fine glossy detail.

| Backend | Old window-relative grid | Internal-resolution grid |
| --- | --- | --- |
| Vulkan | [Reference](candidate-vulkan-1440/quality-1-window-reference.png) | [Updated](candidate-vulkan-1440/quality-1-render-resolution.png) |
| DX12/Wine | [Reference](candidate-dx12-1440-ready/quality-1-window-reference.png) | [Updated](candidate-dx12-1440-ready/quality-1-render-resolution.png) |

The 55-check motion fixture passes on both backends. It covers translation,
rotation, nonuniform scale, simultaneous camera/object motion, perspective and
orthographic projection, stopped movement, visibility/morph rejection,
unrelated matching-material objects, IDs 2048/2049/4095, resize and teardown.
Actual ray dispatches accumulate history ages 1 through 8 while a surface moves.

In eight synthetic moving-surface cases, the known signal's reconstruction
error falls by approximately 87% versus camera-only history, with maximum
weighted-reference error 0.00054. These deterministic filter checks demonstrate
correct history reuse; they are not a measured 87% reduction in gameplay noise.
Glossy angular rejection still limits reuse when the reflection lobe changes.
Deformation motion and motion of objects seen in reflections remain future work.

## Regression results

All runs exited successfully. The only native Vulkan diagnostic was
`An error occurred while trying to get the screen refresh rate`, because the
private NoScanout display has no CRTC. VSync was disabled; no other runtime or
shader errors were accepted.

| Check | Result |
| --- | --- |
| Real dimensions, FSR jitter, history reset, resize and scene RT compatibility | Vulkan resolution-only 104/104; combined DX12 156/156 |
| Rigid motion and surface identity | Vulkan 55/55; DX12 55/55 |
| Glossy reconstruction | Vulkan 31/31 |
| Variance reconstruction | Vulkan 38/38 |
| Transport, emitter extinction, output lifetime | Vulkan 17/17 |
| PT with FSR upscaling/frame generation, pause/resume and resize | DX12 76/76 |
| Live campaign, two zones, saved-game roundtrip and snapshot replacement | Vulkan 31/31; 1,208 active frames, 1,197 instance-update frames, 8 pose-update frames |
| Options, dynamic choices and help layout in EN/RU/DE at 1280×720 and 800×600 | 270/270 |
| Translation coverage | 3,042 entries; 141 dynamic wiki keys; 179 dynamic arena keys; zero errors |
| Pinned DXC shader reproduction | All 18 path-tracing binaries match |
| Final import and Linux/Windows PCK export | Successful, no script/import/export errors |

The updated help was visually checked at 800×600 in
[English](options-vulkan/help-en-800x600-2.png),
[Russian](options-vulkan/help-ru-800x600-2.png) and
[German](options-vulkan/help-de-800x600-2.png). The fixture switches remake text
directly, so unrelated original-archive labels can remain English in these
captures.

All runs used isolated profiles with `confine_mouse=0`, `show_fps=1`,
`volume_sfx=0`, `volume_stream=0`, and `volume_voice=0`. The Windows readiness
reruns reused only the isolated test shader caches. Full commands and result
JSON are retained per run; the local working directory also retains logs,
additional captures and both packaged development builds.

## Reproduction

Use the qualified custom renderer executables and the source fixtures under
`tools/tests`. The standard editor can import/export the PCK but cannot replace
the qualified hardware-RT executable. Launch on GPU 1 with an isolated profile,
the original game data, and the development settings above. The run manifests
contain the exact executable, data and external-fixture arguments.

- `path_trace_motion.gd` validates motion without campaign setup.
- `path_trace_resolution.gd` checks real compositor/PT dimensions and SDK
  readiness through changes.
- `path_trace_resolution_performance.gd --pt-bench-resolution=2560x1440`
  runs the interleaved grid comparison. Include `--ei-profile-rt` to collect PT
  GPU timestamps. The fixture applies and verifies 1440p after startup.
- `--ei-pt-window-resolution` restores the old PT grid for diagnostic runs;
  `--ei-camera-only-history` disables rigid reprojection for the history
  reference. Both are developer switches, not player options.

The report's results correspond to the source hashes in `summary.json`. No new
release number is assigned to this development checkpoint.
