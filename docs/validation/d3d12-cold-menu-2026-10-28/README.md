# Direct3D 12 main menu after an update with DLSS, TAA or FSR 2

A Windows 1.34.0 report (2026-10-28, RTX 4090 Laptop GPU, NVIDIA 621.01,
Windows 10.0.26300) ended three Direct3D 12 starts at
`startup: main menu built; presenting loading animation`. Each time the next
start recorded an unexpected end in the menu, marked D3D12 as failed and
switched to Vulkan. Vulkan started normally. The same profile and settings had
used D3D12 with 1.33.0 for hours the previous evening: High preset, path
tracing (2 bounces), DLSS with Ray Reconstruction and DLSS frame generation,
3840×2160 borderless.

## Confirmed failure

The 1.34.0 package was reproduced on the reporting machine with isolated
profiles (`APPDATA` redirected, free cursor, FPS shown, audio muted). The player's
profile and shader cache were only copied. The packaged executable ignores a
`._sc_` marker, so one early run wrote to the player's profile. Its renderer
files, crash marker and log were restored to their recorded contents and sizes.

- With a copy of the player's shader cache and settings, both the normal startup
  and the menu fixture stopped at the same trace line. Neither presented a menu
  in 150–360 s, and no shader-cache file was written in that time.
- The hung process used 0.1 s of CPU in 10 s; every thread was waiting.
- Disabling the standby simulation worker introduced in 1.34.0 (`--ei-inline-host`)
  did not change the result, so the worker is not involved.
- With DLSS off, the same state opened the menu (14 s). With PT on and
  DLSS off, the first 3D draw took 0.6 s; with DLSS on it took 19.7 s.

The 1.34.0 cache lacked 19 Direct3D 12 entries for the main scene shader:
8 ordinary-pass and 11 advanced-group variants. The advanced group holds the
motion-vector variants that DLSS, TAA and FSR 2 need. 1.34.0 changed the
generated terrain, ground-surface and PT receiver material code. Engine shaders
were already cached; their source hashes are identical in both releases.

## Mechanism

A native stack sample of the hung process (dbghelp `StackWalk64`, export
symbols only; the release executable has no PDB) showed:

- the main thread inside the engine's Forward+ shader code, waiting on a
  condition variable in the worker-pool wait;
- all four worker-pool threads (`threading/worker_pool/max_threads.windows=4`)
  blocked in `RtlEnterCriticalSection` in the same engine code region.

The engine source matches this:

1. The first frame needing motion vectors calls
   `SceneShaderForwardClustered::enable_advanced_shader_group()` at high
   priority. This queues the advanced group for every loaded material behind
   jobs that are already pending.
2. Drawing a material calls `ShaderRD::version_is_valid()` or
   `version_get_shader()`. Each takes the version's mutex and joins its pending
   group compilation (`_compile_version_end` →
   `wait_for_group_task_completion`).
3. Pipeline jobs for the same material need that mutex. When they occupy every
   worker, the joined compilation never starts.

With a free worker, the join completes but still blocks the main thread for the
entire compilation. The FSR SDK path had already avoided this through
background preparation (`experimental-fsr.patch`). DLSS, FSR 2, MetalFX and TAA
did not use it.

Why 1.33.0 worked: its advanced variants for the same materials were already
cached, and loading them from cache creates no compile tasks.

## Change

`engine_patches/godot-4.7/temporal-shader-preparation.patch` (24th Windows
patch) extends the existing background preparation to every temporal mode on
the single main view:

- enable the advanced group at low priority;
- keep validating materials against the ordinary group;
- draw the ordinary pass, copying the internal image to the output, until the
  shaders and all motion-vector pipelines are ready;
- then switch to the mode.

While preparing, the frame requests no motion vectors and does not tag DLSS-G.
That includes the Ray Reconstruction compositor's request, which only DLSS
consumes. An untagged frame already turns frame generation off at presentation
until the next tagged frame. The FSR SDK and frame-generation paths,
reflection probes, multiview and the debug motion-vector view keep their
previous behavior.

## Original-game comparison

Not applicable. Evil Islands and Lost in Astral have no Direct3D 12 renderer, DLSS,
TAA, FSR or shader cache, and their menu path has no equivalent to compare
under Wine. This change does not alter menu content, camera or timing logic.
Only the order in which the renderer compiles shaders changes.

## Regression

