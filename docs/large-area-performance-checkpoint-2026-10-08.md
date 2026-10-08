# Large-area and desktop performance check — 8 October 2026

No production code changed in this check. The game remains at retained checkpoint `bc50825`; all 520 game files match its measured freeze. The same private production APK54 is used throughout Retroid testing. The new benchmark fixture and this evidence are versioned separately.

## Retroid Pocket 5: Original / 1× single-player

The main sweep attempts two 120-second runs per additional area in reversed order, plus a Portal reference. Only runs with a living, moving party throughout enter the table. Suslanger has one valid full run because its second attempt loses a character; City Environs is retested with a revised route. These are normal movement commands and a rotating terrain-aware camera on fully populated maps. Actual Original graphics, a 1920×1080 display at 75% render scale, OpenGL ES, four native workers, difficulty 0, Distant AI off and the default Android scheduler are held constant. No health, enemy, population or gameplay rules are altered.

| Area | Valid runs | Average FPS range | Median p95 / p99 frame, ms | Ten-second FPS range | Simulated seconds per 120 real seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Suslanger | 1 | 50.63–50.63 | 25.139 / 28.581 | 45.7–54.9 | 119.735–119.735 |
| River and Islands | 2 | 48.94–49.19 | 27.587 / 34.591 | 45.1–53.9 | 119.845–119.845 |
| City Environs | 2 | 56.77–57.00 | 21.611 / 24.636 | 51.3–59.9 | 119.900–119.955 |
| Dead City | 2 | 59.86–59.86 | 19.410 / 20.620 | 59.0–60.1 | 119.900–119.900 |
| Portal reference | 1 | 54.28–54.28 | 25.223 / 28.281 | 51.3–57.2 | 119.900–119.900 |

Dead City is close to the handheld target in this bounded walk. Suslanger and River and Islands remain around 50 and 49 FPS respectively despite keeping normal simulation time. Average FPS does not imply every frame meets 16.67 ms; frame percentiles and transient stalls remain visible in the validation.

These fixtures use fresh authored map populations, the supplied Lost in Astral party/progress and authored entrances. They are bounded entrance walks, not coverage of every view or heavy combat encounter. The initial Suslanger route, the second short Suslanger run and both longer City Environs routes and both short entrance-1 routes killed the low-health party; their full averages are excluded and their logs/results retained. The validated Suslanger loop is eight metres along the entrance road; City Environs is retested separately from authored village entrance 5, walking sixteen metres into the area and back; its original entrance-1 attempts remain excluded. No deaths are hidden by modifying actor health.

## Desktop: accumulated Retroid improvements versus Experimental 5

The control is the exact published Experimental 5 Linux engine, pack and native helper (`fc06dcc`). The candidate is the production `bc50825` game in `throughput-worker-cadence02`. Both use Ryzen 9 5950X / RTX 3090, Linux/Vulkan, the real `:0` display, max remake settings, 100% render scale, 2× speed, two-player co-op and the same Portal route. All eight effective-options dictionaries, camera starts, player counts and party survival are checked. The sequence is candidate/control/control/candidate at each resolution.

| Workload | Experimental 5 FPS (median; range) | Latest FPS (median; range) | Median change | Worker CPU change |
| --- | ---: | ---: | ---: | ---: |
| 4K, four × 180 s | 57.59; 55.08–60.10 | 58.14; 57.58–58.70 | +0.96% | -10.76% |
| 1080p, four × 120 s | 106.37; 105.95–106.79 | 159.63; 157.98–161.29 | +50.07% | -10.75% |

The 4K FPS ranges overlap substantially: there is no convincing FPS gain or regression at 4K in these measurements. At 1080p, the latest median rises from 106.37 to 159.63 FPS (+50.07%), with both latest repeats above both controls. This is a clear complete-game FPS gain from the accumulated changes, while the 4K graphics workload masks that gain. The validation records every repeat, p95/p99, ten-second ranges and process CPU usage rather than relying on a best run. All accepted desktop runs retain all 416 actors, two players and three living party members, with approximately 360 simulated seconds per 180 real seconds or 240 per 120.

Point observations show the game can saturate the GPU. It shares that GPU with the desktop compositor and Codex; other Godot games are guarded against, but ordinary desktop graphics activity is not eliminated. This limits interpretation of small differences at 4K. GPU timing reads that synchronize the game are disabled. Native frame-time measurement is unprofiled, and the Android device can run independently while the desktop measures.

This is Linux/Vulkan evidence. It does not validate Windows/D3D12 on the user’s 7945HX/4090 Mobile, resolve the reported approximately 40 FPS at 4K, or turn the older 100+ FPS lower-resolution claim into a 4K result. Windows runtime validation and the 4K graphics bottleneck remain open.

## Reproduction and evidence

Use `tools/benchmarks/large_area_gameplay.gd` and its two versioned base scripts as described in the benchmark README. Proprietary assets/saves remain outside the repository; their hashes, fixture revisions, package hashes, settings and raw artifact hashes are in [the validation](large-area-performance-validation-2026-10-08.json). The portable `$SCRATCHPAD` prefix refers to the local scratchpad root recorded by the handoff. Private orchestration and the archived failed fixtures remain in `portal-throughput-20261007/large-area-sweep`.

The private Android autorun is disabled and both private processes are stopped after testing. Production APK54 remains installed. The normal Android installation, user saves, public release and engine/native modules are unchanged. The CPU-placement experiment was deferred before changing affinity when the user requested this broader validation.
