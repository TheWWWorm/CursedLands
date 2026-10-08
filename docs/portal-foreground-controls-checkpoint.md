# Portal HUD controls checkpoint — 8 October 2026

Retaining unchanged HUD drawing and layout gives a **small complete-gameplay
improvement** on Retroid at actual Original graphics / 1×. Two reversed
60-second comparisons improve the median from **52.15 to 53.64 FPS
(2.85%)**. Because the second pair improved by only 0.70%, a
longer comparison was required: three-minute runs measure **54.20 →
55.24 FPS (1.93%)**, with p95 improving from 25.911 to 24.449 ms.
This modest gain is retained. **Stable 60 FPS remains open.**

## Change and fidelity

The clock hands and speed pointer now draw in a child item, preserving their
per-frame animation while the unchanged clock face retains its commands.
Ring changes, pause blinking, quest pulses, size and selection changes still
redraw immediately. The child ignores input and follows the parent's visibility.
Lower HUD controls retain their offsets until screen/safe-area size, touch mode,
touch target size or HUD scale changes. Selection, speed, pause and world time
still update each frame. Lever usability reuses its immutable science default.

There are three changed game scripts (53 net added lines), with no changes to
engine/native binaries, simulation, presets, terrain, lighting or graphical quality.
The profile motivating the experiment attributed about 2.4% of frontend CPU to
HUD dial drawing, 0.58% to dial layout and 1.1% self time to lever usability.
These percentages describe sampled CPU, not promised FPS gains.

## Complete gameplay

| Production run | FPS | p95 ms | p99 ms | Worst ms | Simulated seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Candidate 60 s / 1 | 53.71 | 24.954 | 28.817 | 56.087 | 59.840 |
| Control 60 s / 1 | 51.11 | 27.092 | 31.235 | 49.772 | 59.895 |
| Control 60 s / 2 | 53.19 | 26.362 | 30.109 | 50.754 | 59.950 |
| Candidate 60 s / 2 | 53.56 | 25.826 | 29.767 | 51.060 | 59.840 |
| Control 180 s | 54.20 | 25.911 | 29.179 | 53.624 | 179.905 |
| Candidate 180 s | 55.24 | 24.449 | 27.931 | 53.971 | 179.905 |

Every run uses all 415 Portal actors and keeps both party members alive.
Private production APK47 is the control; APK49 is the candidate. Effective
options are identical: Original look, 1920×1080 viewport, 75% render scale,
OpenGL ES, four workers, difficulty 0, Distant AI off, and separated
single-player at 1×. The entrance route uses normal movement commands and the
terrain-aware camera. Neither party health nor the actor population is changed.
All three matched comparisons favor the candidate, including p95 and p99, but
the size is small. The longer candidate's ten-second windows range from
52.0 to 60.0 FPS; its worst frame is 53.971 ms.
This is evidence for a modest local improvement, not stable 60 FPS or combat coverage.

## Validation and limits

The new fixture compares 64 clock/movement-dial images pixel-for-pixel against
the former single-item draw order, across sizes, angles, selection and pulse
phases. With redraw, input, visibility, geometry, touch, scale and pause/resume
checks, **107 checks pass on each of stock Linux GL, packaged Linux Forward+
and physical Retroid GL**. Real atlas output and the gameplay screenshot were
inspected. The first fixture passed its checks but leaked textures during
cleanup; it was repaired before acceptance, without a production change.

A further Linux 4K living-party attempt was stopped during loading when another
project started Godot. It is excluded. No Windows 4K/max/D3D12 gain, new full-tick
simulation gain, other-map coverage or public release is claimed. The user's
Windows ~40 FPS report remains unresolved; the earlier 100+ FPS figure cannot
be applied to that setup. The target remains stable 60 FPS at 1× Original on Retroid
and 2× on desktop. Source, artifact, run and test hashes, exclusions and cleanup
are in the [validation record](portal-foreground-controls-validation.json).

The private Retroid build is left on production APK49 with benchmark autorun
disabled and both private processes stopped. Public Experimental 5, the original
Android installation and user saves are unchanged. Next larger candidates are
hidden actor presentation and whole particle stages; any simulation redesign
still needs repeated complete-tick gains, with 60 simulated seconds within
30 real seconds on Retroid remaining open.
