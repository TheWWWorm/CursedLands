# Experimental 3 integration

This release combines Experimental 2's CPU work with the completed Lost in Astral fixes and the latest snow/sand trails. It includes direct location travel, movie narration and silent-cache rebuilding, NPC equipment and faces, invisible boundary blockers, quest items in the belt, shared border fog and continuous ground deformation. The changelog lists the individual changes.

The AI activity scheduler, native libraries and navigation kernel are identical to Experimental 2. The footprint merge retains its typed per-unit state and the authoritative corpse effects. The new contact tracking uses that same state, so it does not restore the older per-frame dictionaries or local corpse timers.

## Runtime comparison

The combined build was compared with Experimental 2 on Linux, using the same patched engine, Ryzen 9 5950X and RTX 3090. River and Islands had 239 units, the same starting camera, 1280×720 rendering at native scale, normal enhanced graphics and Distant AI off. Each run warmed up for 180 simulation ticks and measured 20 seconds without a frame cap. Two interleaved runs per build were made at each speed; the main thread used CPU 15 and workers CPUs 10–13. No other game engines ran during the measurements.

| Speed | Experimental 2 mean FPS | Experimental 3 mean FPS | Difference | Main-thread CPU per frame, 2 → 3 |
|---|---:|---:|---:|---:|
| Normal | 121.99 | 116.35 | −4.62% | 7.66 → 8.11 ms |
| Double | 61.32 | 59.31 | −3.28% | 15.12 → 15.69 ms |

Individual FPS results were 120.70/123.29 versus 108.90/123.81 at normal speed, and 59.02/63.62 versus 61.56/57.05 at double speed. Ambient simulation varies between runs, and these ranges overlap. These measurements do not isolate the cost of each fix or establish performance in large battles or snow-covered scenes. Occasional navigation stalls remain; the longest measured frames were 568 ms in Experimental 2 and 550 ms in Experimental 3.

The earlier [Experimental 2 measurements](performance-experimental-2.md) describe that release's comparison with Experimental 1. Its reported gains are not a new measurement of this combined release.

## Validation

The packaged Linux build passed 869 assertions across 21 fixtures: the ordinary expansion opening and recruiter round trip, NPC equipment save/reload and network records, faces and invisible blockers, quest-item UI in both campaigns, movie sound/cache behavior, foot-contact alignment, 36 moving legged races, trail lifetime/resource limits, and rendered fog and terrain displacement. Vulkan Forward+ and OpenGL Compatibility were exercised. NPC faces, real map scenes and snow/sand captures were also inspected visually.

The merged source passed the native and script AI activity fixtures, real-map reactive AI, hidden-animation and timeline guards, and corpse save/ENet checks. Localization checked 640 translated texts with no warnings. Every platform archive passed its resource/license audit, and all five contain the same 198 compiled game scripts. Android uses version code 14 and the same signing certificate as Experimental 2.

An initial OpenGL analytic fog check sampled its camera during interpolation after a teleport. At the failing sample, the requested depth was 100 metres but the rendered camera was still at 99.62 metres. Disabling interpolation on that synthetic test camera made the exact-depth assertions pass without changing production code or pixel tolerances. The private display emits input-method warnings; OpenGL also reports its unsupported VSync and screen-space AA settings.

## Options and compatibility

Snow and sand deformation uses its existing graphics option. It is enabled by capable-desktop defaults and disabled by Android defaults. Trails have finite geometry and history caches, fade within four minutes and are cleared on leaving a map or loading a save. They do not change collision or navigation.

Save format and co-op protocol remain unchanged. Use the same experimental version on every peer. The first Lost in Astral quest starts after the recruiter conversation and return to the field; its first objective has no marker in the supplied opening-map data. Later authored quest markers retain their usual behavior.

Full campaign playthroughs and Windows, macOS and Android device testing are not established by the focused Linux checks.
