# Third-party notices

## Bink movie decoder

`game/src/ei/bink.gd` and `game/src/ei/bink_audio.gd` are GDScript ports of the Bink container, video and audio decoders of FFmpeg (`libavformat/bink.c`, `libavcodec/bink.c`, `libavcodec/binkdsp.c`, `libavcodec/binkdata.h`, `libavcodec/binkaudio.c`; Konstantin Shishkov, Peter Ross and the FFmpeg developers). These two files are licensed under the [GNU Lesser General Public License 2.1](licenses/LGPL-2.1.txt) (or later), not under the project's Apache-2.0 license.

## LZMA decoder

`game/src/ei/lzma.gd` is a GDScript port of Igor Pavlov's reference LZMA decoder (`LzmaSpec.cpp`, public domain), with LZMA2 framing as in XZ Utils (public domain / 0BSD).

## GOG installer reader

`game/src/ei/inno_setup.gd` reads Inno Setup installers following the file format as documented by the innoextract project. No innoextract code is included.

## Liberation Serif font

`game/fonts/LiberationSerif-Regular.ttf` (Liberation Fonts, Red Hat) is licensed under the SIL Open Font License 1.1; see [`game/fonts/LICENSE.txt`](game/fonts/LICENSE.txt). It stands in for Times New Roman, which the original uses for its text, because it has the same letter widths.

## Godot Engine

Exported builds embed the Godot Engine (MIT license) and its third-party components; their notices are distributed with each export.

## Original game content

Evil Islands: Curse of the Lost Soul («Проклятые земли»), its program, text, models, textures, animation, movies and audio are not licensed by this project. They remain the property of their respective rights holders. No game content is included in this repository or in its releases.
