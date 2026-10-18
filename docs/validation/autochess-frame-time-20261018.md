# Autochess, interface and roster validation — 2026-10-18

Local development changes based on `adf05385` (1.16.0). No published tag,
release artifact or installed Godot template was changed.

## Performance setup

Measurements use a Ryzen 9 5950X, NVIDIA RTX 3090, driver 580.178.04,
Ubuntu 24.04, Vulkan Forward+, Ultra, uncapped FPS and VSync disabled.
The requested 2560×1440 window is clamped by the desktop to **2560×1366**.
The custom Godot 4.7 Linux release template includes the animation-cache patch.
All acceptance runs use Safe rendering, also the Windows project's default.
No builds, other game tests, simulation profiling, manual callback probes or
GPU timing readbacks run during the combat acceptance intervals.

`tools/benchmarks/arena_solo_frame_time.gd` drives the real solo screen and
private authority. Round 12 has nine simultaneous boards, seven two-star
creatures per side (126 figures), seed 7319 and the requested combat speed.
The old roster uses families 7/9/10/11/17/18/22; the new roster uses all six
added families and red harpies. Shopping plans are held fixed to keep the
combat load repeatable. The natural cases wait for every actual battle result;
the short old-roster samples explicitly pause the worker before forced settlement.
The fixtures refill the test armies between rounds, rather than simulating a
human's shopping decisions.

| Case | Round | Average FPS | Lowest rolling 1 s FPS | p99 frame, ms | Worst frame, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| New roster, scouting, 2× | 12 | 152.4 | 79.7 | 15.13 | 48.25 |
| Old roster, 2× | 12 | 103.5 | 84.2 | 18.15 | 33.43 |
| Old roster, 2× | 13 | 102.1 | 83.4 | 18.77 | 22.76 |
| Old roster, 2× | 14 | 99.9 | 78.5 | 18.55 | 25.17 |
| New roster, 1× | 12 | 118.3 | 92.0 | 14.98 | 18.64 |
| New roster, natural end, 2× | 12 | 120.5 | 88.5 | 14.09 | 26.75 |
| New roster, natural end, 2× | 13 | 118.7 | 84.8 | 14.19 | 35.51 |
| New roster, natural end, 2× | 14 | 118.5 | 88.2 | 14.35 | 29.66 |
| All nine boards, natural end, 2× | 12 | 136.0 | 83.0 | 13.68 | 31.59 |

[Raw performance samples](autochess-frame-time-20261018/performance.json)
include preparation, transitions, pipeline counters, simulation clocks, resource
counts and slow-frame positions. These measurements establish a margin above
60 FPS in the tested combat windows; they do not establish a 16.67 ms hard
per-frame deadline on every machine.

Round advancement releases every tracked old world/creature reference and
reuses all nine courtyards. Natural-round advancement takes about 17 ms
synchronously; the first 30 preparation frames average 92–106 FPS, with a
39–41 ms worst frame. Subsequent battle setup spreads model adoption across
frames. Cold first-battle shader preparation still has an isolated roughly
200 ms frame before the combat bell; it is not counted as combat performance.
Scouting has a 48 ms worst frame. There are no multi-second transition freezes
in these runs. Pipeline compilation counters remain constant during combat.

The separate real-host stress test renders a **3840×2160** field at Ultra,
2× speed and 4× MSAA, with a connected guest, seven CPU players, nine
three-star armies and eighteen extra fire emitters. During the watched fight
it records **66.39 FPS average, 61.47 lowest rolling 1 s FPS, 19.36 ms p99
and 54.65 ms worst frame**. The guest remains connected through settlement.
Its 23.78 seconds of combat are measured separately from the remainder of the
30-second observation window, so post-battle idle frames do not inflate FPS.
See [host samples](autochess-frame-time-20261018/host-performance.json).

An earlier diagnostic baseline recorded approximately 23–25 FPS and frames
above one second. Its simulation profiling was enabled, so it is not a clean
paired speedup denominator. The final table uses uninstrumented acceptance runs.

## What changed in the hot paths

Desktop solo combat moves to the existing private local-authority lifecycle.
The visible process retains economy, shopping and saves. Independent arena
random streams and exact headless animation ticks keep private-worker outcomes
and clocks equal to their inline reference. Pending outcomes, pause, empty
armies, worker shutdown and failure recovery have regression coverage.

Courtyards, static navigation and bounded surface/shader caches survive rounds.
Old combat worlds and units do not. Field figures and shop previews share one
model-construction budget. Immutable animation libraries prepare on two worker
jobs, and prepared opponents bind under their final world parent. Human
missing-target lookups are cached for one native animation-cache rebuild.
Shared arrows avoid repeated mesh/pipeline creation; equipment recoloring,
snow-mark rasterization and lightning geometry use optional native kernels.

The overview retains display-rate position interpolation and 20 Hz distant
poses/lightning, restoring full presentation on a focused board. Invisible
particles keep their descriptors and lifetimes without building particle
populations. Hidden grass and subpixel foot contacts skip work. Private
snapshots arrive in three groups at ten updates per board per second, retaining
pending effects. Most importantly, the original 252 antialiased circles per
frame are replaced by cached marker textures with the same radii and colors.
The marker path alone accounted for 3–5 ms of script drawing plus renderer work.

## Interface and localization

