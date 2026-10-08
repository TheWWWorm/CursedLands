**Latest local checkpoint, 8 October — retained HUD controls:** Original graphics / 1× on Retroid improves modestly: **52.15 → 53.64 FPS** median across two reversed 60-second pairs, and **54.20 → 55.24 FPS** in a matched three-minute pair. The longer candidate keeps both party members alive and all 415 actors, advances 179.905 simulated seconds, and has p95/p99 frame times of 24.449/27.931 ms. **Stable 60 FPS remains open.** Clock face drawing and lower HUD geometry are retained between relevant changes; animation, input and visual output are preserved. All 107 checks pass on Linux GL, packaged Forward+ and physical Retroid. Production engine/native binaries and graphics quality are unchanged. The measured private APK49 is installed with autorun disabled and both processes stopped. See [report](portal-foreground-controls-checkpoint.md) and [validation](portal-foreground-controls-validation.json). Public Experimental5 is unchanged. Windows 4K/max/D3D12 at about 40 FPS remains unresolved; another longer Linux 4K attempt was stopped for unrelated Godot activity and excluded. Next: reduce larger actor/effect stages, and require repeated full-tick gains for simulation changes.

**Investigation update, 8 October — authority placement rejected:** exact native batching passes 12,011 placement checks on Linux/Retroid plus existing client and spline checks, but actual Original / 1× Retroid gameplay measures **52.30 FPS candidate versus 52.41 FPS restored control** across reversed pairs. The added implementation and rebuilt native modules were fully reverted; all 520 game files match retained code checkpoint `7aa3d07`. The latest retained three-minute living-party Retroid result remains **53.44 FPS**, below stable 60. A clean Linux RTX 3090 / Vulkan / 4K / 100% / max / 2× co-op pair measured **62.07/64.54 FPS**, but its opening ten seconds were only **46.9/49.6 FPS** and a party death then changed the workload. One pair does not justify retaining the batch or claiming a Windows fix. The longer living-party desktop attempts were stopped/refused for unrelated Godot activity and are excluded. Private production APK47 is restored, autorun is disabled and both private processes are stopped. No public release or original Android installation was changed. See [experiment and evidence](portal-authority-placement-experiment.md) and [validation](portal-authority-placement-validation.json). Next: remove repeated foreground-stage work; require repeated complete-tick gains for further simulation redesigns.

**Latest local checkpoint, 8 October: foreground redraw.** Actual Original graphics
at 1× on Retroid now measures 52.92 FPS median in two reversed 60-second pairs,
versus 49.02 FPS in restored controls. A three-minute living-party walk averages
53.44 FPS and advances 179.905 simulated seconds. Stable 60 FPS remains open.
This changes minimap redraw scheduling and sound-state allocations; it does not
change simulation or graphics quality. See the [checkpoint report](portal-foreground-redraw-checkpoint.md)
and [validation](portal-foreground-redraw-validation.json). These changes are
unpublished, and the reported Windows 4K/max/D3D12 slowdown remains unresolved.

# Experimental 5 performance and gameplay handoff

For subsequent local optimization, see the [Portal throughput checkpoint](portal-throughput-checkpoint.md)
and its [validation record](portal-throughput-validation.json). That unreleased
CPU checkpoint improves complete-simulation time; Retroid's 60 FPS/actual 2×
target and the reported Windows 4K slowdown remain unresolved.

This checkpoint gathers the completed performance work and gameplay repairs on
`release/1.0.3-experimental.5-performance`, version `1.0.3-experimental.5`.
It retains the Experimental 3 integration and the local Experimental 4 checkpoint
`bdaf986bc196a56c55f0b24530f47eb1f98d9d69`.
[Experimental 5 downloads](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.0.3-experimental.5)
use tag `v1.0.3-experimental.5` and include Linux/Windows x86-64, Android ARM64
and universal macOS packages. The earlier branch-only delivery did not create a
GitHub release; these packages are the subsequent publication checkpoint.

**Stable 60+ FPS at actual 2× simulation speed is still not achieved across the
requested devices and locations.** This is a usable experimental checkpoint,
not completion of the performance target. The
[validation record](experimental5-validation.json) separates current results
from earlier comparisons and component microbenchmarks.

## Included repairs

- Retain all eight [campaign and presentation repairs](bugs-2026-10-07.md):
  recruiter and tunnel progression, persistent camp grants, quest-item clicks,
  co-op movie completion, wall visibility, shop spells and inventory rotation.
  Experimental 3's expansion travel, narration, faces/equipment, border fog,
  invisible-blocker cleanup and snow/sand trails remain included.
- Restart repeated non-looping Terror (Ужас) actions using an action serial,
  so its wings animate during consecutive attacks. Apply the authored creature
  spell damage, including `curse_magic` and `rick_magic`, so guards and heroes
  can take damage and die. The focused regression has 22 passing checks; the
  final Portal device run records 22 wing animation keys and party deaths.
