# Dead City, host menu and conversation follow-up

Status: unreleased candidate following the [Portal checkpoint](performance-portal-2026-10-07.md).
The new supplied archive contains base-game quick/autosaves in Мертвый Город
(Dead City, `gz9g`). Tests use isolated copies; original saves are preserved.

## Dead City at 2× in co-op

The candidate averages **5.50 FPS versus 4.65 in Experimental 3**,
a **18.2% increase** on this test machine. This remains a
severe CPU bottleneck. It does not establish the user's hardware frame rate,
and it does not make the scene smooth.

Linux Ryzen 9 5950X / RTX 3090, Forward+ Vulkan, 1280×720 native resolution,
uncapped FPS, default graphics and Distant AI off. Each host has a real ENet
client on separate cores. The host main thread is pinned to core 15, workers
10–13; client main 14, workers 6–9. All these rendered runs use an owned private
Xvfb display. There are 315 units after joining, about 7 visible in the saved
camera view. Reconnection deploys the saved joining hero beside the host.

Every run starts with a fresh isolated profile, loads the quicksave, warms
rendering while holding simulation, waits for the client, then measures 30
seconds. Profiling is off. The complete interval includes initial path/AI
work. Two clean runs per final build are reported; intervening diagnostic
runs and the intermediate candidate are retained separately. These are small
samples, not a broad hardware or campaign benchmark.

| Whole-window measurement | Experimental 3 | Final candidate |
| --- | ---: | ---: |
| Mean FPS | 4.65 | 5.50 |
| Range of run FPS | 4.57–4.73 | 5.45–5.54 |
| Mean p95 frame time | 232.2 ms | 199.1 ms |
| Mean simulation ticks | 695.0 | 821.5 |
| Simulated seconds in 30 wall seconds | 38.2 | 45.2 |
| Mean GPU frame time | 14.2 ms | 13.6 ms |

The game should advance 60 simulated seconds in 30 seconds at 2×. Neither build
keeps up in this scene: the simulation catch-up cap is reached. FPS alone
therefore understates the remaining problem.

### Cause and correction

The activity scheduler checked `GameUnit._hp`. For creatures with body parts,
that field is only an old fallback; actual health comes from the body. Co-op
monster scaling increases maximum/body health without updating the fallback.
Consequently every healthy scaled NPC looked wounded to the scheduler and
could not defer redundant calm decisions. Diagnostics found 255 quiet actors
in the co-op population, but zero deferred decisions before correction.

Eligibility now reads the actual `hp` property. Healthy scaled units can use
the existing patrol/glance deadlines; genuinely wounded actors stay active.
The two final runs omit 198,162–202,132 redundant decisions, roughly 78% of
considered decisions. Unit ticks, movement, damage, healing, scripts and
wake-up tests still run normally. This does not use camera distance or turn
on the optional Distant AI setting. No save or network schema changes.

Before the health fix, the Portal animation/navigation improvements alone
averaged 4.73 FPS here, close to Experimental 3. The Portal gain does
not generalize to every map.

A separate Experimental 3 sampling run attributes about 37% of main-thread
samples to AI decisions, 15% to movement, 12% to perception and 12% to path
search. These are overlapping inclusive categories. Profiling itself costs
about 5% of samples, and these percentages are not a profile of the final
candidate. The remaining targets are repeated perception/decision work and
route construction/retries. Typed persistent simulation records and shared
queries are the next architectural boundary; porting the whole game to a
different language or enabling threads has not been measured as a solution.

## Portal follow-up control

A final Portal run in the current private-display harness measured 3.30 FPS.
That appeared lower than the historical desktop-display measurements, so the
previous checkpoint was rebuilt from its exact source and tested under the
same current conditions: 2.97 FPS. Restoring only the old health eligibility
in the new candidate measured 3.05 FPS. Each is one 30-second run, with clean
host/client exits. These checks do not reproduce a regression from the latest
changes, but the sample is too small for a precise Portal improvement claim.

