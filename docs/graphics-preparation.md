# Graphics preparation

The shared preparation screen covers explicit graphics applications and first-use
shader work. It shows the current operation, elapsed time, and completed material
batches when a real denominator is available. Other work uses an indeterminate
indicator. All text is localized in English, Russian and German.

Covered entry points include campaign and arena shader warmup, graphics options
and presets, graphics detection and its restore/watchdog paths, native temporal
anti-aliasing, SDK FSR upscaling/frame generation, scene/path-tracing pipelines,
water reflections, visible terrain/vegetation preparation, and map-viewer loads.
Existing campaign loading, startup artwork and installer progress remain in place.

## Presentation and completion

`ShaderCompilationScreen` draws a plain opaque canvas with the existing fonts.
It presents that canvas before admitting blocking work, temporarily excluding 3D
from the root and independent SubViewports. Raw canvas commands are necessary
because ordinary Control redraws are deferred during synchronous warmup loops.

Independent owners share the screen. A cancelled or completed owner cannot
dismiss another owner's work. Material counts advance after the corresponding
draw, and SDK owners wait for actual evaluations/dispatches after initialization.
RT/PT settings use request/device-specific render acknowledgments, then wait for
their output to be bound and drawn. A prior valid image cannot acknowledge a new
pipeline variant. Final settling observes presented frames, rather than a timer
that pretends compilation has completed.

The screen makes existing synchronous compilation visible; it does not make all
driver or native temporal pipeline creation asynchronous. An individual blocking
call can still interrupt animation. The SDK's existing asynchronous preparation
continues updating the screen while it works.

Explicit graphics revisions distinguish settings work from ordinary camera
movement, topology recovery and streaming. These routine replacements retain the
existing live view without opening a new modal screen. Visible terrain work is
bounded to the keys requested at application time; its workers are pumped while
paused so the screen cannot deadlock their usual pausable processing.

## Input and gameplay

The cover cancels held controller/touch/direct-control actions and prevents camera
polling from moving behind it. In a visible single-player campaign it owns a
temporary simulation pause. That pause is excluded from the saved gameplay clock;
a pre-existing pause is retained, and multiplayer simulation is never paused by
the screen. FSR frame generation may initialize through this owned pause while
its other gameplay/menu/focus restrictions remain in force.

Graphics detection retains its Escape/controller cancellation and displays its
localized cancellation hint. Preparation frames and their pause are excluded
from its measurement batches. Arena combat remains behind the existing warmup
and animation-readiness gate until the screen finishes.

## Validation

Use the frozen-export runner documented in [PT qualification](path-tracing-qualification.md):

```sh
python3 tools/tests/run_path_trace_qualification.py \
  --executable /build/CursedLands.x86_64 --data-root /data/EvilIslands \
  --profile-root /evidence/preparation-profile --output /evidence/preparation \
  --driver vulkan --physical-gpu 1 --engine-gpu-index 1 \
  --display :97 --xauthority /run/pt-display/Xauthority --suite preparation
```

The group includes localized layout/input/ownership contracts, actual campaign
material and temporal work, arena SubViewport warmup, native PT/RT/water requests,
and graphics detection cancellation/sampling. Synthetic negative controls and
failure injection are labelled in their reports. Repeat on the qualified Windows
DX12 package for actual SDK FSR/FG coverage, and use `--suite core` for movement,
topology, recenter/recovery, resource lifetime and sustained PT checks.
