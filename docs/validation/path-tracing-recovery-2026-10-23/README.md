# Path-tracing recovery and sustained qualification

23 October 2026. Source checkpoint `3a4af9bc`, built on the speed/motion work in `7102e779`. Native Vulkan and DX12 through Wine completed full qualification and 1440p performance comparisons on physical GPU 1. This is a qualified development checkpoint for the tested configuration.

## Changes

Scene recentering keeps the current output active while one replacement is collected, built and rendered. The replacement is published only after its full first frame succeeds. Cancelled and retired builds cannot reactivate lighting through stale callbacks. Failed initial builds recover with bounded backoff; unchanged over-budget content retains a lightweight source watch and waits for changed inputs or camera movement.

Target resizing allocates images and descriptor sets transactionally, and keeps the four previous public outputs alive until the replacement has rendered successfully. Frame uploads, morph uploads and history copies are checked. Failure invalidates history and returns control to the conventional-lighting fallback. Fault injection covers individual and combined failures; it does not provoke physical OOM or driver loss.

The last complete published image remains ready while a sampler, pipeline, resize or emitter update resets temporal confidence. Readiness no longer follows the transient history flag, which could suppress the controller's camera-matrix updates during a separate-thread render. The lifecycle fixture verifies unchanged published pixel bytes through these operations and fresh history after rendering resumes.

Queued build, render and disposal operations now explicitly retain their device owner. Deferred device notifications also retain their source until main-thread delivery finishes. Ordinary method callables and signal values contain weak object identifiers; they do not keep a `RefCounted` target alive. This affected both scene/PT lighting and the shared water-reflection controller. The lifecycle regression blocks the real separate render thread, drops the final main-thread owner, then requires ordered native build/render/disposal, freed GPU images, delivered notifications and final owner release. A weak ordinary callable is its negative control.

Detached combat parts register their actual copied meshes for ray geometry, including transform/visibility updates and removal on expiry. Terrain source versions include the identity of ready normal/macro textures and the edge-blending mode.

The repository-owned [qualification runner](../../path-tracing-qualification.md) freezes fixtures, records build hashes, verifies physical GPU UUIDs and isolated test settings, enforces timeouts through teardown, and rejects partial or unsupported runs. It includes repeated live renderer/scale transitions, actor movement, two campaign zones, generated save/load and resource-lifetime checks.

No player-visible strings, saved options or player defaults change in this checkpoint. The previous EN/RU/DE option/help coverage remains applicable. No release is published or renumbered.

## Hardware and scope

Physical GPU 1 is NVIDIA GeForce RTX 3090 Ti, UUID `GPU-0eee028e-b998-532f-095b-e936c7f6191d`, driver 580.178.04. Runs use a private GPU-backed Xorg `:97` virtual screen at 2880×1800. Native Linux uses Vulkan; the Windows bundle runs DX12 through Wine/VKD3D. Other applications are preserved.

Final qualification preserves the project's production thread settings: separate rendering on Linux and Safe rendering on Windows. Runtime evidence verifies the actual main and render-callback thread identities. Earlier Safe-mode Vulkan runs are supplemental evidence, not the production-thread qualification.

Every test profile uses `confine_mouse=0`, `show_fps=1`, and zero SFX, stream and voice volume. The native virtual screen's exact refresh-rate query error is retained as an allowed diagnostic; other runtime, script and GPU errors fail qualification.