The lower absolute FPS also affects the unchanged previous checkpoint. The
historical Portal measurements used the inherited desktop display; current
ones use private Xvfb. Do not pool those results or infer the exact cost of
the display change from this comparison. Dead City's paired results above
all use the current private-display setup.

## Host campaign creation menu

The saved-game selector decoded every full campaign save from inside row
layout. The layout was rebuilt repeatedly while drawing each frame. Merely
selecting a save could therefore monopolize the main thread before any map
was loaded.

Validated slots and display titles are now cached when entering the co-op
host page. Reopening refreshes the list after save creation, rename or
deletion. Loading still validates the selected save.

| Saved-game host screen | Experimental 3 FPS | Candidate FPS |
| --- | ---: | ---: |
| Base campaign, selected save | 7.71 | 33.04 |
| Base campaign, hosting lobby | 8.21 | 31.26 |
| Lost in Astral, selected save | 8.74 | 31.68 |
| Lost in Astral, hosting lobby | 9.12 | 31.29 |

One three-second sample per phase/build, using copies of the supplied two
saves for that campaign and the same 1280×720 private-display setup. These
short runs establish the large selector cost, not precise general menu FPS.
The animated background remains enabled in these rows. The separate
background-disabled diagnostic in the JSON is an artificial control.

## NPC approach and conversation stalls

Loading the supplied base-game progress into the first village reproduced
the elder issue: topics opened at a distance, then the elder tried to walk
to a camera mark near Zak. The route never reached its exact destination,
and dialogue waited 30.03 simulated seconds for the staging timeout.

Ordinary village interaction now walks the player's hero to the NPC before
opening topics. Picking a topic turns the actors in place and uses their
actual positions/heights for the camera. The reproduced case takes 3.08
seconds of normal approach and 0.11 seconds of staging. Replacing the order
or failing the path clears the pending interaction. The player can continue
issuing commands during the approach.

The first village story deliberately blocks Zak until he speaks to the elder;
that exception still opens topics and completes the unlock. Automatic zone,
script and programmatic side-quest briefings retain their existing staging.
The separate Lost in Astral cinematic/camera and quest-script reports remain
open; this change does not establish that those are fixed.

## Validation and limits

- Activity batch/wake and scaled-body regression suite: 8,020 checks, 0 failures.
- Committed focused [health regression](../tools/tests/ai_activity_health.gd): 45/0,
  across light/normal/strong scaling, 2–4 players, real body injury, healing and
  removing scaling. The broader suite includes the same 45 checks.
- Real-map patrol/deadline/stealth/wake fixture: 22/0; patrol position retained
  and a newly relevant target wakes the scheduled guard on its next tick.
- Committed [dialogue staging regression](../tools/tests/dialogue_approach.gd): 16/0.
- Saved village approach, cancellation/failure, rehire/dismiss/talk: 23/0;
  rendered camera checked. Fresh blocked elder story: 10/0.
- Final co-op dialogue test: 12/0, two real ENet peers in separate multiplayer
  trees inside one engine. The joining player initiates, both peers receive
  the same cast, and completion is credited to the joining player. This is
  not a two-machine/WAN or whole-campaign playthrough.
- Host-menu lifecycle checks: 16/0 in each campaign, including incompatible
  and corrupt saves, selection, refresh and deletion. Candidate export clean.

A baseline benchmark completed timing but hit an RPC-node teardown race in
the private fixture. It is excluded from the clean averages; closing ENet
before destroying nodes fixes the fixture. Earlier zone/name fixture mistakes
and a test-only type-inference error are also retained in private receipts.
The rendered village run printed nonfatal Cyrillic-to-ASCII warnings; no
script errors or assertion failures occurred in the corrected checks.

Windows/device performance and a complete ordinary co-op campaign are not
verified by this checkpoint. Published Experimental 3 remains unchanged. Raw
summary rows and source/runtime hashes are in
[the measurement record](performance-dead-city-measurements.json).
