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

The next useful crash experiment is a controlled startup split: loading movie
alone, menu island without calibration, then individual terrain/water/object
materials, followed by calibration. Compare against a known-working APK on the
same phone. This can locate the failing component without requiring the player
to collect an ADB log. It should precede claiming another general stability fix.
