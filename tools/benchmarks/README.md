# Menu-driven saved co-op retention

`run_menu_coop.py` plays complete online Trials matches, leaves through the
confirmation dialog, hosts/joins the next match from the main menu, and then
loads two supplied campaign saves through the co-op save selectors. The same
two rendered client processes remain open throughout. A player match ends
when both human players have been eliminated or the tournament has ended;
the driver does not keep eliminated players waiting for the remaining bots.

Use an isolated, unpublished export made with the repository's patched engine
templates (see `engine_patches/godot-4.7/README.md`). An editor export with an
official template can silently replace the executable with the stock engine.
Record and check both executable and PCK hashes before interpreting results.
The launcher copies both saves into a new private profile, freezes its driver
sources, records input hashes, and checks that the originals are unchanged.

```sh
python3 tools/benchmarks/run_menu_coop.py \
  --runtime /absolute/export/CursedLands.x86_64 \
  --ei-path /absolute/EvilIslands \
  --host-save /absolute/host/quick.sav \
  --guest-save /absolute/friend/latest-coop.sav \
  --output /absolute/results/menu-coop-01 \
  --cycles 3 --duration 1800 \
  --owner-size 3840x2160 --guest-size 2560x1440 \
  --owner-gpu 0 --guest-gpu 1 \
  --guest-display :41 --guest-xauthority /absolute/test/Xauthority
```

The second display is optional and must already exist; this script does not
reconfigure displays or install drivers. Set both GPU indices to zero for a
single-GPU functional check, but do not compare its FPS with separate-GPU runs.
Use `--cycles 1 --smoke-rounds 3 --duration 40 --stationary` for a short menu
smoke check including scouting, a confirmed Trials exit, campaign load/save,
and both clients' final menu exits. Omit `--smoke-rounds` for complete matches.
A short or stationary run is not evidence of sustained combat performance.

Trials recruitment, arrangement, training, readiness, scouting and menu exits
use input events against visible controls. Campaign movement and combat use
normal game commands with the saved equipment, armor, skills and spell runes.
The guest deliberately stacks Acid Fog and interleaves Lightning and Weakness;
both characters use their available healing. The driver rotates cameras,
cycles isometric/third-person/first-person modes, walks to authored exits,
and clicks the leave, travel-map and objectives screens. It never teleports
actors, changes their stats, creates enemies/effects, or makes them invulnerable.
Graphics are Ultra, game speed is 2×, and real audio stays enabled.

`run.log`, `plan.json` and `processes.jsonl` record lifecycle actions, frame
intervals, resource counts, child processes and build provenance. The isolated
profile additionally contains menu screenshots, per-peer action/retention
receipts and campaign traversal samples. Verify completed casts, kills, living
party members, distance travelled and actual location changes before counting
a run as valid. Active traversal continues defending and healing through the
end of the run; it must not force the party to idle under attack. Use a separate
`--stationary` pass at a verified safe checkpoint for a quiet comparison. A death
view is not a valid performance sample for living-party gameplay. Do not run
another game, build or send concurrent desktop input during the measurement.
This is automated play on Linux/Vulkan, not a Windows/default-renderer result
or a physical-input latency measurement.

For a fresh-process comparison, first verify both characters are alive and safe
in the host checkpoint saved through the pause menu, keep the same executable/PCK and graphics
arguments, and add `--cycles 0 --duration 180 --stationary --checkpoint
--match-poses /absolute/final-poses.json`. The pose file contains `owner` and
`guest` objects, each with the final sample's `position` array and `camera_pose`
dictionary. The guest reclaims the existing saved character by name. Both
characters walk to their recorded positions before measurement. Check that
the positions, zone, camera and health match; report the quiet intervals
separately from travel or loading. A restart difference alone does not prove
a leak, especially if temperature, clocks or background load changed.

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

