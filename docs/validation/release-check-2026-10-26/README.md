# Main-menu update checks, 26 October 2026

The main-menu footer checks GitHub's latest stable release in the background.
A newer version displays a stone menu button, **Download update VERSION**,
**Скачать обновление VERSION**, or **Update VERSION herunterladen**. It opens
that version's page in the CursedLands repository. The separate manual check
uses the same button style. Keyboard focus, controller targets and touch-sized
hit areas remain available.

Checks use an eight-second timeout, a 512 KiB response limit, no HTTP redirects,
a daily success cache, failed-check backoff and GitHub rate-limit deadlines.
Semantic version comparison excludes drafts, previews, invalid versions and
downgrades. URLs are constructed from the fixed repository and validated tag;
API-provided HTML URLs are ignored. Cached update offers survive offline checks.
Failure states offer retries and a download-page button. Browser-launch errors
remain visible until the player retries. No files are downloaded or replaced by
the game, and no automatic restart occurs.

The user requested a visible button and natural Russian update wording. The
initial flat footer action and its literal release terminology were replaced.
The final captions use the update/download wording above.

## Validation

- Deterministic release-policy and actual loopback HTTP tests: **55 assertions**.
  Includes an actual unanswered-request timeout, continued frame processing,
  malformed responses, version boundaries, cache reload and rate-limit headers.
- The explicit live GitHub variant passes **56 assertions**, returning
  `v1.31.1`. GitHub's response also advertises `Access-Control-Allow-Origin: *`.
- A disposable exported Linux template using the unchanged release-check script
  automatically starts the production request with `editor=false`, receives
  `v1.31.1`, and advances **19 frames** while it runs. Its source, export/import
  diagnostics and runtime are disposable; the actual result log is retained.
- Final main-menu button tests pass **738 assertions** and cover EN/RU/DE at **800×600, 1920×1080,
  2560×1440, 3840×2160 and 720×1280**. They check all five request states,
  button styling, text bounds, safe areas, footer separation, controller targets,
  keyboard activation, Options visibility and browser-error retry recovery.
  Native viewport dimensions are asserted; the 4K captures contain 3840×2160
  pixels even when the virtual monitor is smaller.
- Existing base/expansion main-menu alignment checks: **112 assertions**.
  The existing main-menu and actual paused Escape version check passes all
  **58 assertions**, including 4K placement and gamepad hints. Its old summary
  includes the locale, so the evidence harness uses `MENU_BUILD_VERSION en`.
  No fixture assertion or tolerance was changed.
- Runner and gameplay-catalog unit tests: **44 tests**. Translation coverage:
  **3,551 entries, zero errors**.

The initial shortened-timeout fixture was corrected to wait for the unchanged
eight-second production timeout. The first parser test found a trailing-newline acceptance issue; the final
parser requires a complete match. Initial UI tests found a half-pixel footer
intersection at the smallest UI scale. The final footer adds eight pixels of
clearance. Those initial failing logs remain alongside the passing results.
The GPU Lab monitor-refresh diagnostic is classified by the existing runner as
infrastructure; it is retained verbatim. No game error is excluded by this change.

## Scope and evidence

Linux OpenGL and an exported Linux release-check probe were executed. Native
Windows, macOS, Android and browser execution were not performed for this
change. The code uses portable Godot HTTP/browser APIs; those platforms still
require their normal export/device validation. Hosted browser service-worker
updates retain their existing lifecycle.

Original-game code/Wine comparison is inapplicable: this is a new remake
GitHub distribution feature, with no original-game equivalent. No original
behavior or original assets are changed. No push, public release, publication
or version bump is part of this task.

[Results, source hashes and commands](results.json) and compressed logs retain
the assertion evidence. `release-{en,ru,de}-{800,3840}.png` retain the final button
appearance. **9.0.0 in those captures is a local test fixture**, not an available
public release. Workspace cleanup is recorded under `local/maintenance/`.
