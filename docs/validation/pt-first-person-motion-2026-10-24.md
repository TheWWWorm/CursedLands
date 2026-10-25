# PT first-person body and movement validation — 2026-10-24

The first-person body is shifted at the renderer to keep its collar clear of the
eye camera. Scene RT/PT previously tracked the Node3D transform, which excludes
that presentation offset. As animation and camera angle changed the offset,
lighting receiver lookup could reject the visible chest and arms and fall back
to conventional lighting.

Scene tracking now finishes the current body alignment after DirectPose and
applies the visible transform to those camera receivers. Both native and script
trackers use the same correction. Complete shadow/GI and reflection copies retain
their authored transforms. Unchanged instances do not generate redundant updates;
leaving first person restores the ordinary placement. No shader/ray counts, DLSS
settings, normal player defaults or player-facing strings changed.

## Reproduction and rendered validation

The preceding build at `87a9c578` fails the same completed-frame probe: maximum
body/trace disagreement is 0.153876 m. Four instrumented
body captures reject 66–80% of classified body samples. The corrected build has
zero transform disagreement in all qualifying location routes. Body rejection
falls to zero in the Vulkan ruins, cave and desert samples; the Windows DLSS
and script-fallback samples contain at most two classified edge samples per
capture (under 0.01%). Green/magenta instrumentation runs in the production
receiver shader, with the same original meshes and camera.

Prepared routes cover grassy Gipat ruins (`gz1g`), snowy slopes beside the river
(`zone11`), the fire/brazier corridor in `gz14k`, and the desert at `gz15h`.
Each runs 540 held, walking, turning, crouching and first/third-person transition
frames at a 3840×2160 display resolution, 50% internal raster and Low PT
(960×540), with two bounces and responsive accumulation. The Windows snowy route
uses actual DLSS Performance SDK evaluation and records zero SDK errors.
PNG sequences and full-resolution checkpoints were inspected for lighting
dropout, surface instability and view changes. Native full-body water reflection
regression also passes.

## Live traversal

Separate campaign routes use the ordinary single-player simulation process and
real movement, combat, looting and self-healing orders. They travel from the ruins
down the wooded hillside to the beach, with rain, camera switches, pause/resume
and a still-scene accumulation transition. First-person eye view is used through
the ruins/hillside fights and on the final uphill look; the later beach section
also exercises tactical view. Ultra effects are enabled.

- linux: 6128 sampled frames, 253.3 seconds, 130.9 metres; zero PT/NRD inactive frames.
- windows: 5061 sampled frames, 221.5 seconds, 120.1 metres; zero PT/NRD inactive frames.

These figures describe coverage, not performance: visual readbacks can stall and
the diagnostic stages cap rendering at 30 FPS. All GPU runs used automatic GPU
Lab assignment. Profiles were isolated, cursor confinement disabled, FPS visible,
and all game audio muted.

## Checks

The exact exported packs pass 459 checks. The paired JSON preserves
runtime/fixture/report hashes, route stages, SDK status and baseline failures.

| Qualifying run | Checks |
| --- | ---: |
| candidate-native | 285 |
| candidate-vk-first-person-v2 | 11 |
| final-vk-cave-v2 | 12 |
| final-vk-desert-v2 | 12 |
| final-vk-script-tracker | 12 |
| final-dx12-dlss-river-v2 | 14 |
| final-vk-reflections | 9 |
| final-vk-route | 26 |
| final-dx12-dlss-route-warm | 78 |

The final scene probes compare completed frames; earlier probe revisions sampled
before SceneRaytrace updated or read the NRD working flag during reconstruction.
The cave navigation probe was also corrected to choose an actual traversable
corridor. Those earlier runs are recorded as diagnostics rather than passing
qualification. The runtime pack is unchanged across those fixture corrections.

## Limits

Windows execution used Proton/VKD3D on Linux with the original DLSS SR DLLs.
Native Windows and DLSS frame generation were not exercised. An initial cold
Ultra-effects Proton load lost the separate simulation owner while loading;
the completed Windows traversal uses that test profile's warmed shader caches.
Cold-start stability on native Windows remains unverified. This fixes a measured
first-person lighting defect and qualifies the listed routes; it does not prove
every possible shimmer or visual artifact is eliminated.

The earlier lighting, material/effect and texture-footprint fixes remain included,
along with upstream Windows fix `bab580bd`. This is a local test build based on
1.28.0, not a published release.