Version 2 also measures ordinary single-player with `host: false`. Supported
rendered builds start its local simulation worker automatically. Set
`inline_single: true` for a same-build inline control; this bypasses only
automatic worker startup. The result records `single_player_worker`,
`multiplayer_game` and the effective difficulty, so a co-op run cannot be
mistaken for single-player. Both modes pause during camera setup, and the local
worker acknowledges that pause before measurement. Profiling stays off.

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

For inline single-player diagnostics, use `host: false`, `inline_single: true` and
`original_city_gameplay.gd`. Its straight route reaches combat and the party
can die. Use the loop wrapper for matched living-party single-player comparisons,
with `inline_single: false` for the separated candidate. Neither camera variant
is a full map playthrough. In particular,
the close Terror fixture's party dies around 25 seconds: later near-60 FPS
averages include the death view and cannot establish sustained gameplay.

## Original single-player large-area sweep

`large_area_gameplay.gd` extends `original_gameplay_versioned.gd`, which extends
`portal_gameplay.gd`; copy all three into the private application's `user://`
directory. The base Portal fixture retains its original strict population
check. The large-area override requires a matching save basename, zone and
population: `gz2h` (Suslanger, 323), `gz16g` (River and Islands, 294), `gz21k`
(City Environs, 207), `gz7g` (Dead City, 262), or `gz1h` (Portal, 415).

Use the authored-entrance fixtures with the supplied Lost in Astral party and
progress. They contain fresh authored populations and no simulated setup
steps. Keep proprietary saves/assets outside the repository and record their
hashes in the run receipt. Set `host: false`, `speed: 1`, `seconds: 120`,
`terror: false`, and use the versioned Original settings. The current Retroid
comparison uses a 1920×1080 viewport at 75% render scale, OpenGL ES, four native
workers, normal Android scheduling and production APK54.

The fixture follows the party with the ordinary rotating terrain-aware camera
and issues normal movement commands on fixed entrance loops. It records both
characters' health, life state, position and action every half second, plus
population, activity and frame intervals. Require actual simulation progress
and moving, living characters throughout; retain failed runs with their reason.
`single_player_worker: true` and `multiplayer_game: false` establish ordinary
single-player. `online: true` is expected for its private local transport and
does not mean co-op rules are active.

These are bounded entrance-walk measurements on fully populated large maps.
They do not establish performance in every view or heavy combat encounter. The
initial Suslanger route reached a fight and is archived as an excluded run;
the retained Suslanger route walks eight metres from the entrance and back.
City Environs uses authored village entrance 5 (hero at 335.5, 257.5),
walking sixteen metres north and back. Its entrance-1 attempts are excluded
after party deaths. Use the separately frozen entrance-5 save; the earlier
entrance-1 save has the same basename and population but a different route. Health,
population and combat rules remain unchanged. Repeat areas in reversed order,
report ten-second FPS ranges and p95/p99 frames, and keep the measured game
sources unchanged between areas.

## Top-down camera movement at 4K

`map_pan.gd` version 2 measures presentation pacing on a wall-clock camera
route. It loads an original campaign zone, applies a named preset, renders at
3840×2160 with 100% scale, and performs stationary, first-pan and repeat-pan
windows. The camera and its rig both move, so local mist, wildlife, regional
particles, sound and the minimap follow the view. Version 1 moved only the
camera and omitted those movement costs; do not combine their results.

Run a frozen **release export**, not the editor, with separate application
data/config/cache directories for each run. Pass the external fixture through
the game's normal tool entry point:

```sh
XDG_DATA_HOME=/absolute/run/data \
XDG_CONFIG_HOME=/absolute/run/config \
XDG_CACHE_HOME=/absolute/run/cache \
  /absolute/export/CursedLands.x86_64 --rendering-method forward_plus \
  --rendering-driver vulkan --windowed --resolution 1280x720 \
  --audio-driver Dummy -- --ei-path=/absolute/original/game \
  --tool=/absolute/checkout/tools/benchmarks/map_pan.gd \
  --pan-config=/absolute/run/config.json
```

