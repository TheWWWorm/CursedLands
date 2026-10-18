# Autochess second preview validation — 2026-10-18

This unpublished development preview builds on 1.16.0 (`adf05385`). It retains
the interface, camera, cursor, profile and simulation fixes documented in the
[first preview](autochess-frame-time-20261018.md), expands recruitment to forty
families and strengthens the CPU's final-evolution planning. It is not a new
published release. The first preview archive remains unchanged.

## Recruitment and CPU results

The five tiers now have **7 / 9 / 10 / 8 / 6** families, with sixteen available
at the opening. Sixteen families have been appended to the original twenty-four;
existing family indices and saved recruitment lines remain stable. See the
[roster and rules](../arena-autochess-design.md) for prices, tribes and copy costs.
The additions include human melee/ranged troops and casters, zombies, ghouls,
elementals, hounds, evil eyes, dragons, cyclopes, shadows and banshees.

Native combat tests informed these recruit-only adjustments:

- Woodsfolk mystics evolve into a white unicorn, preserving their forest/mage
  connection and giving the final form a viable native attack.
- Evolved dragons and storm banshees use stronger native effect runes.
- Final grey harpies and cyclopes use 44 general armor instead of the original
  boss value of 150; their relative elemental resistances are preserved.
- Prices and copy requirements reflect combat strength and the cost of reaching
  the final form. Campaign prototypes and native spell behavior are unchanged.

The completed validation comprises **5,056 native combat fights**: 800 duels at
rank one, 800 at rank two, 3,200 at rank three and 256 same-tier team fights.
The ten follow-up families face the whole roster at ranks one and two; every
family faces every family in both seat orders at rank three. Team cases place
the candidate behind a fixed two-creature frontline. These test counters and
roles rather than requiring every unit to win half of every fixture.

Four paired legacy/new CPU tournaments ended in **four new-planner victories**.
New seats averaged **3.0th place**, legacy seats **7.0th**. From round eight,
new seats averaged 24.09 gold and 2.19 interest, versus 4.47 and 0.009 for the
legacy planner. The new planner reached 54 gold; the legacy planner reached ten.
Both planners use normal shops, prices and combat rules, without stat bonuses.

The planner previously considered only the next evolution, which could discard
progress toward a stronger final form. It now counts all held copies through
both remaining upgrades and retains useful partial lines. A targeted eighteen-
check test covers completing a final evolution with all four spending profiles,
keeping upgrade progress and releasing savings at critical health. Fourteen of
those checks failed before the correction; all eighteen pass afterward. Native
creature spell evaluation also follows their actual zero stamina cost.

Four additional full self-play tournaments rotated the four profiles between
seats. They ended in rounds 32, 32, 28 and 29. Thirty-one different families were
observed after round fifteen.

| Strategy | Mean place | Wins | Highest bank | Three-star field observations |
| --- | ---: | ---: | ---: | ---: |
| Economy | 5.89 | 1 | 52 | 0 |
| Expansion | 4.56 | 2 | 34 | 15 |
| Evolution | 5.78 | 0 | 44 | 26 |
| Tempo | 3.78 | 1 | 24 | 4 |

Field observations count repeated round snapshots, not distinct recruits.
Evolution produced the most final forms; economy reached the full interest
threshold. This small seeded sample demonstrates distinct behavior and a clear
improvement over the legacy CPU, not perfect balance or equivalence to skilled
human play. Some team fixtures remain unfavorable to particular units even when
the same units perform well in duels.

[Summary](autochess-preview2-20261018/balance.json),
[legacy comparison](autochess-preview2-20261018/legacy-tournaments.json),
[self-play](autochess-preview2-20261018/self-play.json), and
[native combat receipts](autochess-preview2-20261018/combat-receipts.json) retain
the seeds, commands, native results and prototype-immutability checks.

## Frame time and lifecycle

The main-resolution cases pass 60 FPS for both their average and lowest rolling one-second window. The additional 4K Ultra / 4× MSAA host stress remains below that floor; it is reported separately and is not a 60 FPS claim. Both host cases include eighteen extra fire effects and a connected guest.

