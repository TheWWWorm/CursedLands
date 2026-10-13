# Community archive decoder

`ModArchiveExtractor` reads 7z downloads on an installer worker. It does not
execute archives, installers, DLLs or scripts. The wrapper uses Godot file I/O
so Unicode application-data paths work on every supported native platform.

The release catalogue enables the HD Lands download on Windows and Linux.
Android remains disabled until the solid decoder and HD rendering have been
qualified on-device; the Android library is retained for that qualification.

The bundled decoder is the unmodified C decoding subset of Igor Pavlov's
[LZMA SDK 26.04](https://www.7-zip.org/sdk.html), in the public domain. Its source
archive and checksum are in `../NATIVE_ARCHIVE_NOTICES.txt`. Encoder, CLI,
encryption and PPMd support are not built. All upstream includes needed by the
selected translation units are retained, including conditional includes.

Extraction validates all paths, duplicate names, file/directory collisions,
link attributes, file counts and unpacked sizes before writing. It uses a new,
empty private staging directory. Both headers and allocations have limits:
16 MiB during header parsing, 1 GiB total unpacked data and a 1 GiB solid block,
with 16 MiB allocation overhead. Decoding verifies the SDK's CRC checks.
Cancellation is checked while reading compressed input and writing output.
Only cancellation and progress may be called across threads; each extractor
instance performs one extraction. The caller removes staging on every failure.

Solid 7z blocks stay in memory until extraction finishes. HD Lands 1.5.0 can
therefore use approximately 0.8 GiB of additional memory while installing.
Extraction runs before the resource conversion so those allocations do not
overlap. This is not a streaming decoder for arbitrary multi-gigabyte archives.

Build with godot-cpp commit `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`,
the same revision used by the other native helpers:

```sh
cmake -S game/src/native/archive -B /tmp/ei-archive-build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_DIR=/path/to/godot-cpp
cmake --build /tmp/ei-archive-build --parallel
cp /tmp/ei-archive-build/libmod_archive.so game/src/native/bin/
```

Windows uses the same MinGW x86-64 toolchain as the other extensions and
produces `libmod_archive.dll`. Android uses NDK 29, `arm64-v8a`, API 24 and
`c++_static`; copy its library as `libmod_archive_android.so`. Keep the archive,
Godot bindings, Windows runtime and Android runtime notices with distributions.
There is no Web or macOS library; the catalog disables installation when the
extension is absent. Builds for unsupported platforms must exclude the
`mod_archive.gdextension` resource, as the macOS preset does.
