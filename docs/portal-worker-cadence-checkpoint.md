# Portal worker cadence checkpoint — 8 October 2026

The separate simulation worker now runs presentation at up to 30 FPS, while the
visible client renders independently and world simulation retains its original
55 ms ticks and elapsed-time debt. Retroid Original/1× improves from **53.14
to 55.65 FPS** median across two reversed short pairs (**4.71%**).
A matched three-minute pair measures **55.65 → 56.67
FPS (1.82%)**. The change is retained on these complete-game
results. **Stable 60 FPS remains open.**

## Startup bug and implementation

The investigation first found that GameData's delayed window-setting update
replaced the worker's requested limit with the visible player's FPS preference.
With the benchmark's unlimited preference, a requested 30 FPS became unlimited
on the fourth frame. The first candidate and its incomplete comparison are
excluded. The separate worker now skips the window-setting update, preserving
its own frame limit and viewport scale.

That correction was measured separately at the original 60 FPS worker cadence:
Retroid median 53.73 → 54.26 FPS, effectively a small/near-flat result. It is
retained as a tested startup correctness fix, not a substantial FPS claim.
A regression fixture reproduces 16 failures in the former worker behavior;
the corrected worker and ordinary frontend each pass all 19 checks.

The subsequent 30-versus-60 comparison uses that correction on both sides.
Only two production scripts change. Physics cadence, the native world clock,
AI rules, actor population, graphics and native/engine modules are unchanged.
The worker still performs animation and placement needed by gameplay; this
reduces how often it does frame work rather than suppressing that behavior.
Owner snapshots continue every worker frame, including while paused, and the
visible client retains its existing interpolation and rendering cadence.

## Retroid complete gameplay

| Worker / measured duration | FPS | p95 ms | p99 ms | Simulated seconds |
| --- | ---: | ---: | ---: | ---: |
| 30 FPS worker / 60 s | 55.63 | 22.854 | 26.960 | 59.895 |
| 60 FPS worker / 60 s | 52.74 | 23.952 | 29.082 | 59.895 |
| 60 FPS worker / 60 s | 53.54 | 25.078 | 29.231 | 59.785 |
| 30 FPS worker / 60 s | 55.66 | 22.717 | 26.743 | 59.895 |
| 60 FPS worker / 180 s | 55.65 | 23.450 | 26.759 | 179.850 |
| 30 FPS worker / 180 s | 56.67 | 23.833 | 26.563 | 179.905 |

All six cadence runs use actual Original graphics, 1× single-player, a
1920×1080 viewport at 75% render scale, OpenGL ES, four workers, difficulty 0,
and Distant AI off. All 415 actors remain and both party members survive.
The entrance route uses normal movement commands and the gameplay camera;
health, enemies and graphics quality are not altered. APK53 is the corrected
60 FPS control, APK54 the 30 FPS candidate.

The longer candidate's ten-second averages range from 53.6 to 60.0 FPS.
Its worst frame is 54.982 ms. Long-run p95 is slightly worse
(23.450 → 23.833 ms), despite improved average FPS and slightly better p99.
This is a modest improvement, not proof of steady 60 FPS or combat/other-map coverage.
One earlier startup-fix control was excluded under the predeclared survival
rule after a hero died at 54.021 seconds; the failed run and replacement are
recorded. No cadence-comparison run required that exclusion.

## Desktop and remaining Windows report

Three-minute Linux RTX 3090 / Vulkan / 4K / 100% / max remake / 2× co-op runs
complete with two players, all three party members alive and 416 actors:

| Worker configuration | FPS | p95 ms | p99 ms | Simulated seconds | Worker CPU cores used, average |
| --- | ---: | ---: | ---: | ---: | ---: |
| Previous startup behavior | 57.59 | 21.387 | 23.812 | 359.865 | 1.006 |
| Correctly capped 60 FPS | 58.27 | 21.202 | 24.222 | 359.920 | 0.978 |
| Correctly capped 30 FPS | 57.90 | 21.203 | 23.405 | 359.755 | 0.888 |

There is no convincing desktop FPS gain from lowering worker cadence. Worker
CPU use is about 9.1% lower than the corrected 60 FPS control in this pair,
with normal 2× progress. The longer living-party measurements supersede any
implication that the earlier Linux 720p 100+ FPS result established this 4K
workload. The user's Windows 7945HX/4090 mobile / D3D12 / 4K / max / 2× report
of about 40 FPS remains unresolved and unvalidated on Windows.

## Correctness and limits

The final cadence passes clock conservation (8,255 checks on Linux and Retroid),
real single-player load/pause/orders/save/reload/shutdown (30 checks each),
Linux co-op owner commands and authoritative saves/thumbnails (33), and new
campaign/movie/deferred-save/restart/cancellation (19). The response fixture
exercises 12 successive paused commands plus actual 1× and accelerated clocks.
It passes 34 checks on Linux and Retroid. Physical Android Home/resume passes
12 checks, including a fresh authoritative autosave written before foregrounding.

An initial response test incorrectly treated a cropped interval after a cold
resume as a clock-overrun check. The 60 FPS control also repays startup debt:
8.635 simulated seconds in an 8.008-second crop, but 9.515 simulated seconds
across the complete 9.627-second speed phase. The corrected test checks both
rate and catch-up from the actual speed request. Original failures, fixture
versions and final reruns remain in the evidence. Production clock code was
not changed to make the test pass. Cold first progress/action latency remains
an open concern; this is not a claim that all first-use stalls are fixed.
Retroid 2× remains below the requested accelerated rate in the response probe.

Android scheduling samples give both processes access to CPUs 0–7 and observe
the simulation thread on CPU 7. The worker uses the foreground scheduling group,
the visible game top-app. These snapshots do not establish a scheduling cure;
no CPU pinning, process-priority or system setting change is included.

All 520 game files and package hashes are frozen in the
[validation record](portal-worker-cadence-validation.json). Private production
APK54 is installed with benchmark autorun disabled and neither private process
left running. Public Experimental 5 and the original Android app/saves are
unchanged. No new complete-tick throughput, Windows runtime, broad combat or
other-map certification is claimed. The last recorded full-simulation check
at an earlier retained checkpoint took 35.354 real seconds for 60.5 simulated
seconds; the 60-in-30 milestone is open.

Next: reduce larger foreground/authority stages and investigate first-use
stalls and scheduling with direct measurements. Retroid acceptance remains
steady 60 FPS at 1× Original, with desktop 2× and other large maps still in scope.
