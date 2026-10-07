# Desktop export templates

The Windows and Linux x86-64 release templates target Godot 4.7, source commit
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`, with the six patches in this
directory. Apply them in the order listed below and build normal release
templates with the standard Godot build instructions:

1. `render-thread-shutdown.patch`
2. `queued-image-snapshot.patch`
3. `unobserved-pose.patch`
4. `preserve-character-track-caches.patch`
5. `prepare-character-track-caches.patch`
6. `cache-unobserved-track-eligibility.patch`

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
The fifth exposes preparation of those same bindings during loading, without
advancing playback, writing poses or emitting playback/track/mixer events.
This moves first-use setup out of gameplay; it is not a steady-state CPU gain.
The existing invalidation rules still apply. `--ei-lazy-animation-bindings`
keeps first-use construction for comparisons.
The sixth caches whether a clip's tracks permit deferred pose evaluation.
Every internal track-cache invalidation advances a generation, including when
signals are blocked. Playback mode, section and running-state checks remain
live. Adding a method/event track therefore immediately disables deferral.
macOS and Web use the official 4.7 templates. Experimental 5 Android ARM64 uses
the six common patches and `android-headless-service.patch`; earlier public
Android releases used the official template. See
[the Android service guide](../../platform/android/simulation/README.md).
The extra patch guards Android-only sensor dispatch and supplies a surface-free
frame loop for the engine's existing `GodotService`. It does not change the
graphical rendering thread mode. These patches retain
Godot's MIT license; complete engine notices accompany every release package.

The focused `tests/animation_cache_retention.gd` fixture compares normal and
retained players through completion, library/key/target changes, tree reentry,
queued clips and reverse playback. Run a patched game build on an isolated
profile with its normal `--ei-path` argument and
`--tool=/absolute/path/to/engine_patches/godot-4.7/tests/animation_cache_retention.gd`
after the `--` separator. It exits nonzero on failure and requires the new API.
`tests/animation_cache_preparation.gd` compares prepared and lazy players
through events, blending, library edits, target replacement and tree reentry.
`tests/unobserved_eligibility.gd` compares normal and deferred players through
looping, reverse playback, event-track insertion with blocked signals, track
removal/path changes, resource replacement, and tree reentry.
