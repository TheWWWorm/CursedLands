# Portal hidden presentation checkpoint — 8 October 2026

Retroid Original-look Portal rises from a median **30.26 to 55.34 FPS**
in repeated 60-second runs with separated co-op authority. This combines the
previous UI roster checkpoint with deferred work for hidden, inaudible actors
and Original terrain shader specialization. It is a local checkpoint, not a
published release, and **stable 60 FPS at 1× is not achieved**.

The opening ten seconds of combat average 46.7 and
47.1 FPS. The party dies around 25 seconds; later
near-60 averages include the death view. The report retains every control and
does not treat that period as sustained gameplay success.

## Changes

Hidden replicas beyond hearing suspend their unit and model frame callbacks.
Eight staggered queues retain animation time at a 0.2-second cadence. Visibility,
inspection, sound, particle/bone queries and incoming animation changes consume
pending time immediately. Deferred terrain placement and wounds are applied
before observation. The authority keeps simulating every actor normally.
Pause/resume, world replacement and repeated sleep/wake preserve callback state.
The first skipped frame is counted once regardless of actor/world callback order.

Minimap and party-face queries reuse the visible and party rosters. Original
terrain shaders compile disabled detail, ground blending and weather terms out;
live option changes restore their uniforms. With the hidden work in place,
removing only this shader specialization reduced the matched run from
54.48–54.88 to 48.70 FPS. The earlier shader-only experiment had no complete
gameplay gain; the combined comparison is the reason for retaining it now.

One-second hidden schedules and a lower render scale did not convincingly
improve complete gameplay and are not retained. Engine and native binaries
remain unchanged.

## Measurements and correctness

The close Terror fixture starts with 415 actors and advances 59.895 simulated
seconds per 60 real seconds in both final runs. Actual Original look disables
every remake graphics switch. Settings: 1920×1080 viewport, 75% render scale,
OpenGL ES, FOV 55, far 100, four workers, one owner, no external guest, normal
commands/combat and Distant AI off.

| Final run | FPS | p95 ms | p99 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| throughput-original-1x-hidden-v6-60-01 | 55.33 | 27.824 | 32.995 | 84.866 |
| throughput-original-1x-hidden-v6-60-02 | 55.34 | 27.232 | 32.599 | 93.157 |

The three-minute entrance walk uses a terrain-aware rotating gameplay camera,
normal move commands and all 415 actors. It averages **45.09 FPS**,
advances 179.905 simulated seconds, and ends with
two living controlled characters. Both stayed alive throughout the run.
This is separate exploration coverage, not the close-combat comparison.

The lifecycle fixture passes **69 checks each on stock Linux, patched Linux
and physical Retroid**, including the reproduced first-frame clock regression.
The unchanged shader variant passes 308 checks each in headless Linux,
OpenGL compile/draw validation, Mobile Vulkan, Forward+ Vulkan and physical
Retroid OpenGL/Mobile Vulkan. An earlier frozen Original terrain comparison
has zero changed pixels in the central ground region.

A contemporary full-simulation reverse control takes 36.320 seconds versus
36.555 for the hidden-presentation candidate, each for 1,100 ticks / 60.5
simulated seconds. The 0.65% difference establishes no further simulation gain
or material regression. The target of 60 simulated seconds within 30 real
seconds remains open. The final clock-corrected build takes 35.354
seconds (29.537 seconds in the ticks themselves) for the same fixture.

## Limits and next work

An ordinary single-player Portal entrance run at Original/1× measures
**12.41 FPS**, despite advancing 59.62 simulated
seconds in 60 real seconds. It still runs simulation inline and receives none
of the hidden-replica scheduling benefit. Extending separation must preserve
single-player pause, difficulty, experience, story and save semantics.

No desktop gain is established. The earlier 4K/max Linux pair was 67.20 FPS
control versus 63.58 with the intermediate candidate; subsequent attempts
were aborted because unrelated Godot work overlapped. Windows D3D12 was not
tested. The reported 7945xh/4090-mobile, 4K/100%/maximum-settings co-op result
around 40 FPS remains unresolved, and previous 720p Linux numbers are not a
promise for that configuration.

The [validation record](portal-hidden-presentation-validation.json) records
effective settings, artifact/source hashes, all compared runs and limitations.
The private Android package remains separate from the user's installed game
and saves. No new public package is published at this checkpoint.
