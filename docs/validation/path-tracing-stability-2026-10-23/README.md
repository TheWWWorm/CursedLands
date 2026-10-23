# Path-tracing stability investigation — 23 October 2026

The scene-membership bug described below is reproduced and fixed. The reported
native Windows crashes on an RTX 4090 Laptop GPU and RTX 4070 Ti are **not yet
confirmed fixed**. Local Windows tests run through Wine/VKD3D on an RTX 3090 Ti;
they do not reproduce the native Windows driver or watchdog.

## Verified baseline

The latest published stable release at investigation time was
[v1.24.0](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.24.0), published
22 October 2026. Its Windows ZIP matches the published SHA256
`faac6461a5094a748833ced420fb1f305c7d3cf1a9395a2dd982b0a111121ce5`.
The game source is `490a77ed2ada148b7b7dc4a89a0ef793cad5ad4d`.
Published packages and tags were not modified.

The local candidate is `1.24.1-pt-diagnostics.1`, an unpublished diagnostic build.
It starts from that release's game source, adding only the animated-unit scene
admission fix and diagnostic version/profile settings. The diagnostic Windows
engine adds `d3d12-device-diagnostics.patch` after the existing 19 patches.
The later material/lighting changes on the development branch are excluded from
this candidate.

## Reproduced scene rebuild loop

At the ruins start (`gz1g`), a fixed camera at approximately
`(58.5, 17.958, -130)` includes a creature whose root stays 97.230 m from the
snapshot center. Its idle body/leg animation moves their nearest bounds across
96 m (observed approximately 95.86–96.04 m). The old collector admits each mesh
part separately. Its topology poll interprets those crossings as added or
removed geometry and destroys the complete snapshot, including its GPU objects
and pipeline objects.

The live baseline probe recorded 29 samples with this membership discrepancy,
without material, terrain-version or graphics-option changes. A 75-second
baseline run never reached an active PT frame; another preliminary run briefly
activated PT between repeated rebuilds. Frozen-scene tests with hidden actors
did not exercise this case.

The fix admits every supported mesh part of a nearby `GameUnit`, including
hidden parts, using the existing 120 m root admission radius. Roots already
in the snapshot remain until they exceed 128 m. Animated transforms and
visibility continue through ordinary instance updates. Static scenery keeps
its existing 96 m per-mesh test. Equipment, material, spawn and removal changes
still invalidate the scene. Triangle, texture and instance limits are unchanged.

The focused CPU fixture has 48 assertions: it fails 21 against the unchanged
release and passes all 48 against the fixed release source. It includes a
negative control for the old boundary crossing, repeated idle swings, live
transform/visibility updates, equipment/material changes, entry/exit, spawning,
removal, static scenery and resource-budget rejection.

## Windows failure diagnostics

The old DX12 path printed Present failure only in verbose mode, ignored queue
and fence-event HRESULTs, and could wait indefinitely for a failed device.
The diagnostic patch records the operation, HRESULT and device-removed reason.
Synchronization failure terminates before the engine can recycle resources
whose GPU completion was never confirmed. This is a controlled failure path,
**not device recovery or a proven fix for the original crash**.

`EI_D3D12_DIAGNOSTICS=1` enables DRED before device creation and captures available
InfoQueue warnings/errors in the Godot log. The callback copies messages into a
bounded CPU queue; logging happens after returning from the Direct3D callback.
Available breadcrumb progress and page-fault allocation information are printed
on removal. Missing diagnostic interfaces are reported explicitly.
`EI_D3D12_GPU_VALIDATION=1` additionally enables GPU-based validation and can
substantially change execution cost; it is not a performance-test setting.

