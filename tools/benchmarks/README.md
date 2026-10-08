# Portal complete-simulation benchmark

`portal_throughput.gd` is the version-2 fixed-work fixture. It loads a copy of
the supplied Lost in Astral Portal save, requires 415 starting actors in `gz1h`,
and runs 1,100 complete 55 ms world ticks (60.5 simulated seconds). It yields
to the engine after every five ticks. Record both the entire elapsed window and
the sum of tick durations: passing the 2× milestone requires the entire window
to take no more than 30.25 seconds. A tick-only result is insufficient.

Use an isolated application data directory, the matching original expansion
installation and a frozen game export. Do not place original game assets or
saves in the repository. For Linux:

```sh
mkdir -p /tmp/portal-bench-data /tmp/portal-bench-config /tmp/portal-bench-cache
XDG_DATA_HOME=/tmp/portal-bench-data \
XDG_CONFIG_HOME=/tmp/portal-bench-config \
XDG_CACHE_HOME=/tmp/portal-bench-cache \
  /absolute/export/CursedLands.x86_64 --headless --audio-driver Dummy -- \
  --ei-path=/absolute/LostInAstral \
  --tool=/absolute/checkout/tools/benchmarks/portal_throughput.gd \
  --throughput-config=/absolute/config.json
```

The JSON configuration names a unique run, an existing fixture and a writable
result path:

```json
{
  "name": "baseline-01",
  "save": "/absolute/Portal/quick.sav",
  "out": "/absolute/results/baseline-01.json",
  "ticks": 1100,
  "profile": false
}
```

For the private Android test application, copy `portal_throughput.gd` and
`android_portal_throughput.gd` into its `user://` directory. Put the same
configuration in `user://bench.json`, using device-local paths. Launch the
Android wrapper through the private application's tool entry point. It starts
the real headless simulation service, limits the blank frontend to 10 FPS and
disables its rendering loop. Verify the output file, service exit and APK/native
library hashes. The normal user application and its saves are not a test profile.

Keep the production world physics flag enabled. Turning it off selects the
legacy per-actor placement path and adds artificial work during catch-up frames.
The fixture disables automatic world/session simulation, sets the worker role
before creating the game and asserts a headless display. Version 1 results are
not comparable to this fixture.

Run at least three alternating baseline/candidate repetitions with profiling
off. Retain failed or contaminated receipts but exclude them from performance
comparisons. Do not build or run another game on the measured machine during a
timed window. Freeze engine, pack, native module, fixture and configuration
hashes. Keep scheduler, worker-pool settings, device power mode and temperature
consistent. Profiling runs are diagnostic only.

The fixture retains normal actors, combat, movement, scripts, effects and audio
logic. It does not provide deterministic replay: audio/animation callbacks still
use the frame clock and can alter shared RNG consumption. State snapshots and
combat counts diagnose gross fixture errors; use independent correctness tests
for equivalence claims.

This benchmark does not measure rendered FPS, networking under WAN conditions
or ordinary single-player performance. Validate actual gameplay separately with
a fixed renderer, resolution, render scale, camera, graphics options and save.
Report frame percentiles and actual simulated time alongside average FPS.

## Rendered Portal gameplay

`portal_gameplay.gd` versions the bounded gameplay fixture used by the private
Android investigation. It requires the same 415-actor Portal save, follows the
close Terror view, issues normal movement commands and retains combat. Set
`terror: true` for that camera. `isolated: true` with `host: true` starts the
ordinary separated co-op authority. This has one owner and no remote guest;
it does not establish WAN or ordinary single-player performance.

Pass `--gameplay-config=/absolute/config.json` on desktop, or put the
configuration in the private Android application's `user://bench.json`:

```json
{
  "name": "portal-original-01",
  "save": "user://fixtures/portal.sav",
  "graphics": "original",
  "host": true,
  "isolated": true,
  "terror": true,
  "players": 1,
  "speed": 1,
  "seconds": 60,
  "options": {
    "distant_ai": 0,
    "render_scale": 2,
    "q_aa": 0,
    "q_shadows": 0,
    "q_aniso": 1
  }
}
```

`graphics: "original"` calls the same preset function as Options → Original
look and verifies every remake graphics switch is off. It deliberately leaves
render scale and quality at the configured values. `graphics: "configured"`
uses the supplied options; replay the **entire** options dictionary from a
control result for a matched comparison. Platform defaults with only enhanced
materials disabled are not the Original preset.

The result and screenshot are written as `user://<name>.json` / `.png`. The
JSON records all effective options, renderer, adapter, viewport, actual render
scale, camera, frame percentiles, commands, activity and simulated seconds.
Verify that the JSON exists even when the launcher exits cleanly. Keep APK,
engine, native module and fixture hashes in the external receipt. GPU timing
queries are excluded from the measured gameplay window.

A minute at the accepted Retroid 1× target must advance approximately 60
simulated seconds. At requested 2× it must advance approximately 120 seconds;
high rendered FPS alone is insufficient. Frozen scenes and hidden-layer probes
are diagnostics only. After Android testing, disable the private application's
`bench.json` autorun before returning the device.

### Exact Retroid Original fixtures

The wrappers `original_gameplay_versioned.gd`, `original_city_gameplay.gd`
and `original_city_loop_gameplay.gd` retain the exact fixtures used for the
8 October hidden presentation checkpoint. Copy them beside
`user://portal_gameplay.gd` in the private application. The first replays the
complete Android options dictionary before applying Original look. The second
also records party health and sleeping replica counts at every census.

The loop wrapper uses the authored 415-actor Portal population at entrance 3
after the catacombs, with the supplied party/progress and no setup simulation,
healing or invulnerability. Use that fixture as `save`, omit `terror`, and set
`seconds: 180`, `speed: 1`, `host: true`, `isolated: true`. It walks a short
route near the entrance with ordinary commands and a rotating terrain-aware
camera. Both party members remained alive in the recorded run; report this
exploration result separately from the close Terror combat comparison.

For inline single-player diagnostics, use `host: false` and
`original_city_gameplay.gd`. Its straight route reaches combat and the party
can die. Neither camera variant is a full map playthrough. In particular,
the close Terror fixture's party dies around 25 seconds: later near-60 FPS
averages include the death view and cannot establish sustained gameplay.
