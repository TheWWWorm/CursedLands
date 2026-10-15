# Android simulation process

The Experimental 5 ARM64 Android release separates a co-op host's authoritative
world from its local view using the same authenticated loopback protocol as the
desktop `LocalHost`. It has been tested on Retroid Pocket 5.

The subsequent, unpublished single-player checkpoint also uses this service for
ordinary campaign creation and loading. It preserves offline gameplay rules,
menu/controller pauses, saves and the original accelerated clock. Its private
ENet connection binds only to loopback on an automatically assigned port; it
does not advertise a multiplayer game. Platforms without the service retain
inline simulation. The public Experimental 5 release still runs single player
inline. See the [single-player checkpoint](../../../docs/portal-single-player-checkpoint.md)
for the implementation and validation boundaries.

The service runs a separate, headless Godot engine. It shares no mutable engine
objects with the visible engine. Android owns its binding and process lifetime;
the service is not exported. The foreground app pauses and resumes the service,
and each connection has its own generation so late callbacks cannot affect a
replacement. A fresh process is required for each new native engine instance.

The plugin also exposes Android's process-exit history to the existing crash
report. On Android 11+, the frontend registers a session token with
`ActivityManager.setProcessStateSummary`. After an unexpected exit, the next
frontend matches the OS record by package process name, PID and that token.
Simulation exits and older records with a reused PID cannot be attributed to
the frontend session. Android 12+ can additionally provide a native tombstone:
the report includes its signal, abort/cause text and up to 64 frames from the
crashing thread, with library names, relative addresses and build IDs.

Collection happens only after an unexpected frontend exit. It does not install
signal handlers or change rendering. The reader caps input at 4 MiB and excludes
memory dumps, other threads, registers, open files and logcat from its output.
If the OS no longer has the trace, or it cannot be decoded within those bounds,
the exit metadata and ordinary game log remain available. Older Android versions
and templates without the new plugin methods retain the ordinary report.
The player saves or copies the report through the existing dialog; nothing is
uploaded automatically.
Shipping these methods requires reinstalling the plugin sources into the engine
and rebuilding the Java export template; replacing only `libgodot_android.so`
in an older template does not include them.

The Android manifest also installs `StartupApplication`. It registers a session
and atomically saves `files/crash/android-startup.json` before the Activity or
native engine starts. The plugin marks the attempt before `GodotLib.initialize`,
then records native setup/main-loop stages. The journal is handed off only after
the game's regular crash marker for the same session has been written. The
simulation and restart-helper processes are excluded. A process created solely
to serve a file, without attempting the engine, does not trigger recovery.

An unfinished engine launch is retained on the next start. If it requested
Mobile or Forward+, Java writes a Compatibility override before the engine can
read its renderer settings. This covers both a new renderer trial and a
previously confirmed Vulkan choice. Saves and other settings are preserved.
The recovery report includes the attempted renderer, last Java stage, matching
Android exit information and native trace when available. An early engine log
is copied only if it changed during the failed attempt, with a 64 KiB limit.
Up to four failures are retained across subsequent clean launches until a
successful report-file export acknowledges them. Closing the dialog, copying
the report, or failing to save it does not erase the retained diagnostics.

`tools/tests/android_early_startup.gd` verifies this handoff, renderer recovery,
report retention/export and UI in an isolated debuggable QA package. The private
controller pauses Java immediately before `GodotLib.initialize`, verifies that
the native library has not loaded, sends SIGABRT, then relaunches. It checks the
fallback file and unchanged settings before allowing native initialization.
The pause hook belongs only in the private QA template; production sources and
templates contain no pause file, crash trigger or test bootstrap. Also verify
successful Mobile starts/restarts and the existing simulation lifecycle suite.

`python3 platform/android/simulation/tests/run.py` exercises the protobuf reader
on a JDK, including malformed, truncated and oversized input. The two-launch
`tools/tests/android_native_crash_report.gd` fixture requires an isolated,
debuggable QA package and an external controller: wait for
`user://native-crash-ready.json`, send SIGABRT as the package's UID to that exact
PID, wait for death, and relaunch. It checks the real OS record, session matching,
symbolication fields and saving through the startup dialog. Never run this
fixture against a player's installed package. The plugin contains no crash trigger.

