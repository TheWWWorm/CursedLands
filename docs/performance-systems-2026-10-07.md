# Runtime systems redesign, 7 October 2026

This local Experimental 4 checkpoint includes the [campaign and presentation
repairs](bugs-2026-10-07.md), then replaces measured expensive runtime work.
The comparison baseline is `d239eda`, the repaired game before this redesign.
Distant AI remains off. The 55 ms simulation tick, command handling, combat
rules, visual settings and network snapshot cadence are retained.

## Implemented changes

**Navigation owns persistent static records.** The native terrain instance now
also owns block representatives, weighted edges, connectivity, component labels
and endpoint seeds. Its lifetime follows the map revision. Doors, changed
objects and floor updates replace those records; live actor occupancy continues
to enter every moving search window. Directed slopes and exceptional blocked
starts retain their original searches and tie order. Seed caches are bounded.
The large script edge arrays are allocated only when the fallback needs them.
This removes repeated interpreter work without approximating routes or putting
commands behind an asynchronous queue.

**Unit membership has explicit revisions.** `World.set_unit`, `erase_unit` and
whole-roster replacement publish a read-only ordered snapshot. Local queries
reuse its rank map until membership, navigation registration or a unit's
structural lifetime changes. Same-count replacement, erase/reinsert, freed
nodes and script replacement invalidate it. Position and classification changes
still update their existing live spatial/perception inputs. This removes the
full-population registry comparison from every local query.

**Body state uses typed records and derived health is cached by revision.**
Damage, healing, severing and restoration update owner-free revision tokens.
Repeated health reads reuse the exact ordered calculation until a relevant
field or maximum health changes. Body membership is immutable between explicit
replacements; individual body fields stay editable. Save and network numeric
representations are unchanged.

**Movement evaluates owned native spline records.** Routes publish their nodes,
coefficients and intervals once. Sampling retains the script implementation's
double intermediates, Vector2 rounding, interval subtraction and boundary
semantics, including backward seeks. It does not change motion speed or path
selection. The unchanged script evaluator is the diagnostic oracle and the
fallback on platforms without the extension.

**Co-op combat flags share their inputs.** One synchronous batch groups owned
actors and current attackers and reuses the campaign's shared visibility list.
All flags are calculated before network events are published. LMP and offline
visibility remain specific to the queried player. Existing detection refresh
points and timers remain active.

**Character bindings are prepared under the loading screen.** A fifth opt-in
engine patch resolves the same AnimationPlayer track caches before gameplay
starts. It does not advance animation, write poses or emit track/playback events.
This addresses Portal's measured first-use stall. It shifts work into loading;
it is not a claim of lower steady-state animation cost. The earlier retained
bindings, hidden pose handling and ground-contact worklist remain included.

## Measurement

The following means use three interleaved runs per build and scene on a Ryzen
9 5950X / RTX 3090, Linux Forward+ on an owned private Xvfb display,
1280×720 at scale 1.0. The main thread is
pinned to one physical core; renderer workers have four separate cores. Each
co-op host has a real headless ENet peer on separate cores. Profiles are fresh,
rendering is warmed with simulation held, and the measured interval is 30
seconds of realtime play. Profiling is off; no other engine or compilation runs
concurrently. The original-game executable was not compared. Earlier inherited-desktop
River figures used another display context and must not be mixed into these
averages; the absolute FPS here is specific to this test setup.

| Co-op host case | Repaired baseline | Redesign | Change |
| --- | ---: | ---: | ---: |
| Dead City, 2×, complete FPS | 5.78 | 7.15 | +23.7% |
| Dead City, later 10–30 s FPS | 6.36 | 7.85 | +23.4% |
| Portal, 1×, complete FPS | 3.37 | 5.39 | +59.8% |
| Portal, later 10–30 s FPS | 4.36 | 6.10 | +39.9% |

| Case | p95 frame, before → after | Mean worst frame | Simulated seconds in 30 wall seconds | Peak RSS |
| --- | --- | --- | --- | --- |
| Dead City 2× | 195.6 → 170.1 ms | 1,647 → 928 ms | 47.50 → 55.02 | 2,396 → 2,256 MiB |
| Portal 1× | 344.3 → 236.5 ms | 5,235 → 1,319 ms | 23.17 → 27.96 | 3,571 → 3,158 MiB |

