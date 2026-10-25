# Dar Leanos walking, 2026-10-25

Renderer fixes are combined with the validated campaign CPU work from `ef6cc817` and `9101324b` in integration commit `6f32b8fc`. The combined fixed-route comparison and Windows rendering checks passed. The final full-viewport Windows recording also passes all 76 traversal assertions, with per-phase diagnostic readbacks disabled.

## Confirmed causes and changes

- Crowded moving figures packed the same PT motion record two or more times per frame. Coalesce final records, while retaining deformation rejection and stopped-motion retirement.
- Live topology polls scanned thousands of parts synchronously (20–35 ms in the Dar profile). Continue a scan across frames with a 500 microsecond target per controller; one root can exceed that target. Fresh candidate validation remains synchronous.
- The retained scene exceeded 4,096 placements while walking (up to 4,383 in the final route). Replacements failed with `snapshot_budget` and kept the old region. Raise the placement cap to 8,192, within the existing exact identity encoding. Triangle, texture and radius budgets remain unchanged.
- The 128 MiB CPU source cache filled and evicted mesh/texture readbacks during adjacent snapshots. Increase its hard budget to 256 MiB. RT water now retains the same bounded source cache and ground cache across recentering and releases them on teardown.
- The revive overlay performed mouse hit-tests with the pointer hidden in direct control. Match the existing cursor policy; progress bars continue to update.

The original game has neither PT/RT-water acceleration structures nor the remake first-person/revival overlay. A corresponding original-game Wine comparison is inapplicable for these paths. The prechange remake (`cbe0bec9`) was compared under Wine/D3D12, and shader identity behavior was tested with the native Vulkan renderer. The CPU branch records its separate original-code and Wine comparisons.

## Regression evidence

Baseline tests fail: motion packing 3/12, incremental topology 2/13, dense scene 5/8, water cache 3/16, source cache 2/12, hidden-pointer overlay 4/9. Fixed tests pass, including motion identities through 8191 (66), topology and scene lifetime (130), moving shadows (12), history handoff (13), and live water (15). All are registered. The topology test explicitly updates the intentional placement limit from 4096 to 8192; dense-scene hard overflow remains tested.

`final-regressions.json` contains one GPU queue timeout before the water test started; `final-followup.json` reruns that case successfully (16 checks) and validates the overlay (9). The earlier unsupported `--main-pack` runner attempt was an infrastructure failure, not a game result.

## Controlled renderer-only comparison

`renderer-fixed-comparison.json` and `fixed-before/`, `fixed-after/` hold the same four-waypoint route on one RTX 3090 GPU Lab heavy job (`d65cae030a4a48cf`). Windows D3D12 under GE-Proton, 1920×1080, PT/native NRD, 334 authored actors, live AI, separate solo worker, real W steering. Neutral diplomacy and god mode isolate traversal; camera steering is scripted. The fixture is uncapped with `--dar-benchmark`; its inherited generic note incorrectly says 30 FPS. Initial shaders use the same warm cache seed. FG is off for the first two legs and on for the last two. FPS below counts rendered frames, not generated presentations.

| Leg | Before FPS | Renderer fixes FPS | Before p95 ms | After p95 ms |
| --- | ---: | ---: | ---: | ---: |
| 0 | 21.9 | 23.0 | 64.070 | 51.913 |
| 1 | 22.1 | 25.9 | 65.371 | 62.163 |
| 2 | 23.2 | 23.8 | 62.593 | 51.191 |
| 3 | 23.4 | 24.1 | 65.086 | 53.544 |

This is a modest improvement, and large scene activation spikes remain. Larger gains from earlier adaptive exploratory routes are excluded because route branches diverged. The renderer-only candidate predates the overlay gate. A 4K attempt failed the asynchronous window-size assertion; it provides no valid 4K FPS result. Hardware and Wine differences prevent equating these numbers with the supplied RTX 4090 Laptop Windows recordings.

Raw diagnostics and local-only runtime/recording files: `/home/llm2x/Documents/EI/local/scratchpad/ei1-investigation-20261025/dar-leanos`. No runtime or optional FG binaries are part of this evidence commit.

## Combined CPU and renderer comparison

`combined-fixed-comparison.json` records a four-run ABBA comparison on one RTX 3090 Ti, GPU Lab heavy job `24e6ee30449940c4`. All runs pass 76 assertions (304 total); every walking frame retains PT/native NRD, first-person body, usable controls and live solo authority. There were no route detours or stalled-route retries in the accepted runs. The same fixed fixture, warm-cache seed, graphics settings, actor population and real key input were used. The test is 1920×1080, uncapped. The nearby Windows renderer and extension hashes are recorded separately.

