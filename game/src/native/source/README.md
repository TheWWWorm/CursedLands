# Optional compiled hot loops

The `TerrainSearchKernel` extension accelerates integer terrain distances,
component labels, block routes, moving search windows, and obstacle-stamp
painting. It leaves AI scheduling, the 55 ms simulation clock, and network
messages in GDScript. Each terrain instance belongs to the existing navigation
map revision. Stamp painting is stateless and always uses the current units.

The script implementation remains available when the extension is absent and
with the `-- --ei-script-nav` diagnostic launch option. Android, Web, and macOS
export presets exclude the desktop extension and use that implementation.
The current packaged targets are Windows x86-64 and Linux x86-64.

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

## Perception and picking

`UnitQueryKernel` also accelerates ordered cell filtering and nearby-list
validation. It samples current registry membership for each synchronous combat
query; perception rows are bounded and invalidated by unit state changes and
script-instance lifetimes. `UnitNoticeLifetime` provides deletion invalidation
without a per-frame script notification callback. The unit/AI/sound scripts
retain their fallbacks (`-- --ei-script-units`).

`ScreenRectKernel` clips the same posed mesh vertices and triangles against the
camera frustum and returns the same rounded pixel bounds. The script fallback
is selectable with `-- --ei-script-picking`. The extension does not approximate
picking by a mesh bounding box or change animation, simulation, or sound timing.

The focused differential suites cover object deletion/script replacement,
registry edits and ordering, cell rounding, camera clipping and vertex morphs.
ASan/UBSan checks use private instrumented libraries; only normal release
libraries belong in distributable packages.