- Resolve delayed spell callbacks through weak references and validate their
  world before using a caster removed by a quest. Its 32 checks pass on Linux
  and ARM. This fixes a real lifetime error found during longer device runs.
- Repair separated-host travel in the original multiplayer campaign (LMP).
  Player zero still needs a remote map publication and loading acknowledgement
  when its view lives in another process. Base → quest → base, commands,
  character persistence and shutdown pass 19 checks. Also guard stopped process
  handles so liveness checks do not call the OS with PID −1.
- Keep save-thumbnail writes in the authority process. A delayed automatic
  capture carries a per-save ticket and cannot overwrite a newer manual image,
  even when the visible process has not received the cancellation yet.

## Included system changes

Co-op hosting separates the authoritative simulation from the local player's
presentation in independent processes. The owner remains player zero. Commands,
shared pause, saves, thumbnails, reloads, movie barriers and cancellation use the
normal networking rules. Desktop rendering has its own engine thread on Linux
and Windows. Android uses a private, bound headless Godot service with a separate
engine and scene tree; backgrounding the app pauses the service and resuming it
continues the same instance. Ordinary single-player remains inline.

The native extension now also covers actor eligibility and perception batches,
owned route construction/sampling, navigation preparation and turn geometry,
unit presentation/interpolation, fire and spell particles, bulk particle draw
buffers, grass construction, soft-ground mesh work, audio and MMP decoding.
The actor-lifetime registry retains live scalar inputs and shared container
backing stores, with generation-safe unregistering on actor/script replacement.
It is authority-thread state, not data for unsynchronized worker access.

The remaining script-driven AI decisions and movement orchestration are still
large costs. Faster native route construction and registered actor reads pass
parity and sanitizer checks, but the latest 550-tick Android comparison showed
no material full-tick improvement: 26.51 / 26.57 / 26.74 wall seconds for owned /
object / owned reads over 30.25 simulated seconds. Do not promote those
microbenchmark gains to whole-game FPS claims.

Android Compatibility rendering uses a bounded terrain color cache: two workers,
128 MiB resident texture budget and at most one upload per frame. Existing water,
weather and lighting remain active. Terrain sectors use four 16 m draw pieces
instead of one 32 m mesh, retaining all authored attributes and triangles. The
active layout is released when switching; soft-ground deformation returns to
the original full-sector layout after joining outstanding jobs.

Smaller terrain bounds change which local lights reach each draw. They can light
ground that the old mesh's per-object light cap left dark; lit screenshots are
therefore not pixel-identical. A frozen Portal diagnostic improved from 28.00
to 35.42 FPS with 16 m pieces, returning to 27.72 after restoring 32 m sectors.
That result is not a gameplay benchmark: Portal gameplay remained about 19.3 FPS.
Eight- and four-metre pieces added draw overhead for little further benefit.
The Vulkan cache path remains disabled because a rendered brightness mismatch
was found despite passing synthetic color tests. A zero-contribution light
shader branch regressed and was excluded.

## Current measurements

The desktop reference is Ryzen 9 5950X / RTX 3090, Forward+ Vulkan, 1280×720,
scale 1.0, normal graphics, Distant AI off, unrestricted OS scheduling, a local
owner, authority worker and real co-op guest. Two final clean-package Portal
runs at 2× average **77.87 and 115.99 FPS**, with p95 **22.20 and 13.49 ms**,
worst frames **80.91 and 82.62 ms**, and **59.73 and 59.84 simulated seconds**
in 30 wall seconds. They use the same frozen pack and settings; the significant
run-to-run variation is retained in the record. Neither result establishes
locked 60 FPS. The earlier worker25 run averaged 102.79 FPS and is historical
context. Earlier bounded outdoor runs exceed 60 FPS on average but retain
individual 70–160 ms stalls. These are not full-map guarantees.

Retroid Pocket 5 uses Android 13 / Adreno 650, Compatibility OpenGL, 1920×1080
viewport at 0.75 render scale, four engine workers, one owner with an isolated
authority service and 30-second gameplay windows. Requested speed is 2×.
Grass, soft ground, SSAO, volumetrics and water reflections are off; terrain,
water, weather surfaces, fire lighting and combat remain on. These settings
are not equivalent to the desktop graphics configuration.

| Lost in Astral scene | Average FPS | p95 frame | Simulated time / 30 wall seconds | Initial units |
| --- | ---: | ---: | ---: | ---: |
| Portal | 19.35 | 73.94 ms | 37.84 s | 414 |
| Suslanger city | 21.03 | 72.11 ms | 34.48 s | 323 |
| River and Islands | 25.52 | 52.44 ms | 50.43 s | 294 |
| City Environs | 37.94 | 36.67 ms | 59.78 s | 207 |
| Dead City | 36.38 | 35.69 ms | 59.84 s | 262 |

