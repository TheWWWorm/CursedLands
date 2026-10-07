# Portal co-op host CPU investigation

Status: unreleased checkpoint `8976134`, based on Experimental 3 (`7aa520e`). The supplied
Lost in Astral save reproduces severe host slowdown in Portal (`gz1h`) after
the encounter with Ужас. This checkpoint improves it substantially but does
not make this scene run at an acceptable frame rate.

These measurements and validation describe that checkpoint. Later scaled-AI,
host-menu and conversation corrections are documented in the
[Dead City follow-up](performance-dead-city-2026-10-07.md).

## Rendered co-op measurements

Linux, Ryzen 9 5950X, RTX 3090, Forward+, 1280×720 at native resolution, uncapped
FPS. Default graphics, including soft ground, were enabled; Distant AI was off.
The host ran on one pinned main-thread core with four worker cores. A real
headless ENet client connected on separate cores; its FPS was not measured.
There were 416 units after joining, with about 13 visible in the saved view.

Each run used a fresh isolated profile, loaded the supplied quicksave, warmed
rendering with the simulation held, then measured 30 seconds of gameplay. Runs
were interleaved baseline/candidate/candidate/baseline/baseline/candidate, with
three samples per build. There were no other game processes or builds running.
Profiling was disabled for these measurements.

| Host measurement | Experimental 3 | Candidate |
| --- | ---: | ---: |
| Mean FPS, complete 30-second window | 2.94 | 5.50 |
| FPS range across three runs | 2.89–3.01 | 5.23–5.96 |
| Mean FPS after the first five seconds | 3.50 | 6.61 |
| Mean 95th-percentile frame time | 405.8 ms | 259.0 ms |
| Mean simulation ticks completed | 388.7 | 432.0 |
| Mean peak resident memory | 3,579 MiB | 3,565 MiB |

Average FPS increased by 87%. This is a result for this machine, camera and
save, not a prediction of Windows/client/device FPS. The initial simulation
stall remains in the complete-window measurement. The after-five-seconds
column excludes frames that started before that cutoff; it is not a separate
prewarmed gameplay benchmark. Memory variation does not establish a memory
reduction.

After the hidden-figure correction described below, a final 30-second run
measured 5.56 FPS. Disabling only animation binding retention in the same
source/runtime measured 3.02 FPS. These single-run confirmations support the
cache attribution and show that the final correction retained the gain. They
are additional checks, not extra samples in the three-run averages above.

The normal reconnect path deploys the saved joining player's hero beside the
host, alive, although the quicksave stored that hero dead elsewhere. Both builds
used this same reconnect behavior. The test is a reproducible co-op load of the
reported scene, not a replay of the original network session or player inputs.

## Main finding: repeated animation binding reconstruction

Short movement-start, posture-transition and other nonlooping clips finish
before the model starts their successor. Godot's `AnimationPlayer` normally
clears its track caches at that point. The next clip resolves tracks across the
character's animation library again. Repeating that work across hundreds of
characters is expensive even when most are outside the player's view.

The candidate keeps resolved track bindings for the game's fixed character
rigs. It still performs normal playback completion and audio/capture cleanup.
Library edits, explicit stops/clears and scene exit/reentry retain their normal
invalidation. Other animation players retain the default behavior. Stock Godot
uses the existing fallback.

In separate native sampling runs, `AnimationMixer::_update_caches` occupied
about 20% of main-thread CPU samples after the first five seconds before the
change, and about 2% afterward. Initial cache creation still costs time. The
earlier diagnostic used script-stack instrumentation; these percentages explain
the hotspot and are not the basis of the FPS comparison above.

The supplied scene is primarily host simulation and animation work. In the
profiled Experimental 3 co-op run, building/sending snapshots took about
143 ms over 30 seconds, under 0.5% of wall time. The host simulates the full
population; a joining client does not perform the same authoritative AI and
movement work. This helps explain why host and client FPS differ so much.

The original game used a specialized native runtime. This reconstruction paid
for generic animation binding and repeated script/Variant operations in its
hot loops. These are measured remake costs; the original executable was not
benchmarked on the same save, so no original/remake speed ratio is claimed.

## Other changes retained in this checkpoint

- A bounded reachability check can prove that an actor is trapped outside
  attack/spell range before constructing a full route. Uncertain cases use the
  existing planner. In a controlled crowded River and Islands fight, this
  removed 480 failed route attempts and reduced measured world CPU work by
  about 17%, with matching recorded state and combat events. In the Portal
  profile, six checks rejected zero routes: it does not explain the Portal gain.
- Footsteps and terrain contacts consume a queue of units whose animations
  advanced, instead of scanning every unit on every rendered frame. The contact
  geometry and authored footstep events remain the same.
- Figure rebuilding for strength/size effects first resolves a hidden model's
  pending pose. The extended tests found that copying its unevaluated keys could
  otherwise transfer an outdated pose to the replacement. This correctness fix
  followed the six FPS runs; it does not change ordinary animation playback.

## Validation and remaining work

The final candidate and an Experimental 3 control completed exactly 450
simulation ticks with identical recorded unit snapshots, paths, orders,
movement state, perception lists, quest variables, combat RNG state and 61
combat events. Each fixed batch received the same AI random seed. An earlier
baseline/candidate pair also matched, with 66 events. The unchanged baseline
reproduced the variation between pairs: fixed batching does not fully control
asynchronous co-op startup. These are matched recorded outcomes and independent
pose checks, not a guaranteed deterministic network replay or a complete
campaign playthrough.

Paired animation checks covered seven real character models, morph weights,
clock/clip state, movement starts, hidden/visible pose reads, corpse freezing,
strength-driven figure replacement, explicit cache invalidation and tree
reentry. Separate checks covered library/key/target replacement, queued clips,
reverse playback and disabling retention. The stock-engine fallback passed.
Reachability was checked against an exhaustive reference on randomized directed
grids; footstep/contact checks covered all 36 legged races.

Both desktop runtimes were compiled successfully. Linux received runtime tests;
the Windows cross-build has not been run on Windows. macOS, Android and Web
retain the stock-engine fallback, and their device FPS has not been measured.
The save format and co-op protocol are unchanged. The engine patch and its
focused regression fixture are in `engine_patches/godot-4.7`.

The remaining host work is dominated by simulation and script/Variant handling.
The conservative activity scheduler deferred no decisions in this Portal
sample. The next useful redesign targets are shared perception work, persistent
simulation records and movement/decision batching. Merely sending more network
updates or reducing graphics settings does not address the measured main costs.
No AI update-rate reduction was introduced by this checkpoint.

The earlier 3–5% Experimental 2/3 River FPS difference was not stable in a small
interleaved follow-up: Experimental 2 measured 120.54–130.84 FPS and Experimental
3 measured 128.22–134.80 FPS, two runs each. Those ranges overlap; this is too
small a sample to establish a regression or improvement. The corresponding
fixed-work simulation comparison was essentially unchanged. The Portal results
should not be generalized to the River starting scene.

The separately reported Lost in Astral co-op quest exits, Кель's lockpicking,
camp stat grants and dialogue issues remain open. This performance checkpoint
does not claim to fix those scripts.
