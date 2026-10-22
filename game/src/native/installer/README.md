# Installer decoder

`installer_lzma.c` is a compiled copy of the LZMA2 decoder in
`src/ei/lzma.gd` (Igor Pavlov's public domain `LzmaSpec.cpp`, LZMA2 framing as
in XZ Utils), taken from the Demiurges engine's `el_lzma.c`. It unpacks the
file chunks of the GOG installer (`EIInnoSetup`) about 35 times faster than the
script; the setup header and every platform without the library keep the
script decoder. It is a plain C GDExtension without godot-cpp:
`include/gdextension_interface.h` comes from Godot 4.7 (MIT).

The class `InstallerLzmaKernel` has three static methods: `open(packed,
out_size)` returns a handle, `step(handle, max_out)` decodes at least
`max_out` more bytes and returns the bytes decoded so far (-1: damaged data),
and `take(handle)` returns the output and frees the handle. `EILzma.run2`
steps 4 MB at a time so progress and cancelling keep working.

## Build

Linux and Windows x86-64 are cross-compiled with Zig 0.16, Android ARM64 with
the Android NDK r29 clang (API 24, 16 KB pages, as the other Android helpers):

```
python3 game/src/native/installer/build.py --zig /path/to/zig --ndk /path/to/android-ndk
```

The libraries go to `game/src/native/bin/libinstaller_lzma.{so,dll}` and
`libinstaller_lzma_android.so`.

## Packaging

`src/native/installer_lzma.gdextension` loads the library at startup like the
other native helpers; desktop exports copy it beside the executable and
Android exports put it in the APK. The macOS preset excludes the extension and
its libraries. Without the library the import still works, only slower;
`EILzma.native()` reports which decoder is used.
`tools/tests/installer_import.gd` compares both decoders on real installer
chunks (`CL_INSTALLER_DIR`) and times a full import.
