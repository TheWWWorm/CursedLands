# PT travel, history, budget, grass and FG presentation

Local `1.28.0-experimental.5` work, based on stable `1.27.0`. The implementation
and Linux/Proton checks are complete. **Native Windows display pacing is still
unqualified**; a capture runner is supplied for that remaining check. No public
release, tag or push was made.

## Actual campaign traversal

The final candidate ran the recording-derived route through the production
single-player simulation process. It moved the player from the ruins to the
southern beach, encountered and looted the five authored targets, used normal
healing when needed, changed weather, paused and resumed, and looked back uphill.
It did not substitute camera-only travel, teleportation or invulnerability.
AI encounters are live and their timing varies between runs.

GPU Lab assigned RTX 3090 Ti to the final heavy benchmark. The separate RTX
3090 run also passed. Both used isolated displays and profiles, NVIDIA driver
580.178.04 and GE-Proton11-11. Cursor confinement and all audio were disabled;
FPS was visible. The campaign used a 3840×2160 viewport, DLSS at a 2560×1440
internal raster size, a 2560×1440 output, low PT quality, responsive NRD and the
60-rendered-FPS adaptive target. The benchmark was uncapped.

Final route: **143 checks, zero failures; 121.615 metres; zero PT or responsive
NRD inactive frames**. Ten responsive region replacements retained NRD history.
Every sampled unpaused frame had native NVIDIA FG active and two SDK presents
per game present. FG correctly suspended while paused. FSR FG was unused.

| Final route stage | Median rendered frame | Worst rendered frame |
| --- | ---: | ---: |
| Initial held view | 15.82 ms | 114.95 ms |
| First walk out of ruins | 16.42 ms | 29.37 ms |
| Downhill path | 15.69 ms | 58.41 ms |
| Beach boar encounter | 16.41 ms | 56.33 ms |
| Shore after encounters | 15.43 ms | 42.95 ms |
| Look back uphill | 13.66 ms | 54.84 ms |

The worst frame after the initial held view was **58.41 ms**. This is not a
hitch-free result: initial raster pipeline compilation still caused 115 ms,
and resource creation/promotion can still produce shorter spikes. FPS medians
from different GPUs are not treated as a matched performance comparison.

The old experimental.4 opening reproduced a **4444.85 ms** first-footstep stall.
Scoped profiling located it outside GDScript work, at the first projected
ground-mark draw. Warming that exact material and vertex layout under the
loading screen removed the multi-second stall. An intermediate diagnostic
measured 23.78 ms on that walk with FG suspended; the final active-FG run measured
29.37 ms. These are stall-reproduction observations, not a matched FG speedup.

Region replacement now reuses immutable ray programs, limits BLAS creation to
16 new structures or approximately 1.5 ms per step, and separates CPU placement
packing, terrain metadata and native resource creation into different frames.
The previous completed lighting stays bound until the successor renders and
passes its topology check. Allocation itself is not a hard real-time operation.

See [final route](pt-five-targets-2026-10-24/candidate6-final-route-recording-route.json)
and [test/runtime provenance](pt-five-targets-2026-10-24/test-provenance.json).
Diagnostic folder names retain `.4`; their source manifests and binary hashes
identify their contents. Candidate6 contains the final `.5` game source.

## History, adaptive budget and grass

- Real NRD history transfer: **12 checks passed on DX12 and 12 on Vulkan**.
  The same native instance and permanent pool survive replacement. Compatible
  surfaces retain roughly ten frames of history; changed surfaces start at one.
  Retiring the old scene does not release adopted resources.
- Resource failure/lifetime checks: **167 passed**, including failure during
  resize/upload/copy, retention of the public direct-sun texture and final
  disposal of current and retired resources.
- Native ray/NRD checks: **19 passed on DX12 and 19 on Vulkan**. The new direct-sun
  output is dark beneath a traced roof and positive on unoccluded ground.