| Case | Render size | Speed | Mean FPS | Lowest rolling 1 s FPS | Worst frame, ms |
| --- | --- | ---: | ---: | ---: | ---: |
| Round 12 | (2560, 1366) | 2× | 113.10 | 66.07 | 30.67 |
| Round 13 | (2560, 1366) | 2× | 114.09 | 68.23 | 37.75 |
| Round 14 | (2560, 1366) | 2× | 112.65 | 66.23 | 43.48 |
| Nine-board overview, round 24 | (2560, 1366) | 2× | 165.26 | 69.46 | 37.38 |
| Scouting, round 24 | (2560, 1366) | 2× | 141.11 | 69.12 | 48.47 |
| Normal speed, round 24 | (2560, 1366) | 1× | 100.21 | 82.68 | 21.66 |
| 4K host stress (additional) | (3840, 2160) | 2× | 64.14 | 52.26 | 26.57 |
| Host with connected guest | (2560, 1440) | 2× | 103.47 | 62.35 | 24.09 |

Consecutive rounds enter combat with worst frames of 22.95 ms; advancing to preparation peaks at 45.66 ms. Constructing the deliberately replaced maximum-rank stress armies takes 1.44–2.76 seconds of staged, responsive battle preparation. This duration is distinct from a blocked frame. All 171 tracked old combat worlds/creatures are released after each round, with courtyards reused. Native combat advances 120 simulated seconds in about 60 real seconds at 2×.

[Frame-time summary](autochess-preview2-20261018/performance-summary.json) and [reproduction receipts](autochess-preview2-20261018/performance-receipts.json) link the commands to complete per-case results.

The test platform is Linux,
Ryzen 9 5950X and desktop RTX 3090, Vulkan Forward+, Safe render thread, Ultra,
uncapped frame rate and VSync off. Solo requests 2560×1440; the desktop limits
the actual window to 2560×1366. Real-host cases use 2560×1440 and 3840×2160,
both with 4× MSAA and a connected guest. No disabled graphics features, frozen overlays,
profiling probes, builds or competing game tests count as acceptance evidence.

The expanded stress formation contains nine three-star families per army across
nine simultaneous boards (162 creatures). It includes dragons, cyclopes, humans,
shadows and native spellcasters. Consecutive natural rounds, overview, scouting,
1× combat and a real 2× hosted session are tested separately.

Further presentation changes:

- Effect warm-up begins on mode entry and collects one courtyard per frame.
  The previous first-battle collection spike of about 200 ms is removed.
- Rank stars reuse cached images of the same geometry. Health labels retain
  drawing commands while their positions follow the animated head every frame.
- Overview board headers retain their drawing commands until their content
  changes. The battle clock changes theme settings only when its warning state
  changes, avoiding three repeated text/layout invalidations per frame.
- Native morph/skin deformation replaces the per-vertex script loop for exact
  pointer bounds. All 1,558 differential checks pass, including original animated
  models and an ASan/UBSan run.
- A native pose-input query replaces hundreds of individual script calls to
  read morph weights. It samples the current weights and named/indexed bind
  poses without retaining scene objects or caching an older pose.
- Conservative mesh classification skips unnecessary per-vertex plane tests.
  The actual posed vertices still determine the returned rectangle; 432 cases
  match the unclassified script path, including boundary clipping and large
  coordinates. Picking geometry is prepared before the battle bell.
- The battlefield, overview and tooltips reuse input-event coordinates. Repeated
  operating-system pointer queries had blocked for 3.5–6.4 ms in diagnostic slow
  frames. Entry, focus and resize refreshes retain stationary-pointer behavior.
- Health-label picking resolves before detailed body meshes. Exact body hits
  visit candidates from nearest to farthest and stop once the winner is known.
  Empty-space and nearby selection preserve the exhaustive comparison.
