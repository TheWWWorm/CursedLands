# Save loading investigation — 2026-10-26

The initial pass below is followed by a [deeper loading investigation](follow-up.md),
which addresses additional world-building costs and first-load terrain preparation.
The [first-entry follow-up](first-entry.md) then targets shader warm-up draws
and terrain preparation after restarting the application.
The [wisp and post-load validation](../wisp-loading-2026-10-27/README.md)
then covers first-use wisp pipelines and movement after loading.

The report affects recent versions and multiple locations, especially with path
tracing. The reproduced workload enters Foothills (`gz3g`), saves through the
production serializer and repeatedly calls `Session.load_game_shown`. Reloads
use the normal separate authority worker. Loading ends only after the loading
and shader covers close and PT, when selected, has published a complete frame.

## Findings and change

The unfixed release takes roughly 9–11 seconds for repeat loads in the initial
Linux/Vulkan probes. The first load into an empty application cache is much
slower. These are different cases: first-use texture preparation and shader
compilation must not be presented as recurring save deserialization costs.

Unchanged visible terrain pages were baked and uploaded again on each world
replacement. The new content-addressed LRU retains only immutable colour
textures, bounded to 128 MiB and 64 entries. Its key includes the actual atlas
pixels, original tile codes, map dimensions, atlas layout, sampling space,
sector coordinates and output density. New worlds still create their own
materials, live uniforms, geometry and worker state. Changed pixels and tiles
produce different baked output; revisiting unchanged inputs reuses the upload.

The scene controller also discarded immutable PT programs on terrain
replacement, and NRD privately recreated its compute programs for each device.
These programs now share the controller's existing program cache across scene
replacement. Scene buffers, acceleration structures, descriptors, textures and
temporal history remain private. Disabling RT or destroying the controller
disposes the programs after dependent devices. No save format, simulation,
loading-cover behavior, graphics quality setting or player text changes.

This cache lasts within the running process. First use still needs real shader
compilation and asset preparation; this change does not eliminate cold startup
or persist GPU handles across application launches.

## Controlled timings

One GPU Lab heavy job ran both packs serially on the same RTX 3090 Ti with
driver 580.178.04, Linux Vulkan, High graphics, actual 2880×1800 output and a
30 FPS settling cap. PT used balanced quality and NRD, with SHaRC, ReSTIR,
refraction and ray reconstruction disabled. Each process performed an initial
entry and three production save loads. The first save load starts the worker;
the table reports the median of the two subsequent loads.

| Rendering | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Path tracing | 10.755 s | 9.086 s | 15.5% |
| Standard raster | 9.378 s | 7.629 s | 18.7% |

The first worker load also fell from 16.394 to 14.210 seconds with PT and from
14.376 to 12.695 seconds with raster. All three repeated loads went from eight
native terrain page bakes to zero. All four measured processes exited normally.
These small samples establish the saving for this workload, not a universal
loading-time guarantee.

The serial run shared an isolated application profile, so initial-entry times
are order-dependent as driver caches warm; they are deliberately excluded from
the before/after claim. Earlier exploratory cases include fresh-profile startup,
an interrupted driver startup and one baseline shutdown crash after completed
measurements. The final fixture drains PT after recording its screenshot and
timings, using the same cleanup path checked by the reload regression. Excluded
attempts and their logs remain labelled in the local evidence.

## Regression evidence

The new production reload test fails against the unchanged release with six
failures over two reloads: new terrain textures, unnecessary native bakes and
new PT/NRD programs on each load. The same 25 assertions pass with the fix.
Raster reloads, input invalidation and LRU bounds, native colour sampling,
Mobile snow-cache lifecycle, OpenGL reuse, NRD, camera settling, recentering and
resource retirement total **3,485 passing assertions**. The runner's 11 Python
unit tests also pass. Tests use isolated profiles, free cursor, FPS display and
muted audio.

The existing, previously unregistered `terrain_color_forward.gd` was also run
unchanged on both packs. Both fail the same four of 36 assertions comparing
snow mesh identity across terrain-detail changes and subsequent eviction.
`abd4f0ee` introduced deliberate cliff-geometry rebuilds through
`EITerrain.apply_gfx` and `SoftGroundDeform.refresh_geometry`; the old fixture
retains its initial mesh identity across those rebuilds. This is a pre-existing
test/geometry-contract mismatch, not counted as passing. Its assertions were
not weakened, and its temporary runner registration is not part of this change.
Both reports and screenshots remain in the local evidence.

## Original comparison and limits

The retained original decompilation was inspected at `CWorldServer::LoadMap`
(`0x595480`), map-object loading (`0x596030`) and save loading (`0x596e70`).
The original base game was also launched under the registered Wine 11.20
runtime with an exclusively locked disposable prefix. The Load Game menu
successfully restored the Foothills quicksave; menu and loaded-world captures
are retained. That manual run establishes successful original loading, not a
timing comparison. The original renderer has no PT/NRD or this derived terrain
colour cache, so direct parity for their GPU resource ownership is inapplicable.
The existing save/world-loading implementation is unchanged.

The implementation was tested with the qualified Linux release engine on
RTX 3090/3090 Ti hardware. Windows/D3D12 timing and Android device behavior
are not established by these Linux rendered checks. No release or remote update
was performed.

Local raw measurements, exact commands, pack/source hashes, negative controls,
screenshots and cleanup records are under
`local/validation/loading-performance-20261026/` in the EI workspace. The
maintenance index is `local/maintenance/loading-performance-2026-10-26.json`.