| Walking leg | Baseline FPS | Combined FPS | Baseline p95 ms | Combined p95 ms |
| --- | ---: | ---: | ---: | ---: |
| 0 | 24.48 | 28.59 | 59.05 | 44.05 |
| 1 | 24.77 | 31.26 | 61.63 | 44.22 |
| 2 | 26.37 | 29.20 | 58.32 | 44.09 |
| 3 | 26.52 | 27.88 | 57.00 | 46.34 |

Values in the table average the two runs per build. Across all walking phases, rendered frames divided by measured wall time rose from **25.51 to 29.25 FPS (+14.6%)**. FG is off on legs 0–1 and on on legs 2–3; generated presentations do not count toward these FPS measurements. The complete reflection/lighting region now updates; baseline stays at generation 1 after `snapshot_budget`. The retained CPU source data reaches about 160 MB, which fits the new 256 MiB bound without repeated eviction.

This improves ordinary frame pacing but does not eliminate rebuild spikes: the largest combined walking frame was 215.8 ms versus 118.2 ms in the baseline. The baseline's later scene rebuilds fail early; the fixed build completes that work. Synchronous candidate preparation/activation remains an optimization opportunity. Do not describe this as stutter-free or a 60 FPS result.

The separate CPU chat held further timed runs for this comparison. Two short window-only probes ran on the other GPU with no loaded game world. Production actor AI, collision, geometry and rendering quality were retained. Neutral diplomacy and god mode are fixture constraints, so combat pacing and every possible crowd blockage are not certified by this route.

The first combined attempt (`combined-after-1/`) failed the 12-second arrival deadline on leg 1 after temporary movement obstruction. Its trace shows simulation advancing, inputs acknowledged, movement resuming, and the later legs succeeding. It is retained as a failed test and excluded from the accepted comparison. The fixture now allows 20 seconds while preserving the same waypoint and <1 m arrival assertion; it also logs nearby actors when blocked. Both builds were rerun from the same fixture. No production movement or collision behavior was changed to pass the route.

The isolated 4K window probe found Wine converting a screen-covering borderless window to fullscreen at 2880×1800. Shrinking to a smaller framed window and moving it off the screen origin before requesting the oversized borderless viewport preserves an actual 3840×2160 window. This only changes test setup; the service's display and GPU configuration stay unchanged. The same setup still fails the size assertion in the full game with the NVIDIA reconstruction/presentation path enabled (`dar-recording-4k*` failed logs). Those attempts are not valid 4K performance or gameplay results. A native Vulkan 4K pass subsequently completed with 54/54 checks; NVIDIA reconstruction and frame generation are disabled in that separate pass. The entire viewport is genuinely 3840×2160, confirmed by the actual window size and full-size still images. The video is a 1920×1080 central crop because the virtual display is smaller than the viewport. It is visual coverage, not a matched Windows/DLSS performance comparison.

`combined-cpu-checks.json` contains 28,998 successful native checks: script expressions (21,575), retained picking (2,209), batched mechanism picking (5,205), and revival overlay pointer/progress behavior (9). Previous GPU rendering checks remain recorded in the earlier reports.

Final Windows/Wine D3D12 checks also pass: all 66 temporal-motion/identity checks (including IDs 4096 and 8191), and all 9 authored snow/cache checks. Snow receiver coverage remained 99.15% after real deformed footfalls, with zero inactive PT frames. These results are in `combined-d3d-motion/` and `combined-snow/`; they supplement the earlier Vulkan renderer regressions.

## Recording

`recordings.json` records the complete 1920×1080, 60 FPS video and its SHA-256. The 71.5-second recording follows all four fixed waypoints (about 69 m), with frame generation off for the first half and on for the second. All 76 checks pass, with no blocked-route retries. Images retain the same rendering features and crowded map. Encoding capture overhead and concurrent workstation activity make video-overlay FPS unsuitable for comparing builds; use the unrecorded ABBA measurements above.

The maintained final fixture additionally passes the registered `dar_leanos_route` case on native Vulkan: **54 checks, zero failures**, with frame generation disabled and the ordinary 30 FPS inspection cap. `combined-registered-route.json` records the pack, source, script and command provenance.

The 4K native Vulkan run, `dar-recording-4k-vulkan/`, retains PT/native NRD and live controls on every recorded frame and reaches every waypoint. Its full-size `walk-2.png` preserves the entire viewport; the linked MP4 covers the central crop. This diagnostic run includes per-segment still captures, so its pauses are not representative of uninterrupted gameplay. The final Windows recording disables those readbacks.

The final video is `dar-leanos-final.mp4` (listed first in `recordings.json`). It uses the production route directly, without the diagnostic CPU profiler or per-phase PNG readback/encoding. All 76 checks pass, every waypoint is reached, and every frame remains controllable with PT/native NRD active. The game and FPS overlay are captured as rendered; no rate manipulation, frame interpolation in the encoder, or edited-out stalls are used. CPU video encoding still affects performance, so the benchmark remains the separate unrecorded comparison.