The presentation window may be smaller; the fixture explicitly sets its
internal viewport to the configured dimensions. Verify `viewport`,
`render_scale`, `adapter` and the complete effective `options` in the output.
For a 10-second window per phase and an 18-second warm-up:

```json
{"zone":"gz1g","preset":7,"width":3840,"height":2160,"seconds":10,"warmup":18}
```

Preset 7 is Very High. Optional `options` overrides are diagnostic ablations;
record them and do not report a quality reduction as an optimization. Earlier
experimental presets may contain different settings under the same name.
Optional `speed` is metres/second (36 by default), `phases` selects windows,
`hide_hud` removes the HUD and `terrain_shadows: false` removes the land caster
for diagnosis. Keep these identical in a performance comparison.

`user://map-pan.json` records frame intervals, percentiles, long frames over
25 ms and newly compiled draw/mesh pipelines, with a PNG after each phase.
GPU and render-thread timing getters and image readbacks run **outside** the
measured windows; `last_gpu_ms` is a boundary sample, not a phase average.
`process_ms` / `physics_ms` are Godot's periodically sampled engine monitors,
not per-frame callback timings. Do not interpret their distributions as mean
CPU execution cost. Profile separately; counters and instrumentation can change
scheduling. Freeze pack, executable, native library, fixture and config hashes
and do not build or run another GPU workload during the timed windows.

World/session physics are held to preserve the authored population. Production
rendering, UI and effect callbacks continue, but the camera pose is set directly;
this is a render/pacing diagnostic, not a whole-game simulation or input-latency
benchmark. It excludes the camera controller's input, smoothing and camera-fade
update. First-use compilation and streaming still occur. Follow this with live
simulation and actual platform testing before generalizing to gameplay or a
different GPU/driver.

`map_pan_live.gd` is the corresponding live check. Use the same command and
configuration with that filename. It keeps world/session physics active and
presses the currently bound left/right camera keys, changing direction every
four seconds. The production camera handles smoothing, ground clearance and
scenery fading. The result also records simulated seconds, camera travel and
the count of scenery meshes tested for fading. The initial zoom is 42 m.
Synthetic keys do not measure physical input latency, and this ordinary
single-player scene does not represent busy co-op combat. Check that camera
travel is nonzero and simulation advances at approximately one second per
wall-clock second before using its frame statistics. Compare live runs with
live runs; their camera route differs from `map_pan.gd`.

## Full Trials games followed by sustained co-op combat

`session_retention.gd` plays three complete nine-player Trials games through
normal purchases, combat and elimination, then starts two rendered campaign
clients and a private authority. `coop_traversal_session.gd` runs the campaign
portion alone. They use Ultra at 1920×1080, 100% render scale and 2× simulation
speed, with ordinary movement, targeting, weapon attacks and the Lightning,
Acid Fog and Weakness spells. The equipped level-15 heroes use real health,
mana, damage and healing. Authored enemies stay active; no teleports, direct
effect spawns, enemy deletion or invulnerability are used.

Use an isolated user-data directory and a patched release export. For the
release's platform-specific rendering-thread default:

```sh
XDG_DATA_HOME=/absolute/run/data \
  /absolute/export/CursedLands.x86_64 --rendering-method forward_plus \
  -- --ei-path=/absolute/original/game \
  --tool=/absolute/checkout/tools/benchmarks/session_retention.gd \
  --trials-first --default-render-thread --label=default-thread --duration=720
```

Do not add `--render-thread safe` to that command. The user argument
`--default-render-thread` also leaves the guest on its platform default.
`TRAVERSE_RENDER` and each census record report the actual mode, rather than
inferring it from a setting. For an explicit Safe-mode comparison, pass
`--render-thread safe` before `--` and omit `--default-render-thread`.
The unpatched stock editor still requires Safe mode.

