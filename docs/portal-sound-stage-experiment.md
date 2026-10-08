# Sound traversal experiment — 8 October 2026

The proposed native sound traversal is **rejected**. Its median complete-game
result is **53.77 FPS**, versus **53.74 FPS** for
retained code `40394a3` (0.056%). This is effectively flat; the two
matched pairs disagree (-2.78% and +3.07%). The
added script/native implementation and all three rebuilt native modules were
restored to `40394a3`. No new performance improvement is claimed.

## Candidate and checks

The prototype moved the ordered per-frame sound traversal into UnitQueryKernel.
It read live native actor positions where available, retained property fallbacks
for custom actors and marked unheard sound states without entering script. Nearby
actors called the existing sound logic in order, before sampling the next actor.
This preserved callback-driven movement and deletion, but retained a native-to-script
call for every nearby actor on every frame.

An independent copy of the former full traversal compared sound dictionaries,
544 actual footstep/voice API calls, live handles and the next random draw through
240 frames. Boundaries, NaN/infinite positions, silence, death/visibility, clip
switches, missing models/players, record detachment, same-count replacement,
custom actors and callback-driven movement/deletion were covered. The suite
passes 967 checks on stock Linux, packaged Forward+ and Retroid; the older-helper
fallback passes 962. Hidden presentation passes 69 checks on Linux and Retroid,
and shared registry queries pass 1,283 on Linux. The first run caught an explicit-type
requirement in helper initialization; it was repaired before these checks and
before gameplay benchmarking.

## Complete gameplay

| Production run | FPS | p95 ms | p99 ms | Simulated seconds |
| --- | ---: | ---: | ---: | ---: |
| Candidate / 1 | 53.79 | 24.815 | 28.617 | 59.895 |
| Control / 1 | 55.33 | 24.203 | 27.175 | 59.840 |
| Control / 2 | 52.15 | 26.309 | 29.791 | 59.840 |
| Candidate / 2 | 53.75 | 24.814 | 27.728 | 59.950 |

These are two reversed 60-second pairs on the same Retroid, using production
engines, identical actual Original graphics, 1×, 1920×1080 viewport, 75% render scale,
OpenGL ES and four workers. All 415 actors remain; both characters stay alive and
simulation advances normally. Private APK50 is the control and 51 the candidate.
No graphics quality, health or population was reduced. The small mixed result
does not justify retaining the extra implementation or running a longer acceptance
comparison of this design.

## Why the design did not survive

A separate Linux component diagnostic over 415 actors explains a limitation:
the traversal takes 64.2µs instead of 90.4µs with no nearby actors, but 559.7µs instead
of 484.5µs when all are nearby. With 40 nearby actors the saving is only 12.6µs per
update. These are diagnostic component timings, not FPS evidence. Frequent
cross-language callbacks erase much of the filtering benefit and regress dense
nearby populations. The next redesign should remove work across the complete
stage rather than retain this extra boundary per actor.

## Restored checkpoint and evidence

All 520 canonical game files match `40394a3`. Staging runtime files also match;
the documented private export preset and benchmark bootstrap remain separate. Candidate
build objects were removed so a later incremental build cannot reuse the rejected
module after restoring older source timestamps. The candidate source, fixture,
binaries, patch, APK51 and measurements remain archived locally under
`local/scratchpad/portal-throughput-20261007/sound-stage-experiment` and its linked
artifact paths. The private export helper now takes explicit baseline/change
arguments instead of writing stale descriptions into new export receipts.

Private production APK50 is installed again, benchmark autorun is disabled and
neither private process remains. See the [validation record](portal-sound-stage-validation.json)
for hashes, test receipts, measurements and restoration. The retained longer
Portal result remains 55.89 FPS at Original/1×, below stable 60. The Windows 4K/max/D3D12
report is unresolved. No release or broader gameplay certification is claimed.

The next larger target is the worker's presentation stage, previously about 21%
of sampled worker CPU. Any cadence or stage redesign must preserve input and
snapshot responsiveness, dialogue/animation-dependent gameplay and full logic
progress, and survive repeated complete-game/full-tick comparisons.
