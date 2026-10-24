# PT lighting stability — 2026-10-24

This change starts at fetched `origin/main` commit `bab580bd43e7d146c341904c3413bcfb471e5d22`, including the native Windows DLSS HUD-mask fix. The Windows test package retains the hotfixed executable (`68737b9d2edf779585de2fb50e88b19665da1869a2801fc843054077f013d693`). It is a local development build, not a new release.

The supplied recordings show 3840×2160 output, DLSS Performance, frame generation, PT Low (50%), two bounces and responsive accumulation. That combination gives PT a 960×540 lighting grid. The attached recordings are visual evidence, not instructions.

## Changes

- Smooth shading normals crossing the camera horizon used to snap to the triangle normal. A continuous correction into the visible hemisphere replaces that discontinuity in both ray hits and raster receivers. Well-facing normals and the geometric normal used for ray origins are preserved.
- Wind deforms the visible trees, while the acceleration structure contains their undeformed meshes. Foliage now looks up lighting at its interpolated rest position. This retains wind animation and avoids rejecting the same leaf solely because it has swayed away from its traced position.
- The receiver's fallback ring uses Gaussian weights. Valid diagonal samples can have weights below the previous acceptance threshold. The final PT threshold now admits those samples after the existing depth, plane, distance and normal checks; the tests still require unrelated foreground layers to be rejected.
- Diffuse denoising now receives the first secondary hit distance, as the specular signal already did. Summing later segments could replace a nearby hit with an effectively infinite distance when a later bounce escaped to the sky. This follows the [NRD integration contract](https://github.com/NVIDIA-RTX/NRD/blob/e06852bd545973cb224eb28820b891205cfc1624/README.md). Both DXIL and SPIR-V binaries were rebuilt from the same source.

No settings, ray counts, bounce counts, quality defaults or player-facing strings were added.

## Reproductions

These focused tests fail against the original 1.28.0 game pack and pass with the changes:

| Test | Original | Fixed |
| --- | --- | --- |
| Grazing hillside, 41 small camera steps | Largest normal change 1.172720; direct-light jump 0.687500 | 0.001092 and 0.000977 |
| Wind-deformed foliage receiver | Worst phase accepts 13.93% of the leaf sample region | Every visible phase accepts 100%; unrelated foreground accepts 0% |
| Sparse receiver guide | 93.49% correct on the plane, 95.89% with a depth boundary | 100% in both cases |
| First secondary hit distance | Continuing to 2/4 bounces changes it by up to 7508.43 | No change on Vulkan; maximum 0.00195 on DX12 within the 0.01 tolerance |

The four focused suites contain 77 checks per backend. The Vulkan regressions additionally cover leaf transmission and energy (13), thin contact shadows and transformed ray origins (59), NRD dispatch/lifetime/fallback (19), and NRD rigid motion/deformation history (42).

The campaign fixture enables wind, ground contact, terrain detail and foliage lighting on the original Gipat map. It renders 4K output with the 960×540 PT grid, rotates the camera for 120 frames, and captures the actual scene and guide buffers. The Windows variant requires genuine DLSS SDK evaluations in Performance mode. See the accompanying JSON for the measured results and binary hashes.

## Scope and reproduction

All graphical checks use isolated GPU Lab jobs with automatic GPU assignment, free cursor, FPS visible and audio muted. Windows execution here uses Wine/Proton with VKD3D and the standard NVIDIA runtime. These results do not qualify native Windows presentation or DLSS frame generation. No modified frame-generation kernels are used or bundled.

Wind lighting remains an approximation based on undeformed tree geometry: this change does not animate the acceleration structure or its cast shadows. It fixes four reproduced causes of instability; it does not establish that every artifact in the recordings is resolved. Low-resolution foliage can still have visibility and temporal reconstruction limits.

Run each fixture with the packaged game, an isolated settings directory, the original game data and `--tool=<absolute fixture path> --audit-out=<absolute output directory>`. Dependencies in the fixture directory must resolve `res://tools/tests/` to that directory. Use `--pt-dlss` for the Windows campaign fixture and seed `rtx_upscaling=4`, `rtx_frame_generation=0` before startup. The local harness records the runtime hashes independently of inherited package metadata; the development package metadata is regenerated before delivery.

Fixtures: `path_trace_grazing_normals.gd`, `path_trace_hit_distance.gd`, `path_trace_wind_receivers.gd`, `path_trace_receivers.gd`, and `path_trace_wind_live.gd`, under `tools/tests/`.
