# Android startup recovery follow-up

This patch builds on stable 1.1.1 (`182ee0f`) and the
[Android stability audit](android-stability.md). It addresses an uncovered
startup path and adds a way to isolate rendering stages. It does **not**
establish the native fault behind [issue #3](https://github.com/TheWWWorm/CursedLands/issues/3).
No public release has been published from this patch.

## First menu and graphics trials

A fresh handheld previously constructed and rendered its first menu with
enhanced platform defaults before calibration wrote its rollback record. The
Redmagic reports stop in that interval: `graphics detection: first` schedules
calibration, but does not mean a tier has been applied. Recovering an interrupted
test also restored those enhanced defaults, so it did not provide a basic
fallback for a failing first trial.

`GfxDetect.prepare_startup()` now temporarily applies Original look, no
antialiasing or shadows, and a 30 FPS cap before building that first menu. It
applies only when automatic detection is enabled, no detection record exists,
and the graphics still match platform defaults. Manual choices and existing
detection records retain their settings. The temporary choice does not write
preferences or a successful detection result.

Calibration waits for the loading/movie screens to disappear, including when
loading takes longer than the previous 20-second limit. It then uses the
existing transaction: save the basic rollback values and pending tier before
applying enhanced settings. An interrupted trial restores the basic values on
the next launch and skips automatic retries. Successful calibration still
selects and saves its measured tier. An enhanced trial can still crash once;
basic rendering itself has not been qualified on the affected Redmagic.

## Recovery controls and rendering probe

The report offered before startup after an unexpected menu exit has two extra
actions, translated into English, Russian and German:

- **Use basic graphics** disables enhanced effects and automatic detection,
  disables antialiasing/shadows, caps rendering at 30 FPS, and limits resolution
  to at most 75% without increasing an already lower scale. It saves those
  graphics settings and continues startup.
- **Test startup graphics** uses the player's current settings to present the
  loading picture, construct the real menu, then draw sky, terrain, water,
  objects, signpost, the complete scene, and the menu screens. Each stage is
  traced before its work; completed stages require presented frames and GPU
  readback without captured engine errors. The result goes into the existing
  exportable report. The probe does not start calibration or rewrite settings.

The probe freezes the isolated scene while testing its geometry groups. It is
not an animation stress test, a native backtrace, or a qualification of every
graphics combination. A native crash leaves the last stage in the next
startup report. A successful run on one driver cannot qualify another driver.
Ordinary log export and in-game crash reports retain their two report actions.

Hidden Options, Load and network interface boards now use visibility-driven
viewport updates and do not resize while hidden. On the Retroid menu, five
closed boards previously submitted nine extra draw calls per frame; the patch
removes those submissions and still renders/resizes the boards when opened.
This defect existed in 0.1.0, so it is not evidence of a regression introduced
in 1.0.3 and is not claimed as the cause of issue #3.

## Version history relevant to the hypothesis

The shared vertex-lighting and enhanced-water wave changes appear in `862032c`
(1.0.1), after the reported working 1.0.0. The first 1.0.3 release commit was
`969bc7a` on October 6, before the later rendering additions included under the
stable 1.0.3 tag. The menu, loading-screen and graphics-detection sources did
not change between 1.0.2 and that first 1.0.3 commit. Later water sampler packing
changed in `a916f95` on October 10. Thus comparing only today's 1.0.3 tag would
conflate different builds. The earlier shared shader changes remain candidates;
the current evidence does not select one as the cause.

## Validation on 2026-10-14

The exact sources, build hashes, commands and result files are recorded in
[the validation record](validation/android-startup-recovery-2026-10-14.json).
Android tests used an isolated QA package on a Retroid Pocket 5, Android 13,
Adreno 650, with byte-identical native libraries to 1.1.1. Original game data
was not bundled. The QA package was removed afterwards; the installed game and
performance packages were retained.

| Check | Result |
| --- | --- |
| Actual first menu and persisted first tier | Android GLES: 13 checks passed. Desktop GLES handheld test: 14 passed, including the live frame cap/antialiasing state and a 21-second loading-screen hold. |
| Forced interruption during the first persisted Android tier | Restart: 4 checks passed; basic settings restored before menu construction, no automatic retry. This was a controlled SIGKILL, not a reproduced GPU crash. |
| Normal Android startup, intro enabled, fresh settings | Menu ready and calibration completed with no captured errors; no test bootstrap active. Intro was skipped through ordinary input. Asset caches were reused. |
| Recovery controls and nine real rendering stages | 386 checks passed on each of desktop GLES, Android GLES and Android Vulkan Mobile. Settings and detection records retained during the probe. |
| Hidden interface viewports | 9 checks passed on desktop GLES and Android GLES, with explicit disabled/always-render controls. |
| Dialogue, save/load, background/resume and worker shutdown | 26 checks passed on Android GLES. This fixture uses Original look and disables calibration. |
| Existing interrupted-detection and startup-report fixtures | 27 headless recovery checks and 86 rendered startup-report checks passed. Headless checks do not qualify rendering. |
| Localization and build | 1,145 translation entries, zero errors; EN/RU/DE report layout inspected on desktop and Android; editor import and desktop/Android exports passed. |

The Redmagic/Adreno 840 crash, broad upgrade behavior, sustained gameplay
performance and the unconfirmed forum reports remain open. The next affected
device run should compare basic startup with the staged probe and preserve the
last completed stage. A failure in the shared basic renderer would require a
different fix from an enhanced-only failure.
