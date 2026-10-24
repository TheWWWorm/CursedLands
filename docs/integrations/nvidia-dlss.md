# Restored NVIDIA DLSS

The Windows 1.28.0 build uses the restored Streamline 2.14.16
integration on the current patched Godot 4.7 renderer. It retains NRD 4.18
REBLUR, the DXR barrier fixes, scene caching, terrain-sector tracing, grass
lighting and the animated blood-mark performance fix. DLSS Super Resolution
and DLAA reconstruct the final campaign image; NRD separately denoises traced
lighting. This is not DLSS Ray Reconstruction or Multi Frame Generation.

## Settings

On Windows select **Options → Screen → Renderer → Forward+ (Direct3D 12)**.
Choose **NVIDIA DLSS** under **Anti-aliasing**, apply and restart when prompted.
The ordinary executable reads the saved setting; no special launcher is needed.
**Upscale quality → Native AA** selects DLAA; the other choices are Quality,
Balanced and Performance. These quality changes apply live in a DLSS session.
Switching to an ordinary AA or FSR mode is always possible, including with an
unsupported saved DLSS request. Switching SDK presentation owner requires a
restart. Settings preserve the older `rtx_upscaling` and `rtx_frame_generation`
keys. Other viewports retain ordinary scaling.

**Frame generation → NVIDIA DLSS** requests one generated frame per rendered
frame. It requires active DLSS/DLAA, an SDK-supported GPU/driver, Reflex support
and Windows hardware GPU scheduling. Its actual SDK capability gates the
choice. The path suspends for menus, loading, movies, pause or focus loss.
The FPS display uses measured presentation counters; it never assumes that
an enabled option doubles output. The standard NVIDIA runtime does not expose
FG on RTX 30. The optional [DLSS-G SM86 package](dlssg-sm86.md) enables native
NVIDIA generation on Ampere through a third-party compatibility layer.

The engine captures HUD-less color before canvas drawing, then captures real
canvas opacity after all HUD layers. RGB output is retained while alpha is
restored for normal presentation. The final compositor tags HUD-less color and
UI alpha at the actual swapchain size; a scaled full-window viewport is
resampled consistently. Equal-size output uses the original buffers directly.
Both HUD opacity textures use R16 floating point. Godot's D3D12 allocations
are typeless, and Streamline 2.14.16 resolves R16 to a valid floating-point view
but leaves R8 typeless. The R8 mask caused native D3D12 device removal when
frame generation started. Both mask-writing shaders use the matching format.
Cropped, letterboxed and multi-window layouts are not qualified; incompatible
mappings suspend FG while ordinary rendering continues.

The AMD and NVIDIA SDKs have exclusive presentation ownership. A NVIDIA
selection clears AMD upscaling/FG requests; selecting ordinary/AMD AA clears
NVIDIA requests. FSR frame generation remains independent of FSR upscaling in
an AMD session. Missing SDK DLLs or unsupported hardware leave ordinary
rendering active and expose an unavailable reason.

## Native integration

The restoration selectively merges the previously qualified NVIDIA engine
code with the current twenty-patch engine. It preserves async FSR preparation,
independent FSR frame generation, diagnostic hooks and DXR enhanced barriers.
The patched engine is pinned to Godot
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`. Apply `restore-dlss.patch` last.
Streamline's `slUpgradeInterface` registers devices created by the Agility
factory; the old system-runtime bypass is removed. SDK functions remain
behind native capability checks. Only the signed production DLLs beside the
executable are loaded; automatic SDK downloads are disabled.

Forced loading/warm-up draws receive separate frame tokens even when they run
inside one simulation tick. This prevents `eErrorDuplicatedConstants` from
disabling DLSS during campaign loading. The Windows local simulation also
retains its authenticated owner while ENet keep-alives continue through a
long synchronous load; its existing disconnect handling remains active.

The original port derives from [NVIDIA's Godot fork](https://github.com/NVIDIA-RTX/godot),
commit `54c99593e0abd3126eb6974abc2d843f015b288a`. The pinned
[Streamline release](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16)
and [interface upgrade guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.14.16/docs/ProgrammingGuideManualHooking.md)
document the dependency and native interface handling.

## Build and distribution

Fetch with `tools/prepare_rtx_sdk.py`; the archive SHA-256 is pinned in that
script and `engine_patches/godot-4.7/streamline-sdk.json`. The latter also pins
every shipped production DLL and notice. Add `use_streamline=yes` to the
current Windows FSR/DXR build command; no Linux engine change is needed.
Install the matching headers into the patched engine with:

```sh
python3 tools/prepare_rtx_sdk.py --archive /build/streamline-sdk-v2.14.16.zip \
  --output /build/streamline-sdk --engine /build/godot
```

The Windows exporter `tools/build_fsr_preview.py` accepts `--rtx-sdk` to include
DLSS in a local review export. Audit with:

```sh
python3 tools/check_fsr_distribution.py --nvidia --package /build/CursedLands
```

Every Windows preview includes the combined NVIDIA/AMD splash and credits;
Linux includes NRD credits without claiming DLSS. Attribution depends on
package contents, including when features are disabled or unsupported.
The complete notices accompany the binaries. The NVIDIA placement review
remains pending: see [SDK attribution](../branding/graphics-sdk-attribution.md).
No NVIDIA notification or approval request is sent by these build tools.
The native Windows fix and RTX 4090 Laptop frame-generation checks are
recorded in the [native validation](../validation/dlss-framegen-native-2026-10-24/README.md).
Other GPUs, HDR, XR and multi-window output require separate qualification.

The [PT and presentation validation](../validation/pt-five-targets-2026-10-24.md)
records current traversal, HUD opacity, output-size checks and the remaining
native Windows pacing capture. The [restoration report](../validation/dlss-restoration-2026-10-24.md) records
the exported binary hashes, actual SDK evaluations, traversal measurements,
settings checks and attribution captures.
