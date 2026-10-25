# Dar Leanos walking, 2026-10-25

Work in progress: renderer fixes below are validated; combined CPU-branch measurements and final recording will be appended before completion.

## Confirmed causes and changes

- Crowded moving figures packed the same PT motion record two or more times per frame. Coalesce final records, while retaining deformation rejection and stopped-motion retirement.
- Live topology polls scanned thousands of parts synchronously (20–35 ms in the Dar profile). Continue a scan across frames with a 500 microsecond target per controller; one root can exceed that target. Fresh candidate validation remains synchronous.
- The retained scene exceeded 4,096 placements while walking (about 4,200–4,300). Replacements failed with `snapshot_budget` and kept the old region. Raise the placement cap to 8,192, within the existing exact identity encoding. Triangle, texture and radius budgets remain unchanged.
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
