# Path tracing: responsive reconstruction, camera continuity and snow

This change keeps the current PT scene active during geometry replacement,
reduces noise in the fast response mode, and aligns traced loose-ground heights
with the rendered snow and sand. It is based on stable 1.26.0 (`96aaeb78`). The
qualified engine and ray-tracing shader binaries are unchanged. No new settings,
translations, public release or claim of Dark Souls 2 quality parity is involved.

## Reference and implementation choices

The [Dark Souls 2 Lighting Engine author's page](https://www.nexusmods.com/darksouls2/mods/1146?tab=description)
credits NVIDIA NRD and its sample as foundational to its native PT work.
[NRD's integration documentation](https://github.com/NVIDIA-RTX/NRD/blob/master/README.md)
describes reconstruction of low-sample lighting using temporal history, surface
guides, motion, separate diffuse/specular signals and material demodulation.
These support prioritizing reliable history and reconstruction before increasing
bounce counts. This implementation follows those principles with the existing
custom filter; it does **not** integrate NRD or DLSS Ray Reconstruction.

Three concrete problems were found:

* Geometry membership/material changes called `_release()` on the live device.
  Camera mode changes and moving actors could therefore remove PT while another
  snapshot was gathered. They now use the existing private candidate mechanism:
  publish its first complete frame, then retire the old device. Removed meshes
  remain masked by ordinary instance updates. Real device failures retain the
  existing fallback/retry path.
* Tiny daylight changes used the same short history limit as torch flutter.
  At 30 Hz that allowed roughly 1.8 frames instead of the responsive mode's eight.
  Gentle daylight alone now retains eight frames; changing local lights retain
  the short time-bounded response. Abrupt illumination changes still reset.
* Loose snow is raised in the raster vertex shader, by up to 0.2 metres, but ray
  geometry used the original terrain height. Nearby snow could consequently
  reject almost every PT lookup. `raytrace_ground.gd` applies the same base
  snow/sand profile to copied acceleration geometry, including rotated tiles,
  shifted MPR vertices, triangle interpolation and hard-ground/water boundaries.
  Authored terrain and collision arrays are unchanged.

The added spatial pass filters diffuse and rough specular lighting separately
with two 5×5 passes at strides one and two. Depth, normal, plane distance,
roughness/material and local variance limit mixing across surfaces. Very narrow
glossy lobes bypass it. Temporal history is copied **before** spatial filtering,
so its broader blur cannot accumulate recursively. Progressive still-scene
convergence bypasses the pass exactly. Resize, partial workgroups, allocation
failure and teardown are covered by device tests.

## Measurements

Primary setting: 3840×2160 output, Low / 50% PT (1920×1080 trace lattice), two
bounces, fast response, FSR off, noon Ingos (`zone11`), soft ground enabled.
Eight held-camera frames advance daylight at a controlled 30 Hz. Simulation is
frozen for reproducible image comparisons; separate live campaign tests exercise
ordinary simulation. All profiles keep the cursor free, FPS enabled and audio
muted. Captured HUD counters during frozen fixtures are not performance data.

| Measurement | Stable 1.26.0 | Candidate |
| --- | ---: | ---: |
| Inactive PT frames on Ingos camera/topology route | 218 / 400 | 0 / 448 |
| Nearby terrain pixels accepting traced lighting | 4.90% | 99.43% |
| Temporal diffuse luminance variance, nearby overlapping guides | 0.00192961 | 0.000179118 |
| Mean diffuse luminance over that region | 0.839974 | 0.839701 |
| Temporal variance on central snow slope | 0.00126074 | 0.0000358820 |

The nearby region contains 1,296,189 pixels with valid depth below 55 metres in
both captures and normal dot product above 0.9. Variance uses linear diffuse
irradiance, luminance weights (0.2126, 0.7152, 0.0722), and sample variance across
eight frames before averaging pixels. The slope subset contains 379,182 pixels.
The reductions are **90.7%** and **97.2%**, respectively. Stochastic frame seeds
are driver scheduled, not identical. This is a measured held-view improvement,
not a universal moving-image quality score or an unbiased path-tracer claim.

Terrain coverage is a separate raster diagnostic: green accepts the existing
PT receiver test, red rejects it, and surfaces beyond 55 metres are excluded.
Tone mapping requires relative red/green thresholds, not exact RGB values.
`measurements.json` contains corrected full-image counts. Early route JSON files
used overly strict colour thresholds; their original counters are not used here.
An earlier diagnostic mistakenly wrote emission under an unshaded material and
displayed black terrain; it was corrected to albedo and excluded from evidence.

An isolated GPU Lab heavy job on an RTX 3090 alternated spatial filtering
off/on/on/off, with 40 warm-up and 120 measured frames per block. Whole PT GPU
medians were 3.913 / 5.349 / 5.367 / 3.944 ms: about **1.43 ms added GPU work**.
Wall-frame medians were 15.16 / 14.44 / 14.90 / 15.22 ms; this CPU-limited run does
not establish an FPS gain. Two extra RGBA16F images cost 31.64 MiB at the tested
trace resolution, excluding descriptors and driver overhead.

## Movement and regression evidence

Windows executables ran under **Wine/VKD3D on Linux**, using their production
Safe render-thread mode. Native Linux Vulkan also passed with the production
separate render thread. This is not native Windows OS qualification.

| Test | Result |
| --- | --- |
| 4K Ingos DX12 strafe/pan, actor mesh replacement, travel/recenter and orthographic cut | 448 recorded frames, zero PT dropouts |
| 4K Ingos DX12 actual tactical → third-person → first-person cameras, three rounds with turns | 360 recorded frames, zero PT dropouts; free cursor retained |
| 1080p Ingos Vulkan, separate render thread | 390 recorded frames, zero PT dropouts; 99.52% nearby terrain coverage |
| 1080p Gipat Vulkan (`zone3obr`) | 363 recorded frames, zero dropouts; 98.50% terrain coverage |
| 1080p Suslanger DX12 (`zone15`) | 346 recorded frames, zero dropouts; 99.71% terrain coverage |
| Live DX12 campaign (`gz1g`, `bz8k`), turns/recenters, actors, generated save/load | 31 checks; 4,183 active frames and 4,164 live update frames; PT restored after loading |
| Spatial reconstruction, Vulkan / DX12 | 21 checks each: analytical means, noise, depth edge, glossy/progressive bypass, untouched history, resize and teardown |
| Lifecycle, separate-thread Vulkan / Safe DX12 | 168 / 167 checks, including spatial image/descriptor failure and bounded resource counts |
| DX12 light history / glossy / motion | 49 / 31 / 55 checks |
| CPU topology / Vulkan controller / actual cave | 82 / 47 / 12 checks |
| Qualification runner negative controls | 23 Python tests |

Normal Ingos, Gipat and Suslanger captures were inspected, along with the
first-person view. The tests exercise receiver continuity and real scene updates;
an active flag alone does not prove every pixel is artifact-free.

Raw evidence is retained in the local task workspace
`/home/llm2x/Documents/EI/local/scratchpad/pt-motion-20261024/checks/`.
Relevant run names are `before2-ingos-dx12`, `baseline3-ingos-coverage`,
`candidate2-ingos-dx12`, `candidate2-gipath-vulkan`, `candidate2-suslanger-dx12`,
`motion-final-ingos-vulkan`, `actual-camera-modes-dx12`, `live-stability-dx12`,
`spatial-performance-dx12`, `lifecycle-final-vulkan` and `lifecycle-final-dx12`.
The sibling `measurements.json` and `analyse.py` preserve the numerical analysis.
These are local evidence paths, not published/downloadable artifacts.

Early scratch runner reports recorded `HEAD:game` while the source was dirty;
that field identifies the **base** game tree, not the candidate. Keep those
historical files intact. The final qualification manifest freezes executable,
pack, runtime library and fixture hashes; candidate build metadata identifies
the modified source tree. Do not use the old scratch field as candidate provenance.

The first combined qualification completed its five movement/reconstruction
suites but stalled before the lifecycle fixture's first pixel sample. That run
was cancelled and retained separately. Instrumented lifecycle retries passed on
both GPUs, so a deterministic renderer failure was not reproduced. The synthetic
helper now waits for explicit GPU texture readback instead of a presentation
event from its empty viewport. Ordinary qualification launches are capped at
30 FPS; performance suites retain their intended uncapped behavior.

The final `qualification-final-windows` run passed **307 checks** across
`motion_quality` and `motion`, with unchanged executable, pack and runtime
library hashes. Its 4K route recorded 408 active frames without a dropout; the
actual camera-mode test recorded another 360. The revised GPU-readback helper
also passed native Vulkan motion (55) and separate-thread lifecycle (168).
The shared water collector passed all 15 live reflection checks. Compact
[measurements and artifact hashes](../validation/path-tracing-motion-2026-10-24.json)
are retained in the repository; complete manifests, logs and captures remain in
the local evidence directories.

## Remaining limits and repeatable checks

Dynamic footprint depressions are still approximated in ray geometry. Four real
snow footfalls in an open close view changed receiver coverage from 100% to
99.02%; PT remained active. Their small local fallback patches need a bounded
dynamic terrain update path, not looser receiver rejection across the whole map.
Suslanger's steep cliff UV stretching and angular authored silhouettes also
remain; this renderer correction does not replace those assets.

NRD integration, directional diffuse reconstruction, better specular motion and
authored material/lighting calibration remain substantial future work. The
[material and lighting research](path-tracing-materials-and-lighting-research-2026-10-22.md)
describes that asset scope. Matching Dark Souls 2's overall presentation cannot
be established by this noise measurement alone.

Use the documented [qualification runner](../path-tracing-qualification.md)
against a frozen export with `--suite motion_quality`; run
`--suite spatial_performance` separately in a heavy GPU Lab job. Individual
`camera_routes` fixtures accept `--pt-map=zone3obr` or `--pt-map=zone15`,
`--pt-hd`, `--pt-live-clock` and diagnostic `--pt-no-soft`. The same-build
`--ei-pt-no-spatial` flag isolates reconstruction cost. These are test arguments,
not player-facing options. HLSL binary verification and EN/RU/DE translation
coverage remain clean; no player-visible strings were added.
