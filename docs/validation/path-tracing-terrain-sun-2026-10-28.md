# Terrain sunlight and sparse-light validation — 2026-10-28

Shared terrain sunlight samples remove the dark interior cliff bands in the
Gipath ruins reproduction. Object contacts and disconnected terrain shadows
retain exact receiver rays. Managed Quality also avoids RTXDI reservoirs when
the existing estimator already sums all local lights. The implementation is
documented in [terrain sunlight reconstruction](../integrations/path-tracing-terrain-sun.md)
and [RTXDI sampling](../integrations/path-tracing-rtxdi.md).

The original report used DLSS Quality, four-bounce PT, 3840×2160 output and
2560×1440 input. It was produced by 1.32.0; the later screenshot was identified as
1.33.0. Screenshot settings cannot be inferred solely from that older report.
The cliff failure was independently reproduced on the available RTX hardware.

## Failure controls and regressions

| Regression | Before | Corrected |
| --- | --- | --- |
| Terrain terminator and contacts | Public 1.33.0: 93 checks, 13 failures | 93 checks, no failures |
| Captured cliff shared edge | Earlier nearest-exit correction: 31 checks, 3 failures | 31 checks, no failures |
| Finite sun | Central-direction cache: 37 checks, 8 failures | 37 checks, no failures |
| Sparse-light RTXDI selection | Baseline: 37 checks, 12 failures | 37 checks, no failures |
| CPU preparation and worker lifetime | Pre-async helper fails async support and readiness gating | 56 checks, no failures |

The raw captured-edge visibility jump falls from 1.0 to a mean 0.0257. Lit and
shadowed anchors, thin objects, independent terrain walls, posed geometry,
transforms, casting masks and finite sunlight remain covered. Full-frame RR and
NRD captures confirm that the correction removes the visible bands, beyond the
synthetic tests alone. Authored terrain geometry and the earlier foliage fixes
are retained.

The bounded caller-thread prototype delayed scene replacement and failed all
four travel routes. A private CPU thread now prepares immutable terrain values
alongside ordinary resource construction; it owns no scene nodes or GPU device.
Cancellation joins after a short work slice. Tests cover caller mutation, exact
serialized output, cancellation during work, restart, replacement, disposal,
independent owners, invalid poses and reclamation of all ten worker instances.
The render-thread readiness hook avoids spinning while that worker runs.

| First replacement frame, maximum 60 | Baseline | Corrected |
| --- | ---: | ---: |
| Vulkan daytime | 53 | 53 |
| Vulkan night | 49 | 49 |
| D3D12 4K RR daytime | 53 | 53 |
| D3D12 4K RR night | 49 | 54 |

Every route has complete near-field coverage by arrival, preserves PT and RR
history where applicable, and passes the ground-detail/night-color and early-stop
checks. No travel assertion or frame budget was relaxed.

The combined acceptance record contains **38 suites, 1,324 checks and zero
failures** across Vulkan, CPU checks and Windows D3D12 through standard Proton.
Related coverage includes terrain/materials, grazing normals, contacts, RTXDI,
SHaRC, refraction, water, raw RR, sparse updates, staging, retirement and history
handoff. All affected lifetime/staging/CPU/travel tests were rerun after the
threading change; the material suites use identical final shader binaries.
All 97 DXIL/SPIR-V programs reproduce with the recorded compiler and SDKs.
The regression-runner unit suite passes 13 tests.

## Performance

An exclusive GPU Lab ABBA run compared the full correction against the earlier
local integration source on one **RTX 3090**, with standard Proton/VKD3D. Each
phase used 90 warmup frames and 180 measured frames, fixed camera, weather, wind
and time, 4K output, DLSS Quality, RR and refraction. Frame generation was off;
bounce counts were unchanged. Values below average the two per-arm medians.

| Preset | Before frame time | Corrected frame time | Change |
| --- | ---: | ---: | ---: |
| Quality, four bounces | 94.293 ms | 79.427 ms | 15.8% lower |
| Balanced, two bounces | 52.818 ms | 54.885 ms | 3.9% higher |

Quality benefits from removing unnecessary reservoir work. Balanced already
used the summed-light estimator and pays the additional cost of corrected terrain
sunlight. A separate isolation run on a 3090 Ti measured the sparse-light change
alone at 21.4% lower Quality frame time; that is not the combined-fix result.
GPU 0 also drives the desktop, so this is a paired local measurement rather than
a hardware-wide performance guarantee. No RTX 5090 was available for validation.

The original game has no hardware path tracer, DLSS or equivalent sun-visibility
reconstruction. A fresh original-game Wine comparison is therefore inapplicable.
Original assets and conventional-renderer controls were retained; parity with
the original renderer is not claimed.

Exact commands, source and PCK hashes, before-failure logs, raw outputs, final
images and benchmark arms are retained under the workspace's
`local/validation/pt-terrain-shadow-fix-20261028/`. Start with
`verification-summary.json`, `final-benchmark-summary.json` and
`verified-source-hashes.json`. Cleanup receipts and the workspace map live in
`local/maintenance/`. No release or remote update is part of this change.
