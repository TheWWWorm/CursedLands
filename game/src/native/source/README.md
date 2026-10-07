# Optional compiled hot paths

The `TerrainSearchKernel` extension accelerates integer terrain distances,
component labels, bounded AI reachability, block routes, moving search windows, and obstacle-stamp
painting. It leaves AI scheduling, the 55 ms simulation clock, and network
messages in GDScript. Each terrain instance belongs to the existing navigation
map revision. Stamp painting is stateless and always uses the current units.

The script implementation remains available when the extension is absent and
with the `-- --ei-script-nav` diagnostic launch option. Libraries are supplied
for Windows x86-64, Linux x86-64 and Android ARM64. Web, macOS and other Android
architectures must exclude this extension and its binaries to use the script
implementation. Published packages may predate the Android native helpers;
the ARM64 build has been tested in a separate private Retroid Pocket 5 app.

The terrain instance also owns persistent static block topology: representatives,
weighted edges, connectivity, labels and bounded endpoint-seed caches. Door,
floor and object changes invalidate it through the existing map revision.
Moving actor occupancy remains a live input to each search window. Directed
slopes, blocked starts and tie ordering retain the script graph's results.
`-- --ei-script-topology` keeps the original topology adapter for comparison;
older libraries automatically use it. Large script edge tables are allocated
only if a fallback actually needs them.

Before a loaded zone is published, independent movement classes prepare their
static connectivity and all weighted edges in occupied components on worker threads. Each job owns
one graph, and loading joins every job before gameplay or network callbacks can
access those graphs. Later map edits retain the existing invalidation path;
actor occupancy is never prepared or cached this way. `-- --ei-lazy-nav` keeps
first-use preparation for comparisons; `-- --ei-lazy-route-weights` prepares
connectivity while retaining first-use edge weights. Preparation runs at high
priority while loading so small desktop pools can use all available workers.

`NavTurnKernel` runs the ordered local path-refinement loop using the original
81 templates. Every request owns its frontier, chains and cost cache, and reads
the shared map arrays without detaching them. Live actor stamps are captured
synchronously for each changed search rectangle. The retained `NavTurn.refine_script`
is selected by `-- --ei-script-turn`, by `-- --ei-script-nav`, or automatically
when the helper is unavailable. Tests compare routes and costs, including large
maps, directed slopes, stamp changes and original executable reference cases.

`MmpTextureKernel` decodes the authored raw 16/32-bit texture formats, and
`AudioDecodeKernel` converts IMA sound blocks to identical PCM bytes. Audio calls
have independent predictors and output buffers, so the existing sound-prefetch
workers can share the decoder. `-- --ei-script-audio` selects the script decoder.

`UnitPresentationKernel` batches replica interpolation and placement before
animation and camera callbacks. It reads common terrain revisions once and
preserves the script transform/cache rules. Scene changes remain on the main
thread. `NetSmoothKernel` holds typed replica interpolation and placement
records so stationary actors avoid repeated script-property lookups. Direct
script placement invalidates the copied record; terrain/floor revisions and
external transform edits retain their original checks. `-- --ei-script-presentation`
selects both scalar implementations. These helpers need `Node3D` and `Time`
in the generated binding profile.

`SoftGroundMeshJob` tessellates and assembles touched snow/sand sectors in
compiled worker jobs. Jobs own immutable packed snapshots; scene nodes,
materials, textures and mesh installation remain on the main thread. Later
contacts are coalesced, while expiry, capacity resets and sector replacement
invalidate older results. World cleanup joins outstanding jobs. Subdivision,
triangle order, interpolated attributes and local shadow geometry match the
retained script implementation (`-- --ei-script-soft-ground`). Unsupported
platforms or mesh layouts use that script path automatically.

`MotionSplineKernel` constructs and owns the typed nodes and coefficients of a movement
route, without allocating a script dictionary for each control and node.
Debug/inspection records are exported lazily. Its samples retain double intermediates, float Vector2 rounding and
the scalar interval order, including zero-speed paths and backward seeks.
`-- --ei-script-motion` uses the retained scalar evaluator. Platforms without
this class use the same fallback automatically. `-- --ei-script-motion-build`
keeps script construction while using native sampling for matched comparisons.
The construction fixture passes 57,185 checks on Linux, Android ARM64 and with
address/undefined-behavior sanitizers. The large isolated construction gain is
not a comparable whole-game gain: the Retroid full-tick profile improved little.