These mechanisms follow Microsoft's
[DRED guidance](https://learn.microsoft.com/en-us/windows/win32/direct3d12/use-dred),
[GPU-based validation guidance](https://learn.microsoft.com/en-us/windows/win32/direct3d12/using-d3d12-debug-layer-gpu-based-validation),
and [fence removal semantics](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12fence-getcompletedvalue).
A breadcrumb indicates execution progress, not necessarily the exact faulty operation.

## Quality and memory

Low quality reduces target resolution and ray count but retains the same scene
collection radius and geometry work. The PT targets total 104 bytes per trace
pixel before alignment: 4 raw and 8 history RGBA16F images plus 2 RG16F images.
At output 1440p, Low/Medium/High consume approximately 91/206/366 MiB; at 4K,
206/463/823 MiB. These exclude raster resources, acceleration structures,
scratch buffers, textures and driver allocations. Consequently, a crash at Low
does not rule out geometry-update or resource-lifetime failures.

Unbudgeted first-use BLAS builds and synchronous pipeline linking remain
profiling candidates. They are not established crash causes. NVIDIA recommends
[profiling dynamic build flags and spreading costly rebuilds across frames](https://developer.nvidia.com/blog/best-practices-using-nvidia-rtx-ray-tracing/).
No build-flag change, watchdog registry edit or shader simplification was made
without evidence.

## Qualification boundaries

All local GPU runs select physical GPU 1 (RTX 3090 Ti) on a private virtual X
server. Test profiles keep the cursor free, show FPS and mute all audio.
Existing unrelated GPU processes are retained. These runs establish functional
behavior, not comparative FPS or native Windows certification.

The live fixture keeps actors and simulation active, turns the camera, moves
the hero and camera, forces three snapshot replacements, enters `bz8k`, writes
an isolated save and restores it through `Session.load_game`. The generated
save is not the user's particular Ingos save. The native Windows frontend/
simulation-worker handoff and the user's saved state still require confirmation.

| Run | Output / PT settings | Result |
| --- | --- | --- |
| Original Windows engine + scene fix, Wine/VKD3D | 2560×1440, Low, two bounces | 31/31 checks, exit 0, no engine errors or crash signatures |
| Final diagnostic Windows engine + scene fix, Wine/VKD3D | 3840×2160, Low, two bounces | 31/31 checks, exit 0, no engine errors or crash signatures |
| Original Linux engine + scene fix, native Vulkan | 2560×1440, Low, two bounces | 31/31 checks, exit 0; one known virtual-display refresh-rate query error |

The final 4K run used a 4352×2448 virtual monitor so the game's window fits
without repeated clamping. It recorded only two initial resolution applications,
compared with 1741 in the preliminary run using an exactly 4K monitor. The final
diagnostic run reports enhanced barriers and DXR enabled. Wine cannot provide
the Windows debug layer; this is reported as an availability warning. DRED
configuration succeeds, but no device-removal fault was injected, so native
breadcrumb/page-fault capture and GPU-based validation remain unqualified.

The final EXE's six embedded icon frames match the approved ICO pixel-for-pixel.
A comparison of all 1447 staged files against the original release stage found
only the scene collector, project settings and export settings changed, with
no added or removed files (excluding the import cache). The private GPU display
was stopped and its temporary authorization file removed after testing.

Runtime outcomes, source/binary hashes and local evidence locations are recorded
in [results.json](results.json). Early fixture failures and the private-display corrections
are retained there rather than counted as successful stability tests.

## Trying the diagnostic candidate

Extract the unpublished `1.24.1-pt-diagnostics.1` Windows ZIP into its own writable
folder and run `Run-PT-Diagnostics.cmd`. The launcher prepares a separate
`%APPDATA%\Cursed Lands PT Diagnostics` profile with copied settings and saves.
It initially selects Low/two-bounce PT and preserves the copied resolution.
The launcher and its instructions cover English, Russian and German. They have
been reviewed statically; Windows PowerShell execution has not been tested here.

Try the ruins turn/movement and the existing Ingos save. If the game freezes or
exits, preserve the matching `diagnostics\<timestamp-PID>` folder beside the EXE;
that folder contains this run's engine log and available GPU/exit information.
The in-game export-log dialog reads its default log path and may omit this
relocated diagnostic log. The separate `Run-PT-GPU-Validation.cmd` is an optional
slower investigation mode, not the first stability or performance check.