- Snow mesh jobs keep their complete geometry and timestamps. New tiles batch
  over 50 real milliseconds; at most one finished sector publishes per frame
  across all boards. Existing track textures continue updating every frame.
- The nine-board overview uses 10 Hz distant figure poses, 20 Hz lightning
  geometry and display-rate interpolated movement. Individual actor and bolt
  phases survive long frames instead of resynchronizing their work. Focused
  boards retain normal animation detail. Repeated spell attachment queries are
  reused only within the same synchronous effect update.
- Private overview snapshots arrive one board per staggered slice, retaining
  ten updates per real second for every board and all of their effect events.
- Overview pose phases use deterministic spacing across all creatures. One
  courtyard publishes the shared wind/cloud state, while each terrain clock
  continues advancing. Scouting transfers publication to the focused board.
- Lightning updates reuse compatible GPU buffers and rebuild them when the
  geometry size changes. The 1,271-check rendered comparison preserves all
  279,936 vertices, UVs, colors and RNG states against the script renderer,
  including translated boards and negative atlas phases. Branch initialization,
  noise-key updates and glow slices also use native calculations. Short overview
  flashes draw immediately before subsequent updates use staggered slots.
- Effect attachment bounds read the current authored part origins through a
  native helper. All 952 comparisons match, covering 112 recruited models,
  three poses, detached models, same-frame edits and freed weak references.
  Both new geometry paths also pass ASan/UBSan checks.
- Arena snapshots consume exact body health directly instead of temporarily
  applying rounded health and restoring every part afterward. The 32-check
  online feedback test includes unchanged fractional health, precise healing,
  maximum changes and absence of repeated false damage notifications.

The frame-time target is evaluated using average FPS and the lowest rolling
one-second FPS, with worst individual frames reported separately. This does not
mean every single frame completes within 16.7 ms or that startup is hitch-free.
Cold mode/army setup still has isolated roughly 130 ms frames in diagnostic runs.

## Interface, localization and regression checks

All sixteen added families and their three ranks were rendered in English,
Russian and German. The translation audit covers 2,687 entries, 141 dynamic wiki
strings and 161 dynamic arena strings, with zero errors. Original localized
archives supply creature names where present, including the intentionally
identical English/German “Ghoul”. Tribe icons, readable inspector layouts and
native creature models are covered by the rendered tests.

Scalable menu and HUD font labels use their final displayed pixel density.
Original stone-sign lettering remains part of its source texture artwork.
Held Q/E and right-drag camera behavior is checked at 1× and 2×, and menus retain
the original cursor. The persisted shared name is under Settings → Remake →
Network and co-op → Player name, and is reused by multiplayer and autochess.

The initial [regression/build evidence](autochess-frame-time-20261018.md#regression-and-build-evidence)
still applies to unchanged native code and engine templates. Follow-up results
cover the forty-family roster, CPU planning, rendered layouts, retained markers,
exact crowded selection, snow geometry/capacity/seams and round resource cleanup.

## Artifact and platform limits

The second Windows preview is packaged separately from the initial archive.
Both use the same custom engine with fourteen common desktop patches. This
follow-up changes game scripts/assets and rebuilds the native libraries for
Linux, Windows and Android ARM64 with the exact picking helpers.
The Windows executable and native DLL are cross-compiled, but Windows and an
RTX 4090 laptop were not available for execution. Linux frame-time measurements
must not be presented as measurements from that machine. Compatibility rendering,
Android, Web and native-kernel script fallbacks are outside the 60 FPS results.

The [build manifest](autochess-preview2-20261018/build-manifest.json) records
archive CRC verification, SHA-256 hashes, the source fingerprint and the matching
Windows/Linux game packs. [Regression receipts](autochess-preview2-20261018/regression-receipts.json),
[native builds](autochess-preview2-20261018/native-builds.json) and
[picking sanitizer receipts](autochess-preview2-20261018/asan-picking.json) and
[effect sanitizer receipts](autochess-preview2-20261018/asan-effects.json) record
the follow-up checks.