`tools/run_native_d3d12_cold_start.ps1` with `tools/tests/d3d12_cold_menu_start.gd`
reproduces the update path: the previous release seeds a new profile with the
reported settings, then the package under test opens the real menu
(`Main.open_menu()`). It requires:

- the menu presented within 60 s of process start;
- no frame longer than 20 s;
- frames keep presenting afterwards;
- motion-vector shaders compiled in that run;
- the mode finally active: actual DLSS SDK evaluations, and for every mode
  main-view frames drawn first while preparing and then with the temporal pass
  (`temporal_preparing_frames` and `temporal_active_frames` in
  `FidelityFX.get_status()`). The fixture keeps measuring frame times until
  the mode draws, so the switch itself is covered.

The seed pass only fills the previous release's cache. It is not held to the
menu budget, because the previous release has the same stall on a new profile.

A process that never reports is killed after 240 s. Synthetic seeds without the
previous release (ordinary shaders only, or one changed terrain option) did not
reproduce the stall and are not used.

## Results

Native Windows, RTX 4090 Laptop GPU, NVIDIA 32.0.16.2101, 1920×1080 window,
1.33.0 release as seed, 1.34.0 PCK. "Unfixed" is a local rebuild of the
23-patch stack; it behaves like the published 1.34.0 executable in every
fixture run. "Fixed" adds the new patch.

| Mode | Unfixed: menu / longest frame | Fixed: menu / longest frame |
|---|---:|---:|
| DLSS + PT + FG | 47.7 s / 38.0 s — FAIL | 17.7 s / 8.1 s — PASS |
| TAA | 44.1 s / 37.7 s — FAIL | 14.6 s / 8.2 s — PASS |
| FSR 2 | 47.1 s / 40.5 s — FAIL | 14.7 s / 8.1 s — PASS |

Fixed DLSS presented 18,214 menu frames while preparing (longest interval
57 ms after the menu) and evaluated DLSS 60 s after the menu appeared.

The fixed executable also opened the menu from a copy of the reporting profile's
shader cache with its settings, the state in which every unfixed start hung. The
menu appeared after 17.7 s; 15,828 frames followed (longest 71 ms) before DLSS
started, and the process exited cleanly. With DLSS off, the same state still
shows the 7.0 s ordinary-shader frame described below.

