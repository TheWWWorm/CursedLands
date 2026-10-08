# Portal touch-picking checkpoint — 8 October 2026

Retroid single-player Portal at actual Original graphics and 1× improves from
**44.53 to 49.55 FPS median** in two reversed 60-second comparisons, an **11.26%
complete-gameplay gain**. Both party members stay alive and simulation keeps
normal time. **Stable 60 FPS remains open.** This local, unpublished checkpoint
builds on the [single-player separation checkpoint](portal-single-player-checkpoint.md),
commit `78651d4`.

## Change and evidence

A diagnostic script sample profile of the same walking route attributes 10.7%
of main-thread CPU samples to unit picking, mostly detailed animated mesh
projection. When no exact unit hit exists, touch fallback previously calculated
those bounds for every visible unit, even far from the pointer.

The fallback now first checks the existing conservative screen bound expanded
by the current touch radius. Only plausible candidates need detailed bounds.
Exact-hit priority, silhouette distance, tie order and touch radius are
unchanged. Bounds crossing behind the camera keep the conservative fallback.
This changes two game files and adds no engine, native, AI or graphics-quality
changes. Diagnostic profile FPS is excluded from the performance comparison.

| Production run | FPS | p95 ms | p99 ms | Worst ms | Simulated seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Candidate 1 | 50.00 | 27.128 | 29.882 | 54.426 | 59.785 |
| Restored control 1 | 45.44 | 28.466 | 33.358 | 55.799 | 59.950 |
| Restored control 2 | 43.63 | 30.348 | 34.552 | 60.270 | 59.950 |
| Candidate 2 | 49.09 | 27.639 | 31.610 | 54.552 | 59.840 |

The private control is APK42 and the candidate is APK43, both with byte-identical
production engine and native module. The full effective options hash matches.
The fixture is the same living-party entrance-3 walking loop: all 415 actors
simulate normally, difficulty 0, Distant AI off, Original look, 1920×1080
viewport, 75% render scale, OpenGL ES, four workers and exact 1×. Battery
temperature spans 33.5–35.0°C. Source/artifact hashes and raw result hashes are
in the [validation record](portal-touch-picking-validation.json).

The first control installation was refused as an Android version downgrade;
no control run started. The controller resumed with the appropriate private
debug-package downgrade flag. The completed first candidate was retained.

## Correctness and limits

The selection fixture compares the optimized picker against the previous
exhaustive fallback on actual human and winged-creature meshes. It covers idle,
walking, attacking and death poses, perspective/orthographic cameras, rotation,
silhouette edges, nearby taps, distant taps, hidden units and a camera inside
the bound. **1,352 checks pass in each of stock Linux headless, stock rendered
GL, packaged Forward+ and physical Retroid GL.** Detailed bounds calls in the
Retroid fixture fall from 3,695 to 2,715 while selecting the same units.

The candidate has two 60-second gameplay repetitions. The preceding checkpoint's
three-minute run is separate coverage and is not presented as a three-minute
measurement of this change. Frame times still exceed the 16.67 ms target.
No new full-simulation gain or Windows 4K/max/D3D12 improvement is claimed.
The user's Windows result near 40 FPS remains unresolved. The public release
and original Android app have not been changed.

Remaining frontend costs include native/driver work outside script samples,
hidden presentation, snapshots, audio scanning and minimap drawing. Subsequent
changes should be selected from profiles and survive complete-gameplay repeats.
