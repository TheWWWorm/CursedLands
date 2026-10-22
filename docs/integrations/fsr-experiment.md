# AMD FSR on Windows

Cursed Lands includes AMD FSR in the normal Windows executable. It uses a custom native Godot renderer;
an ordinary Godot export alone cannot enable it. Upscaling and frame generation
both start **Off**.

## Enable FSR

1. Extract the complete Windows package and run `CursedLands.exe` as usual.
2. Open **Options → Screen → Renderer**. If necessary, select
   **Forward+ (Direct3D 12)** and accept the normal restart prompt.
3. In **Screen → Anti-aliasing**, choose ordinary AA or **FSR 3.1 / FSR 4**.
4. For FSR, use the adjacent **Upscale quality** dropdown to choose **Native AA**,
   **Quality**, **Balanced** or **Performance**.
5. Choose an available **Frame generation** version on the same screen. It
   generates one intermediate frame per rendered frame during campaign gameplay
   and also works with ordinary AA, without FSR upscaling.

The same installation, settings, saves and mod profiles are used. No special
launcher or command-line flag is needed. The earlier local experimental profile
is not imported automatically; existing ordinary release profiles stay in place.

Version availability is queried from the SDK on the active device. Unsupported
choices are greyed out and cannot be selected. Screen shows a renderer-switch
instruction when Direct3D 12 is required; option help explains other blockers.
Saved unsupported requests can still be switched off. An FSR 4 request never silently uses FSR 3.1; the runtime
records the actual provider version after context creation.

| Feature | Hardware and qualification |
| --- | --- |
| FSR 3.1 upscaling | Compatible Direct3D 12 GPUs, including NVIDIA. Tested on RTX 3090 through Wine/VKD3D-Proton. |
| FSR 3.1 frame generation | Compatible Direct3D 12 GPUs, including NVIDIA. The same RTX 3090 run verified generated output reaching the presentation path. |
| FSR 4 upscaling | AMD's SDK 2.3.0 documents Radeon RX 7000 discrete or RX 9000 and newer GPUs. Integrated but untested on compatible AMD hardware. |
| FSR 4 frame generation | AMD documents Windows 11 and RX 9000 or newer. Integrated but untested on compatible AMD hardware. |

