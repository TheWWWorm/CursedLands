# Android simulation process

This source is experimental, has been tested on Retroid Pocket 5 and is included
in the Experimental 5 ARM64 Android release. It separates a co-op host's
authoritative world from its local view using the same authenticated loopback
protocol as the desktop `LocalHost`. Ordinary single-player sessions still use
the inline world. This change does not make Portal sustain 60 FPS or true 2× on
the Retroid by itself.

The service runs a separate, headless Godot engine. It shares no mutable engine
objects with the visible engine. Android owns its binding and process lifetime;
the service is not exported. The foreground app pauses and resumes the service,
and each connection has its own generation so late callbacks cannot affect a
replacement. A fresh process is required for each new native engine instance.

To build a template, use the Godot commit in `engine_patches/godot-4.7/README.md`:

1. Apply the six common engine patches, then `android-headless-service.patch`.
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

Later native and rendering changes reach about 20.5 FPS in the final Portal run and 21–38 FPS
in the other measured expansion locations. Portal still falls short of actual
2×. See the [current handoff](../../../docs/performance-handoff-2026-10-07.md)
for settings, build provenance and limits. The private benchmark APK is not
a distributable player build.
