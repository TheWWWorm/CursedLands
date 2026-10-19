# Post-session allocation and callback isolation

Local investigation on 19 October 2026, continuing the [full-game and traversal
validation](../campaign-controls-presence-20261019/README.md). Production source
is unchanged from `65e4ca6c`; `c2e1cdb0` adds the preceding validation records.
This investigation does not establish the cause of the reported threefold FPS
recovery after restarting.

## Allocation attribution

Two standalone diagnostics rendered a populated late-round Trials battle,
waited for its result, freed its scene, then released cache categories in an
otherwise empty scene. These are isolation experiments, **not full tournaments
or gameplay FPS measurements**. Each used an isolated data directory, Ultra,
Forward+ and 1920×1080 on the same RTX 3090 Linux machine as the earlier runs.

The extended run recorded:

| Stage | Engine-reported allocation | Live scene nodes |
| --- | ---: | ---: |
| Before Trials | 19.39 MiB | 14 |
| After the battle scene was freed | 295.03 MiB | 14 |
| After model, texture, animation, head, wound and audio cache release | 272.18 MiB | 14 |
| After noise and shader-warmup resource release | 269.71 MiB | 14 |
| After releasing the empty scene's large shadow atlases | 141.71 MiB | 14 |

Releasing application asset caches reclaimed 22.85 MiB, while the shadow-atlas
step reclaimed exactly 128 MiB. Ultra selects an 8192² 16-bit directional atlas;
that renderer-global texture can remain when a world leaves and is needed by
the next Ultra world. This explains part of the retained allocation. It does
not explain the entire remaining total or prove that every retained allocation
is necessary.

The local engine source's `RenderingDevice::get_memory_usage(MEMORY_TOTAL)`
returns the Vulkan driver's VMA allocation-byte total, whereas texture and
buffer counters cover narrower categories. That total is not a direct measure
of resident VRAM or exclusively application asset memory. It can include driver
transfer allocations. RSS also includes allocators and the driver; freeing live
objects need not return the same amount to the OS immediately.

Consequently, the earlier 349–351 MiB totals after three full Trials games should
not be labeled entirely as reusable asset caches. The earlier README now makes
that distinction. No broad cache purge or reduction in gameplay graphics quality
was added.

The extended exploratory script's final attempt to replace the root World3D
logged `Parameter "scenario" is null`. Its measurements were unchanged. That
operation occurred **after** the cache and shadow observations above and is
excluded from the reusable diagnostic. The original log and script are retained
as evidence, including the error.

## Callback profile

Private instrumented copies loaded the saved endpoint with 81 dead creatures,
two rendered co-op clients, Ultra and 2× speed. The characters remained stopped
at the saved position for three 30-second intervals. These short stationary runs
isolate work in the state reached by the preceding gameplay traversal; they do
not replace that traversal.

The broad profile measured about 1.85/1.87 ms per frame in `UnitFog._process`
(owner/guest), and 1.77/2.05 ms in `Game.world_tooltip`. Adding a scope around
mechanism picking attributed 1.16/1.15 ms to `pick_lever`. A further scope found
32 mechanism-usability queries per frame and roughly 226–263 mesh-bound queries
across mechanism and unit picking. Scope overhead raises these later timings.

All times are **inclusive**: nested callbacks must not be summed. Instrumented
FPS is not a production performance result. The three profiles show a remaining
picking cost, not a growing allocation or a reproduced 90-to-30 FPS decline.
No approximate hit boxes, stale hover cache or changed interaction rules were
introduced on this evidence.

`summary.json` records weighted callback times, call counts, allocation stages
and binary hashes. Raw interval JSON, logs, the profiling helper and the list of
207 final injected scopes accompany it. The copied exploratory `.gd` files are
execution snapshots with their original paths, rather than standalone launchers.

## Same-save mode-switch comparison

A separate **uninstrumented** run completed three populated late-round Trials
battles, then loaded the same saved endpoint. It used the timer-fixed exported
runtime and normal co-op authority. The owner retained its Trials allocations;
the guest was a fresh process. Both used Ultra and 2×. The comparison below uses
four full intervals ending around 30, 60, 90 and 120 seconds, excluding the
single-frame starting sample and the owner-only final interval.

| Client | Earlier fresh-process mean | After three battles | Extra reported allocation |
| --- | ---: | ---: | ---: |
| Owner | 74.2 FPS | 75.2 FPS | 91.4 MiB |
| Guest | 71.9 FPS | 72.5 FPS | 4.0 MiB |

Player positions and settled camera centres match the earlier restart run
exactly; both retain the same 81 corpses and record no movement or new deaths.
NPC activity continues, so the frames are not identical. This does not show a
meaningful performance loss after the mode switches on this machine. The owner
ends at 150 seconds; the guest's last complete interval ends at 120.86 seconds
before the owner closes it. These battles are not three full tournaments; the
earlier full-tournament and sustained-traversal evidence remains separate.

No production performance claim is based on the synthetic cache releases or
the instrumented callback timings. The larger reported slowdown remains
unreproduced, and a broad cache purge is not justified by these measurements.

## Repeating the allocation diagnostic

Use `tools/benchmarks/render_cache_release.gd` with an exported runtime built
from this source, the original assets and **isolated user data**. It exits after
freeing the temporary scene and checking the empty scene's allocations. It does
not attach to an existing play session. For example on Linux:

```sh
XDG_DATA_HOME=/absolute/path/to/isolated-cache-probe \
  /absolute/path/to/CursedLands.x86_64 --rendering-method forward_plus \
  --render-thread safe -- --ei-path=/absolute/path/to/original-game \
  --tool=/absolute/path/to/repo/tools/benchmarks/render_cache_release.gd
```

The result is `cache-release-probe.json` in that isolated Godot user-data
directory. `--validate-only` checks script loading without starting the battle.
Both the full rendered diagnostic and parse-only mode exited successfully. The
rendered repeat returned to 14 scene nodes and measured 295.0 → 272.1 → 141.7 MiB
at scene teardown, asset release and shadow-atlas release respectively, with no
script or engine errors. Its raw log and JSON are included.
