# Ray Reconstruction validation — 2026-10-26

Standard NVIDIA DLSS RR evaluates the campaign image with the signed
Streamline 2.14.16 runtime and preset F. The final campaign run records 375 RR
evaluations, nine history resets and zero SDK errors. Ordinary SR resumes after
RR is disabled. This is executed feature coverage, not a performance comparison
or a claim that RR improves every scene.

The isolated Windows engine retains the current twenty-two-patch engine used
by 1.29/1.30, including the corrected Streamline camera convention and R16 HUD
masks. The new ten-file patch was replayed against that exact source and all
ten files matched the built source byte for byte. Build command, base provenance,
runtime hashes and per-case results are in [rr-results.json](rr-results.json).
The tested executable SHA-256 is
`9ddd49a39e801f30dbea00e49ce335e79bd743953665af4c2349056bc279b500`.

## Executed checks

All graphical cases ran on isolated GPU Lab displays with automatic GPU
assignment. Windows tests used the standard GE-Proton11-11 runtime with one
exclusively locked writable prefix; reference seeds remained unchanged. Actual
adapter identity was preserved. Audio was muted, the cursor was free, FPS was
visible, and rendering was capped. DX12 execution under Proton is not a native
Windows OS qualification.

| Case | API | Checks | What was exercised |
| --- | --- | ---: | --- |
| `path_trace_rr_live` | DX12 | 32 | Actual RR, raw inputs, camera/jitter agreement, native input validation, motion/cuts, Quality/DLAA, 4K Performance and return, streaming, Still/Responsive, missing callback, release and SR fallback |
| `path_trace_rr_raw` | DX12 | 14 | Exact raw channel copies, no upstream denoising, authored dielectric guide, resize, NRD restoration and teardown |
| `path_trace_rr_raw` | Vulkan | 14 | Same raw-input contract on the other RT backend |
| `path_trace_rr_options` | DX12 + Vulkan | 50 each | Capabilities, saved settings, translations, nine layouts at 720p, 1440p and 4K per API |
| `path_trace_rr_unavailable` | DX12 | 7 | Both RR DLLs absent; actual SR continues and selected directional NRD remains active |
| `rtx_super_resolution` | DX12 | 58 | Existing DLAA/Quality/Balanced/Performance, forced loading draws, motion, resize, camera cut and Off |
| `path_trace_nrd_motion` | Vulkan | 42 | Existing NRD moving geometry, camera and temporal rejection |
| `path_trace_lifecycle` | Vulkan | 169 | Existing render resource ownership and reconstruction modes |
| `scene_raytrace_options` | Vulkan | 550 | Existing RT/PT settings and localized layout contracts |
| `path_trace_water` | Vulkan | 22 | Existing independent water PT, emission, directional denoising and 4K output |

All 1,008 graphical assertions pass with clean engine/script error checks.
The camera matrix regression also passes three CPU tests, including an unfixed
negative control. Shader/source audits verify 26 shared PT, 13 SHaRC and 26 NRD
binaries. All ten shipped NVIDIA production DLL hashes match the SDK manifest.

The original 2001 game has no PT buffers, DLSS renderer or material-guide
contract. An original Wine comparison cannot validate this new rendering
feature; no original-game visual parity is asserted. Existing scene behavior,
water and renderer regressions supply the relevant controls.

## Failures investigated

An early native run executed RR but produced 6,681 invalid material descriptor
errors when entering RR or resizing, plus one invalid free. It is recorded as
failed despite its passing assertions. Replacing public PT textures from the
PRE_OPAQUE callback invalidated already prepared material descriptors. The
implementation now allocates/rebinds those textures before viewport preparation;
the callback only renders into them. Pipeline disposal also precedes shader
disposal. Final logs have neither error, and the tests explicitly check guide
retirement and the return from 4K.

A later test-only projection assertion used a method that GDScript's Projection
does not provide. That run failed compilation; comparing its four Vector4
columns corrected the assertion. The final native test actually checks camera
agreement. No production behavior or passing threshold was weakened.

## Visual evidence and remaining limits

[4K campaign output](rr-4k-performance.png) uses a 1920×1080 RR input;
[Quality output](rr-quality.png) uses 853×480 for 1280×720. The complete native
stages are in [rr-live.json](rr-live.json). Retained localized option/help captures
include [English](rr-help-en-3840x2160.png), [Russian](rr-help-ru-3840x2160.png) and
[German](rr-help-de-3840x2160.png), with matching 1440p captures beside them.
Text and tooltip boundaries were checked at all three resolutions.

The guide approximation for raster-only foliage and distant geometry, existing
transparent composition and separately denoised water are documented in the
[integration guide](../../integrations/dlss-ray-reconstruction.md). Native Windows,
HDR, XR/multiview and RR plus FG remain unqualified. The actual RTX 3090/3090 Ti
test adapters expose RR but not standard NVIDIA FG. No withdrawn RTX 30 FG
package was loaded or staged. No release or remote publication was performed.
