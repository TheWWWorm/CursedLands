# Third-party notices

## Optional AMD FSR experiment

The Windows experimental package includes the signed AMD FidelityFX SDK 2.3.0
loader, upscaler and frame-generation DLLs. Their license and third-party
notices are supplied under `licenses/AMD-FidelityFX/`. These binaries retain
their own terms and are not relicensed under this project's Apache-2.0 license.
The SDK API headers retain their original MIT notices; the build helper makes
one MinGW ABI adjustment to the Direct3D resource-description helper.
The complete AMD copyright, permission and disclaimer text is preserved in
`licenses/AMD-FidelityFX/license.md`, alongside `3rdpartynotice.md`.
AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of
Advanced Micro Devices, Inc.

The experimental AMD path also includes Microsoft Direct3D 12 Agility SDK
1.618.5's x64 `D3D12Core.dll`. Its license notices are included under
`licenses/Microsoft-DirectX/`. No debug runtime or SDK tools are distributed.

The official AMD FSR logos retain AMD's trademark rights. They are not covered
by the project's Apache-2.0 license. See [asset provenance](docs/branding/graphics-sdk-assets.json)
and [attribution](docs/branding/graphics-sdk-attribution.md).

## Bink movie decoder

`game/src/ei/bink.gd` and `game/src/ei/bink_audio.gd` are GDScript ports of the Bink container, video and audio decoders of FFmpeg (`libavformat/bink.c`, `libavcodec/bink.c`, `libavcodec/binkdsp.c`, `libavcodec/binkdata.h`, `libavcodec/binkaudio.c`; Konstantin Shishkov, Peter Ross and the FFmpeg developers). These two files are licensed under the [GNU Lesser General Public License 2.1](licenses/LGPL-2.1.txt) (or later), not under the project's Apache-2.0 license.

## LZMA decoder

`game/src/ei/lzma.gd` is a GDScript port of Igor Pavlov's reference LZMA decoder (`LzmaSpec.cpp`, public domain), with LZMA2 framing as in XZ Utils (public domain / 0BSD).

Windows and Linux x86-64 and Android ARM64 packages also include a compiled copy of the same decoder for installer import (`game/src/native/installer/installer_lzma.c`, Apache-2.0, from the Demiurges engine by TheWWWorm), loaded through `game/src/native/installer_lzma.gdextension`. `game/src/native/installer/include/gdextension_interface.h` is part of Godot and is distributed under Godot's MIT license. The desktop libraries are built with Zig and the Android library with the Android NDK (`game/src/native/installer/build.py`); the Windows library contains MinGW-w64 runtime startup code (ZPL-2.1; its notices are in `game/src/native/NATIVE_NAVIGATION_NOTICES.txt`), and the Android NDK notices are in `game/src/native/NATIVE_ANDROID_NOTICES.txt`. Other platforms use the GDScript decoder.

## GOG installer reader

`game/src/ei/inno_setup.gd` reads Inno Setup installers following the file format as documented by the innoextract project. No innoextract code is included.

## InstallShield cabinet reader

`game/src/ei/astral_disc_import.gd` reads the expansion's InstallShield cabinets using the Unshield format reference. The associated permission notice is included below.

InstallShield cabinet format reference: Unshield
https://github.com/twogood/unshield

Copyright (c) 2003 David Eriksson <twogood@users.sourceforge.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Liberation fonts

`game/fonts/LiberationSerif-Regular.ttf`, the bundled Liberation Sans fonts and `game/fonts/LiberationMono-Regular.ttf` (Liberation Fonts, Red Hat) are licensed under the SIL Open Font License 1.1; see [`game/fonts/LICENSE.txt`](game/fonts/LICENSE.txt). Liberation Mono is used by the developer console. Liberation Serif stands in for Times New Roman, which the original uses for its text, because it has the same letter widths.

## Godot Engine

Exported builds embed the Godot Engine (MIT license) and its third-party components; their notices are distributed with each export.

## Community archive decoder

The optional community downloader uses the public-domain decoding subset of
Igor Pavlov's LZMA SDK 26.04. Source, upstream notices and build instructions
are in `game/src/native/archive`; provenance and binding/runtime notices are
listed in `game/src/native/NATIVE_ARCHIVE_NOTICES.txt`. Distribute those notices
with the archive helper. The catalogue links to the original publisher;
third-party mod assets are not bundled with the game.

## Original game content

Evil Islands: Curse of the Lost Soul («Проклятые земли»), its program, text, models, textures, animation, movies and audio are not licensed by this project. They remain the property of their respective rights holders. No game content is included in this repository or in its releases.

## Optional compiled navigation

Windows and Linux x86-64 packages include the project’s Apache-2.0 native helpers, built with MIT-licensed godot-cpp bindings at commit `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`. Current source also supplies Android ARM64 helpers. Binding and Windows compiler-runtime notices are in `game/src/native/NATIVE_NAVIGATION_NOTICES.txt`; Android NDK toolchain and sysroot notices, including the static C++ runtime, are preserved in `game/src/native/NATIVE_ANDROID_NOTICES.txt`. Source and build instructions are in `game/src/native/source`. Other platforms retain script implementations.

## Optional formula runtime

The Windows/Linux formula runtime uses Lua 5.1.5 (MIT), with execution-budget
and recursion bounds in its string library. See
`game/src/native/NATIVE_LUA_NOTICES.txt` and `game/src/native/mod_lua/README.md`.
The wrapper is Apache-2.0 and uses the same godot-cpp revision and compiler
runtime notices as the optional navigation helper above.

## Optional path-tracing denoiser

Windows/Linux x86-64 path tracing includes NVIDIA NRD 4.18.0 REBLUR under the
NVIDIA RTX SDKs license, separately from the application's license. Full NRD,
MathLib and ShaderMake notices are in `game/src/native/NATIVE_NRD_NOTICES.txt`.
The project adapter uses the godot-cpp bindings and compiler runtime described
under Optional compiled navigation. Pinned revisions, build commands and the
RenderingDevice integration are documented in
`docs/integrations/path-tracing-nrd.md`.
