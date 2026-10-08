# Portal foreground redraw checkpoint — 8 October 2026

Actual Original graphics / 1× single-player Portal on Retroid improves from
**49.02 to 52.92 FPS median** across two reversed 60-second comparisons
(**7.94% complete-gameplay gain**). A three-minute living-party walk averages
**53.44 FPS**, advancing 179.905 simulated seconds.
**Stable 60 FPS remains open.** This is a local checkpoint after `8bbc09b`,
not a new public release.

## Retained change

Camera rotation previously redrew the complete minimap every frame, including
its map geometry, markers and frame. Only its direction arrow needs that update.
The arrow now has a child drawing item; the map keeps its existing 55 ms update
cadence, with immediate redraws for zoom, sliding, button and layout changes.
The arrow still updates every rendered frame. Unit sound updates also reuse the
world's immutable actor roster and a shared empty lookup default. They retain
the same sound-state, actor order, hearing range and acknowledgement behavior.
There are two changed game files, with no engine/native, simulation, graphics
preset or quality changes.

## Complete gameplay

| Production run | FPS | p95 ms | p99 ms | Worst ms | Simulated seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Candidate 1 | 54.15 | 25.075 | 27.702 | 49.417 | 59.840 |
| Restored control 1 | 49.00 | 27.142 | 31.586 | 54.644 | 59.840 |
| Restored control 2 | 49.05 | 28.429 | 33.045 | 46.806 | 59.840 |
| Candidate 2 | 51.69 | 25.033 | 29.382 | 56.324 | 59.840 |
| Candidate 180 s | 53.44 | 25.140 | 28.632 | 94.638 | 179.905 |

All runs retain all 415 simulated actors and both living party members. Private
APK43 is the control and APK47 is the candidate, with identical production
engine/native binaries. Effective options match exactly: Original look,
1920×1080 viewport, 75% render scale, OpenGL ES, four workers, difficulty 0,
Distant AI off and normal 1× time. These are ordinary single-player worker runs
on the entrance walking loop, not a stationary death view. Raw run, source,
artifact and options hashes are in the [validation record](portal-foreground-redraw-validation.json).

## Validation and diagnostic findings

The minimap fixture compares the new child drawing with the previous single
canvas-item path. All 24 images match pixel-for-pixel across heading, zoom,
slide and viewport scale. Including redraw cadence, input and hide/show checks,
**29 checks pass each on Linux GL, packaged Forward+ and physical Retroid GL**.
The existing hidden presentation/hearing fixture passes **69 checks each on
Linux and Retroid**. Two initial fixture errors and their corrections are
retained in validation; neither required a production change.

Native sampling of the prior production build found 29.87 CPU seconds in the
worker and 26.53 in the frontend over a 30-second window. A private diagnostic
that disabled authority actor/model presentation reduced worker CPU to 24.77
seconds; it is **not a valid gameplay implementation and was not retained**.
An RPC-aligned worker script profile attributes roughly 56% to complete
simulation and 21% to actor presentation. An earlier profile included loading,
which misleadingly emphasized audio; it is excluded from gameplay attribution.
Instrumented FPS is never used for acceptance.

The user accepted 60 FPS at 1× Original on Retroid; frame times still exceed that
budget here. No new full-simulation throughput or Windows 4K/max/D3D12 gain is
claimed. The reported Windows ~40 FPS remains unresolved. The public release,
original Android installation and user saves are unchanged. Future worker
changes must preserve poses needed by gameplay and survive full-tick and
complete-gameplay comparisons.