To build a template, use the Godot commit in `engine_patches/godot-4.7/README.md`:

1. Apply all twelve common engine patches in the order documented in the engine
   README, then `android-headless-service.patch`.
2. Run `python3 platform/android/simulation/install_into_engine.py /path/to/godot`
   from this repository. It installs the Java plugin and private manifest entries
   into the template source, and checks conflicting entries.
3. Build the normal ARM64 release engine and Android export template with Godot's
   build system. Keep its matching `libc++_shared.so` in the template. Include the
   game's ARM64 GDExtension as described in the native guide.
4. Export a clean `game/` copy using that custom **release** template, the ARM64
   GDExtension and the existing public signing credentials. Preserve package ID
   `org.cursedlands.engine`; Experimental 5 uses version code 15. Include the
   repository, Godot, font and native-library notices, and exclude private
   benchmark tools and test bootstrap changes. The template and APK must not
   have `android:debuggable` enabled. Stock templates have no
   `EISimulation` singleton and retain the inline host automatically.

The 10 October local continuation rebuilds Android from the same pinned Godot
commit with all twelve common desktop patches plus the service patch. Its
release engine was tested in an isolated, debuggable private container on
Retroid Pocket 5: settings/presets/attack/pollen/startup162 checks, Mobile startup10,
service lifecycle22 and real Home/resume12, all passing. These are bounded
qualification checks, not a reproduction of the reported Adreno610 load exit.
See [the device/settings receipt](../../../docs/validation/device-settings-gameplay-2026-10-10.json)
for native hashes, frozen fixtures and platform limits. Player APKs must still
use a clean non-debuggable release template and exclude the private bootstrap.

The device lifecycle test is `tools/tests/android_simulation_lifecycle.gd` (and
its `android_service_counter.gd` child). It checks immediate cancellation,
duplicate starts, restart, stale handles, independent process IDs, background
pause/resume and actual process termination. `tools/tests/local_host_worker.gd`
also exercises the owner protocol, paused commands, authoritative saves,
thumbnails, reload and cleanup; pass a disposable save copy via `--save`.

On Retroid, the private service build passed 22 lifecycle checks and 33 campaign
checks. A real Home-button test also confirmed a held simulation counter in the
background, progress after resuming the same child, and clean shutdown.
An earlier matched Portal pair averaged 3.93 FPS inline and 8.50 FPS with the
service, but only 37 simulated seconds elapsed in 30 real seconds with 2×
selected. These are incomplete performance results, not acceptance numbers.

The published native and rendering changes reach about 20.5 FPS in the final Portal run and 21–38 FPS
in the other measured expansion locations. Portal still falls short of actual
2×. See the [current handoff](../../../docs/performance-handoff-2026-10-07.md)
for settings, build provenance and limits. The private benchmark APK is not
a distributable player build.

The later single-player checkpoint measures 43.95 FPS median at actual Original
graphics and 1× in Portal, versus 11.83 inline in the same private APK. A
three-minute living-party walk averages 44.65 FPS. Neither is stable 60 FPS.
The service saves authoritative single-player state on Android's application
pause notification: the frontend's save request may still be queued when the
service suspends. `tools/tests/single_player_android_background.gd` plus an
external Home/resume controller verifies the save reaches disk before resume.

The subsequent [touch-picking checkpoint](../../../docs/portal-touch-picking-checkpoint.md)
raises that same walking route to 49.55 FPS median in two 60-second runs, versus
44.53 in contemporary controls. Stable 60 FPS remains unfinished; both later
checkpoints are local and unpublished.

The local [foreground redraw checkpoint](../../../docs/portal-foreground-redraw-checkpoint.md)
reduces repeated minimap and sound-state work. The same Original/1× single-player
loop measures 52.92 FPS median versus 49.02 in restored controls; a three-minute
walk averages 53.44 FPS with both party members alive. Stable 60 FPS remains open,
with p95 25.14 ms and a 94.64 ms worst frame in the longer run. The private build
uses the same production engine and native module. The worker-presentation
suppression experiment was diagnostic only and was not retained.