Frame intervals are measured without per-frame renderer timing queries.
`--render-timings` opts into those queries for a separate instrumented profile;
they can synchronize the renderer, so do not combine such samples with the
ordinary run. GPU/render-CPU fields are `null` when not measured. Screenshots
are captured once a minute and can affect their surrounding frame interval.

Inspect travel, depth, actual cast animations, enemy deaths, health and route
progress alongside FPS. A completed timer alone does not establish sustained
play. The initial sample is not a full interval; discard intervals that include
loading, disconnection or a clock change. Both clients share one GPU in this
fixture, and moving views have different workloads. A lower or higher FPS in a
different location is not by itself evidence of a leak or a fix.

# Trials balance depth

`arena_balance_contexts.gd` compares every unordered pair of recruit lines at the same
shop price in physical, fire and lightning support teams. It tests two- and
three-star candidates, with two fixed seeds and mirrored sides: 1,848 native
fights. The three shared two-star supports never duplicate either candidate.
Native movement, targeting, regeneration, typed armor and alliance thresholds
remain active. `--tiers=1,2` restricts price tiers; `--families=28,29` keeps pairs
containing either selected recruit, and `--ranks=0,1,2` selects zero-based star
ranks. These are controlled substitutions, not 1,848 independent tournament
observations. A 90-second timeout is retained
as a draw rather than counted as a win.

`arena_balance_catalog.gd` exports all 90 recruit/rank combinations, their spells,
cadence, per-type armor and 1,890 actual `Combat.absorb` samples, plus the shop odds
and level costs. `arena_star_balance.gd` checks promotions and equal-purchase-cost
alternatives. Acquisition analysis must also account for rerolls and XP.

Run these via the game's `--tool=/absolute/path/to/script.gd` entry point against
a frozen patched export and an isolated profile. Before launching, set
`confine_mouse=0`, `show_fps=1`, and `volume_sfx=volume_stream=volume_voice=0`.
Run `arena_bot_tournaments.gd --games=12 --first-game=0 --all-new` for six paired
seeds with rotating economy, expansion, evolution and tempo policies. Compare
the same seeds before and after changes; retain raw JSON and executable/PCK
hashes. Policies are purchasing heuristics, not expert players. Automated
results screen for outliers and strategy imbalance; they cannot establish fun.

The 19 October follow-up includes 16 tournaments per build (eight seeds, two
policy rotations), with frozen before/intermediate/final records. Reproduce the
summary and exact whole-shop acquisition costs with:

```sh
python3 docs/validation/trials-balance-depth-2026-10-19/analyze.py
```

See [the balance depth report](../../docs/validation/trials-balance-depth-2026-10-19.md)
for the interpretation, remaining outliers and rendered planning-view checks.

## Multi-area CPU expression comparison (25 October 2026)

`campaign_cpu.gd` is the version-3 fixed-work companion to
`portal_throughput.gd`. Add `"zone":"gz1h"` and `"units":415` to the same
configuration shape; `ticks` can be 600 for a 33-second simulation window.
Each run requires the specified authored population and headless authority.
The result includes per-tick percentiles, the complete window, party health,
quest globals and whether native expressions were selected. Keep profiles
muted with the cursor free and FPS enabled as required for other fixtures.

Compare the same frozen export with and without `--ei-script-expressions`.
The flag selects the script evaluator in that process; automatic solo worker
children do not inherit it. For rendered worker comparisons use separate frozen
packs with the original and accelerated VM, with all other changes identical.
Use reversed order, fresh profiles, matching saves/settings, and record hashes.
Do not interpret instrumented runs as performance measurements. Animation
callbacks and wall-time budgets can vary state/RNG across separate runs even
without a code change; use the expression and scheduler regressions for semantic
equivalence. Simulation time is not rendered frame time or an FPS prediction.

The five-area results and original-code comparison are retained in
`docs/validation/cpu-traversal-2026-10-25/`.
