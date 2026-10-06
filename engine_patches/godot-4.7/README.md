# Desktop export templates

The Windows and Linux x86-64 release templates use Godot 4.7, source commit
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`, with the four patches in this
directory. Apply them in the order listed below and build normal release
templates with the standard Godot build instructions:

1. `render-thread-shutdown.patch`
2. `queued-image-snapshot.patch`
3. `unobserved-pose.patch`
4. `preserve-character-track-caches.patch`

The first two patches repair separate-render-thread shutdown and snapshot
mutable images for queued texture uploads. The third lets an unobserved looping
character advance its animation clock while delaying pose evaluation until it
is needed. The fourth adds an opt-in cache lifetime for immutable character
rigs: finishing a short clip keeps resolved track bindings for the next clip.
Playback completion, signals, audio and capture cleanup are retained. Animation
library changes, explicit clearing/stopping and entering/leaving the tree still
invalidate bindings. Callers that replace a track target must clear caches.
The option defaults to off and is enabled only for the game's fixed character
rigs. The game also supports unmodified Godot through capability checks.
Android, macOS and Web use the official 4.7 templates. These patches retain
Godot's MIT license; complete engine notices accompany every release package.

The focused `tests/animation_cache_retention.gd` fixture compares normal and
retained players through completion, library/key/target changes, tree reentry,
queued clips and reverse playback. Run a patched game build on an isolated
profile with its normal `--ei-path` argument and
`--tool=/absolute/path/to/engine_patches/godot-4.7/tests/animation_cache_retention.gd`
after the `--` separator. It exits nonzero on failure and requires the new API.
