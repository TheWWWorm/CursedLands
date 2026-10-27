# Solo authority rate presentation — 27 October 2026

Addresses [#119](https://github.com/TheWWWorm/CursedLands/issues/119). Based on
local main `34a17e14`, branch `fix/issue-119-worker-rate-20261027`.

## Confirmed cause

A solo campaign runs its authority in a separate process. The owner predicts
clips and effect counters at the dial's rate between snapshots. When the
authority's frames exceed the native five-interval clock cap (`0x456440`,
already modelled in `World._sample_frame`), the excess wall time is discarded
and the simulation runs below the selected rate. The owner kept presenting
2.037x and each snapshot pulled counters back.

- Reporter video (1.32.0, Foothills, 19–26 FPS): Eagle Sight fell by about
  0.9 units/s while fast and 1.1 units/s while normal.
- Foothills authority cost on a Ryzen 9 5950X (released 1.32.0, 214 units):
  p50 6.0 ms per tick; script VM about 2.7 ms. The worker process used 33%
  of one core at normal speed and 52% at fast speed.
- Worker confined to one core shared with three busy loops: normal 0.99–1.03x;
  fast 1.12–1.23x, with 10–11 visible counter reversals of up to 12 ticks per
  5 s. Unrestricted: 1.00x and 2.03x.

The reporter's hardware is unknown; that their worker is CPU-bound is an
inference consistent with the video, not a confirmed observation.

## Change

`World` records, for real-time frames that reach the simulation, the
selected-rate time requested and the part admitted by the cap. Pauses, movies,
travel holds and isolated stalls over one second are excluded. The solo
worker's `LocalHost` reports the admitted fraction about once per simulated
second when it changes by at least 0.05; 0.95 or more counts as sustained.

The owner presents `selected × fraction` through `Engine.time_scale`. The
dial, `game.speed`, the rate requested from the authority (now derived from
the selection, not the presented scale) and saved speed are unchanged. A new
zone, dial change or stopped host returns to the full selected rate; reports
measured at a previous rate are ignored. Co-op hosting is unchanged.

`--ei-simulation-load-ms=N` is a diagnostic forwarded to the worker, which
waits N ms after each authority tick. It is used only by the regression.

## Original comparison

Not run under Wine. The original has no separate authority or owner
prediction: one loop reads the clock once per rendered frame and caps it at
five intervals, so an overloaded original slows animation and timers together
without reversals. This is inferred from the documented native routine, not
from a captured overloaded original session; a remake-only two-process
failure cannot be reproduced in the original.

## Regression evidence

Evidence: `local/validation/issue-119-20261027/` (workspace, outside Git).

| Case | Unfixed main + diagnostic hook | Candidate |
| --- | --- | --- |
| `worker_rate_presentation` (headless) | 7/21 failed twice: presented 2.037x at 1.23–1.35x authority, 53 backward Eagle Sight ticks | 21/21 twice: presented 1.28–1.38x, at most 2 backward ticks |
| `worker_rate_presentation_rendered` | — | 21/21: presented 1.33x at 1.34x |

The first control run used an incomplete editor import and was discarded.

Related registered checks passed: `worker_travel_clock` (headless and
rendered), `foothills_actor_clock` (both), `foothills_campaign_flow`,
`local_host_clock_resync`, `local_host_shader_stall`, `local_host_play_clock`,
`worker_overload_recovery`, `campaign_feedback` and `dialogue_clock_coop`.
Unregistered clock programs passed: `local_host_simulation_rate`,
`local_host_loaded_rate`, `local_host_resume_rate` (generated paused fast
save, including 15 and 5 FPS owners), `local_host_zone_speed`,
`zone_speed_retention`, `worker_clock`, `network_render_clock`,
`pause_menu_clock`, `campaign_clock` and `local_host_permissions`.
`local_host_worker` with the Portal fixture fails one assertion ("load resets
shared clock") identically on unfixed main; it is pre-existing and unrelated.

## Remaining limitation

Presentation now matches the simulation, but a CPU that cannot sustain the
Foothills authority at 2x still runs below 2x. About 14% of a 5950X core is
fixed per-frame worker overhead; reducing it and the per-tick script/AI cost
needs profiling and parity checks and is not part of this change.