`UnitSimulationState` retains live actor inputs for native activity/perception
consumers. Scalar setters publish changes; arrays and dictionaries retain their
actual backing store, including nested/in-place edits. These records are confined
to the authority thread, **not** immutable worker inputs. The object-ID registry
does not own actors or records. A unit-owned generation-checked lease unregisters
on deletion, state replacement or script replacement; consumers acquire record
references under the registry lock. Custom scripts and absent records retain
the property-based path. `-- --ei-script-unit-state` disables record creation.
Native activity batches retain the quiet set and initial positions, while all
eligibility decisions still recheck live health, metadata and revision guards.
The record, activity and perception fixtures pass on Linux/ARM64 and under
sanitizers. Full 550-tick Retroid comparisons currently show no material speedup;
this is infrastructure for further batching, not a completed simulation redesign.

`FireParticleKernel` updates complete fire/smoke emitters in one native call.
It captures the emitter's settings once and keeps its own arrays and RNG on
the existing particle worker. Inner loops no longer dispatch GDScript callbacks
or validate emitter objects for each particle; stable compaction also removes
repeated array shifts. The scalar callback path remains the oracle and fallback
for missing libraries and custom callbacks (`-- --ei-script-fire`). Particle
order, all interpolation fields and the subsequent RNG state are identical.
`tools/tests/fire_particles.gd` covers lifecycle boundaries, changing wind and
emission settings, custom callbacks and concurrent independent emitters.
The generated binding profile includes `RandomNumberGenerator` for this helper.

The extension and its bindings compile with `-ffp-contract=off`, matching the
engine. This is required for exact interpolation on ARM: fused multiply/add
otherwise changes intermediate rounding and subsequent movement state.

`NavigationBuildKernel` constructs the initial height/liquid cells, dry-cell
classification, movement-class weights and dilation, AStar grids, and connected
regions in bulk. It returns the same packed arrays consumed by the existing
search and dynamic-update code. Region relabeling after object/lever changes also
uses the helper. Component IDs retain first-cell row order. Inputs are current
map data; no navigation state is read from a persistent cache.

`NavGrid` keeps its original script construction when the new class is absent,
including with older desktop libraries, or when `-- --ei-script-nav` is set.
The build profile includes `AStarGrid2D` for the bulk grid writes.

Derived foliage masks have a separate, platform-independent cache under
`user://cache/foliage-v1`. Entries are keyed by normalized source pixels,
dimensions and texture name, contain checksummed RGBA data, and are replaced
atomically. A missing, stale, corrupt or unwritable entry uses ordinary mask
generation. Bump the cache version when changing the mask algorithm/regions.
No original game data or generated cache entries belong in an export.


`UnitQueryKernel` accelerates ordered cell filtering and nearby-unit list
validation. Combat queries sample the live registry, including changed IDs
and same-count replacements; a synchronous all-player flag batch shares that
sampling. World spatial queries reuse an ordered roster snapshot until its
explicit membership or registration revision changes. Live membership edits
use `World.set_unit`, `erase_unit`, spawn/removal, or whole-roster replacement;
the exposed dictionary and row array are read-only. An owner-free unit lifetime
token also invalidates the order cache on freeing or script replacement. Its
perception rows store only faction/controller/dead/hidden fields; field edits
invalidate them, and a unit-owned `UnitNoticeLifetime` token invalidates them
on destruction or script replacement. The token must remain owned solely by
its unit. Caches are capped at 1,024 observers and a conservative 8 MiB.
Diplomacy, positions, native refresh timing and random draws retain their
existing sampling points. `-- --ei-script-units` selects the script path.

For fully registered local perception queries at positive coordinates,
the helper filters the existing coarse buckets by the exact notice-cell mask
before reading and ordering their units. Radius and final cell checks remain
unchanged. Queries crossing zero, very large queries, unregistered worlds,
and platforms without the helper retain the existing two-pass path.

`ScreenRectKernel` calculates bounds from the same posed vertices, frustum
clipping and nearest-even pixel rounding used by `MeshScreenRect`. It does
not substitute boxes for exact mesh geometry or retain scene references.
`-- --ei-script-picking` selects the script path. The script implementations
also remain active automatically on platforms without the extension.

## Build

