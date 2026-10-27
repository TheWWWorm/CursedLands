# Loading follow-up, 2026-10-26

The first pass removed repeated terrain colour bakes and PT/NRD program
creation. Further profiling found that each repeat load still spent about
1.6 seconds applying terrain graphics, including roughly 0.8 seconds classifying
cliffs and 0.5 seconds preparing their patches. The separate simulation process
also built terrain atlases, meshes and optional effects without a display.

## Changes

- Propagate the world's existing presentation flag into map and terrain loading.
  Simulation worlds still read the original geometry, ground types, water and
  object floors and build the same navigation grids. They omit terrain rendering
  assets and their visual processing.
- Retain prepared cliff/snow data in a two-entry cache with a 64 MiB payload
  budget. Identity includes
  actual geometry, normals, tile metadata, original artwork and all source mesh
  attributes, including underwater colours. Immutable textures may be shared;
  serialized data restores separate field/geometry dictionaries for every world.
  Materials, shaders, snow deformation and the previous world are not retained.
- During explicit loading, prepare independent native terrain-colour pages on
  available CPU cores, bounded to eight jobs and 64 MiB of estimated completed
  image payload. This is not a process-memory quota: allocator and native bake
  scratch storage are additional.
  Large pages reduce concurrency. Handheld and ordinary streaming retain the
  existing two-job limit; ordinary streaming uses background priority.

Graphics settings, sample quality, simulation rules and save formats are unchanged.

## Controlled timings

The final comparison ran both packs serially in one GPU Lab heavy job on the
same RTX 3090 Ti: Linux Vulkan, driver 580.178.04, High graphics, actual
2880×1800 output and a 30 FPS settling cap. PT used balanced quality and NRD,
with SHaRC, ReSTIR, refraction and ray reconstruction disabled. Timings end
after both loading covers close and the requested renderer has completed its
first picture, followed by five stable frames.

| Foothills save load | Unchanged 1.32.0 | Final change | Reduction |
| --- | ---: | ---: | ---: |
| Repeated PT load | 11.036 s | 7.129 s | 35.4% |
| Repeated raster load | 9.446 s | 5.667 s | 40.0% |
| First PT save after application launch | 18.771 s | 17.133 s | 8.7% |

Repeat medians use two loads after the worker has started: PT
11.373/10.699 → 7.179/7.078 seconds; raster 9.831/9.061 → 5.728/5.606.
The first worker load within those runs also improved, from 16.027 to 11.895
seconds with PT and from 14.407 to 10.576 seconds with raster.

The first-save cases load the same saved file directly into an empty game and
start a new authority process. Two fresh application processes per pack ran in
before/after/after/before order: 18.741/18.801 → 17.064/17.201 seconds. They
share the warmed isolated driver/application cache; these are not cold shader
cache measurements. First launch still creates world resources, materials and
PT scene data. The in-process caches cannot remove that work. Initial inline
zone-entry timings are excluded because scene-specific cache warming depends
on order. These small samples describe the measured workload, not a guarantee
for every machine or save.

Additional PT comparisons used the same hardware/settings and sequential
before/after pairs. Each process warms its own scene and starts its worker
before the two measured reloads. Suslanger reverses the pair order.

| Area | Unchanged 1.32.0 | Final change | Reduction |
| --- | ---: | ---: | ---: |
| Ingos (`gz11k`) | 19.166 s | 11.377 s | 40.6% |
| Suslanger (`gz18h`) | 16.536 s | 12.498 s | 24.4% |

Ingos samples were 19.444/18.888 → 11.578/11.175 seconds. Its terrain setup
dropped from 7.177/7.044 to 1.526/1.481 seconds. Suslanger samples were
16.716/16.355 → 12.349/12.646 seconds. All measured processes exited normally.

Two exploratory attempts were interrupted and excluded. An unchanged baseline
stalled before reporting its Vulkan adapter. A modified-pack Suslanger attempt
waited before drawing the loading artwork, with sleeping threads and an idle
GPU. Direct stack attachment was unavailable; a subsequent child launched
under GDB loaded the same area/profile and exited normally. The baseline
control and the subsequent uninstrumented matched pair also completed. The
cause of these intermittent stalls is **unresolved**, and this change does not
claim to fix them. Logs, the stalled capture and diagnostic commands are kept;
debugger timings are excluded from the performance tables.

## Validation

Final measurements and regression totals are recorded with the completed run in
`local/validation/loading-deeper-20261026/`. The same qualified Linux engine is
used for the unchanged 1.32.0 pack and the modified source pack. No native engine
or asset changes are part of this work.

The acceptance set contains **4,052 passing assertions across 25 registered
cases**, plus 11 Python runner tests. It covers actual PT and raster worker
reloads, released-world/resource lifetime, LiA weather reloads, water/cloud
preparation, PT camera settling, shader completion, exact native colour bakes,
OpenGL reuse, Mobile terrain lifecycle, cliff and snow geometry, and simulation
clock handling. The authority comparison checks three original maps, all eight
movement classes, water changes and navigation inputs. New tests fail against
the corresponding unfixed build; the loading-batch negative control uses the
first-pass build, which has the terrain cache but lacks loading concurrency.

The composed-cliff visual control exposed an existing fixture error on both
the unchanged release and the modified build. It cleared the projection mask
but left the separate snow-geometry admission mask enabled, so its supposedly
unclassified control still generated geometry. The fixture now clears/restores
both masks. Its exact-pixel assertion is unchanged; both packs pass all 87
Forward+ and 20 OpenGL assertions with the corrected control. Before/after
reports are retained, and superseded failures are not counted as passes.

The original-game reference is the first pass's retained Foothills save load
under Wine 11.20 and inspection of the original server/map/save loaders. The
new cliff geometry, terrain-colour bakes and PT programs have no original-game
equivalent. Their caching is therefore checked against uncached remake output;
terrain simulation is checked against the existing presentation loader, including
all eight movement classes. This follow-up does not claim a new original-game
timing measurement or native Windows/Android qualification.

The first pass also records an existing four-assertion mesh-identity mismatch in
the older, unregistered terrain colour Forward+ fixture. Its assertions remain
unchanged; the actual cliff/snow geometry and lifecycle checks are retained.

No remote update or release was performed.

The workspace's `local/maintenance/loading-deeper-2026-10-26.json` records final
cleanup. Disposable export projects, generated packs, hardlinked test runtimes,
staged test copies and renderer/texture caches are removed after preserving
reports, source changes, exact build settings, recipes, screenshots and saves.
Existing original-game evidence and shared reference/toolchain assets are retained.