This sweep uses APK20 for Portal/Suslanger and APK21 for the other three
(version-only change). The final APK23 Portal repeat, including the packaging
repairs, reaches **20.50 FPS**, p95 **70.88 ms**, worst **117.00 ms**, and advances
**36.685 simulated seconds in 30 wall seconds**. It records 22 wing animation
keys and exits without runtime errors. These runs show variation, not a matched
performance gain from the packaging repairs.
All five runs completed with zero recorded runtime errors. City Environs and
Dead City approximately sustain actual 2×. Portal, Suslanger and River do not.
The earlier 3.74 FPS result predates multiple architectural and visual pipeline
changes, so it is not a matched before/after ratio for any single change.

## Validation and build instructions

The final candidate passed 37 focused Linux fixture runs, including both
campaigns' shop stocks, story/movie logic, combat, native parity, navigation,
particles, terrain, loading and worker clocks. Terrain layout has 17,946 checks
on Linux and ARM, plus 1,346 ARM cache/deformation/toggle lifecycle checks.
Actor registry, live eligibility, senses, perception and route construction
passed ASan/UBSan; production libraries were restored after sanitizer runs.
Android previously passed 22 service lifecycle and 33 owner/save/reload checks.
The final APK23 owner/save/reload test again passes all 33 checks, including
an explicitly late screenshot after a newer manual save. The Linux clean pack
also passes 33 owner/save/reload, 19 LMP travel, 19 campaign/movie/cancellation,
216 rendered shader and 17,946 terrain-layout checks, plus recruiter legacy
reload and Kel tunnel progression. The latter story, shader, terrain and
campaign checks preceded the final thumbnail-only repair; save/reload and LMP
were repeated on the final pack. Two gameplay scripts changed after the core
suite; the other 202 compiled scripts are byte-identical.
A real Home-button test held the child counter at 30 frames while
backgrounded and resumed to 155, with the same child PID and no leftover process.

Desktop export templates use Godot commit
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` with the **six** common patches listed in
[the engine guide](../engine_patches/godot-4.7/README.md). Do not substitute the
older four- or five-patch templates from previous handoffs. Follow
[the native build guide](../game/src/native/source/README.md) for Linux, Windows
and ARM64 libraries, and [the Android service guide](../platform/android/simulation/README.md)
for the additional headless patch and Java integration. Stock Android templates
lack the service and automatically retain inline hosting.

Export a clean copy of `game/` with these matching templates. Keep private tools,
profiles, original assets and saves out of the export. All co-op participants
must use the same experimental build (protocol 5). The engine still requires the
player's original game data. The audited desktop packages each contain 557 resources and 204 compiled
gameplay scripts, with no private probes, original game data or user saves. Windows is cross-compiled; it has not been executed on Windows.
The public Android APK is a clean release export, without the private benchmark
bootstrap or probes. It uses the tested production ARM64 engine and native
library, the six common patches and Android service integration. It retains
`org.cursedlands.engine` and the previous public signing certificate, with
version code 15. Experimental 5 Android supports ARM64 only; older public
packages also included x86-64. The private profiling APK remains separate and
is not a release asset.

macOS includes Intel and Apple silicon executables from the stock Godot 4.7
template, with the same 204 gameplay scripts and their native-free fallbacks.
It does not include the patched engine or native hot paths, and it has not been
runtime-tested on macOS. The app is unsigned and not notarized. Do not apply
Linux or Retroid performance measurements to the macOS package.

Useful diagnostic fallbacks are `--ei-inline-host`, `--ei-script-motion-build`,
`--ei-script-motion`, `--ei-script-unit-state`, `--ei-script-terrain` and
`--ei-whole-terrain`, passed after the engine's `--` separator. Retain the normal
55 ms simulation clock, gameplay timing and live actor state when comparing.

## Remaining work

1. Batch more AI decisions and movement orchestration into owned native data
   processing. Profiles still show repeated per-actor script/engine dispatch.
   Separate scalar-oracle correctness from whole-frame acceptance.
2. Extend simulation separation to ordinary single-player with save, pause,
   movie and travel parity. Do not claim the current co-op service covers it.
3. Profile visual callbacks, driver submissions and GPU cost independently.
   Terrain subdivision is a limited rendering gain; Portal still needs major
   simulation and presentation improvements to reach 60 at actual 2×.
4. Repeat extended Portal combat, post-tunnel Suslanger travel, open-world and
   expansion gameplay on the actual targets. Report p95/p99/worst frames and
   simulated seconds, not just average FPS or a selected 2× setting.
5. Validate Windows and macOS, real WAN co-op, longer Android background/resume and
   physical touch/controller paths. Two earlier desktop NVIDIA Xid 32 / Vulkan
   device-loss startup failures remain an unresolved environment/runtime issue.

The original user saves, original game data and the user's regular Android
installation remain untouched. Failed experiments and setup failures are
retained separately as evidence and are not counted as passing results.
