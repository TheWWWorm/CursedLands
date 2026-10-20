# Autochess presentation validation — 2026-10-19

Local changes based on published Cursed Lands **1.18.0**, commit
`ba04fa9ba3854ae231806616b85c239507e4dcd6`.
The separate worktree is on `fix/autochess-snow-camera-20261019`.
This is a Linux development preview, with release metadata retained at 1.18.0.

## Findings and resulting behavior

- Level three is the intended opening deployment capacity: three slots,
  zero experience, six experience required for level four.
- The courtyard continues into textured snow at every supported zoom, including
  the overview. Clockwise ring faces and upward normals match native ground
  lighting, avoiding a visible square boundary. The default camera uses a
  diagonal horizontal orbit; its tilt remains 34 degrees and its starting
  height remains 42.10144 metres at 1280×800.
- Arena deformation previously retired tiles after a 128-tile allocation.
  The complete clearing and a 2.5-metre shoulder fit a bounded 16×16 tile
  window, retaining 256 tiles without evicting old trails. The campaign
  budget remains 128; individual arena sectors remain within their native cap.
- Finished damage reports retain the combat roster and totals through shopping,
  evolution, withdrawing and preparation. The next battle resets the report.
  Winner names stay green and loser names red until the next battle starts.
- Result bolts use the HUD camera projection, follow player identity through
  standings reordering, and remain alive for long flights at large resolutions.
  Their source now uses the visible creature's animated casting socket.
- Zero health can precede final placement because all boards settle together.
  The interface shows localized `Out` until the shared tie rules assign a
  finishing place. Eliminations enqueue one localized notification per player.
- Projectile-mouth fix `3768e462d1e510874fcbd0c799323bb21dc3ccc8` is an ancestor
  of 1.18.0 and its shipped source. Its released-projectile attachment was
  present, while elemental charge-up particles still queried the general
  body point and result salutes still used a fixed body height. Both paths
  now use the same animated socket as the released spell. Incoming spells
  and other attached body effects retain their existing anchors.
- Horror lightning uses the animated right fingertips, rather than a point
  inside the palm mesh. Its only authored death clip, `cdeath`, is an airborne
  cycle. Trials presentation supplies its descent and grounds the final
  visible mesh vertices, including on first scouting a finished board.
  Combat placement and health remain authoritative and unchanged by the fall.

## Validation

The [machine-readable report](report.json) lists the latest successful test
runs, profile/log paths, source file hashes and local preview hashes. Regression
runs were repeated after changes affecting their paths; the final preview was
checked with the rendered standings/socket and post-battle fixtures.

- Native socket, scaled-model charge-up and corpse handling: EN/RU/DE.
- Damage persistence, serialized board reports, elimination ranking, online
  replication, deformation capacity and the existing projectile-origin suite.
- Rendered result colors and localized notifications/reports in EN/RU/DE.
- Compatibility and Forward+ camera/snow captures, including 2560×1440,
  full zoom, rotated views, Home/scout reset, projection and ground picking.
- Translation checker: 2814 entries, 141 dynamic wiki keys, 179 dynamic arena
  keys, zero errors. `git diff --check` and preview-launcher syntax pass.
- The preview launcher was started and verified against its isolated profile:
  free cursor, FPS visible, three audio volumes zero, Autochess selected.
  All test profiles receive these preferences before launch and use Dummy audio.

All runtime checks ran on Linux with the qualified 1.18.0 custom Godot 4.7
engine and original localized game archives. These changes have not been
qualified on Windows, macOS, web or a physical Android device.

## Captures

- [Default camera](snow-default.png), [maximum zoom with continuous snow](snow-wide.png).
- [Persistent result colors](result-colors.png), [German elimination notice and retained report](elimination-de.png).
- [Dragon fireball at the mouth](dragon-mouth-release.png).
- [Horror fingertip lightning](horror-fingertips.png), [grounded corpse](horror-corpse.png).

The close-up creature fixtures use a fixed camera and manually advance the
native particle/animation clock to make origins and contact visible. They do
not represent a performance measurement.

During visual verification, reversed ring winding was corrected after it
produced a lighting boundary. ArrayMesh normal compression also required a
numeric tolerance rather than component equality in the fixture. The result
salute fixture holds processing before inspecting the queued event; ordinary
processing can consume that event on the same frame. These were corrected
before the final captures and passing runs.
