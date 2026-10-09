# Desktop export templates

The template recipe targets Godot 4.7, source commit
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`. Apply the common patches in the
order listed below and build normal release templates with the standard Godot
build instructions. Adding a patch here does not update installed templates.

1. `render-thread-shutdown.patch`
2. `queued-image-snapshot.patch`
3. `unobserved-pose.patch`
4. `preserve-character-track-caches.patch`
5. `prepare-character-track-caches.patch`
6. `cache-unobserved-track-eligibility.patch`
7. `mobile-shader-recompile-lock.patch`
8. `forward-shader-recompile-lifetime.patch`
9. `far-dof-sharp-guard.patch`

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

The seventh finishes Mobile's pending pipeline jobs before changing shader state
and limits its shared compiler mutex to the compiler call. Previously,
`ShaderData::set_code` kept that mutex while `clear_pipelines` waited for jobs
that could call `get_shader_variant` and need the same mutex. Live shader
changes could therefore deadlock, including disabling foliage wind on a loaded
map. Waiting before changing the version also prevents a worker from trying to
free obsolete shader RIDs, which must happen on the render thread. Apply this patch
before accepting the native Mobile wind/cache path. It changes no shader
equations, cache policy, or Compatibility/Forward+ code. Linux validation and
the paired engine controls are recorded in
[`local-shadow-cache-2026-10-08.json`](../../docs/validation/local-shadow-cache-2026-10-08.json).
Windows, Android and macOS builds of this patch still need platform validation.

The eighth applies the shader-version lifetime ordering to Forward+: finish
pending pipeline jobs before changing shader code, uniforms or version state.
Its compiler mutex already had the correct scope. Without this ordering, a
cold-cache live option change can let a pending worker free obsolete shader
RIDs from outside the render thread. The same game pack reproduced 50 invalid
frees and 50 leaked shader RIDs before this patch; the paired Linux cold-cache
run passes without either. See
[`biome-mounds-2026-10-09.json`](../../docs/validation/biome-mounds-2026-10-09.json)
for the frozen pack, engine build, controls and rendering-thread coverage.
This changes no shader equations or cache policy. Platform template builds and
validation remain separate work; installed templates are not changed here.

The ninth guards far-only depth of field. Focused, foreground and clear-sky
texels remain sharp, integer taps reject sharp foreground colour, and Mobile
uses exact raster pixel centres. Far-only box/hexagonal blur runs at full
resolution with at least Medium quality; a far-only Circle request uses the
protected Hexagon filter. Near-enabled blur retains its original path, quality
and shape. This deliberately changes far-only filtering and costs more than
its old half-resolution path. It does not add render targets. The game's
optional lens remains off by default and checks the native
`OS.has_feature("ei_far_dof_guard")` capability before allocating a helper.
That capability is defined by the patch, never by this project's export tags;
stock and older runtimes leave the option inactive. Linux strict pixel checks,
26 unchanged near-blur control images, the build recipe and four-file source
manifest are recorded in
[`camera-depth-of-field-2026-10-09.json`](../../docs/validation/camera-depth-of-field-2026-10-09.json).
Other platform templates and representative performance still require
validation; no installed template is changed here.

macOS and Web use the official 4.7 templates. Experimental 5 Android ARM64 uses
the first six common patches and `android-headless-service.patch`; earlier public
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