- Grass receiver checks: **8 passed on each backend**. A nearby shadow caster
  reduces direct sunlight while indirect illumination remains. The rendered
  synthetic fixture uses the actual grass shader; it is not a map-wide visual
  quality guarantee. The local contribution fades from 18 to 24 metres.
- Adaptive-budget checks: **11 passed**. Isolated CPU stalls, loading, pause and
  repeated timestamps do not lower quality; sustained GPU pressure lowers
  resolution in 0.05 steps to a 0.65 floor. Recovery requires sustained headroom.
  The final RTX 3090 Ti route stayed at 1.0 because its measured GPU work met
  the target. The RTX 3090 route made four gradual changes, lowering to 0.90
  and later recovering to 1.0, without PT/NRD dropouts.
- Settings layout: **373 checks passed**, including EN/RU/DE at 800×600 and
  1280×720. Translation coverage: **17,258 checks**, 173 options and 2,952 keys.
- All 18 PT shader binaries and all 16 NRD shader binaries match their manifests.

## FG opacity and output dimensions

The engine captures canvas-composited opacity into a dedicated mask while
preserving the game's RGB output, then tags it alongside HUD-less colour,
depth and motion. If the final full-window output differs from the viewport,
HUD-less colour and opacity are resampled to its actual size. Equal-size output
uses the existing textures without an extra resample. Cropped/unsupported
mappings suspend FG and preserve ordinary rendering.

The current engine passed **43 checks** using the native NVIDIA runtime through
the optional pinned `dlssg_for_sm86` package. At each enabled phase, 180 rendered
frames produced 180 game presents and 360 SDK presents. Disabled phases produced
no generated frames. Tests cover opaque HUD coverage, 50% opacity, empty pixels,
the FPS label, resize to 1600×900 and a 1920×1080 viewport mapped to 1600×900.
See [FG results](pt-five-targets-2026-10-24/candidate5-fg-mask-output-dlss-framegen.json).

The first campaign fixture left the native window maximized while requesting
a smaller logical window. The new guard correctly suspended FG in those runs;
they were not counted as FG qualification. Correcting the isolated fixture's
saved resolution and native window mode produced the passing full traversals.

The engine patch was replayed against the previous engine source and all 31
changed files matched the built tree. See the
[engine manifest](pt-five-targets-2026-10-24/engine-manifest.json).

## Remaining native Windows check

SDK present counts under Proton cannot prove physical display pacing on Windows.
The optional mod's native NVIDIA backend is exercised here, but Linux NVAPI
Reflex synchronization limitations remain as documented in the
[previous qualification](dlssg-sm86-2026-10-24.md). Native Windows, latency,
different refresh rates, HDR, XR and multiple windows remain unqualified.

The package includes `qualification/run_native_dlss_qualification.ps1` and its
fixture. On the Windows test machine, obtain
[PresentMon](https://github.com/GameTechDev/PresentMon/releases) separately, then
run from the preview package directory (use the optional RTX30 package on Ampere):

```powershell
.\qualification\run_native_dlss_qualification.ps1 `
  -Package . `
  -OriginalGame 'C:\Games\Evil Islands' `
  -PresentMon 'C:\Tools\PresentMon.exe'
```

The runner copies the package into a unique results directory under Documents,
creates a separate muted profile, captures PresentMon data and records runtime
hashes, OS/driver details, time zone and phase timestamps. A custom `-Output`
must be outside the package directory. Keep the resulting directory for review.
Passing script assertions alone does not mark display pacing qualified: review
the display intervals, generated-frame classification and phase timestamps.

The runner passes PowerShell parsing and rejects Linux before running the game.
Its native Windows execution remains pending. Its PresentMon arguments follow
the [official console documentation](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md).
No PresentMon binary is bundled. Existing NVIDIA/NRD/AMD notices and the complete
optional-mod notices remain included; NVIDIA placement review is still pending.
