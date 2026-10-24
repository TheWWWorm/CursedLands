# Optional native NVIDIA frame generation on Ampere

`1.28.0-experimental.4` can be prepared with
[dlssg_for_sm86 0.4.0](https://github.com/sdli1995/dlssg_for_sm86/releases/tag/0.4.0).
This runs NVIDIA's DLSS-G model/runtime with SM86-compatible kernels on RTX 30;
it is not the DLSS-to-FSR frame-generation replacement. The normal build keeps
standard SDK capability detection. Installing the optional mod lets that same
integration discover and use the newly available NVIDIA path.

## Reproduce the package

Download the exact upstream `dlssg-release-0.4.0-x64.zip`, then run:

```sh
python3 tools/prepare_dlssg_sm86.py \
  --base-package /build/CursedLands-1.28.0-experimental.4-windows-x86_64 \
  --archive /downloads/dlssg-release-0.4.0-x64.zip \
  --output /build/CursedLands-1.28.0-experimental.4-rtx30
```

The tool verifies SHA-256
`5865360c3295038f0ff979d303bb7eb9437eec09fbc08686967d3b5d41d9c019`, copies
the base into a new directory, and refuses an existing output or existing
proxy. It installs upstream `alternatives/winmm.dll`, `dlssg_sm86.ini` and the
complete `dlssg_sm86` directory. Cursed Lands imports WINMM; its rendering
executable did not load the default VERSION proxy in testing. No original
NVIDIA SDK DLL is replaced. Existing game files, profiles and system DLLs are
not modified.

The configuration selects `Engine=DLSS`, `MaxGeneratedFrames=1` and
`Optimized=1`. The latter is upstream's exact consistency tier; lossy tiers
and the optional INT8 super-resolution replacement are disabled. This does
not expose multi-frame generation or Intel XeSS. Use the ordinary Screen
options for DLSS and NVIDIA frame generation. Three-language player setup and
removal instructions are in [README-RTX30](dlssg-sm86-player.txt).

The preparation tool retains upstream MIT copyright/license text, the full
third-party notices, manifests and documentation under
`licenses/dlssg_for_sm86`. Upstream distinguishes its own MIT code from the
NVIDIA runtime and NVIDIA-derived kernel assets; MIT does not relicense those
assets. The existing game package also retains NVIDIA, AMD and NRD notices.
This optional local experiment is not part of a published stable release.

## Renderer corrections and qualification

D3D12 queue submissions without a swap chain no longer emit Reflex present
markers. DLSS-G configuration queries run only when enabling a viewport;
presentation counts are sampled once at the real present boundary. A GPU test
requires 180 rendered frames to produce 180 game presents and approximately
360 SDK-reported output frames. It checks motion, resize, disabling and
reenabling, SDK error state and zero AMD frame-generation dispatches.

Captured NGX generated-image surfaces provide an additional check beyond the
capability flag and FPS counter. The recording-derived campaign fixture also
accepts `--route-dlss --route-dlss-fg` to check normal gameplay gating with
path tracing and NRD. See [validation](../validation/dlssg-sm86-2026-10-24.md).

Tests use GPU Lab and isolated profiles on RTX 3090-class hardware through
GE-Proton11-11, including its full CUDA Wine relay in the private prefix.
The older Wine 9 environment lacked the required CUDA/HWS compatibility.
Neither Proton nor its relay is included in the Windows player package.
The separate [dlssg-open](https://github.com/dniminenn/dlssg-open) Linux relay
also activated NVIDIA FG during investigation; it is not shipped or required
by this SM86 package. Native Windows, other RTX 30 models, HDR, XR and
multi-window rendering remain unqualified.
