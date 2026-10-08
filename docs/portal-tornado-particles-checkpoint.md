# Portal tornado particle checkpoint — 8 October 2026

Batching the existing tornado particle stage improves complete Portal gameplay
on Retroid at actual Original graphics / 1×. Two reversed 60-second comparisons
improve the median from **52.55 to 55.57 FPS (5.75%)**.
A matched three-minute comparison measures **53.95 → 55.89
FPS (3.60%)**. The change is retained on this full-game evidence.
**Stable 60 FPS remains open.**

## Change and fidelity

The existing native spell helper now handles tornado particle update, spawning
and delayed removal in one call per emitter. It removes repeated script callbacks
and per-particle emitter lookups. Ground-following controls still use the original
script and immutable ground snapshot. Existing particle workers retain independent
emitter arrays and RNG streams. Particle count, motion, fade, interpolation fields,
random draws, rendering and graphical quality are preserved. Custom callbacks and
older or absent helpers retain the script implementation.

The frontend profile motivating this experiment attributed 23–25% of particle
worker self samples to the tornado update callback. Faster isolated kernel times
were diagnostic only; the complete-game comparisons below decide retention.

## Complete gameplay

| Production run | FPS | p95 ms | p99 ms | Worst ms | Simulated seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Candidate 60 s / 1 | 56.36 | 22.941 | 25.917 | 50.828 | 59.950 |
| Control 60 s / 1 | 51.86 | 26.998 | 29.944 | 47.796 | 59.895 |
| Control 60 s / 2 | 53.24 | 24.428 | 28.228 | 53.903 | 59.840 |
| Candidate 60 s / 2 | 54.78 | 24.469 | 28.183 | 55.054 | 59.840 |
| Control 180 s | 53.95 | 25.889 | 29.093 | 50.196 | 179.850 |
| Candidate 180 s | 55.89 | 24.253 | 27.503 | 52.598 | 179.850 |

All six runs use 415 Portal actors, keep both party members alive and advance
simulation at 1×. Production APK49 is the control and APK50 the candidate.
Options are identical: actual Original look (all gfx switches off), 1920×1080
viewport, 75% render scale, OpenGL ES, four workers, difficulty 0, Distant AI off,
and separated single-player. The entrance walk uses normal movement commands
and the terrain-aware camera, without modifying health or actor population.
The longer candidate's ten-second windows range from 52.9 to 60.1 FPS;
its worst frame is 52.598 ms. This remains below stable 60 FPS.
The second short pair's p95 is effectively unchanged (24.428 → 24.469 ms),
despite its higher average FPS; the full frame-time results above remain part
of the acceptance evidence.

## Validation and limits

The independent retained script callbacks are the reference. The new fixture
compares every serialized particle and control field, flags, lifetime and RNG
state through 180 ticks across changing position, motion, height, lean, radius,
colors, emission settings, capacity and carrier state. It includes custom
callbacks and 24 concurrent emitters on four workers. **26,244 checks pass each
on stock Linux, packaged Linux Forward+, physical Retroid and an older-helper
fallback.** The existing modifier/orbit suite also passes **76,995 checks each
on Linux and Retroid** after sharing the kernel.

The first two test runs failed exact-state comparisons: GDScript parsed one long
decimal radius coefficient one ULP below the C++ compiler. Using the engine's
decimal parser for that constant fixed the discrepancy; the reference script
was not changed. These failures and the repair remain in the evidence record.
Linux, Android ARM64 and Windows x86-64 native modules build successfully.
The Windows module has not been runtime-tested on Windows.

Two longer Linux 4K/max/2× attempts are excluded. The first exposed a benchmark
bug: its joining peer reused the join deadline and disconnected before the
180-second measurement ended. The frozen v2 probe separates those deadlines,
fails on a player disconnect and records every party member. The second attempt
was stopped when another project's Godot import began. No candidate/control
desktop performance pair was completed. These exclusions and the harness repair
are recorded rather than treating the partial runs as stable co-op evidence.

No new full-simulation throughput gain, Windows 4K/max/D3D12 fix, combat coverage
or other-map coverage is claimed. The user's Windows ~40 FPS report remains
unresolved. No new release is published. The measured private production APK50
is left installed with autorun disabled and both private processes stopped.
The source freeze, artifact hashes, repeated runs, tests and exclusions are in
the [validation record](portal-tornado-particles-validation.json).

Next work remains reducing whole foreground and authority update stages while
preserving observed animation and gameplay state. Retroid acceptance is stable
60 FPS at 1× Original; desktop 2× and other large maps remain in scope.
