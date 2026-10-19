# Trials board placement regression

Validated on 2026-10-19 with the native Linux/Vulkan export and physics
interpolation enabled. The regression occurs during live multi-round scouting;
checking only `visible` flags or CPU global transforms does not detect it.

## Reproduction and fix

Two real ENet clients played ordinary early rounds while switching between the
nine-board overview and individual boards. Before the fix, both clients sampled
meshes 128m or 143m from their correct global positions. Their visible flags
were true, but screen notifiers consequently classified them as off screen.
Health markers used the correct positions and remained visible.

The field's stage inherited physics interpolation. Descendants presenting on
the native frame clock could retain an ancestor's former overview offset after
the branch was hidden, despite local transform refreshes and interpolation
resets. The field stage now explicitly uses the presentation frame. Units that
need physics interpolation can still opt in independently.

Repeating the live two-client probe with that change produced no displaced
meshes in the sampled rounds. The paired JSON files record mesh positions,
interpolated positions, visibility, layers and processing state; the PNGs show
the focused board before and after the change.

## Regression test

`tools/tests/arena_board_presentation.gd`: **477 checks, no failures** in the
native exported runtime. It covers stopped units, 20 rapid overview/scout
returns, five round generations received while hidden, 16 live combat scouting
cycles, camera clipping and eliminated-player hover access.

The added position checks failed against the preceding export, including
90.51m offsets after hidden round changes. They compare rendered transforms,
not merely node visibility. A 2m tolerance allows a moving limb's CPU/render
sampling difference; the erroneous overview displacement is at least 64m.
The separate clipping check deliberately shortens the far plane, then verifies
that returning from overview restores the fitted plane and visible pixels.

The long retention run started before this fix. Its Trials FPS samples can
include missing geometry and are therefore unsuitable as proof of full battle
rendering performance. Its process lifetime and post-match release counters
remain useful retention evidence.
