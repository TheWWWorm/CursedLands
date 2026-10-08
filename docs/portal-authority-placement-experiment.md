# Authority placement experiment, 8 October 2026

The native authority-placement batch was **rejected and completely reverted**.
Correctness passed, but repeated Retroid gameplay did not improve. The retained
production source remains `7aa3d0762c0bd4e2c5021d20c2fb3ed64020dc1a`.
The Retroid target remains **stable 60 FPS at 1× with actual Original graphics**;
Windows/desktop 2× remains in scope. No new release is published.

## Experiment and acceptance

The prototype read terrain revisions once per world presentation pass, reused
placement state, and read typed spline samples without per-actor dictionaries.
It preserved per-frame transforms and animation speeds, and kept script
fallbacks for custom actors/splines, legacy smoothing and route transitions.
It added roughly 92 production source lines after accounting for removed code.

The complete placement comparison passed 12,011 checks each on stock Linux,
packaged Forward+ and physical Retroid. Existing client placement (40,969) and
spline sampling (10,221) also passed on Linux and Retroid. Exact equivalence or
an isolated native speedup is insufficient: the whole-game result decides
whether this added implementation should survive.

## Actual Original / 1× Retroid comparison

The order was candidate, restored control, restored control, candidate. Each
run used the production engine, 1920×1080 viewport, 75% render scale, OpenGL ES,
four workers, separated single-player, Distant AI off, all 415 Portal actors,
and the same entrance route. Both party members lived throughout every run.
All four complete settings hashes are identical.

| Run | FPS | p95 ms | Simulated seconds |
| --- | ---: | ---: | ---: |
| candidate-60-01 | 52.15 | 26.010 | 59.895 |
| control-60-01 | 50.87 | 27.687 | 59.895 |
| control-60-02 | 53.95 | 25.059 | 59.950 |
| candidate-60-02 | 52.46 | 25.727 | 59.950 |

Median: **52.41 → 52.30 FPS (-0.21%)**.
The control spread alone exceeds the possible benefit. The prototype is not
retained. No new complete-simulation throughput gain is claimed.

## Desktop 4K correction and coverage

A clean Linux RTX 3090/Vulkan pair at 4K, 100% scale, maximum graphics and
2× co-op measured **62.07/64.54 FPS** (control/candidate),
with 119.790/119.900 simulated seconds per minute.
This is one pair, insufficient to establish a separate desktop gain. The
opening ten seconds measured **46.9/49.6 FPS**;
a party member died about 21.67/21.94
simulated seconds into the runs. Higher later averages do not establish stable
60 FPS during ordinary living-party combat.

The three-minute 4K living-party entrance test is not yet validated. Two launched runs were stopped after unrelated Godot processes appeared, and another launch was refused by the contention guard. These are excluded, not performance results.

These measurements reinforce the correction to the earlier 100+ FPS claim:
short Linux 720p runs cannot support that promise for a Windows laptop at 4K.
The user's roughly 40 FPS report on a 7945xh/RTX 4090 mobile, shipped default
D3D12, maximum graphics and 2× co-op remains unresolved and unvalidated on Windows.

## Restored state and next work

All 520 production game files were verified against the `7aa3d07` freeze after
restoration. The runnable project and Android stage retain those restored
sources/binaries. Private production APK47 is installed, benchmark autorun is
disabled and neither private Android process is running. The rejected source,
fixture and native binaries are archived in the local
`portal-throughput-20261007/authority-placement-experiment` evidence tree;
APK48 and the complete runs remain in their recorded private artifact paths.

The updated frontend profile still attributes substantial CPU to actor
presentation, sound, particles and UI, while about 40.5% of main-thread samples
fall outside script. This authority-only batch did not remove the limiting
foreground work. Next experiments should remove repeated work across complete
foreground stages, and use repeated whole-tick measurements for simulation
redesigns. Avoid further native ports based on isolated timing alone.

See [validation](portal-authority-placement-validation.json) for individual
runs, source/artifact checksums, test receipts and exclusions. The latest
retained Retroid three-minute living-party result remains **53.44 FPS**;
stable 60 FPS is open.