Menu and Trials text rasterize at their displayed Control scale. This fixes
scaled font softness; the lettering baked into the original 3D signpost's
source textures is still original artwork. Tribe emblems accompany localized
inspector names. Q/E uses continuous acceleration, RMB dragging uses a small
movement threshold, and camera timing is independent of 1×/2× combat. Focus
loss, modals and release events clear held input. Autochess menus install the
original cursor for arrow and button-hand shapes and restore the previous owner.

The global player name is edited in Settings → Remake → Network and co-op,
saved in the existing configuration, and reused by campaign multiplayer and
Trials. The name limit is 24 characters. The new profile dialog, camera help,
family labels and error text have English, Russian and German entries. All 18
new native form titles were resolved through the original language archives.
Rendered checks cover all three languages, inspector rows, scaled text, cursor
ownership, camera inputs and profile persistence across reloads.

## Recruitment and computer opponents

Six appended families expand the roster from 24 to 30 without changing saved
family indices: brigands, marksmen, battle mages, zombies, guards and ice
elementals. They retain native models, equipment, spells and combat prototypes.
Prices and copy requirements are mode rules, not changes to campaign creatures.
Zombies cost four gold after the initial three-gold tournament showed excessive
cost efficiency; their three-copy upgrades now cost as much in total as guards.

CPU players use four stable economy/expansion/evolution/tempo profiles. They
save toward interest thresholds, spend more when losing or near elimination,
replace obsolete units, pursue coherent upgrades, recognize alliance thresholds,
and place ranged attackers behind the frontline. They receive the same offers,
prices, income and combat rules as human players.

The native duel matrix compares six additions at all three ranks against the
24 existing families on both sides (864 fights). Another 216 paired fights
compare the additions with one another, for **1,080 completed native duels**.
Four full tournaments test the final prices. The new planner wins all four;
over 18 seats per planner its mean placement is **3.39 versus 6.61** for the
legacy planner. From round eight onward, its mean bank is **17.38 versus 4.49
gold**, with **1.54 versus 0.04 interest** per sampled preparation and a maximum
bank of 54 versus 11 gold. Runs finish in rounds 24–27. See
[balance summary](autochess-frame-time-20261018/balance.json) and
[complete tournament observations](autochess-frame-time-20261018/bot-tournaments.json).
Single-unit
duels expose strength/counter outliers but do not prove whole-team balance.
The recorded tournaments compare both planners under paired seeds and reversed
seat assignments; they are evidence of improvement over the old CPU, not a
claim of perfect balance or human-level play.

## Regression and build evidence

All **27 final acceptance fixtures pass**, covering the solo worker and its
recovery, round cleanup, host clock scheduling, formation and presentation,
roster rules, camera input, profile persistence, UI text, native geometry and
surface caches. The animation-cache lifecycle fixture reports 1,256 checks;
the missing-target fixture reports 36. Two ground-rendering fixtures require
the real renderer and were rerun successfully there (152 and 288 checks).
[Acceptance receipts](autochess-frame-time-20261018/acceptance-tests.json)
record the commands, exit codes and summaries.

Additional rendered checks cover the new roster and scaled menu/HUD text in
English, Russian and German. Translation validation reports zero errors across
2,651 remake entries, including 141 dynamic encyclopedia and 151 dynamic arena
keys. Independent ENet and WebSocket peers complete six rounds with matching
health and no disconnects. Speed persistence is checked in both directions.
[Supplementary receipts](autochess-frame-time-20261018/supplementary-tests.json)
and [peer results](autochess-frame-time-20261018/online-peers.json) preserve these
results.

Five Linux ASan/UBSan fixtures pass: fire (43,389 checks), spell particles
(101,055), equipment material colors (5,290), snow painting (6,291,456 channel
samples) and lightning (292,032 vertices). Leak detection is disabled for this
Godot embedding; the sanitizer run checks invalid access and undefined behavior,
while the round-lifecycle fixture checks release of old combat references.
See [sanitizer receipts](autochess-frame-time-20261018/sanitizers.json).

The custom Linux and Windows x86-64 engine templates include all fourteen
documented patches. Native helpers rebuild for Linux, Windows x86-64 and
Android ARM64. [Native build receipts](autochess-frame-time-20261018/native-builds.json)
and [build hashes](autochess-frame-time-20261018/build-manifest.json) identify the
local artifacts. Windows and Android results are compilation checks; only the
Linux runtime was executed. Local preview packages are unpublished.

One preliminary host benchmark crashed after retaining an effects node that
the game had correctly freed at battle end. The benchmark now checks instance
validity and measures combat separately. The corrected full observation run
above exits successfully; the crashed diagnostic is excluded from acceptance.

## Reproduction and platform limits

Run the standalone tools with the rebuilt template and original game data:

```sh
CursedLands.x86_64 --render-thread safe --gpu-index 0 -- \
  --ei-path=/path/to/original-game --no-movies \
  --tool=/absolute/repo/tools/benchmarks/arena_solo_frame_time.gd \
  --cycles=3 --seconds=65 --speed=2 --round-transitions --new-roster
```

Use `--overview` for all nine boards, `--scout` for switching boards every four
seconds, and omit `--new-roster` for the original stress army. The separate
`arena_host_process_frame_time.gd` fixture tests a real host, guest, seven CPU
players, nine three-star armies and eighteen extra native fire emitters.

The measured GPU is a desktop RTX 3090. A Windows RTX 4090 laptop was not
available for execution; native cross-compilation is not a Windows FPS test.
Linux native helpers are exercised both normally and under ASan/UBSan. Windows
x86-64 and Android ARM64 native libraries are compile checks. Unsupported
platforms retain script fallbacks; their performance is outside these results.