Use CMake 3.22+, a C++17 compiler, Python 3, and the MIT-licensed
[godot-cpp bindings](https://github.com/godotengine/godot-cpp) at commit
`507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`. The extension targets Godot 4.7.
The checked-in build profile restricts generated bindings to the classes used.

```sh
git clone https://github.com/godotengine/godot-cpp.git /path/to/godot-cpp
git -C /path/to/godot-cpp checkout 507ed9d840c01a3c5b2a39af8bb4000bfac30bf5
cmake -S game/src/native/source -B /path/to/navigation-build \
  -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_DIR=/path/to/godot-cpp
cmake --build /path/to/navigation-build --config Release --parallel 4
```

For the development tree, replace `game` with the project directory. Copy
`libterrain_search.so` or `libterrain_search.dll` into `src/native/bin` before
importing and exporting the Godot project. A Windows cross build can use a
MinGW-w64 CMake toolchain; the build links its compiler runtimes statically.
Do not use CPU-specific compiler flags for distributed binaries.

For Android ARM64, use the NDK CMake toolchain (tested with NDK 29.0.14206865):

```sh
cmake -S game/src/native/source -B /path/to/navigation-android \
  -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_DIR=/path/to/godot-cpp \
  -DCMAKE_TOOLCHAIN_FILE=/path/to/ndk/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_static
cmake --build /path/to/navigation-android --parallel 4
```

Copy that build's `libterrain_search.so` to
`game/src/native/bin/libterrain_search_android.so`. Retain the ARM64 library
entry when exporting an ARM64 APK. Android x86-64 requires its own compatible
build or an export that excludes the extension; the Linux library is not an
Android x86-64 library. Reconfigure CMake after changing `build_profile.json`
so newly required bindings are generated.

Distribute `NATIVE_NAVIGATION_NOTICES.txt` with the shared library. It contains
the binding and Windows runtime notices. Android builds also distribute
`NATIVE_ANDROID_NOTICES.txt`, preserving the NDK toolchain and sysroot notices
for the statically linked C++ runtime. The engine's existing notices still
apply. Engine assets and original game data are separate; no original data is
part of this extension.

## Verification

Tests in the development tree compare every distance and moving-window field
against the script implementation, including directed slopes, blocked cells,
overlap/reopening, stamp thresholds, and equal-cost queue order. Random block
routes and stamp clipping are checked separately. Integration tests compare
recorded unit state, paths, orders, combat events, and random-generator state
through the same number of native simulation ticks.

Performance measurements must compare equal simulation work in release builds.
Headless fixed-step throughput is CPU cost, not a measurement of player FPS.

The public `tools/tests/nav_topology.gd`, `motion_records.gd`,
`registry_queries.gd` and `dynamic_navigation.gd` fixtures cover the persistent
records, scalar oracles, same-size roster edits and a real changing door with
live occupancy. Run them through `--tool=/absolute/path/to/the/test.gd` after
the normal `--ei-path` argument. Dynamic navigation requires Lost in Astral
content; the other fixtures use synthetic records. The navigation and motion
suites have also run under ASan/UBSan on Linux. The final benchmark report is
`docs/performance-systems-2026-10-07.md` in the repository root.

`nav_build_test.gd` compares every generated array and AStar cell against the
frozen script builder, with all eight classes, boundary costs, liquid/height
cases, and object/floor insertion/removal. `nav_build_map_test.gd` repeats the
comparison on actual maps. The frozen reference changes only its class name and
the typing of unused path-refinement calls. `foliage_cache_test.gd` compares all
supported atlas pixels/mipmaps and checks content invalidation and corruption.

The unit-query tests also cover registry mutation, freed nodes, script
replacement and exact cell boundaries/order. Geometry comparisons cover
clipping, projection modes, morphs and cache reuse. Run the native helper
suites under address/undefined-behavior sanitizers in a private test build.

## Shared AI activity pass

`AIActivityKernel` summarizes faction/stimulus masks in spatial cells from packed
arrays, then marks potentially active observers. It is an intentionally
conservative activity filter, separate from exact sight and combat decisions.
Its standalone `ai_activity_core.h` uses only owned C++ data and does not access
Godot objects, scene state, shared mutable caches or RNG. Linux, Windows and ARM64 Android
ship the kernel; the same scheduler has a GDScript fallback on other platforms.
`-- --ei-script-activity` selects that fallback. `-- --ei-legacy-ai` disables
reactive scheduling entirely. See `docs/ai_activity.md` for behavior and wake-up
contracts. The earlier statement about leaving AI scheduling in GDScript still
applies: the scheduler still chooses when to defer. Its live actor eligibility
predicate is also compiled, with the independent `_eligible_script` fallback.
It reads current fields and metadata on the main thread at decision time;
no wound, command, script, deadline or perception condition is cached.
`tools/tests/ai_live_eligibility.gd` covers immediate mutation and scaled body HP.

`tools/ai_activity_test.gd` checks the bridge and scheduler;
`tools/ai_activity_core_test.cpp` can be compiled independently with C++17 and
ASan/UBSan. Its optional extra argument runs synthetic scaling measurements.
`tools/reactive_gameplay_test.gd` checks real-map reaction, stealth and patrols.
The main-world CPU cost includes packing, live eligibility checks and the
existing unit loop; kernel timings alone are not a gameplay benchmark.

## Bounded AI reachability

Before constructing a route merely to judge an attack or spell option, AI can
prove that its actor is trapped outside the action's range. The proof visits at
most 128 cells inside a 17-by-17-cell window, using current terrain, directed
slope rules and the same max-combined occupancy stamps as the planner. The
actor and its target are excluded from those stamps. Any possible endpoint in
a reachable cell is covered by a conservative range margin.

Reaching the window boundary, approaching the target, or hitting the work limit
means unknown and immediately uses the existing planner. A completed sealed
component can reject the option without generating a path, turn refinement or
retries. No result persists across decisions: moving units, deaths, teleports
and changed doors are considered on the next call. Map revisions still own
static terrain kernels.

The native method and GDScript fallback implement the same certificate. Older
libraries without the method also use the fallback. This does not change AI
tick frequency, movement commands, save data or the network protocol. The
private `reach_pocket_test.gd` fixture compares both implementations and checks
positive certificates against complete weighted floods.

## Particle and grass batches

`FireParticleKernel` and `SpellParticleKernel` own particle state and random
streams through complete update/spawn/compaction passes. The script adapters
retain scene-dependent carrier setup and custom callback fallbacks.
`GrassFieldKernel` captures immutable terrain and texture inputs once; bounded
`GrassChunkJob` workers produce complete MultiMesh buffers without scene access.
The game installs those buffers on its main thread and joins stale jobs on zone
teardown. Windows, Linux and Android ARM64 include these helpers.

The focused fire, spell and grass fixtures compare the retained script paths,
including random streams, particle controls, rotated terrain tiles and actual
rendering-buffer readback. The spell fixture passed 76,995 checks on Linux and
Android; grass passed 3,719 rendered checks and 196 authored-map checks on both.
Native fire, spell and grass code also passed ASan/UBSan fixtures on Linux.
These checks establish equivalence of those kernels, not whole-game frame rates.

`PerceptionKernel` evaluates a whole list of new perception candidates in one
native call at the original decision point. It reads authored packed float32
and float64 detection vectors directly, combines live effect modifiers and
preserves the exact cone, distance and peripheral/life-sense boundaries.
Occlusion remains a synchronous world query in original candidate order;
NPC filtering, the retained-target drop pass and corpse suspicion retain
their existing ownership. Custom unit/AI/world scripts use the original
ordered loop. No cross-tick visibility cache or worker access to scene
objects is introduced. `-- --ei-script-perception` selects the script path.
The regression fixture compares numeric boundaries, ray-call order and full
AI metadata transitions, including live diplomacy, death and hiding. It
passes 2,857 checks on Linux and Android ARM64, including the authored
packed-vector path, which also passes ASan/UBSan on Linux.

`ParticleDrawBuffer` packs and sorts one emitter's complete MultiMesh buffer
in compiled code. Each effect owns its writer; independent emitters may run
concurrently, while scene and rendering submission remain on the main thread.
Instance order, previous/current positions and colors, atlas rectangles,
capacity growth, culling bounds and reach match the retained scalar packer.
Returned buffers remain immutable when the next tick reuses the writer.
Unsupported records switch that effect to the scalar path; the diagnostic
`-- --ei-script-particle-buffer` selects it globally. The fixture passes
1,723 Linux checks and 1,963 Android checks, including actual MultiMesh
readback, and ASan/UBSan. The inner-loop improvement did not measurably raise
Portal's whole-game frame rate by itself.

`TerrainColorField` captures immutable tile codes and owned RGB bytes, then
builds mipmapped sector color textures on two bounded workers. A shared
256-entry lookup table avoids expanding every source channel to float.
Source atlas storage is bounded to 128 MiB; map codes are stored separately.
The scene-side `TerrainColorCache` additionally limits resident textures to
128 MiB and uploads at most one completed sector per frame. Loading prepares
visible sectors before play, camera changes queue missing sectors, and
uncached sectors retain the original shader. Cleanup joins all jobs.
Geometry, dynamic lighting, weather, water levels, relief and sharpening
keep their existing renderer paths. Soft-ground mode uses its original
materials. Android Compatibility enables the cache automatically; other
Compatibility platforms can opt in with `-- --ei-baked-terrain`, and
`-- --ei-script-terrain` disables it for comparison. Unsupported renderers
retain the original shader. The compact source representation passes 2,598
checks on Linux and Android plus ASan/UBSan, with 173 device cache lifecycle
checks. An extended linear/sRGB fixture adds Vulkan color-space coverage
and passes 3,300 checks on Linux; its rendered Vulkan validation is separate.
