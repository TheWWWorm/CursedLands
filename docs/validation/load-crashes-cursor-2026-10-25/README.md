# Load-time rendering failures and cursor coordinates

This follows the [full issue review and original-game comparison](../issues-109-112-2026-10-24/README.md). The gameplay and board fixes are in `493f5e15`; these additional changes address the supplied crash reports and console-coordinate mismatch.

## Supplied reports and source inspection

Both Windows 1.28.0 reports end in Direct3D 12 resource-descriptor exhaustion, failed/null uniform sets, and a failed GPU fence with device-removed reason `0x887a0006`. Both last identify the Lost in Astral map `gz1h`. The reports contain the last 5,000 log lines, starting inside an error storm, rather than the complete loading history. [Hashes, counts and line references](report-summary.json) preserve the relevant evidence without copying the full machine reports into the repository.

| Report | Resource-heap errors in retained tail | Null uniform-set errors | Terminal fence failure |
|---|---:|---:|---:|
| `CursedLands-report-20261024-234059.txt` | 2 | 2,492 | 1 |
| `CursedLands-report-20261025-004033.txt` | 7 | 2,478 | 1 |

The corresponding engine source explains the failure path:

- `RenderingDeviceDriverD3D12::uniform_set_create` allocates a contiguous range from the resource descriptor heap. An allocation failure returns an invalid set after printing the exact message in both reports. This explains missing draw bindings and is consistent with the reported black surfaces.
- `DescriptorHeap::free` returns ranges to D3D12MA, and `uniform_set_free` releases its resource range and sampler reference. The project had no override for the driver's 65,536-entry default.
- `MaterialStorage::global_shader_parameters_instance_allocate` reserves 16 shader-buffer entries per instance. A failed reservation is retained as `-1`, so later retries on the same instance also produce the duplicate-allocation diagnostic.
- `Session._build_world` creates the replacement before `Game.attach_world` queues the outgoing world for deletion. The resulting overlap, plus deferred GPU destruction, must fit in both allocations.

The supplied tails do not contain the second shader-instance-buffer error. It was discovered independently during the reproduction below. No conclusion about the crashed session's memory growth is drawn from the reports' *new-session* performance record.

## Change

| Allocation | Before | After |
|---|---:|---:|
| D3D12 resource descriptors | 65,536 | 262,144 |
| Global/instance shader-buffer entries | 262,144 | 524,288 |

The shader buffer grows from 4 MiB to 8 MiB in RenderingDevice renderers; each entry is a 16-byte value. Compatibility continues to apply its existing hardware clamp and material-uniform fallback. The descriptor heap is a separate binding allocation, not a texture-memory quota. No threading, world-retention, loading-cover, graphics preset, or player-preference changes are required.

`cursor` now calls the same terrain/BASE-face projection as gameplay orders and prints EI map x/y plus a directly usable `teleport x y` command. It rejects loading/stale worlds, nonfinite points, and positions outside the map. Formatting truncates to three decimals so a point at the outer edge cannot round up to teleport's excluded boundary. When no map ground is available, it explicitly labels the existing pixel coordinates. Help and statuses have EN/RU/DE translations; command permission rules are unchanged.

## Before/after evidence

The baseline run used the standard Windows 1.28.0 executable and the preceding issue-fix PCK, with the original allocation settings. The first `gz1h` load succeeded. Reloading it exhausted both allocations. Five completed load samples were retained before cancelling the already-failing run: `gz1h`, `gz1h`, `gz2h`, `bz2h`, `gz1h`. Old-world weak references were cleared after each replacement, and the resource count stayed at 631. This establishes a transition-capacity failure in the tested path, rather than retained world nodes accumulating on each reload.

[Baseline error counts](checks/baseline-error-counts.json) include 842 resource-heap allocation failures and 530 instance-buffer exhaustion errors. [The compact log](checks/descriptor-baseline4.txt) retains the first occurrence of every error with context and every completed load sample; [raw sample data](checks/baseline-reload.json) is separate. The supplied reports' terminal device hang was not reproduced or deliberately induced. Settled baseline screenshots recovered normal ground rendering despite the errors during loading; no screenshot is presented as proof of the reported persistent black ground.

The synthetic [descriptor-budget test](../../../tools/tests/d3d12_descriptor_budget.gd) allocates 2,048 sets of 64 storage-image descriptors, releases them, waits for deferred disposal, and repeats three times. The baseline can allocate only 1,023 / 1,022 / 1,022 sets and emits the same resource-heap failure. The repaired heap allocates all 2,048 on every pass. This separately verifies capacity and reclamation; it is not a simulation of a player save.

