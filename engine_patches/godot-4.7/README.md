# Desktop export templates

The template recipe targets Godot 4.7, source commit
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`. Apply the common patches in the
order listed below and build normal release templates with the standard Godot
build instructions. Adding a patch here does not update installed templates.

`experimental-fsr.patch` is an optional Windows D3D12 integration applied after
the sixteen common patches. Build with `use_fsr_sdk=yes` and the pinned AMD
headers. See [FSR setup and build instructions](../../docs/integrations/fsr-experiment.md).

`restore-dlss.patch` restores the Windows DLSS/DLAA/Reflex integration after
all twenty current Windows patches (including FSR, DXR and device diagnostics).
Build with both `use_streamline=yes` and `use_fsr_sdk=yes`, using the pinned
Streamline 2.14.16 headers. It preserves the FSR enum value and the corrected
DXR barriers. Agility-created devices are upgraded through Streamline instead
of bypassing the Agility device factory. The saved DLSS request chooses the
presentation owner before creating devices; changing AMD/NVIDIA owner requires
a restart. Headless workers do not initialize Streamline. See the
[restored integration](../../docs/integrations/nvidia-dlss.md).

`water-raytracing-uniform-stages.patch` is an optional Vulkan experiment applied
after the common patches. It fixes RT uniform stage masks and adds a capability
guard. See [the water experiment](../../docs/integrations/water-raytracing-experiment.md).

`water-raytracing-d3d12.patch` adds the Windows DXR backend and explicit native
DXIL library import. Apply it after `water-raytracing-uniform-stages.patch`
(and after `experimental-fsr.patch` when including FSR). It requires rebuilding
the Windows executable; a new PCK alone cannot enable DX12 ray tracing. The game
ships matching DXIL/SPIR-V shaders built from one HLSL source. See the water guide
for compiler pinning, limitations, and the DX12/Vulkan regression fixtures.

The DXR barrier masks keep acceleration-structure build stages out of constant
buffer, vertex-fetch and shading-rate accesses. A TLAS rebuild after tracing
must not turn a frame-uniform transition into a constant-buffer barrier with
an acceleration-structure build scope. Native D3D12 rejects that command list;
the resulting device removal can subsequently crash a driver resource binding.
Enhanced barriers remain enabled. Rebuild the Windows template to apply this
fix. `tools/tests/water_raytrace_device.gd` covers hidden-to-visible geometry,
tracing followed by a TLAS rebuild, resizing and GPU readbacks.
`tools/tests/path_trace_save_load.gd` exercises repeated loads through the
frontend and simulation worker using a copied save in an isolated profile.
See the [native Windows validation](../../docs/validation/path-tracing-save-load-2026-10-24/README.md)
for reproduction, engine build details and regression results.

`d3d12-device-diagnostics.patch` is an optional diagnostic/hardening patch
applied after the DXR patch. `EI_D3D12_DIAGNOSTICS=1` enables DRED before device
creation and records debug-layer warnings, device-removal reasons and available
GPU fault evidence. `EI_D3D12_GPU_VALIDATION=1` additionally enables GPU-based
validation; it is separate because it changes shader execution cost. Missing
Windows Graphics Tools/DRED support is reported. Synchronization failures stop
before unconfirmed GPU work can be recycled; this is not device recovery.
The normal rendering path does not enable the diagnostic layers. A rebuilt
Windows executable is required. See the [PT stability investigation](../../docs/validation/path-tracing-stability-2026-10-23/README.md)
for the tested scope and the native Windows qualification gap.

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
13. `forward-shadow-blend-guard.patch`
14. `cache-missing-animation-targets.patch`
15. `boot-window-title.patch`
16. `cancelled-tooltip-timers.patch`

The sixteenth patch expires a native tooltip timer when its tooltip is cancelled,
replaced by a new hover, or shown explicitly. Disconnecting its callback alone
leaves it in SceneTree's idle and physics scans until its original deadline.
Cursed Lands delays native tips while its own localized TipLayer displays them;
without this patch, mouse movement accumulates long-lived timers even after
leaving gameplay. Active tooltip delays and ordinary popup behavior are unchanged.
Run `tests/tooltip_timer_retention.gd` in a rebuilt template, followed by the
game's `tools/tests/tooltip_lifetime_ui.gd`. The former includes 100,000 hover
events, paused play, zero/double time scale and ordinary native tooltip controls.
This fix requires a rebuilt executable; exporting a new game pack alone does
not apply it. Other platform templates must include this patch when rebuilt.

The fifteenth patch applies `application/config/name` before the main window
is shown, so the project's boot splash already has the game's name in its
title bar. The usual translated title and debug suffix are still applied
when the main loop starts. Editor, project manager, command-line tools and
headless startup retain their normal behavior. The splash artwork comes
from `application/boot_splash/image`; Cursed Lands uses the approved dragon
CL logo. This patch requires rebuilt export templates and does not change
existing published executables.

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

macOS and Web use the official 4.7 templates. Stable 1.0.3 Android ARM64 uses
the first twelve common patches and `android-headless-service.patch`; Experimental 5
and 6 used the first six common patches plus that service patch. See
[the Android service guide](../../platform/android/simulation/README.md).
The extra patch guards Android-only sensor dispatch and supplies a surface-free
frame loop for the engine's existing `GodotService`. It does not change the
graphical rendering thread mode. These patches retain
Godot's MIT license; complete engine notices accompany every release package.

The Android GLES startup patch adds
`android-gles-lazy-scene-variants.patch` after those thirteen patches. On Android,
only `SceneShaderGLES3` skips eager compilation of the four default modes when
there is no usable cache. The existing synchronous bind path compiles the
requested mode and specialization, then saves it through the existing cache
format. Empty mode maps are valid; later colour, shadow and instanced draws
populate them normally. Existing cached programs are retained, including any
extra default programs from an earlier engine. No shader source, light limit,
rendering equation or graphics setting changes. Other shader families and
non-Android builds keep their existing initialization.

This relies on the pinned engine's synchronous specialization path. Its unused
asynchronous fallback is hard-disabled; revisit the patch if an upstream update
enables that fallback and starts requiring default programs. Apply only the
production patch to release templates. The separate
`tests/android-scene-variant-audit.patch` adds development-only compilation and
cache timings for a matched baseline/candidate comparison and must be excluded
from release engines.

The startup fixture is `tools/tests/android_scene_startup.gd`. The rendering
fixture, `tools/tests/android_scene_variants.gd`, also requires
`android_figure_compatibility.gd` beside it. Compare every saved capture between
engines, and require clean native process exit in addition to fixture assertions.
Device measurements, cache-transition checks, APK hashes and limitations are in
[`android-gles-scene-variants-2026-10-14.json`](../../docs/validation/android-gles-scene-variants-2026-10-14.json).
The 1.3.0 Android package includes this fourteenth patch. Its release engine
matches the uninstrumented candidate above; installed global templates remain
unchanged. Combined-source rendering, lifecycle, package and browser checks are
recorded in
[`stable-1.3.0-2026-10-14.json`](../../docs/validation/stable-1.3.0-2026-10-14.json).
The Redmagic 11 Pro crash remains unconfirmed as fixed.

`mobile-render-work.patch` follows those fourteen patches in the Android
validation engine. It changes four Mobile paths:

- Empty instances are excluded before their materials can request depth or
  screen copies. Making a MultiMesh visible again restores its normal draws.
- The directional shadow shader shares one PCF call site between the primary
  and transition cascades. A transition with zero blend weight needs no second
  filter. Cascade count, sample count, bias, blur and blend equations remain.
- Sky shaders may opt into `skip_unneeded_radiance`. Only opted-in skies defer
  radiance updates when ambient light, reflections, aerial fog and the shader's
  `RADIANCE` builtin do not consume it. Background/subpass rendering stays live;
  pending radiance updates run before a consumer returns. Ordinary skies keep
  their existing behavior. Direct panorama baking of an opted-in, unconsumed
  sky may see deferred radiance; such callers must not opt in.
- `Light3D.set_custom_baked(bool)` marks a transient light already represented
  by a custom material. Mobile omits flagged omni lights only for surfaces with
  `skip_custom_baked_omni_lights`, repacks their indices and specializes the
  shader for the remaining count. Other materials in the same mesh retain all
  their lights. This flag does not change bake mode, cull masks or shadows and
  is not a serialized scene property. The caller must clear it when its custom
  lighting no longer includes that light. Compatibility ignores the API;
  Forward+ retains its existing light lists.

The native capabilities `ei_mobile_lazy_sky_radiance` and
`ei_mobile_baked_omni_lighting` gate the game's opt-ins; never add them to export
tags. The game retains older-engine paths. Android ARM64 is the validated
template for this patch; installed global templates are not replaced.
`tests/mobile_baked_lights.gd`, `tests/mobile_lazy_sky.gd` and
`tests/mobile_shadow_cascades.gd` cover material isolation, radiance consumers
and paired shadow captures. The game fixtures are
`tools/tests/baked_pass_lights.gd` and `tools/tests/particle_shader_options.gd`.
Build hashes, device timings and test results are recorded in
[`android-vulkan-original-performance-2026-10-16.md`](../../docs/android-vulkan-original-performance-2026-10-16.md).

`mobile-screen-mip-demand.patch` follows `mobile-render-work.patch`. Mobile
tracks mip-filtered screen samplers on its visible material surfaces and builds
the screen mip chain only when one is present. Level zero is still copied for
ordinary screen samplers. The demand flag resets per render list, and the normal
material-cache invalidation handles live shader changes. Allocations are kept
compatible with a consumer returning; mip consumers retain the previous full
chain. Forward+ callers keep the original default. The capability
`ei_mobile_screen_mip_demand` identifies the patched engine; do not add it to
export tags. Older engines remain visually compatible with the game's sampler
change but still generate the unused levels.

`tests/mobile_screen_mips.gd` compares level-zero and forced-mip references,
mixed consumers, visibility/culling, shader changes, empty/restored MultiMeshes
and next-pass materials. Run it on both engine versions and compare all captures.
The water setting/image fixtures are `tools/tests/mobile_water_options.gd` and
`tools/tests/mobile_water_render.gd`. Android ARM64 measurements and the native
source/build audit are in
[`android-vulkan-water-performance-2026-10-17.md`](../../docs/android-vulkan-water-performance-2026-10-17.md).
Shared installed templates are not replaced by this validation.

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

The thirteenth skips Forward+'s second directional PCF shadow lookup where its
cascade blend weight is zero. The positive-weight transition still uses the
same two filtered lookups, kernel, atlas, bias and blend equation. The angular
soft-shadow path, Mobile and Compatibility shaders are unchanged. This requires
a rebuilt native template; changing the game pack alone cannot enable it.

`tests/forward_shadow_cascades.gd` records 72 deterministic images across Hard,
Soft Low and Soft High filtering, one/two/four cascades, blending on/off and
four camera offsets. Run it in both matched native builds via an absolute
`--tool` path after `--`. On Linux Vulkan all paired PNGs are identical; all
24 two/four-cascade blend controls differ from their non-blended counterparts,
confirming that the tested transitions are visible. The matched engine builds,
first-person 4K timings and platform limits are recorded in
[the performance validation](../../docs/validation/campaign-autochess-20261018.md#directional-shadow-blend-work).
Windows templates and execution still need validation; installed templates
are not replaced by this recipe.

The fourteenth remembers unresolved animation paths for one binding-cache
rebuild when invalid-track warnings are disabled. Human libraries contain many
clips targeting equipment variants absent from an individual figure. Repeated
clips no longer traverse the same missing hierarchy. The temporary set expires
at the end of the rebuild; library edits, explicit clearing and tree changes
keep their existing invalidation. Enabling invalid-track warnings retains every
per-clip diagnostic. No animation keys, poses or playback clocks change.

`tests/animation_missing_targets.gd` checks existing, added, renamed and replaced
targets, library edits, tree reentry and the diagnostics path. Run it together
with the preparation, retention and unobserved-pose tests in the rebuilt native
template. See [autochess validation](../../docs/validation/autochess-frame-time-20261018.md)
for tested builds and frame-time measurements. Installed templates are unchanged.
