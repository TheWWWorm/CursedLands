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

The unit-query tests also cover registry mutation, freed nodes, script
replacement and exact cell boundaries/order. Geometry comparisons cover
clipping, projection modes, morphs and cache reuse. Run the native helper
suites under address/undefined-behavior sanitizers in a private test build.
