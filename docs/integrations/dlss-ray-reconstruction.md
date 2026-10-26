# DLSS Ray Reconstruction

Player PT presets automatically request NVIDIA Ray Reconstruction when
DLSS/DLAA is selected in a supported Windows Forward+ Direct3D 12 session.
Missing native support or an absent RR runtime retains radiance NRD; Linux
keeps its NRD path. The diagnostic launch flag `-- --ei-pt-tuning` restores the
individual **DLSS Ray Reconstruction** setting and the saved NRD/accumulation
choices. Still accumulation bypasses RR. Labels, choices, help and unavailable
reasons are in English, Russian and German. See the
[player preset and tuning contract](path-tracing-experiment.md#controls).

This implementation uses the signed production Streamline **2.14.16** release,
including `sl.dlss_d.dll` and `nvngx_dlssd.dll`. The runtime reports
**DLSS RR2 310.9.16, transformer preset F**. Preset F is selected explicitly.
The two DLL hashes are pinned in
[`streamline-sdk.json`](../../engine_patches/godot-4.7/streamline-sdk.json);
`tools/prepare_rtx_sdk.py` includes them. Existing distribution checks consume
that same manifest. No modified kernels or GPU identity overrides are required.

## Image and resource contract

The main PT view traces one new path sample per pixel at the full DLSS input
resolution. The saved RT lighting quality and adaptive PT frame target are
temporarily inactive; disabling RR restores their normal behavior. RR may cost
more than low-resolution NRD lighting, particularly with DLAA. There is no
dynamic-resolution RR path or measured performance advantage claimed here.

The compositor traces at PRE_OPAQUE using the renderer's exact jittered camera.
The material receiver shader uses the same projection. Raw diffuse/specular
lighting, albedo and geometry guides are copied into stable public textures;
the main-view NRD, direct-light temporal filter and spatial filter are bypassed.
The full HDR raster scene supplies colour, depth and dense camera/object motion
vectors to RR. RR replaces SR for that frame; it does not run after SR.

Four additional images carry diffuse albedo, specular albedo, world normals
with linear roughness, and secondary specular hit distance. Specular albedo
uses the documented environment BRDF approximation, authored dielectric
reflectance and metalness. Hit distance is a secondary-ray measurement, not
camera depth. Depth mismatch rejects a traced foreground material. Raster-only
grass, displaced leaves and distant surfaces use their actual raster normal and
roughness with an approximate neutral diffuse guide. This fallback is less
accurate than a complete raster albedo pass.

The native bridge accepts only current-size, single-view, single-sample guides
with the required formats. Inputs are cleared at every frame and resize. A
missing callback therefore selects ordinary SR instead of reusing stale guide
RIDs. The owner retains textures until the render transaction ends; public PT
textures are resized before material descriptor preparation. RR resources are
retired on mode changes, and camera cuts, scene changes and context rebuilds
reset accumulation. An RR SDK failure disables that optional path without
disabling ordinary DLSS for the session.

Water's separate PT reflection renderer keeps its selected NRD filter. Water,
particles and other transparency retain their existing composition; optional
pre-transparency colour inputs are not supplied to RR. This implementation
does not claim full translucent-material reconstruction, mirror primary-surface
replacement, XR, HDR, or RR plus frame-generation qualification. The tested
RTX 30 hardware supports standard RR but does not expose standard DLSS FG.

Subsequent [Windows stability validation](../validation/pt-stability-2026-10-26/README.md)
records RR with standard DLSS frame generation on an RTX 4090 Laptop GPU.
Unlocked foreground runs confirm actual generated presentation in the saved
camera route and live river/snow traversal. Further scene-handoff and small-detail
stability work is in progress; the linked record separates completed checks from
remaining qualification. This validation is separate from the original RTX 30
qualification above.

## Engine and verification

Apply the patches in the [engine recipe](../../engine_patches/godot-4.7/README.md).
A PCK-only update cannot provide the native bridge. The game checks both bridge
methods and actual SDK support before enabling RR on the root viewport.
Other cameras retain their own compositors and scaling paths.

Registered regressions are `path_trace_rr_live`, `path_trace_rr_raw`,
`path_trace_rr_options` and `path_trace_rr_unavailable`. The live case requires
a real RR-capable Windows DX12 runtime launched with DLSS selected. The
unavailable case deliberately omits the two RR DLLs while retaining standard
SR. Tests reject engine/script errors even when assertion counts pass.
See [results and limitations](../validation/pt-transport-2026-10-26/rr-validation.md).

Primary references: [NVIDIA release](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16),
[RR integration guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.14.16/docs/ProgrammingGuideDLSS_RR.md),
[RR interface](https://github.com/NVIDIA-RTX/Streamline/blob/v2.14.16/include/sl_dlss_d.h).