These results qualify only the tested configuration. They do not establish native Windows recovery, resolve the separately documented native Windows device-loss reports, certify other GPU vendors, or replace a full campaign playthrough. The bounded renderer and reconstruction limitations remain in the [integration notes](../../integrations/path-tracing-experiment.md#limits-and-qualification).

## Results

The final runs passed **55 suites / 2,902 checks** on source checkpoint `3a4af9bc`, including clean process-group exit and unchanged executable, pack and recursively fingerprinted runtime libraries. Two additional performance runs passed 51 checks and all 16 measurement blocks.

| Backend | Suites | Checks | Result |
| --- | ---: | ---: | --- |
| Native Linux Vulkan, separate render thread | 27 | 1,369 | Pass |
| Windows DX12 through Wine, Safe render mode | 28 | 1,533 | Pass |

DX12 includes all seven production FSR/frame-generation presentation phases (76 checks), with actual generated/presented frame counters, HUD, resizing, pause and renderer transitions. Every suite confirmed physical GPU 1 by UUID. The runner's 20 CPU failure-path tests, ownership probes in both thread modes (7 checks each), weak-reference regressions on stock and qualified runtimes (4 checks each), and exact hold-accounting replay (10 checks) also passed.

Both sustained runs completed **six cycles, 42 renderer transitions, six generated save/load roundtrips and 19 device retirements**, with no failures. Every ready-output hold completed within the unchanged recovery bound. The DX12 run also passed all 18 actual FSR 3.1 readiness gates.

| Sustained result | Native Vulkan | DX12 through Wine |
| --- | ---: | ---: |
| Checks | 352 | 389 |
| Fixture duration | 427.5 s | 740.4 s |
| GPU allocation growth, cycle 2 → 6 | 5.50 MiB | 8.67 MiB |
| Host RSS growth, cycle 2 → 6 | 221.54 MiB / 4.63% | 65.80 MiB / 2.00% |
| Object count change | +81 | +142 |
| Resource count change | 0 | 0 |
| Node count change | −4 | 0 |

All allocation and lifetime gates passed, and both processes exited without forced cleanup or surviving live descendants. These are bounded growth observations, not a proof that every allocation path is leak-free. Raw samples and budgets are retained in each sustained fixture and runner report; missing static-allocation counters remain explicit.

The first live DX12 FSR phase required **89.1 seconds** of cold temporal-shader/pipeline preparation before its readiness gate passed. FSR 3.1.5 context creation itself took 517 ms. The resolution fixture had already warmed the same advanced shader group through native FSR2 phases, so its subsequent SDK gates completed in 611–671 ms. Engine source confirms that first temporal use enables the advanced group for existing shader versions and then waits for material pipelines; the exact split within the 89.1 seconds was not separately instrumented. The readiness limit remains 180 seconds, and actual successful SDK evaluations are required. This checkpoint does not claim to eliminate that first-use preparation delay.

## 1440p performance

The comparison changes only the old window-relative PT grid versus the applied-render-resolution grid inside the same committed build. It retains the same detailed river scene, acceleration structures, four-bounce mode, responsive history and raster upscaler. Water reflections and frame generation are off. Each backend records two alternating rounds, 120 samples per block after 45 warm-up frames. Values below are the mean of the two block medians; raw medians, p95 values and stage timings remain in the reports.

| Backend / upscaler | Quality | PT GPU ms, window → render grid | PT time reduction | Total frame ms, window → render grid |
| --- | --- | ---: | ---: | ---: |
| Vulkan / FSR 2 Quality | Low | 2.482 → 1.184 | 52.3% | 4.257 → 3.056 |
| Vulkan / FSR 2 Quality | Medium | 13.300 → 6.079 | 54.3% | 15.241 → 7.982 |
| DX12 / FSR 3.1 Quality | Low | 3.104 → 1.517 | 51.1% | 5.947 → 4.243 |
| DX12 / FSR 3.1 Quality | Medium | 17.039 → 7.822 | 54.1% | 19.576 → 10.177 |

Medium total frame time decreases by 47.6% on Vulkan and 48.0% on DX12 in this controlled workload. This establishes the resolution optimization's retained benefit after the lifetime/recovery changes; it is not a universal campaign FPS estimate. DX12 blocks also require at least 110 actual SDK evaluations each. Normalized image mean absolute error is 0.0038–0.0047, with mean energy ratios of 1.0006–1.0016. Visual inspection of the saved comparisons found no missing lighting or geometry; fine sampled detail varies with the reduced grid.

Medium Vulkan [window-grid reference](qualification-vulkan-benchmark-final-03/quality-1-window-reference.png) and [render-grid result](qualification-vulkan-benchmark-final-03/quality-1-render-resolution.png); Medium DX12 [reference](qualification-dx12-benchmark-final-03/quality-1-window-reference.png) and [result](qualification-dx12-benchmark-final-03/quality-1-render-resolution.png).

## Reproduction and evidence

[summary.json](summary.json) contains the source hashes, exact source commit, per-suite counts and calculated performance comparisons. The final [Vulkan manifest](manifests/qualification-vulkan-final-03.json) and [DX12 manifest](manifests/qualification-dx12-final-03.json) retain commands, GPU UUID observations, runtime settings, actual thread identities, complete suite results and immutable-input checks. Each backend folder contains raw fixture reports, process logs and GPU/RSS telemetry. Benchmark folders contain all eight blocks and full-resolution comparison captures. Use the [qualification workflow](../../path-tracing-qualification.md) to repeat the tests with a new isolated profile and evidence directory.

The [ownership-crash analysis](ownership-crash/symbolication-findings.md) retains the exact native/VM evidence behind the fixed teardown crash. CPU evidence includes the [20 runner tests](qualification-cpu-tests.log), [hold-accounting replay](hold-accounting/README.md), ownership probes and weak-reference regressions. Preliminary failed runs are preserved separately and excluded from final pass totals. The large crash core, exported binaries and isolated profiles remain in the local artifact directory recorded by the summary; they are not copied into this report.

## Rejected preliminary runs

The first production-thread qualification completed all 104 resolution assertions, wrote its report, then crashed during game teardown. Two GDB reproductions localized the fault to `scene_raytrace_device.gd::dispose`: its first `_published_valid=false` assignment executed after the script instance's member storage had been destroyed. The native assignment destination was `0x348` (member 35 × 24 bytes), with null member storage. The queued method callable had not retained the device. This is a confirmed production ownership bug, separate from the fixture-only compiler retention issue below. The failed run is excluded even though its assertions passed. The retained dispatch and notification fix addresses the lifetime directly without changing engine thread defaults.

The first sustained Vulkan run was interrupted after its workload gate showed render scale remained at 1.0. Its fixture changed the saved option without applying the window/render options. The fixture now calls the production application path before waiting for the requested effective scale. This run is excluded from successful qualification. It did confirm the requested physical GPU UUID and isolated runtime settings.

Subsequent preliminary stress runs exposed three fixture issues: the engine's native FSR 2 scale is 0.67 rather than exactly two-thirds; a Godot compiler temporary could retain a device reference across an asynchronous weak-reference test; and a blind timed hold could sample a legitimate topology rebuild before output returned. The scale expectation now uses the applied production constant. A standalone CPU regression reproduces the temporary retention and requires synchronous weak capture to release before coroutine completion. The live hold now records real ready frames, output sizes and fallback intervals, requires a full uninterrupted ready interval, and fails if recovery exceeds its bounded window. Actors and ordinary simulation remain active.

These rejected runs remain excluded from pass totals. Neither the compiler diagnostic nor a disposed Texture2DRD's stored RID alone is treated as proof of a live GPU allocation; retirement gates observe owner disappearance and actual resource validity.

The next separate-thread stress run maintained valid output for all 2,229 counted frames in its failing hold, with no output/device/generation boundary. Its 288 apparent interruptions came from `frame_post_draw` notifications arriving before the main-thread rendered-frame counter advanced. The fixture now records these notifications separately: they earn no frame/time credit and preserve an otherwise valid interval. Actual mismatches still reset the interval, and the original wall deadline and per-frame credit cap remain in force.

Release builds do not expose Godot's static allocation counter here. Missing counters remain explicit, and object/resource/node plus available GPU allocation trends and per-process RSS telemetry provide the available memory evidence.
