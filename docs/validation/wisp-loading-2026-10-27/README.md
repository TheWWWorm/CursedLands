# Wisp first-use preparation and post-load validation

This change completes the earlier [save-loading work](../loading-performance-2026-10-26/README.md)
and prepares the native `WillowispM1`, `WillowispM3` and `WillowispM5` family
before its first Autochess recruitment or combat appearance.

## Reproduction and change

The real recruitment card reproduced a large first-appearance stall even after
the existing arena preparation completed. A cold card added a surface pipeline
and a specialization pipeline. Repeated appearances did not. Scoped probes put
morph decoding at about 1.7 ms; the large delay came from first-use graphics
work, including material reflection/duplication and pipeline preparation.

Opening preparation now draws a small off-screen instance of the ordinary
Paperdoll with the real animated wisp meshes. It waits for framing and four
completed draws. The world-material pass also includes the authored wisp vertex
layout. Restored shop offers wait for this preparation, while the existing
animation and picking gates remain in effect. Prepared resources are reused;
shader changes invalidate readiness. Cancellation releases both the viewport
and its unique compilation-cover owner.

Campaign forced preparation retains its synchronous API. The temporary preview
has its own canvas so a hidden HUD cannot prevent framing. This edge case was
found by the campaign reload tests, fixed, and added to the regression. Deferred
preparation owns a separate cover until it finishes. The new canvas is retired
after preparation and has no ongoing gameplay work.

No authored mesh, crystal animation, pulse, particle callback, combat rule,
graphics-quality setting or player text changes. The earlier loading changes
retain every material representative and four completed settling draws per
batch. Terrain preparation still joins its load-time jobs before reveal;
ordinary terrain streaming retains its existing two-job limit. Cliff/snow
reconstruction and PT/NRD program reuse occur during the existing loading path.

## Matched wisp measurements

One serial GPU Lab heavy job used the same qualified Linux executable, High
settings, RTX 3090 Ti, Vulkan and fresh isolated profiles. The order was
before/after/after/before. The unchanged comparator includes all three earlier
loading passes, isolating this wisp change. Each run prepared the real arena,
displayed a valid non-wisp recruitment card, then recruited all native wisp
forms and revisited the first one. The sampling window includes `update_offer`.

| First wisp appearance | Before | After |
| --- | ---: | ---: |
| Worst delivered frame, two launches | 775.122 / 1,015.171 ms | 33.362 / 33.354 ms |
| New surface pipelines | 1 / 1 | 0 / 0 |
| New specialization pipelines | 1 / 1 | 0 / 0 |

The card comparison uses a 30 FPS limit; 33.3 ms is its ordinary frame interval.
It demonstrates removal of the first-use stall, not a general FPS improvement.
The initial exploratory 862 ms versus 33 ms result agrees with this matched run.
An earlier probe used an invalid wolf ID and crashed while switching cards; it
is retained as an excluded fixture error, not performance acceptance evidence.

## Regression and original-game scope

The registered `wisp_loading` fixture checks first recruitment and combat
appearance, all five authored crystals and independent phases, completed draws
on the rendering thread, repeated preparation, shader refresh/restoration,
cancellation, re-entry and a hidden campaign HUD. The final base-campaign run
passes 36 checks. The same final 36-check fixture fails seven assertions against
the unchanged wisp build, including new first-use recruitment and combat pipelines.

LiA has a different monster catalog and does not support the base Autochess
roster. Its separate 10-check fixture verifies that both campaign preparation
paths skip the missing wisp without allocating a preview or retaining a cover.
An initial attempt to reuse the base-roster fixture crashed after it tried to
inspect a missing creature; that invalid fixture and its failed report are
retained. No LiA content was added or substituted to make the test pass.

Campaign save-load cache checks pass in PT and raster modes, and the existing
material preparation test confirms its synchronous completion and draw bound.
The arena progress fixture now waits until the actual covered image reaches
readback before selecting its first screenshot. It retains all three required
captures, the same opacity/legibility thresholds, and completed-draw ordering.
It passes 27 checks on both unchanged and changed builds. The original queued
previous-frame failure is retained in the evidence.

The final production pack passes **24,475 assertions across 17 distinct
registered cases**, plus 11 Python runner tests. This includes the related
particle, picking, creature-animation, native-callback, combat, both wisp
renderers, campaign-loading and first-person traversal checks. The retained
acceptance index identifies the exact successful reports without counting
reruns twice. Initial river-route failures and excluded fixture errors remain
separately recorded; the earlier loading reports retain their own qualification.

The corresponding original renderer has no Godot pipeline compiler, Autochess
shop or remake wisp pulse shader, so a new Wine timing comparison would not
exercise this failure. The earlier loading pass retains its original save-load
comparison under Wine. The [original wisp disassembly and executable callback
fixture](../wisp-native-glow-2026-10-18/README.md) establish the preserved native
geometry/particle behavior; the callback, animation, picking, combat and visual
regressions are included in this task's validation. No original-game timing
parity or native Windows/Android performance claim is made.

## Post-load traversal

The additional comparison covers the complete loading change against the
unchanged local-main commit `9cacce1a83f176753447d4cf6b4a72bf13c060a9`.
It uses the same executable and frozen source packs, real solo-worker save
loads, live unit orders and camera input, with no settling period after reveal.
The frame-by-frame evidence includes ordinary movement, new terrain entering
view, repeated movement, PT rebuilds and a second load of the same save.

The benchmark pilot's starting hero died and paused simulation. It is excluded.
The matched fixture instead uses identical retained saves with ordinary level-15
attributes and authored equipment, leaving enemies, damage and simulation
active. It rejects a dead hero, interrupted simulation or stationary camera
pan. Full measurements and their limitations are recorded with the completed
comparison evidence and the [post-load frame-pacing report](post-load-traversal.md).

## Evidence

Raw reports, frame timelines, source/pack/save hashes, screenshots, executed
fixtures, excluded attempts and GPU job records are retained in the workspace
at `local/validation/wisp-loading-20261027/`. The maintenance ledger records
local-main integration and removal of task-owned export staging, profiles,
reproducible caches and duplicated test libraries. Shared engines, original
assets, unique saves and reference evidence are preserved.
