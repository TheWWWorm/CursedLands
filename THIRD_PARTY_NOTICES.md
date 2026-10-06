# Third-party notices

## Bink movie decoder

`game/src/ei/bink.gd` and `game/src/ei/bink_audio.gd` are GDScript ports of the Bink container, video and audio decoders of FFmpeg (`libavformat/bink.c`, `libavcodec/bink.c`, `libavcodec/binkdsp.c`, `libavcodec/binkdata.h`, `libavcodec/binkaudio.c`; Konstantin Shishkov, Peter Ross and the FFmpeg developers). These two files are licensed under the [GNU Lesser General Public License 2.1](licenses/LGPL-2.1.txt) (or later), not under the project's Apache-2.0 license.

## LZMA decoder

`game/src/ei/lzma.gd` is a GDScript port of Igor Pavlov's reference LZMA decoder (`LzmaSpec.cpp`, public domain), with LZMA2 framing as in XZ Utils (public domain / 0BSD).

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

## Liberation Serif font

`game/fonts/LiberationSerif-Regular.ttf` (Liberation Fonts, Red Hat) is licensed under the SIL Open Font License 1.1; see [`game/fonts/LICENSE.txt`](game/fonts/LICENSE.txt). It stands in for Times New Roman, which the original uses for its text, because it has the same letter widths.

## Godot Engine

Exported builds embed the Godot Engine (MIT license) and its third-party components; their notices are distributed with each export.

## Original game content

Evil Islands: Curse of the Lost Soul («Проклятые земли»), its program, text, models, textures, animation, movies and audio are not licensed by this project. They remain the property of their respective rights holders. No game content is included in this repository or in its releases.

## Optional compiled navigation

Windows and Linux x86-64 packages include the project’s Apache-2.0 navigation module, built with MIT-licensed godot-cpp bindings at commit `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`. The desktop packages include binding and compiler-runtime notices in `NATIVE_NAVIGATION_NOTICES.txt`. Source and build instructions are in `game/src/native/source`. Other platforms use the script implementation.
