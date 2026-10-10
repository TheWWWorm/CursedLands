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
10. `sky-subpass-alpha.patch`
11. `worker-thread-language-shutdown.patch`
12. `far-dof-reference.patch`

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
initial optional lens checked the native
`OS.has_feature("ei_far_dof_guard")` capability before allocating a helper.
The current lens uses the twelfth patch below and remains off by default.
That capability is defined by the patch, never by this project's export tags;
stock and older runtimes leave the option inactive. Linux strict pixel checks,
26 unchanged near-blur control images, the build recipe and four-file source
manifest are recorded in
[`camera-depth-of-field-2026-10-09.json`](../../docs/validation/camera-depth-of-field-2026-10-09.json).
Other platform templates and representative performance still require
validation; no installed template is changed here.

The tenth preserves data written to sky-subpass `ALPHA`: screen and radiance
sampling unscale RGB only. Mobile's packed colour has two alpha bits, so only
ALPHA-using half/quarter sky programs get RGBA16F subpass and radiance storage.
Ordinary and RGB-only sky programs keep their original backend formats.
Quality/format changes retire incompatible screen targets and invalidate the
old radiance allocation. The native `ei_sky_subpass_alpha` capability is never
an export tag; optional cloud volumes fall back to the moving layer on older
Mobile runtimes. Linux Forward+/Mobile checks cover actual screen and baked
radiance values, allocation formats, live quality changes and released RIDs.
The old Mobile runtime reproduces ten alpha failures; all fourteen ordinary
sky/RGB control images and five real-map Off/Moving-layer images remain exact.
See [`sky-subpass-alpha-2026-10-09.json`](../../docs/validation/sky-subpass-alpha-2026-10-09.json)
for the four-file source audit, inherited nine-patch audit, build and full RGB
controls. XR/multiview and other platform templates still need execution tests;
no installed template is changed here.

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

The eleventh wakes workers that have not acknowledged language shutdown once
both task queues drain. Previously, a worker could see pending work at the
initial shutdown notification, return to sleep, and never be notified after
another worker finished the queue. A captured hang has empty queues, all four
workers asleep, and only one acknowledgement. The patch affects only
`RUNLEVEL_PRE_EXIT_LANGUAGES`; normal task scheduling and rendering are unchanged.
It is separate from the first patch's later RenderingDevice ownership repair.
Four Linux separate-thread runs pass 207 checks and terminate normally, with
66 captures unchanged across the engine patch. Linux and Windows release
templates build; Windows execution remains untested. See
[`cloud-radiance-2026-10-10.json`](../../docs/validation/cloud-radiance-2026-10-10.json).

The twelfth adds an explicitly enabled far-field pass for Forward+ and Mobile.
Nine centre-depth samples select the median; two 1×1 R32F textures hold its
0.3-second logarithmic GPU history. The other four draws prefilter, gather,
fill and composite the far field with sharp-foreground rejection and bounded
terrain coverage over the sky edge. Work textures use ceil half resolution,
or ceil third resolution above 1440 pixels tall, with 16 or 40 gather taps.
The shader adapts R1's depth convention to Godot reverse-Z and retains linear
HDR before tonemapping. Per-view histories reset on attribute changes, explicit
camera cuts, projection-mode changes, resize and reactivation. Named textures
are released when the effect becomes inactive. Canvas UI is drawn separately.

`RenderingServer.camera_attributes_set_far_dof` is opt-in and defaults to false;
manual far blur and near-enabled blur retain the existing BokehDOF path.
`OS.has_feature("ei_far_dof_reference")` comes from the native patch, never an
export tag. The game keeps the existing option and preserves camera exposure
and other attribute owners. Compatibility and older runtimes leave it inactive.
See [`camera-depth-focus-2026-10-10.json`](../../docs/validation/camera-depth-focus-2026-10-10.json)
for GPU focus/image/resource checks and exact legacy controls. Linux and Windows
templates were compiled; Windows runtime and representative device costs remain
separate acceptance work. No installed templates are replaced by this recipe.
