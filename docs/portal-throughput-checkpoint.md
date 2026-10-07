# Portal simulation checkpoint after Experimental 5

This local checkpoint reduces complete Portal simulation time. It does **not**
reach 60 FPS or actual 2× simulation on Retroid, and it does not establish a fix
for the reported Windows slowdown. It follows published Experimental 5 commit
`fc06dcc93353969f093072030b4add9124fda140`; no new release is published here.

The user subsequently accepted **60 FPS at 1× with Original graphics** as the
Retroid target (8 October). The 2× measurements below remain the CPU checkpoint
record; the desktop/Windows 2× target remains open. Current Original-look
validation is recorded separately.

## Retained changes

- Native AI eligibility and sensing use shared empty defaults instead of
  allocating temporary arrays/dictionaries for every actor query. Live state,
  health and custom-script fallbacks remain checked at decision time.
- Thirteen frequently called methods enter their bodies directly when profiling
  is off. A diagnostic scope records normal and early returns when profiling is
  enabled. Normal play creates no scope objects.
- The conservative AI movement envelope is 2 m rather than 16 m. Each actor may
  move at most 1 m from the tick snapshot before immediately invalidating the
  batch. Larger movement and teleports use live decisions; movement speed,
  combat, scripts, patrol deadlines and simulation frequency are unchanged.
- Positive movement steps no longer calculate a spline sample that the same
  loop immediately replaces. Zero-time steps and segment transitions retain
  their required sample. Empty effect sets avoid the no-op update/allocation.

The source change removes more lines than it adds. Linux, Windows and Android
native modules were rebuilt; Windows is cross-compiled, not runtime-validated.
The native movement-contact fusion and animation-query cache experiments were
reverted because they did not demonstrate complete-simulation gains. A separate
actor-physics-callback diagnostic did not justify changing callback lifecycles.

## Complete-simulation measurements

The [versioned fixture](../tools/benchmarks/README.md) loads 415 Portal actors and
runs 1,100 full ticks: **60.5 simulated seconds**, including normal engine yields.
Profiling is off. Values below are whole elapsed seconds, not sums of isolated
functions. The [validation record](portal-throughput-validation.json) contains
individual runs, hashes, settings, exclusions and correctness results.

| Machine | Experimental 5, three runs | Candidate, three runs | Median time reduction |
| --- | --- | --- | --- |
| Retroid Pocket 5, production headless service | 42.55 / 43.44 / 41.55 s | 35.81 / 34.64 / 35.64 s | 16.2% |
| Linux, Ryzen 9 5950X | 21.23 / 21.01 / 20.67 s | 16.86 / 17.68 / 17.00 s | 19.1% |

The Retroid target is at most **30.25 real seconds for this 60.5-second fixture**.
It remains unmet. Tick-only times below 30 seconds do not satisfy that target.
The smaller cleanup also survived a reverse-order comparison: the prior
candidate took 36.26 seconds, followed by 35.64 seconds with the cleanup.

A matched 60-second Retroid gameplay pair uses 1920×1080, 75% render scale,
OpenGL Compatibility, the close Portal camera, four worker-pool threads and a
real separated co-op authority. It retains ordinary movement and Terror combat:

| Build | Average FPS | p95 / worst frame | Simulated seconds per real minute |
| --- | ---: | ---: | ---: |
| Experimental 5 | 22.08 | 65.19 / 110.30 ms | 75.74 |
| Candidate | 22.03 | 64.84 / 113.39 ms | 91.14 |

Simulation progress improves, while rendered FPS is effectively unchanged.
This is one matched gameplay pair, not a sustained-performance certification.
Rendering, driver work and competition between the frontend and simulation need
separate investigation. No graphics option or actor population was reduced to
produce these results.

## Correctness and measurement limits

Linux and physical ARM checks pass for native/scalar AI sensing and live
eligibility, movement construction and sampling, diagnostic scope lifetime, and
the Terror animation/damage regression. The movement envelope tests cover exact
boundaries, independently randomized pair motion, immediate overflow invalidation,
teleports and in-tick wake-up conditions. Linux also passes 8,255 worker-clock
checks. The validation JSON lists each bounded fixture; this is not a full
campaign or WAN certification.

The fixture's earlier version disabled world physics and accidentally selected
legacy actor placement during catch-up frames. Those results are excluded. The
corrected fixture keeps the real draw-clock branch while manually delivering
world ticks. Audio and animation callbacks still use the frame clock, so equal
RNG/state snapshots are not required or claimed as deterministic replay.

Three attempted longer Linux 4K rendering runs were aborted when unrelated
Godot tests started. Another complete-simulation run overlapped one of those
tests and was replaced. These receipts remain in the evidence but are excluded
from clean performance comparisons.

## Windows report and visual review

The user reports approximately **40 FPS** on a Windows laptop with a reported
7945xh CPU and RTX 4090 mobile GPU, latest experimental, 4K, 100% render scale,
maximum remake settings and co-op at 2×. The shipped Windows default is
Direct3D 12. Earlier Linux 720p averages of 100+ FPS do not validate this setup.
No Windows performance fix is claimed by this checkpoint.

This checkpoint changes no terrain code. Review of the earlier 32 m/16 m Portal
images confirms a visible change: the right-hand fire illuminates more ground
with smaller terrain pieces. Texture layout and geometry align in that view;
the illumination is not pixel-identical. Keep this documented as a visual
change, with broader lighting review still open. The Vulkan color cache remains
disabled because its earlier rendered comparison is visibly brighter.

Ordinary single-player still runs authority inline. The next milestone remains
60 simulated seconds within 30 real seconds on Retroid, alongside independent
rendering improvements and target-platform validation. Longer runs, other large
maps, single-player process separation and new release packaging remain open.
