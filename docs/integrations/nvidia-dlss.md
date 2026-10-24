# Restored NVIDIA DLSS

The local `1.28.0-experimental.3` preview restores the prior Streamline 2.14.16
integration onto the current patched Godot 4.7 renderer. It retains NRD 4.18
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
an enabled option doubles output. RTX 30-series hardware can validate DLSS
SR/DLAA and unavailable-FG handling, but cannot qualify NVIDIA frame generation.

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
The package is local and unpublished; native Windows, RTX 40/50 frame
generation, HDR, XR and multi-window output remain separate qualification.
