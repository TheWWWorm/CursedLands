# Android stability investigation

Evidence reviewed on 2026-10-14, against stable **1.1.1** (`182ee0f`).
The machine-readable record is
[android-stability-audit-2026-10-14.json](validation/android-stability-audit-2026-10-14.json).
This is investigation and validation evidence, not release notes or a claim that
the reported crashes have been fixed.

## Reports and confirmation

| Report | Observed symptom | Current status |
| --- | --- | --- |
| [GitHub #3](https://github.com/TheWWWorm/CursedLands/issues/3), Redmagic 11 Pro, Android 16, Adreno 840 | Launches and plays movies, then exits while presenting the menu/loading screen. Both supplied 1.1.1 reports end after `graphics detection: first`. | Open. No native fault location or reproduction on the available device. |
| [4PDA #42](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145476939), post names Realme 14 | Reports that 1.0 works and subsequent versions crash after loading the menu. | Open. Exact failing APK and device remain unverified; the profile names a different phone. |
| [4PDA #38](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145457396), 1.0.3 | Better FPS, but a frozen world after save/load/dialogue/new game, with failed saves. | A related resume/pause defect was reproduced and fixed locally before 1.0.4. No confirmation from this reporter that their case is resolved. |
| [4PDA #36](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145446886), 1.0.2 versus 1.0.0; [#20](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145379491) | Worse performance; another report describes severe slowdown during play but smooth rendering while paused. | Open performance reports. Paused/running comparison suggests testing simulation cost separately from GPU cost. It is not a crash diagnosis. |
| [4PDA #43](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145481861) | Heat and faster battery drain, including after leaving the game. | Open. APK, device, meaning of "leaving", and measured background activity are unspecified. |
| [4PDA #26](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145384258), Snapdragon 680 / Adreno 610 | Vulkan is faster but terrain is white or missing textures. | Open rendering correctness report. A shader draw smoke test cannot establish correct terrain appearance. |
| [4PDA #22](https://4pda.to/forum/index.php?showtopic=1127294&view=findpost&p=145380808) | Loading picture and music continue without entering the game. | Open. No exact version or device supplied in the post. |

All three forum pages were read. The latest visible post, #44, distributes
1.0.5; it does not confirm the preceding reports were resolved. The topic header
still names 1.0.0. An absent follow-up is not a successful retest, and a forum
profile device is not necessarily the device used for a report.

## What the startup reports establish

The two Redmagic reports identify **OpenGL Compatibility**, not Vulkan. They
reach construction of the menu island and signpost. Neither records
`startup: main menu ready`, an applied calibration tier, or a completed result.

`GfxDetect.auto_start()` prints `graphics detection: first` when scheduling the
test. `_run()` then waits for the startup/movie screen before writing the
pending-test record and applying tiers. The last line therefore does **not**
prove the calibration itself crashed. The transition into the first 3D menu
frames, the loading movie, and the detection overlay need separate probes.
The existing interrupted-calibration recovery does not cover a failure before
its pending record is written. The early crash report UI in 1.1.1 improves
report access; these two logs demonstrate it did not remove the original fault.

## Source and shipped-artifact checks

- The stable 1.0.3 and 1.1.1 APKs contain byte-identical Godot native engines,
  terrain helpers and `classes.dex`. The 1.1.1 APK adds the archive helper.
  Earlier 1.0.0 and the first 1.0.3 artifact have different engine binaries.
  This narrows the history, but cannot exclude new scripts/shaders triggering an
  existing engine or driver defect.
- Increasing `rendering/limits/global_shader_variables/buffer_size` is not an
  explanation for the Compatibility regression in this engine. GLES caps the
  hardware limit to 1 MiB, then caps the allocation to that limit. The previous
  default of 65,536 sixteen-byte entries already reaches that ceiling; raising
  it to 262,144 entries does not raise the GLES allocation.
- The older Android pause handler independently paused the simulation tree
  while the service already suspended its frame loop. Resuming with an
  unchanged owner clock could leave the world paused. The existing fix removes
  that extra pause. The recorded baseline failed the resume check; its fixed
  counterpart passed. See
  [the original comparison](validation/experimental-1.0.4-2026-10-11.json).
- Enhanced water retains reflection shader code even when its runtime option
  is off. That is a candidate for a controlled shader simplification experiment,
  not evidence that reflections cause the reported crash.

## Tests performed in this audit

The physical device was a Retroid Pocket 5, Android 13, Adreno 650. Tests used
an isolated QA package with the 1.1.1 native binaries and game scripts. Its
only game-script difference is an opt-in test bootstrap in `main.gd`; that
bootstrap was absent for normal startup. The normal installed game and its
saves were not modified.

- **Fresh normal start:** movies enabled, default settings, automatic graphics
  detection enabled. Reached the menu and completed detection. The final result
  was tier 5, Original look, 30 FPS. This is one device, not Redmagic acceptance.
- **Lifecycle:** 26 checks passed, including dialogue, save/load, suspend/resume
  with running and intentionally paused clocks, and simulation-service stop.
  This fixture uses Original look with automatic detection disabled and cannot
  qualify default startup rendering.
- **Service shutdown:** repeated the lifecycle run and held the owning activity
  alive for 15 seconds after worker stop. Android logged a scheduled restart,
  but no service process restarted during the observation. No restart loop was
  reproduced; the forum battery report remains unexplained.
- **Shader draws:** 14 variants passed on Android GLES and Vulkan Mobile and
  desktop GLES. These cover seven base shader families, with fog off/on, using
  each platform's base options. Headless execution correctly exits with code 2.

`tools/tests/mobile_shader_slots.gd` previously inspected the shader uniform
list and called that driver compilation. It also set `_vol_fog` before calling
`make_shader()`, which reset it, so the nominal fog pass duplicated the other
pass. The fixture now composes the requested fog variants, draws them, waits
for GPU readback, and fails on captured engine/rendering errors. It refuses
headless qualification. These are test corrections, not a production crash fix.

The fixture uses a small quad and default sampler resources. It does not check
authored geometry, texture correctness, all graphics combinations, native
crashes on other drivers, or sustained thermal behavior. An external timeout
and process-exit check are still required for native crashes and hangs.

## Android acceptance checklist

Record exact APK hash/version, source, engine hash, phone, Android version,
renderer and GPU driver for every run. Preserve the last working reference APK
and use a separate package/profile for comparisons.

1. Exercise normal cold startup with movies and automatic detection enabled.
   Require the final menu-ready and calibration-completion markers; a tier
   measurement or a last trace line is not completion. Repeat with warm caches.
2. Exercise upgrades from the reported working versions (1.0.0 and 1.0.3),
   preserving settings and saves, and compare with a fresh profile. Do not treat
   clean installs alone as upgrade acceptance.
3. Run the shader draw fixture on physical GLES and Vulkan devices. Require all
   14 completed draws, the expected renderer, no runtime errors and no timeout.
   Inspect actual terrain, water and unit appearance separately. Use affected
   hardware or another independently tested driver family before making a
   broad Android compatibility claim.
4. Run `android_local_lifecycle.gd` through the real Android service, including
   save/load, dialogue, background/resume and both clock states. After explicit
   exit, observe processes/service records long enough to catch a scheduled
   restart; do not immediately force-stop and call shutdown verified.
5. Compare the same scene and settings on reference and candidate versions
   while running and paused. Record frame time, memory and sustained behavior;
   menu FPS or a synthetic feature check does not qualify gameplay performance.
6. Keep `locally verified`, `reporter confirmed`, `not reproduced` and `open`
   separate. A locally fixed mechanism does not close every similar report.

## Original figure compatibility candidate, October 14

The subsequent [issue #3 run](https://github.com/TheWWWorm/CursedLands/issues/3#issuecomment-6169364461)
completed the loading picture, menu construction, sky, terrain and water,
then exited at the object stage with enhancements and automatic detection off.
This does not identify the failing mesh or shader. Further per-object probes
are kept on the investigation branch; this candidate adds no player test steps.

Original settings previously retained disabled relief, per-pixel material
lighting, leaf transmission and character sharpening in the shader sent to
Godot. Replacing an option with a constant-false branch does not remove that
branch from Godot's function/sampler analysis. The candidate uses preprocessing
to omit those inactive features on **Android OpenGL Compatibility**. It retains
the current original lighting math, alpha handling, wound overlays and texture
data. Turning a feature on restores its existing implementation. World, fade,
Paperdoll and translucent-preview shader identities and bindings survive the
transition; unchanged settings do not recompile them. Enhanced ground-contact
materials retain their existing composition.

This is a compatibility candidate, not a demonstrated explanation of the
Redmagic crash. Figure vertex lighting changed in 1.0.1 and remains in Original
graphics; sharpening already existed in 1.0.0. The candidate removes inactive
work without reverting the lighting corrections or inferring a culprit from
version dates. Android Vulkan, desktop and browser do not enable the new
specialization. No additional player-visible text or settings are introduced.

Validation is recorded in
[android-figure-compatibility-2026-10-14.json](validation/android-figure-compatibility-2026-10-14.json).
The rendered fixture compares the old and compact paths in the same held scene,
using the actual menu and separate material controls. It covers all eight
material/foliage/sharpness combinations, alpha cutouts, translucent previews,
wounds, fog, mapped/overflow/local lights, shadows, MSAA, and live restoration.
GPU readbacks, material identities and the preprocessed source are checked;
the fixture is a development tool, not part of startup.

The final RTX 3090/OpenGL and Adreno 650/GLES runs each passed 525 checks and
59 GPU readbacks; all 28 image pairs matched exactly. Android also passed 416
material-option checks across 126 shader draws and 26 real-service lifecycle
checks, including save/load and suspend/resume. All 96 desktop shader-source
comparisons against the published 1.2.0 executable matched after whitespace
and comment removal. These results are scoped to the recorded fixtures.

Initial fixture runs passed their image checks but failed during shutdown.
A minimal test on the unchanged 1.2.0 executable isolated that failure to a
temporary lambda left connected to a statically cached preview shader. The
fixture now disconnects its observer before teardown, and qualification requires
clean process exit in addition to its assertions. This is not evidence for the
reported menu crash. Existing nonfatal Scudo allocation-region warnings in the
Android QA runtime are recorded separately; this change does not resolve them.

The affected Adreno 840 is not available locally. Local comparison and lifecycle
results qualify the candidate on the listed systems, not a universal Android
stability claim. A single normal-play confirmation on the affected phone remains
necessary before calling issue #3 fixed; no further diagnostic sequence is
required by this change.

## Upstream and hardware compatibility review, October 14

The [upstream compatibility review](validation/android-upstream-compatibility-2026-10-14.json)
compares vendor API support, Android packaging requirements, Godot reports and
the source of the shipped engine. No unsupported CPU/GPU feature or matching
native crash was established. Qualcomm advertises GLES 3.2 support, while
Godot Compatibility targets GLES 3.0. The published 1.2.0 APK has four AArch64
libraries with 16 KB ELF alignment and passes the APK's 16 KB alignment check.
This does not establish the phone's page size or full runtime compatibility.

One earlier candidate needs narrowing: **Android GLES does not upload our
world textures as BC1/S3TC**. The engine explicitly disables that capability
on Android, and GameData uses the RGBA fallback while preserving authored mip
pixels. BC1 entries in the desktop object census do not describe Android GLES.
The authored mip change remains, but unsupported BC1 hardware decoding is not
the active path in this configuration.

An [October 10 upstream report](https://github.com/godotengine/godot/issues/86731#issuecomment-6097946499)
describes long cold-compilation stalls on Adreno in Godot's GLES 3D shader
initialization. Our engine contains the same mechanism: the first uncached use
compiles four default modes, with all light types enabled, before compiling the
requested specialization if it differs. This is an engine-level source of
unnecessary compiler work that the figure candidate does not remove. It is a
local profiling lead, not evidence that compilation caused the Redmagic exit.

The recent [global-parameter storage change](https://github.com/godotengine/godot/pull/124336)
addresses Compatibility buffer limits, especially for instance uniforms. Our
Compatibility path already converts instance uniforms to material uniforms,
so the linked node-limit failures do not establish a match. The
[Adreno ubershader workaround](https://github.com/godotengine/godot/pull/119639)
is already in our Vulkan engine code and does not cover this OpenGL session.
A [DXVK Adreno 840/842.xx report](https://github.com/doitsujin/dxvk/issues/5899)
also uses Vulkan; matching hardware names alone cannot transfer its diagnosis.
No renderer switch, driver blacklist or engine backport was applied on the basis
of these reports.

## Android GLES scene compilation, October 14

The local engine experiment confirms substantial unnecessary compilation work
on the available Adreno 650. The retained patch skips eager default programs
for Android's `SceneShaderGLES3` and uses the engine's existing synchronous
compilation path for each requested mode and specialization. It leaves shader
math and the binary cache format unchanged. Cached older programs remain valid;
new caches can omit unused modes and fill them when a draw needs them.

Three alternating baseline/candidate pairs used identical game packs, a held
640×480 Original menu, fixed noon lighting and warmed CPU asset caches. Each
cold run started with an empty **Godot** shader cache; any driver-managed cache
was outside the test's control. The benchmark explicitly disabled the separate
compact-figure candidate on both engines to isolate this engine change.

| Measurement | Existing engine | Candidate |
| --- | ---: | ---: |
| Scene programs compiled during a cold launch | 46 | 19 |
| Median total scene compilation time | 6.806 s | 1.800 s |
| Median menu setup through first GPU readback | 6.763 s | 2.006 s |
| Median same-menu readback on a warm launch | 0.481 s | 0.397 s |

The menu readback interval excludes earlier engine startup and intro movies;
it includes four rendered frames. These are startup measurements, not gameplay
FPS or sustained thermal measurements. The requested rendering programs retain
the same source, so no reduction in visual quality is intended. First use of
an uncached specialization can still pause synchronously, as before.
An additional cold pair without either engine's profiling logs measured
6.718 s versus 2.004 s, with identical pixels.

The baseline, instrumented candidate and final engine without profiling logs
each passed 536 rendering assertions. All 65 captures matched exactly across
engines, including live feature changes, wounds, alpha, shadows and instancing.
Both cache upgrade directions rendered the same menu without recompiling.
A separate process first saved colour-only caches with three empty mode maps;
the next run loaded those caches and correctly compiled instanced colour and
both shadow modes on demand. The fully warmed rendering suite compiled no
scene programs. The final engine also passed 26 real-service campaign checks
covering dialogue, save/load, suspend/resume and worker shutdown, with clean
native process exit.

A normal launch with the QA bootstrap inactive, default settings and an empty
Godot shader cache completed both movies and reached the menu and graphics-check
consent. Skip persisted, and Exit terminated the app cleanly; no QA process
returned during the following 15 seconds. The private QA package was removed
after testing, leaving the normal game and existing performance profile intact.

All thirteen existing engine patches were retained; the three comparison APKs
have identical entries except the Godot library and signatures. The production
patch is restricted to Android GLES scene initialization; desktop, Vulkan and
other GLES shader families retain their previous path. Existing nonfatal Scudo
warnings appeared with both engines. The affected Adreno 840 is unavailable,
and no crash was reproduced here: these results establish a startup improvement,
not the cause or resolution of issue #3. Installed templates and published
artifacts were not replaced.

The [measurement record](validation/android-gles-scene-variants-2026-10-14.json)
contains build provenance, individual timings, image hashes, cache checks and
the final normal-start result. The patch and development-only profiling patch
are documented in [the engine recipe](../engine_patches/godot-4.7/README.md).
