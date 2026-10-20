# Bounded formula runtime

`ModLuaKernel` is an Apache-2.0 GDExtension wrapping Lua 5.1.5 for Cursed Lands
formula API 1. It reuses the bounded interpreter groundwork from the unpublished
Jamais Vu branch. No legacy DLL ABI or native-address adapters are included.
Lua is MIT-licensed; see `../NATIVE_LUA_NOTICES.txt`.

Vendor provenance: Lua 5.1.5 archive SHA-256
`2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333`.
`vendor/lua-5.1.5/lstrlib.c` retains the prior execution meter and recursion
limit. The wrapper uses the same MIT godot-cpp revision as the other helpers:
`507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, Godot 4.7.

```sh
cmake -S game/src/native/mod_lua -B /tmp/mod-lua-build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_DIR=/path/to/godot-cpp
cmake --build /tmp/mod-lua-build --parallel
cp /tmp/mod-lua-build/libmod_lua.so game/src/native/bin/
```

For Windows, pass a MinGW CMake toolchain and copy `libmod_lua.dll` instead.
The CMake target links the Windows GCC/C++ support libraries statically.
Distribute the existing `NATIVE_NAVIGATION_NOTICES.txt` compiler/binding notices
alongside the Lua notice.

The descriptor is deliberately named `../mod_lua.cfg`. Godot does not discover
it as an automatic GDExtension. `ModFormula` calls
`GDExtensionManager.load_extension` only when a selected script package needs it.
The config file must be included in the PCK. Export packaging must copy the
matching binary to `src/native/bin/` beside the executable; see
`tools/build_mod_preview.py`. Merely exporting a PCK does not package this
optional library.

The interpreter has no host callback bridge. `configure(sources, entry)` opens
only restricted libraries and declared modules. `invoke(name, arguments)`
accepts and returns bounded plain data. The adapter creates a new instance
for every formula; there is no retained runtime or checkpoint API. Source-only
loading, finite-number validation and allocator/step bounds remain mandatory.

Run `tools/tests/mod_formulas.gd` through the game's `--tool` entry point with
`--mod-tests --examples=/absolute/path/to/packaged/examples`, using isolated
XDG directories and the development settings specified by `AGENTS.md`.