Executables (SHA-256 prefixes): published 1.34.0 `92ebff4d6abe`,
unfixed rebuild `b783c5aa7783`, fixed rebuild `4937b04613d7`. These native
results predate the frame counters added during integration. The final patch
was qualified natively afterwards (see "Native Windows qualification of the
final patch").

### Proton reproduction on the integration workstation

The integration rebuild added the frame counters above to the patch and
re-ran the unchanged fixture under GE-Proton 11-11 (vkd3d-proton) in GPU Lab,
RTX 3090, 1920×1080 window, 1.33.0 seed, 1.34.0 PCK. The native runner refuses
Wine; a workstation copy of it seeded and measured each mode the same way, in
one locked suite prefix with a new profile per mode. The stall is in Godot's
own shader compilation, so it reproduces here, but this is supplementary
evidence, not native Windows qualification.

| Mode | Published 1.34.0: menu / longest frame | 24-patch rebuild: menu / longest frame / frames preparing → active |
|---|---:|---:|
| DLSS + PT + FG | 60.1 s / 49.2 s — FAIL | 25.9 s / 13.2 s / 15,841 → 30 — PASS |
| TAA | 47.5 s / 38.0 s — FAIL | 29.0 s / 14.1 s / 10,525 → 30 — PASS |
| FSR 2 | 74.6 s / 59.1 s — FAIL | 28.8 s / 14.3 s / 12,471 → 30 — PASS |

The modes started 74–83 s after the menu, so the settle limit is now 150 s
(it was 90 s). A second run of the final fixture also passed every mode
(menus at 16–22 s, longest frames 8.1–9.3 s, modes active 46–55 s after the
menu, with warmer host driver caches). On a new profile, the 1.33.0 seed pass
itself drew a 44–73 s frame in every mode, which is why the seed pass is no
longer held to the menu budget.

Under Proton, `path_trace_rr_guides.gd` passed 95/95 with the rebuild.
`rtx_frame_generation.gd` reports blocked (no DLSS-G under Proton) for both
executables. `path_trace_rr_live.gd` failed the same 6 of 38 checks with the
published 1.34.0 executable and the rebuild ("baseline uses NRD" and five
dependent RR-off checks), so that failure belongs to the Proton environment.
The native runs below remain the qualification for these fixtures.

Executables (SHA-256 prefixes): rebuilt template `779b6fd9b34b` (patch
`012609ea5c56`), tested as `CursedLands.exe` in a copy of the 1.34.0 package.

### Native Windows qualification of the final patch

This run used the Windows test machine (RTX 4090 Laptop GPU, NVIDIA
32.0.16.2101, Windows 10.0.26300) and `main` at `a9f95e07`:

- **Engine:** the 23-patch tree plus the committed
  `temporal-shader-preparation.patch` (`012609ea5c56`), built with the
  integration flag set (without `agility_sdk_multiarch`, `winrt` and
  `disable_path_overrides`). The result is executable `890c744a3e6e`. This
  build is not byte-identical to the workstation's `779b6fd9b34b`; both come
  from the same sources and patch.
- **Test:** `CursedLands.exe` in a copy of the 1.34.0 package, run with the
  final fixture and runner. The 1.33.0 release was the seed, with a 1920×1080
  window and a new profile per mode.

| Mode | Published 1.34.0: menu / longest frame | Final rebuild: menu / longest frame / frames preparing → active / mode active after menu |
|---|---:|---:|
| DLSS + PT + FG | 40.3 s / 31.0 s — FAIL | 25.0 s / 12.5 s / 20,546 → 30 / 68.6 s — PASS |
| TAA | 36.4 s / 30.5 s — FAIL | 14.6 s / 8.0 s / 8,661 → 30 / 53.2 s — PASS |
| FSR 2 | 36.6 s / 30.9 s — FAIL | 14.3 s / 8.0 s / 13,283 → 30 / 54.6 s — PASS |

The published executable also fails the frame-counter check because it has no
counters. Its stall failures are the regression signal.

### Related Windows checks

These ran with the same executables on new profiles with DLSS requested at
launch. `path_trace_rr_*` used test scripts staged as in `check_regressions.py --packaged`.

| Fixture | Unfixed | Fixed | Final rebuild `890c744a3e6e` |
|---|---:|---:|---:|
| `rtx_frame_generation.gd` (DLSS SR + DLSS-G, resize, scaled output, HUD mask) | 68/68 | 68/68 | 68/68 |
| `path_trace_rr_live.gd` | 38/38 | 38/38 | 38/38 |
| `path_trace_rr_guides.gd` | — | 95/95 | 95/95 |

On native Windows, `path_trace_rr_live.gd` passes all 38 checks, including the
6 that fail under Proton for both executables. `rtx_frame_generation.gd`
measured actual DLSS-G presentation, which Proton does not provide. PresentMon
pacing (`tools/run_native_dlss_qualification.ps1`) was not captured in this
run.

`rtx_frame_generation.gd` sampled DLSS immediately after creating the menu
scene. On a new profile, the fixed renderer starts DLSS only after the background
preparation, so the first sample failed (67/68). The fixture now waits for DLSS
to start, for up to 120 s, and asserts that it did. All existing sample
assertions are unchanged; the edited fixture also passes on the unfixed rebuild.

## Known limits

From an independent source review of the patch:

- **Slow start of the mode.** Preparation compiles at low priority. With the
  four-thread pool, one worker handles this, so the mode can start a minute
  after the menu appears. The menu keeps drawing at full rate meanwhile.
- **Unprotected engine features.** Subsurface scattering, separate specular
  (SSR), lightmaps, VoxelGI and SDFGI still request advanced variants
  synchronously. If one is active while a temporal mode prepares, the render
  thread can again join low-priority work. The game uses none of these
  features; a renderer that enables one needs the same treatment.
- **FSR SDK change.** A compositor's motion-vector request now also waits while
  the FSR SDK prepares; before, it forced the synchronous path.
- **Jittered fallback.** Fallback frames keep the camera jitter without
  resolving it, as on the existing FSR SDK path.
- **Unchanged synchronous paths.** Multiview/XR, the debug motion-vector view,
  and compositor effects without a temporal mode keep their previous
  synchronous compilation.
- **Ordinary-shader stall.** Materials whose generated code changed still
  compile their ordinary shaders on first draw: 7–8 s in one frame for the
  1.34.0 terrain on this machine, with or without a temporal mode. That frame
  stays within the regression's limit, but Windows may briefly show the window
  as not responding. Removing it needs separate work.
- **Coverage.** The menu does not run frame generation (`RtxGraphics` keeps it
  off outside the campaign), so DLSS-G after preparation is covered by the
  campaign frame-generation checks, not by this fixture.