Dead City loading is essentially unchanged, 4.66 → 4.69 seconds. Portal loading
increases from 10.58 to 12.53 seconds; its main-thread load CPU increases from
9.62 to 11.62 seconds. Moving binding setup out of gameplay is an explicit
tradeoff. The later-gameplay gains demonstrate that this is not the only
improvement. Main-thread CPU remains near saturation while completing more
simulation and rendering work.

These are meaningful gains, but both demanding hosts remain slow on this test
machine. Dead City's first 30 seconds still miss the ideal 60 simulated seconds
at 2×; Portal also loses time to its initial stall. No lower tick rate, Distant
AI approximation or graphics reduction was used. Individual FPS runs, frame
times, simulated work, memory and loading are in the [measurement data](performance-systems-measurements.json).
The final code is frozen for these comparisons. Small per-component pilot
runs and query microbenchmarks are not headline FPS evidence.

One Portal baseline run was rejected because the private fixture left callbacks
running after closing ENet during cleanup. Callback shutdown was repaired after
the measurement boundary, and all six accepted Portal runs exited cleanly.

## Additional host checks

Dead City at normal speed, with three interleaved runs per build, improves
10.68 → 12.96 FPS (+21.3%). Simulated progress increases 26.97 → 28.78 seconds
in the full 30-second window. p95 falls 120.7 → 104.2 ms and mean worst frame
2,188 → 927 ms; peak RSS falls 2,400 → 2,219 MiB. Initial simulation debt
remains even at normal speed; later-window FPS improves 12.78 → 14.70.

A separate two-core host diagnostic pins the main thread to CPU 15 and every
host worker to CPU 14. The headless peer uses CPUs 13 and 12. Two runs per
build, in baseline/final/final/baseline order, show Dead City 2× improving
5.36 → 6.49 FPS (+21.1%) and 43.89 → 51.42 simulated seconds per 30 wall
seconds. p95 improves 205.5 → 186.6 ms. This supports a benefit under CPU
contention; it does not emulate an older computer or meet the ideal 60
simulated seconds. All original visual settings remain enabled.

## River controls

Three interleaved runs per build use River and Islands, 239 units, the same
camera, 180 warm-up simulation ticks and 20 measured realtime seconds. All
builds use the private display and matching options, with Distant AI off.

| Starting scene | Experimental 2 | Experimental 3 | Local Experimental 4 |
| --- | ---: | ---: | ---: |
| 1× FPS | 17.87 | 17.97 | 19.48 |
| 2× FPS | 11.44 | 10.57 | 13.53 |

The normal-speed scene improves 8.4% over Experimental 3. The 2× scene improves
28.0%, with about 40.1 simulated seconds completed in each 20-second interval.
Experimental 2 and 3 overlap at 1×. Experimental 3 is slower in this 2× batch;
the final build exceeds both and retains the combined visuals. This result
does not establish a separate cost for any individual visual effect.

A crowded combat control places 32 fighters on each side in the same River
map. Three runs per build average 3.92 FPS on Experimental 3 and 3.98 FPS on
the redesign, with wide overlapping ranges (3.50–4.58 and 3.17–4.98 FPS).
This does **not** establish a combat FPS improvement. Mean worst frames fall
from 1,099 to 596 ms and peak RSS from 2,492 to 2,287 MiB, but p95 frame time
does not improve (383 → 397 ms). Combat progression and strike counts vary.

A separate private sampling run after warm-up attributes 32.0% of main-thread
samples inclusively to path finding, 20.7% to block-carrier construction and
28.1% to AI choice; these overlap and must not be added. Visibility rays are
1.6% self time. The remaining crowded-combat work is primarily dynamic route
preparation and active decisions. Static topology records do not eliminate
those tasks. The diagnostic sampler is excluded from production builds and
from FPS comparisons.

## Rendered joining client

Three interleaved Portal runs per build also render the joining client. Both
processes share one RTX 3090 and have separate CPU affinity. Matching initial
and final camera views are verified. Continuous client sampling covers the
host's full 30-second interval, including frames crossing its boundaries.
These are not two-PC client FPS figures and are separate from the headline
host comparisons above.

