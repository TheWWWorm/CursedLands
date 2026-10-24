# Native Windows DLSS frame-generation validation

## Change

The DLSS-G HUD opacity textures now use R16 floating point, including the
resampled output mask. Both compute shaders write the matching format.
HUD recomposition, frame generation, enhanced barriers and production NVIDIA
runtime components remain enabled.

Godot allocates these D3D12 resources as typeless textures. Streamline 2.14.16's
[D3D12 view-format resolver](https://github.com/NVIDIA-RTX/Streamline/blob/v2.14.16/source/platforms/sl.chi/d3d12.cpp)
converts R16_TYPELESS to R16_FLOAT, but leaves R8_TYPELESS unchanged. Its texture
view creation reads the native resource description, so changing only the
tag's nativeFormat would not fix the R8 allocation.

## Failure evidence

The published 1.28.0 executable completes the DLSS Super Resolution phase of
the hardware fixture, then loses the D3D12 device when frame generation starts.
Present returns 0x887a0005 with device-removal reason 0x887a0001
(DXGI_ERROR_INVALID_CALL). Disabling HUD recomposition alone and changing
resource tag lifetimes both reproduce the failure. Omitting both HUD inputs
avoids device removal but produces no generated frames, so it is not a fix.

The R16 mask completes the same fixture with HUD recomposition enabled and
actual 2x SDK presentation counts. No diagnostic bypass is present in the
final engine.

## Environment and build

- Windows 10.0.26300, RTX 4090 Laptop GPU, NVIDIA driver 621.01, native D3D12.
- Game source: 926579c4 plus this change; local unpublished 1.28.0 development build.
- Godot 5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88, all 21 Windows patches.
- Streamline 2.14.16 signed production DLLs and Agility SDK 1.618.5.
- Release template built with MinGW, use_streamline=yes and use_fsr_sdk=yes.
- All 21 patches apply to clean pinned sources; all 77 patched source files
  match the compiled source tree exactly.
- The full EXE and PCK were exported using the rebuilt template and resource
  editing. Native code matches the template, and all six embedded icon sizes
  match the approved transparent branding.
- Tests use isolated profiles with a copied campaign save and its HD texture
  mod, free cursor, visible FPS and muted audio. Player saves and preferences
  were not modified.

## Regression evidence

The native HUD fixture passes 67 checks covering DLSS SR, real game/SDK presentation counts, HUD
opacity, native and scaled output sizes, disabling/re-enabling, resize and
teardown. Each enabled sample presents 360 frames for 180 game frames.
Opaque, translucent and empty mask regions retain their expected values.
The format assertion requires a readable half-float mask.

The save-load fixture exercises the real frontend and simulation worker with
the normal RtxGraphics gameplay gate. It completes three campaign loads and
three pause/resume cycles at 3840 x 2160 with 71 checks and no failures.
All six loaded/resumed samples present 360 frames for 180 game frames.
All three paused samples continue rendering and produce no generated frames.
The final exported EXE and PCK are byte-identical to those used for this run.

Machine-readable counters and package hashes are in [results.json](results.json).
The final package also passes the combined graphics distribution audit,
including the pinned production NVIDIA DLLs, notices and DirectX runtime.
Native SDK layers were unavailable on this machine; these are actual
hardware execution/counter checks, not a clean debug-layer validation claim.
Other GPUs and long-duration frame-pacing validation remain outside this run.

Example, with an isolated profile containing a copied save:

```text
CursedLands.exe --audio-driver Dummy --rendering-driver d3d12 -- --no-movies --tool=C:/projects/CursedLands/tools/tests/rtx_frame_generation_save_load.gd --save-slot=save6 --cycles=3
```

The runnable local package is in builds/windows-dlss-framegen-fixed/.
Detailed build and test logs are under builds/dlss-fg-crash/.
