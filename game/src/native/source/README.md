# Optional compiled hot paths

The `TerrainSearchKernel` extension accelerates integer terrain distances,
component labels, block routes, moving search windows, and obstacle-stamp
painting. It leaves AI scheduling, the 55 ms simulation clock, and network
messages in GDScript. Each terrain instance belongs to the existing navigation
map revision. Stamp painting is stateless and always uses the current units.

The script implementation remains available when the extension is absent and
with the `-- --ei-script-nav` diagnostic launch option. Android, Web, and macOS
export presets exclude the desktop extension and use that implementation.
The current packaged targets are Windows x86-64 and Linux x86-64.

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
validation. Every combat query samples the actual live registry, including
changed IDs and same-count replacements, before reusing a pruned list. Its
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

Distribute `NATIVE_NAVIGATION_NOTICES.txt` with the shared library. It contains
the binding and Windows runtime notices. The engine's existing notices still
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
Godot objects, scene state, shared mutable caches or RNG. Linux and Windows
ship the kernel; the same scheduler has a GDScript fallback on other platforms.
`-- --ei-script-activity` selects that fallback. `-- --ei-legacy-ai` disables
reactive scheduling entirely. See `docs/ai_activity.md` for behavior and wake-up
contracts. The earlier statement about leaving AI scheduling in GDScript still
applies: only the packed activity calculation is native.

`tools/ai_activity_test.gd` checks the bridge and scheduler;
`tools/ai_activity_core_test.cpp` can be compiled independently with C++17 and
ASan/UBSan. Its optional extra argument runs synthetic scaling measurements.
`tools/reactive_gameplay_test.gd` checks real-map reaction, stealth and patrols.
The main-world CPU cost includes packing, live eligibility checks and the
existing unit loop; kernel timings alone are not a gameplay benchmark.