The repaired Windows run completed **12 loads** (`gz1h`, `gz1h`, `gz2h`, `bz2h`, repeated three times) with **zero descriptor, shader-instance or null-uniform errors**. Every outgoing world was freed; resources stayed at 631. Figure caches reached a plateau (2,016 meshes / five materials). Warm per-map VRAM stayed near 921 / 884 / 1,067 MB rather than increasing on every return. [Samples](checks/load-fixed-descriptor-reload.json), [log](checks/load-fixed.txt), and [last-cycle screenshots](rendering/) are retained.

The final two-peer Windows check completed **four `gz1h` loads**, with both host and guest cameras rendering loaded terrain. Both worlds reached each new generation, old worlds were freed, resources stayed at 632, and VRAM settled from 1.223 GB to 1.165 GB. No game-allocation or script errors were recorded. [Samples](checks/load-coop-rendered-final-descriptor-coop.json), [log](checks/load-coop-rendered-final.txt), [host](rendering/descriptor-coop-host.png) and [guest](rendering/descriptor-coop-guest.png) are retained. This validates the crash/cursor PCK; subsequent path/snow/tutorial changes were tested separately.

Earlier co-op fixture attempts exposed teardown RPC calls and a 114-second cold D3D12 compilation stall that exceeded ENet's 60-second timeout. The fixture now stops peer processing before closing sockets and extends its loopback peer timeout to 300 seconds after admission. Production networking is unchanged. A sky-only guest capture was rejected; the accepted run explicitly places both cameras over their loaded party. These corrections avoid counting a disconnected or unrendered guest as successful co-op rendering.

## Cursor validation

The existing cursor suite passes 27 headless and 30 graphical checks, including real pointer movement, sampling while closed/paused/slowed, interval validation, output retention/export, completion, and a narrow German console. The new terrain/teleport integration passes 23 headless and 23 graphical checks. Each language's generated command is executed through the existing console-command handler and verified against the actual character position. Client-side coordinate inspection, loading rejection, an outside-viewport point, and the closed-campaign fallback are included.

The first graphical version of the new fixture compared later samples with a camera projection captured before the loading screen finished resizing the viewport. Four assertions failed; the fixture now waits for presentation and computes each expected pick with the current camera. The production cursor code was unchanged by that test correction.

All 3,521 translation keys, 171 dynamic wiki keys and 199 dynamic arena keys pass coverage checks. The [six console captures](layout/) were inspected: map output at 1024×768 and fallback/help at 1280×800 in each language. Original archive text remains in the installation's language; remake console strings use the selected language.

## Reproduction and limits

Use a separate development profile with mouse confinement disabled, FPS visible, and SFX/stream/voice volume zero. All rendered runs use GPU Lab with automatic device selection, safe render threading, Dummy audio, and a 30 FPS cap. Windows checks use the standard released executable with a source-exported PCK, Wine 11.20, and VKD3D-Proton 3.1 on the assigned RTX 3090/3090 Ti. Optional upscaling/frame-generation SDKs are absent and those features are disabled. Virtual-display EDID/white-level and missing optional FSR-runtime warnings are recorded, rather than treated as game-allocation failures. No native Windows driver qualification is claimed.

Prepare the three rendering saves with `rendering_reload_fixtures.gd`, using Lost in Astral data and `--seed-save=/absolute/test.sav` on an isolated, headless profile. The source seed is a pre-existing local test fixture, not either user's unavailable crashed-session save. Its hash and the tested executable/PCK hashes are in [provenance](provenance.json). Copy the resulting `saves/lost_in_astral` into the isolated rendered profile, then run `rendering_reload.gd`. It drives the normal separate simulation process and frontend, takes a screenshot after each load, and records old-world lifetime, nodes, resources, caches and VRAM. `rendering_coop_reload.gd` instead uses two actual ENet peers and two rendered worlds in one process; sharing a RenderingDevice makes it an allocation stress case, not two independent PCs.

Run test scripts with `--tool=/absolute/repo/tools/tests/NAME.gd` after `--`, along with `--ei-path=/absolute/original/game --no-movies`. Use `--rendering-method forward_plus --rendering-driver d3d12` for the Windows tests. The cursor graphical tests also run on OpenGL, with `--display-driver x11` on Linux. Logs and snapshots are test evidence, not a release package.