These hardware requirements come from the pinned
[FSR 4 upscaling guide](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/v2.3.0/Kits/FidelityFX/docs/techniques/super-resolution-ml.md#limitations)
and [FSR 4 frame-generation guide](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/v2.3.0/Kits/FidelityFX/docs/techniques/frame-interpolation-ml.md#limitations).
Compatible drivers and runtime support are also required. Native Windows
execution remains unqualified; Linux testing used the Windows executable
through Wine. See the [release validation](../validation/release-1.20.0-2026-10-20.json).

Since 1.24.0, the DX12 build can combine FSR 3.1 with hardware ray-traced
water. Its river regression measures actual generated/presented frames, the FPS
overlay, Mirror/RT switches, resize and pause/resume. See the
[water guide](water-raytracing-experiment.md). This requires the additional DXR
engine patch, included in the 1.24.0 Windows executable; 1.23.0 used Mirror for
that option in DX12. Vulkan RT remains available, but this FSR SDK integration still requires
DX12. First use can show **Preparing FSR…** while temporal shaders compile.

Start with SDR, native window/display size and VSync off. The package includes
Microsoft's x64 Agility 1.618.5 runtime in `x86_64/`; keep that directory beside
the executable. A Microsoft Visual C++ v14 x64 runtime may also be needed by
the production SDK DLLs.

## Behavior and limits

Upscaling replaces anti-aliasing and the render scale on the root 3D viewport.
Native AA uses scale 1; the other scales are 2/3, 1/1.7 and 1/2. The integration
provides linear HDR color, reverse-Z depth, decoded motion vectors, jitter,
camera-cut resets and an extracted reactive mask before tonemapping.

Frame generation can use native resolution, the ordinary render scale and
Off, SMAA, MSAA, TAA or FSR 2 anti-aliasing, independently of AMD SDK upscaling.
The normal game controller suspends it during pauses, loading, movies, camera-blocking HUD
panels and loss of window focus. It resumes automatically in active campaign
gameplay. Trials and portrait/reflection subviewports retain their own scaling.

The renderer supplies a full-size tonemapped scene before canvas/HUD drawing
to AMD's HUD-less input. AMD's proxy swapchain extracts the UI contribution
and presents the generated frames. There is no separately rendered UI-alpha
surface. Interpolation uses the game graphics queue; asynchronous presentation
is managed by the SDK. Resource transitions return to Godot's expected state,
and resize/context destruction drains pending work.

The first SDR root swapchain is supported. HDR presentation, non-native
viewport stretching, XR, additional windows and long sessions remain
unqualified. Transparent effects, foliage, distortion and UI edges need
further image-quality review on native Windows and AMD hardware. This is 2×
generation only; it does not include path tracing, ray reconstruction or
generation of more than one intermediate frame.

While frame generation is active, the FPS overlay shows **rendered FPS** and
**presented FPS**, sampled from the actual game and underlying DXGI present
counters over the same rolling time interval. It never assumes a 2× multiplier.
A short “…” appears until a valid presentation sample exists; pauses, resumes,
resets and long gaps discard stale samples. With FG off, the ordinary single FPS
counter remains. Frame generation has a processing cost, so rendered FPS can
fall while presented FPS increases.

Windows borderless fullscreen uses a screen-sized undecorated window so the
viewport and DXGI presentation surface have identical dimensions. Godot's
nonexclusive fullscreen mode adds two pixels to the surface, which prevents
this integration's exact-size frame-generation context from activating.

`fsr-status.json` in the game profile reports actual SDK versions, successful upscale dispatches, generated
frames, game presents, real DXGI presents and errors. `presented_frames`
counts calls reaching the underlying swapchain; it does not measure how many
frames a monitor physically scanned out. Screenshots taken through Godot
capture rendered frames, not the interpolated frames.

`frame_generation_blockers` records the active gameplay gate, including menus,
loading, pause and lost focus. The status also retains whether generation has
ever been active and the time since it was last allowed, so switching away to
read the file does not hide the preceding activity.

First activation prepares the engine's motion-vector shaders and pipelines on
Godot's compiler workers, then creates the requested AMD context on a bounded
background worker. The ordinary color pass continues, with spatial scaling if
needed, until the feature is ready. **Preparing FSR…** is localized in EN/RU/DE.
Readiness is retained for the configured render buffers, so later unrelated
pipeline compilation does not repeatedly suspend FG. Applying unchanged settings
preserves the current context. Obsolete pending size/version requests are
discarded at handoff; device shutdown joins the worker before releasing D3D12.

The loader verifies the exact SHA-256 of each production AMD DLL before
loading it from beside the executable. Missing or mismatched DLLs leave the
ordinary renderer available. An SDK error disables the affected feature until
restart; the game restores ordinary scaling after an upscaler failure.

## Rebuild

1. Start from Godot commit `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`.
2. Apply the sixteen common patches in the
   [engine recipe](../../engine_patches/godot-4.7/README.md), then
   `experimental-fsr.patch`.
3. Prepare the pinned AMD SDK headers and runtime:

   ```sh
   python3 tools/prepare_fsr_sdk.py \
     --output /build/fsr-sdk \
     --engine /build/godot \
     --agility-archive /build/Microsoft.Direct3D.D3D12.1.618.5.nupkg
   ```

   The helper verifies the SDK files against `fsr-sdk.json`, installs the seven
   public headers, adjusts the resource-description helper for MinGW, and
   extracts the Agility core and its notices from a verified NuGet archive.
   AMD binaries are the signed production SDK 2.3.0 distribution.

4. Build the Windows x86-64 release template with the optional AMD backend:

   ```sh
   scons -j6 platform=windows arch=x86_64 target=template_release \
     production=yes optimize=speed debug_symbols=no lto=none \
     use_fsr_sdk=yes module_mono_enabled=no \
     module_openxr_enabled=no use_pix=no accesskit=no
   ```

   The local cross-build also sets `use_mingw=yes use_static_cpp=yes`,
   `mingw_prefix` and `mesa_libs`. The SDK build option defaults to `no`.

5. Commit the desired game source, then export the branded executable:

   ```sh
   python3 tools/build_fsr_preview.py \
     --output /build/fsr-preview \
     --windows-template /build/godot/bin/godot.windows.template_release.x86_64.exe \
     --fsr-sdk /build/fsr-sdk
   ```

   The output directory must be new. Exporting embeds the approved dragon icon
   and version metadata. Keep all DLLs, PCK, launchers, licenses and the Agility
   subdirectory together. The tool does not publish or tag a release.

The implementation uses the SDK's
[versioned API](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/v2.3.0/Kits/FidelityFX/docs/getting-started/ffx-api.md),
[frame-generation API](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/v2.3.0/Kits/FidelityFX/docs/techniques/frame-interpolation-api.md)
and [DX12 swapchain](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/v2.3.0/Kits/FidelityFX/docs/techniques/frame-interpolation-swap-chain.md).
The tested conventional providers are SR 3.1.5 and FG 3.1.6; the SDK also
contains the ML SR 4.1.1 and FG 4.0.1 implementations.
