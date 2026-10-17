# Pause-menu rendering and build version

17 October 2026. Local fix for [#17](https://github.com/TheWWWorm/CursedLands/issues/17),
based on published stable v1.10.0. No release or version bump.

## Cause and change

The pause signpost uses a SubViewport whose texture retains the previous
fully opened menu. With the desktop's separate rendering thread,
`frame_post_draw` is delivered later on the main thread. The first completion
received after opening can belong to a frame submitted before the new pose.
Waiting for that one signal can reveal the retained texture too early.

The original report's video shows this on reopening at approximately 5.133 s:
the complete signpost appears, followed by the bottom of its opening slide.
The released Linux executable reproduces the retained texture in the regression:
the settled and first refreshed samples both contain 115,977 opaque samples.
The original opening-frame assertion fails; the other 20 clock assertions pass.

The fix holds the opening pose and keeps the texture transparent through two
draw completions. Closing invalidates any pending reveal and restores the
viewport's visibility-based update policy. The real-time animation clock starts
after preparation, preserving the full opening clip at low frame rates and
under gameplay pause or acceleration. Headless execution does not wait for a
render completion.

A shared `BuildVersion` control shows `application/config/version` in the bottom
right of the main and pause menus. `Version %s` is translated through
`RemakeText.t` in EN/RU/DE. The footer follows the existing interface font scale,
reserves space below main-menu buttons, clears controller hints, and ignores
pointer input. Options and resumed gameplay hide it with the owning menu.
It currently displays 1.10.0 because this is an unreleased local change.

## Reproduction and checks

Use the project's normal test entry point with original game data, for example:

```sh
./CursedLands.x86_64 --rendering-method gl_compatibility -- \
  --no-local-worker --ei-path=/path/to/original-game \
  --tool=/path/to/checkout/tools/tests/pause_menu_clock.gd
```

Run against an exported pack with the production Linux executable. Its default
separate rendering thread is significant; editor-only verification does not
cover that configuration. Use disposable XDG data/config/cache directories.

- `pause_menu_clock.gd` checks the first refreshed texture, hover protection,
  clip duration at three gameplay speeds, paused and unpaused play, a speed
  change during opening, and reopening an interrupted slide. Timing assertions
  allow completion on the next process frame, recording its measured interval;
  this distinguishes animation speed from an occasional window/render stall.
- `pause_menu_frames.gd` captures the complete displayed opening at normal and
  low frame rates, with pause and acceleration, repeated reopening and immediate
  cancellation. It also checks that closing stops forced viewport updates.
- `menu_build_version.gd` builds the actual main menu and opens the actual HUD
  pause menu in a solo campaign. It checks localization, corner placement,
  button separation, input transparency, options visibility, pause restoration
  and controller-hint clearance at 800×600, 1024×768, 1920×1080 and 3840×2160.
  EN/RU/DE runs use their original language archives.
- `menu_hidden_viewports.gd` checks draw submissions while other menu screens
  are closed, opened and closed again.
- `lia_tomb_exit.gd` checks that the combined local pack retains the issue #16
  story and saved-game recovery fix.

The clock checks pass 21 assertions in each rendered configuration:
Compatibility with a separate render thread, Forward+ with a separate render
thread, and Compatibility with the safe rendering mode. Headless passes 18.
The first visible texture contains 6,685 opaque samples after the fix, rather
than the retained 115,977-sample complete signpost.

The composited frame checks pass 28 assertions on each of Compatibility and
Forward+. Each language passes all 58 layout and menu-lifecycle assertions,
including visual inspection of the rendered screens. Hidden-menu rendering
passes nine assertions; the combined pack passes all 36 tomb regressions.
The translation scanner reports 2,473 remake entries, 141 dynamic wiki keys,
123 dynamic arena keys and zero errors.
The [validation record](pause-menu-frame-and-version.json) lists the final
results and source/log hashes. These checks total 356 passing assertions.

Validation uses Linux/Godot 4.7 and the release's production executable, with
Compatibility and Forward+ renderers and both rendering thread modes. No
Windows, macOS, Android, browser or network runtime qualification is claimed.
The existing stable tag, release artifacts and hosted export are unchanged.