Mean client FPS is 11.76 → 12.93 (+9.9%). Mean worst frame falls from 2,678
to 1,581 ms; p95 stays essentially unchanged at 93.6 → 94.5 ms. The gain
primarily reduces stalls rather than ordinary client frame cost. The discarded
pilot sampler could miss a first frame before seeing the host's begin signal;
all six accepted runs use the corrected complete-window sampler. Production
code did not change during this correction.

## Validation

- Fixed-work real-ENet replay: 450 logic ticks in each supplied scene preserve
  byte-identical normalized states, event counts and combat RNG against the
  repaired baseline (Dead City: 14 events; Portal: 69). Measured work completes
  in 13.20 → 10.77 seconds and 26.76 → 20.82 seconds respectively. These are
  one controlled pair per scene, separate from realtime FPS, and do not promise
  deterministic network replay under arbitrary asynchronous startup.
- Native topology: 7,072 exact graph, component, representative, seed and route
  checks, including directed slopes, blocked starts and script fallbacks.
- Motion records: 10,221 exact samples, including interval boundaries, empty
  routes, zero speeds, turns, backward seeks and rebuilds.
- Both native suites also pass ASan/UBSan. A private loader adapter removes
  Godot's DEEPBIND flag for these tests; production binaries contain neither
  that adapter nor sanitizer instrumentation.
- Original LiA door and moving occupancy: 133 complete planner/revision checks.
- Body records: 4,025 checks; focused scaled-health/activity eligibility: 45.
- Registry/spatial queries: 1,283 checks against exhaustive results, including
  same-size replacement, ordering, teleports, ownership, freeing and script
  replacement. The 2,000-query microbenchmark is diagnostic, not a game FPS claim.
- Shared combat inputs: 480 checks against the previous exhaustive logic.
- Animation preparation: 1,435 lifecycle/event/pose checks; retained cache
  lifecycle: 1,256. Animation playback and invalidation remain covered.
- Integrated real ENet recruiter/tunnel progression, mid-walk reload, known
  legacy recovery, camp grants, movie completion and rendered wall visibility
  pass with the redesigned systems. The real-map patrol/stealth fixture retains
  its 22 checks and first-relevant-tick wake-up.

The tests are bounded fixtures, not a full campaign playthrough. Original
player saves remain private and unchanged. Linux has runtime validation;
Windows is cross-compiled and requires device validation. Controller/touch
physical devices, WAN behavior, Android and macOS remain unverified here.

## Clean desktop packages

The local Linux and Windows exports contain the same 201 compiled gameplay
scripts, byte-identical to the benchmark pack. Each clean pack contains 551
resources; private probes, original game assets and player saves are excluded.
The production engine and native-module hashes match the frozen inputs.
The version is `1.0.3-experimental.4`; it has not been published.

The actual Linux export passes 22 package cases: 27,610 assertions plus four
recruiter/tunnel progression scenarios. These include single-player controls,
co-op legacy and mid-walk reloads, movie completion, animation lifecycle,
native/script queries, camp grants, reconnect, spell purchase/learning,
quest-item clicks, wall visibility, both host menus and item previews in
Forward+ and OpenGL. There are no runtime errors. Private-display input-method
and OpenGL capability warnings remain environmental diagnostics. Windows has
binary/export inspection only, not Windows execution.

The first package tunnel invocation omitted its required saved party and had
no Kel; it is retained as a failed fixture setup. The corrected invocation
uses the same companion-bearing save as the earlier integrated test and exits
to `gz1d2` on both peers after the mid-walk reload.

## Maintenance and fallbacks

Code that changes live world membership must use `set_unit`, `erase_unit`, the
ordinary spawn/removal methods or whole `units` replacement. Direct dictionary
membership edits are deliberately rejected. Retaining an old snapshot is safe;
it remains ordered and unchanged. Body arrays follow the same replacement rule.

`--ei-script-topology`, `--ei-script-motion`, `--ei-script-units` and
`--ei-lazy-animation-bindings` select diagnostic fallbacks after the normal
Godot `--` separator. Stock Godot simply omits the new animation capability.
The other desktop engine patches and native helper fallbacks remain in force.

No worker queue or C# runtime was added. Profiling showed substantial repeated
script/data work around the small native kernels; moving the kernels alone to
workers would leave that serial preparation in place. This checkpoint removes
that work first. Heavy active AI and perception remain areas for future work;
no claim is made that demanding scenes now reach a particular user's FPS.
