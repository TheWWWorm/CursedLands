# RTXDI validation — 2026-10-26

RTXDI 3.1.0 runs its actual SDK reservoir resampling on Vulkan and Direct3D 12.
GPU readback verifies valid packed reservoirs, finite weights, bounded sample
counts and reuse across all 14,400 pixels of the controlled scene. This is
executed rendering coverage, not a shader-name or settings-only check.

## Measured lighting

The local-light reference independently sums renders containing at most seven
lights, for which the existing tracer samples every light. The emissive
reference uses the existing MIS path tracer. Both are compared with raw RTXDI
lighting before reconstruction.

| Measurement | Vulkan | DX12 |
| --- | ---: | ---: |
| Maximum channel error against summed 64-light reference | 2.02% | 1.49% |
| Emissive-surface energy error | 0.041% | 0.083% |
| Raw luminance MSE, 16 fresh RIS candidates | 0.06392 | 0.06390 |
| Raw luminance MSE with spatiotemporal reuse | 0.01396 | 0.01443 |
| Reused/fresh MSE ratio | 0.218 | 0.226 |

The 77–78% error reduction applies to this controlled unoccluded local-light
scene. It is not a performance measurement or a universal image-quality claim.
Fresh visibility rejects an inserted blocker immediately even with retained
reservoir history. Removal, changing light membership, emitter extinction,
camera/history reset, odd-size resize, Still accumulation and Off are exercised.

## Regression coverage

| Case | API | Checks |
| --- | --- | ---: |
| `path_trace_rtxdi` | Vulkan + DX12 | 27 each |
| `path_trace_rtxdi_options` | Vulkan + DX12 | 59 each |
| `path_trace_many_lights` | Vulkan | 20 |
| `path_trace_device` | Vulkan | 17 |
| `path_trace_nrd_directional` | Vulkan | 21 |
| `path_trace_sharc` | Vulkan | 25 |
| `path_trace_lifecycle` | Vulkan | 169 |
| `path_trace_water` | DX12 | 22 |
| `fsr_attribution` | Vulkan / DX12 | 113 / 120 |
| `path_trace_rtxdi_live` | DX12 | 38 |

All **717 assertions pass** with clean engine/script error checks. The final
campaign run records 377 real RR evaluations and nine resets without SDK errors.
RTXDI remains active through camera motion, streaming, DLAA, 4K Performance and
the return to directional NRD. The combined mode uses matching noisy PT inputs;
Still accumulation suspends the optional sampling and reconstruction modes.
[Results and runtime/source hashes](rtxdi-results.json) include every counted
run; [native campaign stages](rtxdi-rr-live.json) retain SDK and device telemetry.

Retained visual evidence includes [4K campaign output](rtxdi-rr-4k-performance.png),
[Quality output](rtxdi-rr-quality.png), [directional NRD](rtxdi-rr-off-directional.png)
and 4K help in [English](rtxdi-help-en-3840x2160.png),
[Russian](rtxdi-help-ru-3840x2160.png) and [German](rtxdi-help-de-3840x2160.png),
with matching 1440p captures. Fonts, wrapping and tooltip bounds are readable.

The new cases are registered in `tools/regressions.json`. Settings checks include
actual window and viewport dimensions at 1280×720, 2560×1440 and 3840×2160,
English/Russian/German labels and complete help, tooltip bounds and availability
under Off, Still and Responsive modes. Packaging credits include the new SDK.

GPU Lab assigned both GPUs automatically. Tests used isolated profiles, muted
audio, a free cursor, visible FPS and a 30 FPS cap. DX12 ran through the registered
GE-Proton11-11 runtime in one exclusively locked writable prefix. Adapter
identity and capabilities were not spoofed. Native Windows OS, non-NVIDIA
hardware, HDR, XR and frame generation are not qualified here.

## Investigated failures

The initial 16-pixel neighborhood reduced raw error by only 9–11% and failed the
noise regression's required 35% reduction. Readback confirmed correct camera
matrices, previous surface data and reservoir reuse; most interior reservoirs
contained 656 candidates. The broad search combined noticeably different local
light distributions and introduced normalization noise. Reducing its radius to
eight pixels produced the measurements above. The regression threshold remains
unchanged. Failed results and diagnostic reservoirs are retained locally.

The first test script needed explicit integer typing for its reservoir-array
index; that compile failure did not exercise the renderer. A later Windows UI
capture overlapped the application's deferred initial window placement and
stalled. The test now waits for placement to finish, selects windowed mode and
checks the real viewport extent before each layout capture. All nine layouts
pass on the same native executable with ordinary DLSS disabled.

An attribution test also caught missing SDK declarations in the local test-pack
builder. It now declares the libraries actually packaged, using the production
packaging convention. The complete credit tests pass on both APIs; no assertion
was disabled or relaxed.

The original game's Wine renderer cannot validate reservoir sampling because
it has no path tracer or RTXDI integration. Independent lighting references and
the related renderer regressions are the applicable controls. See the
[integration guide](../../integrations/path-tracing-rtxdi.md) for the algorithm,
memory cost, source pins, build commands and remaining approximation limits.
