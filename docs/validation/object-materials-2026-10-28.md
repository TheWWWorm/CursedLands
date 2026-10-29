# Object material families for the base game and Lost in Astral — 28 October 2026

Local change on `main` after 1.35.0 (`c166495c`), tested on the Windows
workstation (RTX 4090 Laptop, Direct3D 12, released 1.34.0 engine with a pack
exported from this source by stock Godot 4.7.2). Nothing was pushed or
published.

## What was wrong

Placed map objects received their highlight/roughness/metalness/relief from
`SurfaceMaterials.object_profile`, a list of twenty texture names. Everything
else, including every Lost in Astral atlas, was the dull dielectric default in
both the raster material and the path-traced scene. The per-part material
records that the original artists authored in each figure (`materials.res`:
leather, wood, metal, cloth, skin, stone, magic) only supplied the legacy
diffuse and emissive colours.

A read-only inventory of every `maps/*.mob` placement joined with the figure
records of each placed template:

| Edition | Maps | Object placements | Distinct atlases | Non-tree placements with a listed family |
| --- | ---: | ---: | ---: | ---: |
| Base game | 99 | 44,196 | 168 | 2,380 of 10,286 (23%) before, 9,234 (90%) after |
| Lost in Astral | 130 | 82,175 | 232 | 3,541 of 24,546 (14%) before, 21,757 (89%) after |

Trees are 77% of base and 70% of Lost in Astral placements. The base trees
(`tree02`, `tree03`, `tree04`) have authored leaf/bark masks; the expansion's
autumn trees (`tree01`, `tree05`, `tree06`, 15,331 placements) had none, so
their leaves admitted no light and their bark had no relief.

## Change

- `SurfaceMaterials.OBJECT_FAMILIES` lists 139 atlases of both editions by
  family: masonry, plaster/mixed houses, timber, iron, gold, clay, bone and
  cloth. The verified rock and plank atlases keep their established profiles.
  Each atlas was reviewed on a contact sheet exported from the installed
  archives before classification; Lost in Astral's Jigran, Haburu and
  teleport artwork is covered by name because its figure records are not
  reliable (several walls are tagged skin or an unknown id).
- `object_profile(texture, material_id)` now also receives the part's figure
  material record. A part marked metal (ids 19 and 25) always renders as
  metal, even inside a listed timber atlas (torch holders, fallen warriors'
  armour). Unlisted atlases fall back to the record: stone and wood roughness
  without relief, leather, cloth; skin, magic and unknown ids keep the dull
  default. `EIFigure.world_material_for` already keys its material cache by
  `(texture, material_id)`, so this costs no extra materials.
- Foliage masks for the autumn trees: the three atlases are recolours of
  `tree02` with identical cutouts (alpha IoU 1.000 against the base atlas,
  0.313 against `tree04`). Hue cannot separate orange leaves from brown
  twigs, so the mask reads the leaf pigment from the green original at the
  same texel when its coverage is identical, and otherwise uses a warm
  brightness/chroma rule. The cache fingerprint covers both images.
- Path-traced scalar profiles follow the raster material: foliage traces with
  its bark roughness (0.86 instead of 1.0) and Surface materials off restores
  rough dielectrics in the traced scene as it does in raster.

Relief strengths for the new families are lower than the verified rock
atlases (0.45 masonry, 0.30 plaster and timber) because mixed atlases carry
painted shading. The chest's authored metal mask and the three authored
surface-detail maps are unchanged and keep precedence.

## Regression evidence

`tools/tests/figure_material_surface.gd` is registered twice in
`tools/regressions.json` (`figure_material_surface` for the base game,
`figure_material_surface_astral` for the expansion). It checks the table
against the installed archive, the record fallback and precedence rules,
placed original figures (`stwa10`/`hadoganwall00`, `stto2`/`torch00`,
`stbuho53`/`runnerstent00`, `goldpile00`, `nafltr21`/`tree01`), the values the
PT collector packs for the same meshes, the Surface materials gate, foliage
roughness, and the autumn masks' agreement with the `tree02` mask.

| Case | Changed source | Unchanged source (negative control) |
| --- | --- | --- |
| `figure_material_surface` | 42 checks, 0 failures | parse failure (new API); old-API control: 5 of 5 checks fail |
| `figure_material_surface_astral` | 60 checks, 0 failures | parse failure (new API); old-API control: 6 of 6 checks fail |

Related regressions on the changed pack, same machine:

| Case | Result |
| --- | --- |
| `chest_surface_material` (headless) | 15 checks, 0 failures |
| `chest_surface_live` (D3D12) | 9 checks, 0 failures |
| `path_trace_material_receivers` (D3D12) | 7 checks, 0 failures |
| `path_trace_surface_maps` (D3D12) | 16 checks, 0 failures |
| `terrain_sun_shadows` (D3D12) | 14 checks, 0 failures |
| `path_trace_terrain_sun_continuity` (D3D12) | 31 checks, 0 failures |
| `path_trace_terrain_sun_radius` (D3D12), with the four new drift/turn checks | 40 checks, 0 failures |

The terrain-sun cases cover the separate cache tolerance described in
[the performance plan](../integrations/path-tracing-performance-plan-2026-10-28.md).

The registered fixture cannot parse against the unchanged source because it
names the new table and the two-argument profile call, so the negative
control additionally ran an unregistered copy that uses only the previous
API (`negative_material_surface.gd`, retained with the logs). Against a pack
exported from the unchanged scripts it reports the Hadagan wall as dull
`(0.04, 0.96, 0, 0)`, the brazier as dielectric, no PT roughness for the wall,
profiles reaching PT with Surface materials off, foliage traced at roughness
1.0 and no mask for `tree01`. The changed pack passes the same checks.

Every run used an isolated profile with free cursor, FPS visible and all
audio volumes zero. Rendered cases ran through the local Windows stand-in for
the GPU Lab runner (same verdict rules); the official runner executed the
headless cases with `--packaged`. Logs are retained under
`C:\web\local\validation\object-materials-2026-10-28\`.

## Path-tracing performance changes

The same session rebuilt the path-tracing shaders with the official DXC
v1.9.2609 Windows release after confirming it reproduces every committed
binary byte for byte (44 path-tracing, 16 RTXDI and 13 SHaRC programs; the
manifests now record that compiler). Four shader changes and one controller
change are described in
[the performance plan](../integrations/path-tracing-performance-plan-2026-10-28.md):
one importance-sampled local shadow ray per continuation vertex, no relief or
detail normals on continuation hits, a 0.15 rad texture cone for diffuse
bounces, footprint-based alpha tests on continuation rays, and a 0.1 degree
tolerance before the terrain sunlight cache retraces.

`path_trace_light_performance.gd` (original river, probe lights, two bounces,
Low, 1280×720, NRD, 90-frame blocks, two rounds), PT GPU medians on the RTX
4090 Laptop through Direct3D 12:

| Lights | Unchanged | One bounce shadow ray only | All changes |
| --- | ---: | ---: | ---: |
| 7 | 2.479 / 2.472 ms | 1.890 / 1.895 ms | 1.775 / 1.780 ms (−28%) |
| 16 | 2.743 / 2.746 ms | 1.999 / 2.000 ms | 1.892 / 1.886 ms (−31%) |
| 64, static | 3.315 / 3.351 ms | 2.404 / 2.444 ms | 2.376 / 2.424 ms (−28%) |
| 64, one moving | 3.369 / 3.370 ms | 2.454 / 2.462 ms | 2.393 / 2.392 ms (−29%) |

With the later terrain colour shortcut and triplanar floor (same fixture,
one round, all 24 regression fixtures above green again): 7 lights
1.517 / 1.505 ms, 16 lights 1.599 / 1.595 ms, 64 static 2.123 / 1.895 ms,
64 moving 2.059 / 2.062 ms, a 39–42% reduction from the unchanged shaders.

With the visible-surface loop capped at four exact lights (same fixture,
one round, light history, direct stability, emitters, bounce lights, RTXDI,
contacts, NRD, SHaRC, controller and CPU-cache regressions and the many
lights, optimization and sampling fixtures green): 7 lights 1.476 / 1.476 ms,
16 lights 1.587 / 1.585 ms, 64 static 2.053 / 2.013 ms, 64 moving
2.032 / 2.020 ms.

Carrying the bounce footprint on shadow and emitter rays that leave a
continuation vertex changed neither benchmark measurably (7 lights
1.495 / 1.510 ms; Foothills ray stage 1.06–1.34 ms over two runs) while the
same twelve registered cases and four estimator fixtures passed; it is kept
for the alias-noise reduction in bounce shadows through canopies, not as a
performance gain.

A contribution-bounded roulette on the local-light and emitter rays leaving
continuation vertices passed the same fixtures (bounce lights, emitters,
light history, contacts, RTXDI, SHaRC, NRD, direct stability, healing glow,
many lights, sampling, optimization, emitters, variance) but measured
1.577 / 1.566 ms at 7 lights, slower than without it; it was reverted and is
recorded in the plan.

`path_trace_location_walk.gd --pt-location-benchmark` (Foothills, first
person, 4K output, 1080p internal, NRD, Ultra; two processes per pack, six
180-frame blocks each): ray-stage medians 1.27–1.53 ms unchanged against
1.15–1.44 ms with the first four changes and 1.08–1.29 ms with the terrain
colour shortcut added (two runs each), frame medians 9.4–10.6 ms against
8.2–8.7 ms and 8.3–9.4 ms.
The instrumented controller shows where its main-thread time goes per
frame: native transform tracker 0.70 ms, render submission 0.54 ms, frame
constants 0.20 ms, first-person presentation 0.16 ms, morph scan 0.12 ms.
This scene has few local lights, so the ray saving is the bounce material
and footprint work; the frame is main-thread bound, and the controller CPU
medians (1.75–1.83 ms against 1.95–2.14 ms) moved with the run order, so the
frame difference is reported, not claimed as a GPU result.

DLSS Ray Reconstruction, the configuration of the original report
(`--pt-qhd --pt-dlss`, 2560×1440 output, DLSS Performance input, RR traces
the full input lattice; `rtx_upscaling=4` selected at launch so the SDK is
active; two processes per pack in base/final/base/final order, six 180-frame
blocks each). Ray-stage medians, forward views then ground views:

| Pack | Forward views | Ground views |
| --- | ---: | ---: |
| Unchanged | 2.60–3.18 ms | 2.25–2.70 ms |
| Final | 2.11–2.64 ms | 2.07–2.48 ms |

Frame medians are 8.8–10.4 ms in both: with RR the GPU frame (8–9 ms) is
dominated by raster, RR and the DLSS pipeline, and PT is roughly a quarter of
it, so the 8–19% PT saving changes frame time little in this configuration.

Regressions on the pack with all changes, same machine, Direct3D 12 (the
pack with only the light-sampling change passed the same registered set):

| Case | Result |
| --- | --- |
| `path_trace_bounce_lights` (new, registered) | 16 checks, 0 failures; bounce energy of 2, 7 and 16 lights within 0.4% of the single-light sums |
| `path_trace_terrain` | 120 checks, 0 failures |
| `path_trace_terrain_terminator` | 93, 0 |
| `path_trace_terrain_horizon` | 25, 0 |
| `path_trace_grazing_normals` | 44, 0 |
| `path_trace_contacts` | 59, 0 |
| `path_trace_surface_maps` | 16, 0 |
| `path_trace_material_receivers` | 7, 0 |
| `path_trace_cover_receivers` | 65, 0 |
| `path_trace_nrd_device` | 26, 0 |
| `path_trace_emitter_live` | 14, 0 |
| `path_trace_sharc` | 25, 0 |
| `path_trace_rtxdi` | 27, 0 |
| `path_trace_transmission` | 33, 0 |
| `path_trace_water` | 22, 0 |
| `path_trace_light_history` | 52, 0 |
| `path_trace_motion` | 66, 0 |
| `path_trace_shadow_motion` | 12, 0 |
| `path_trace_figure_live` | 8, 0 |
| `path_trace_healing_glow` | 8, 0 |
| `path_trace_direct_stability` | 14, 0 |
| `path_trace_alpha` (unregistered) | 9, 0 |
| `path_trace_many_lights` (unregistered) | 20, 0 |
| `path_trace_sampling` (unregistered, raw paths against analytic integrals) | 67, 0 |
| `path_trace_variance` (unregistered) | 38, 0 |
| `path_trace_optimization` (unregistered, raw estimator against saved package) | 37, 0 |
| `path_trace_material_minification` (unregistered) | 9, 0 |
| `path_trace_glossy` (unregistered) | 31, 0 |

Vulkan was not exercised: this workstation has no Linux display, so the
SPIR-V side of the rebuilt programs is verified only by the builders'
reproduction check and by the manifests, not by a native Vulkan run.

## Moving local lights keep their history

`scene_raytrace.gd` now classifies a local light that moves up to a tenth of
its range per frame, with an unchanged range, like flame flutter: the frame
keeps its history with the three-frame local limit, and the NRD pack's
existing per-receiver confidence shortens history only where current local
lights reach. Jumps beyond that fraction, range, size or hue changes, new or
extinguished sources and list changes still reset the frame.

`path_trace_light_history` carries the new contract (58 checks: drift keeps
the short history, motion up to a tenth of the range keeps it, a larger jump
or a range change resets, the multi-light and daylight variants likewise);
`path_trace_many_lights` adds the jump case beyond slot seven (21 checks).
The many-light benchmark's moving case, which previously recorded 90 full
resets in 90 frames, now records none at the same PT GPU time
(2.099 / 2.092 ms); its frame median fell from 7.7–8.0 ms to 6.6–6.7 ms
because the denoiser no longer restarts every frame. NRD motion (42), direct
stability (14), emitters (14), controller (49) and SHaRC live (18) pass.
`path_trace_nrd_live` and `path_trace_rtxdi_live` could not complete on the
1.34.0 engine (a cold-start temporal-shader stall fixed in 1.35.0, and an
inactive DLSS SDK); they were rerun on the published 1.35.0 Windows package
(`CursedLands-1.35.0-windows-x86_64.zip`, checksum verified against the
release's SHA256SUMS) with this pack beside it: `path_trace_nrd_live` 12
checks, `path_trace_rtxdi_live` 44 (with `rtx_upscaling=4` selected at
launch), and the unregistered `path_trace_torch_history_live` (10) and
`path_trace_spell_lights_live` (8), all without failures.

## Full registered path-tracing set on the 1.35.0 engine

All 77 registered rendered `path_trace_*` cases ran on the published 1.35.0
Windows engine with the final pack (the ten DLSS-dependent cases with
`rtx_upscaling=4` selected at launch). 68 pass. The nine remaining verdicts:

| Case | Result | Cause |
| --- | --- | --- |
| `path_trace_water_options`, `path_trace_rr_options` | all 28 / 50 checks pass; 19 engine errors each | `Index p_screen = 0 is out of bounds (screen_count = 0)`: the desktop had no active screen during these runs |
| `path_trace_rtxdi_options`, `path_trace_transmission_options` | 59 / 56 checks, 3 UI-extent failures each | the only screen is 1463×914, so the 1440p/4K option-panel extents cannot be presented |
| `path_trace_transmission_live` | 21 of 25 registered checks, none failing | resolution-dependent checks skipped on that screen |
| `path_trace_travel_rr`, `path_trace_travel_rr_night` | native output size (2560, 1514) instead of the recorded size | window geometry on that screen |
| `path_trace_rr_unavailable` | needs the two RR DLLs omitted from the engine folder | not staged here |
| `path_trace_travel_night` | replacement catches the camera at frame 72 (limit 60); night RR variant 64 | see the control below |

The four RR traversal routes (river, snow, desert, cave) pass with 49 checks
each on this screen, as do RR live (38), RR details (67), RR presentation (40),
RTXDI (27), RTXDI sparse (37) and RTXDI live (44).

Travel-night control: the unchanged pack on the same engine and screen also
fails the same three checks, with the replacement catching the camera at
frame 69 (changed pack: 72 and, in the RR variant, 64; limit 60). The
catch-up frame count is this workstation's replacement-build timing, not a
change in the renderer; the earlier Linux/Proton record measured 49–54 on
that hardware.

RTXDI candidate change (constant emission as the resampling target): RTXDI
(27), RTXDI sparse (37), RTXDI live (44), emitter deep SHaRC RTXDI (15),
emitter SHaRC (14), emitter live (14) and bounce lights (17) pass on the
1.35.0 engine. The Foothills benchmark does not exercise ReSTIR, so its ray
stage is unchanged (1.08–1.33 ms); no separate ReSTIR timing fixture exists,
so this change is qualified for correctness only.

## Ray Reconstruction traces into the published images

Under RR the ray programs now write the four published images directly and
the per-frame copies are gone (`_ray_targets`). On the 1.35.0 engine: RR raw
(15, now asserting the direct contract), RR resources (19), RR staging (20),
RR guides (95), history handoff (13), SHaRC (25) and SHaRC live (18), NRD
device (26), controller (49), retirement (29), lifecycle (168), resource and
upload staging (50, 14), coverage handoff (6), travel coverage (9), loading
recenter (14), recenter programs (12), NRD live (12) and the river and cave RR
traversal routes (49 each) pass. RR live, RR details, RR presentation and
RTXDI live read the raw slots in their byte comparisons and were updated to
read the ray targets; their reruns are recorded below.

DLSS RR benchmark (`--pt-qhd --pt-dlss`, DLSS Performance input 1280×720,
two processes per pack in base/final/base/final order): main GPU medians
8.43–9.28 ms unchanged against 8.06–8.47 ms final, ray stage 2.55–3.23 ms
against 2.03–2.49 ms. The main-GPU saving equals the ray-stage saving within
noise, so at this input size the removed copies themselves are below the
benchmark's resolution; the change is kept because its cost scales with the
DLSS input area (four 16-bit RGBA images per frame, 118 MB at a 2560×1440
input) and it removes work rather than adding any.

Reruns with the updated fixtures on the 1.35.0 engine: RR live 38, RR
details 67, RR presentation 40 and RTXDI live 44 checks, no failures.

## NRD dispatch plan cache

The NRD render loop now reuses a per-slot plan (pipeline, pass resources,
descriptor sets) while its integer key repeats, updating only the constants
buffer. NRD device (26), NRD motion (42), NRD directional (21), light history
(58), controller (49), history handoff (13) and RR raw (15) pass. Foothills
4K render-submission medians moved from 0.54–0.58 ms to 0.42–0.62 ms
(median about 0.48 ms) over two runs: at most a few hundredths of a
millisecond, within run-to-run noise. It is kept because it removes
per-frame allocations without changing any dispatch.

## Side-effect regressions

The device and material changes also touch the water ray tracer, the shared
ray-scene collector and the raster material shaders. On the committed pack:
water RT rebuild (16) and live (15), ray-trace topology budget (13), dense
scene (8), source cache (12), retained sources (19) and textures (41), gather
budget (15) and retirement budget (9), chest surface live (9) and material
(15), terrain surface maps (79) and live at 720p/1440p/4K (39 each), foliage
feature combinations (67) and all-effects scene (10), and the two
figure-material cases (42, 60) pass. `terrain_surface_help` passes its 37
checks but logs the same no-screen errors as the option-panel cases above.

## Qualification fixtures and the detached-geometry case

Rendered qualification cases on the committed pack (1.34.0 engine, Windows
D3D12): character live (8), camera routes (5), cave (12), daylight live (12),
cloud weather (32) and authored ambient (7) pass; camera modes exits 0 without
a parsed summary line. `path_trace_character_lighting` stops with the
"Required object rp_child is null" window error and `path_trace_equipment_live`
needs the `--pt-hit-reference` capture, both environmental on this
workstation.

`path_trace_detached_live` failed its "hidden detached geometry disappears
from native primary rays" check twice on the unchanged pack and twice on the
committed pack, so the failure predates this work. The fixture counted
placement identities in the custom filter's identity auxiliary
(`_filter_auxiliary[3]`), which the production path only refreshes when NRD
is unavailable; under NRD it reported the geometry from the last filtered
frame. The ray programs write the placement identity into the alpha half of
the raw diffuse image every frame (`indirect_image[pixel].a = 0x3c00 +
instance_id`), so the fixture now reads `ray_targets()[0]` instead. With that
source it passes its 15 checks on both packs (`det2-base`, `det2-mine`), and
the before-hide and after-reveal counts remain above twenty pixels, so the
hidden-geometry check is exercised rather than vacuous. No renderer behaviour
changed.

## Refraction pass

Measured with the new `path_trace_transmission_performance.gd` (original
river, PT Low, two bounces, 1280×720, `--ei-pt-tuning`; refraction off, on
with a still view, and on while the camera turns 0.0004 rad per frame; 90
frames per block, cases in ABBA order; 1.34.0 engine, Direct3D 12). Ray-stage
medians, four runs of the previous pack (`trans-bench-old1/2/3/5`) and four of
the final pack (`trans-bench-new3/4` with the one-path reuse, `new5/6` with
the lighting signature as well), two blocks per case and run:

| Case | Previous shaders | Refraction changes |
| --- | ---: | ---: |
| Refraction off | 0.597–0.791 ms | 0.600–0.820 ms |
| Still view | 1.057–1.143 ms | 0.753–0.887 ms |
| Turning view | 1.081–1.127 ms | 1.078–1.118 ms |

The first new pack (`trans-bench-new1/new2`, dielectric-only camera ray and
pixel skip only) measured 1.063–1.092 ms still and 1.109–1.147 ms turning:
the mask change alone did not register on the river, where most pixels are
water. The one-path reuse carries the still-view saving. The turning view
resets its history every frame (the fixture confirms the reset count) and
traces two paths as before.

Regressions on the final pack: `path_trace_transmission` 33 checks,
`path_trace_transmission_occlusion` (new) 21 checks, 0 failures (on the
previous pack it fails the 63-frame limit, the lighting-change and the
history-flag checks, as intended), and
`path_trace_transmission_live` runs 21 of its 25 registered checks with no
failures on the changed and unchanged packs alike (the Ray Reconstruction
checks need the RR runtime, which this workstation lacks).

The lighting-signature finding: before the change, the transmission pass
compared the entire frame block minus the previous-frame matrices and the
frame counter, so the advancing campaign sun (every frame in daylight), a
fluttering torch colour or a moving cloud phase reset its history every
frame; the still-frame accumulation only engaged in frozen scenes such as
this benchmark. This is inferred from the signature code, the frame layout
and the controller's own notes that the campaign clock advances sunlight and
sky every frame and that fire flutter changes every frame; the benchmark
freezes the simulation and `path_trace_transmission_live` disables the
daylight update (2 resets in 15 frames on both packs), so the live reset rate
under an advancing clock was not reproduced here.

## Where the river's ray time goes (Low, 1280×720)

`path_trace_performance.gd` on the committed pack, `--pt-case=path-2-low`,
two runs per configuration, ray-stage medians (`terrain-*`, `attr-*`,
`cases-*`, `stages-*` runs):

| Configuration | Rays |
| --- | ---: |
| No detail features | 0.41–0.50 ms |
| Surface materials only | 0.39–0.42 ms |
| Leaf lighting only | 0.38–0.44 ms |
| Terrain relief and transitions only | 0.47–0.50 ms |
| Terrain with cliff projection | 0.58–0.65 ms |
| All detail features | 0.59–0.66 ms |

Object surface materials and leaf lighting cost nothing measurable on this
view; terrain relief and transitions add about 0.05 ms and the cliff
projection about 0.1 ms, so the cliff walls of the river banks are the one
detail feature with a visible share (roughly a sixth of the ray stage).

With every detail feature on, the Quality bounce count (`path-4-low`, which
also enables refraction) measures 1.01–1.07 ms against 0.62–0.80 ms for two
bounces; about half of that difference is the refraction pass on the still
water (see above), the rest the compensated deep tail. Within one process the
later cases run slower than the earlier ones by up to 25% (path-2-low
0.62 ms in the first round, 0.77–0.85 ms after the four-bounce cases), which
is consistent with the laptop GPU warming; every comparison in this record
therefore interleaves its packs within a run or alternates run order.

A new `PT direct filter` timestamp splits the reconstruction stage: the
direct-light filter (its dispatch plus the four history copies) takes
0.091–0.097 ms and NRD 0.185–0.196 ms of the 0.28 ms stage, with the final
composite in the 0.012 ms "copies" slot.

## Controller frame constants

The controller rebuilt the 64-entry local-light tables every frame with four
array allocations per slot and compared every slot's history record even when
no light had changed. It now writes only the present lights into zero-filled
tables and skips the per-light comparison when a table is unchanged; the
uploaded frame bytes are identical. `path_trace_light_history` (58),
`path_trace_bounce_lights` (17) and `spell_lighting_gallery_pt` (85) pass on
the changed pack. The benchmarks now sample the controller's phase timings per
frame under `--ei-profile-rt`; `cpu_frame_ms` medians, two runs per pack in
ABBA order (`cpu-river-*`, `cpu-lights-*`):

| Scene | Previous | Changed |
| --- | ---: | ---: |
| River, 1 light | 0.123–0.130 ms | 0.081–0.091 ms |
| River, 7 probe lights | 0.119–0.137 ms | 0.082–0.107 ms |
| 16 lights | 0.139–0.147 ms | 0.108–0.124 ms |
| 64 lights, still | 0.189–0.192 ms | 0.164–0.189 ms |
| 64 lights, one moving | 0.220–0.235 ms | 0.172–0.204 ms |

The scene-update (0.39–0.52 ms) and render-submission (0.41–0.51 ms) phases
are unchanged and remain the larger controller costs; the GPU ray stage is
identical within noise, as expected for identical frames.

## Controller render submission

The render-submission phase (0.45–0.49 ms per frame on the river) is timed
per step under `--ei-profile-rt` (`render_detail` in the statistics; the
benchmarks report medians). On the river at Low: scene update 0.02 ms,
targets 0.008, frame upload 0.004, ray dispatch 0.017 (terrain sun 0.007),
direct filter 0.011, composite 0.003, publish 0.006, and the NRD step
0.35–0.37 ms, of which the native dispatch description took 0.09–0.11 ms,
planning the nine dispatches 0.22 ms and recording them 0.024 ms.

The planning cost came from the cache: the plan was stored per pass slot and
keyed by the pass's resource list, but REBLUR alternates its history pools
between frames, so every slot missed every frame and rebuilt its uniforms,
descriptor keys and constants descriptor. Plans are now keyed by pipeline
and resource list content, confirmed by comparing the native list, and own
their constants buffer; the recorded GPU work is unchanged. ABBA on the
river (`nrdplan-river-*`, two blocks per run):

| Phase | Previous | Keyed plans |
| --- | ---: | ---: |
| NRD planning | 0.217–0.227 ms | 0.072–0.075 ms |
| NRD step | 0.362–0.374 ms | 0.222–0.235 ms |
| Render submission | 0.475–0.492 ms | 0.333–0.351 ms |
| Controller total | 1.201–1.278 ms | 1.121–1.187 ms |

`path_trace_nrd_device` (26), `path_trace_nrd_motion` (42),
`path_trace_nrd_directional` (21) and `path_trace_light_history` (58) pass on
the changed pack; the ray stage is unchanged within noise.

## ReSTIR direct lighting cost

`path_trace_light_performance.gd` with `--ei-pt-tuning` forces RTXDI on
(`pt_restir=1` in the launch settings), so the many-light river benchmark
can compare the ReSTIR estimator with the plain one at every light count.
RT GPU medians at 1280×720, Low, two bounces (first round / second round):

| Configuration | 7 lights | 16 lights | 64 lights | 64, one moving |
| --- | ---: | ---: | ---: | ---: |
| Plain estimator (RTXDI off) | 1.49 / 1.51 ms | 1.61 / 1.63 | 2.06 / 2.15 | 2.11 / 2.17 |
| RTXDI, 16 candidates, 5 neighbours (previous) | 3.81–4.42 / 3.60–3.95 | 3.88–4.48 / 3.94–4.02 | 4.23–4.80 / 4.26–4.37 | 4.48–4.85 / 4.50–4.83 |
| RTXDI, 4 candidates | 3.80 / 3.50 | 3.84 / 3.55 | 4.09 / 3.91 | 4.12 / 4.14 |
| RTXDI, 1 candidate | 3.51 / 3.18 | 3.56 / 3.24 | 3.83 / 3.68 | 3.89 / 3.90 |
| RTXDI, 16 candidates, no reuse | 2.55 / 2.27 | 2.57 / 2.33 | 2.71 / 2.66 | 2.83 / 2.83 |
| RTXDI, 1 candidate, no reuse | 1.94 / 1.80 | 1.96 / 1.83 | 2.10 / 2.03 | 2.22 / 2.15 |
| RTXDI, 1 neighbour | 3.25 / 2.93 | 3.29 / 2.98 | 3.55 / 3.39 | 3.63 / 3.64 |
| RTXDI, 5 neighbours, no permutation | 4.28 / 3.57 | 4.34 / 4.44 | 4.65 / 4.71 | 4.69 / 4.68 |
| RTXDI, 5 neighbours, bias correction off | 3.94 / 3.14 | 3.95 / 3.16 | 4.26 / 3.59 | 4.32 / 4.32 |
| RTXDI, 2 neighbours, 2 boost, no permutation | 3.64 / 3.30 | 3.70 / 3.59 | 4.00 / 4.04 | 4.08 / 4.06 |
| RTXDI, uniform light index (timing experiment) | 3.88 / 3.36 | 3.93 / 3.42 | 4.15 / 3.77 | 4.21 / 4.23 |
| RTXDI, storage-buffer tables, 5 neighbours | 4.37 / 4.05, 4.30 / 4.10 | 4.42 / 4.13, 4.33 / 4.22 | 4.70 / 4.56, 4.68 / 4.69 | 4.73 / 4.73, 4.72 / 4.72 |
| RTXDI, storage-buffer tables, 2 neighbours (final) | 3.56 / 3.61, 3.66 / 3.46 | 3.61 / 3.61, 3.70 / 3.69 | 3.83 / 3.89, 4.05 / 4.06 | 3.92 / 3.93, 4.09 / 4.09 |

Runs: `restir-lights`, `plain-lights`, `cand-*`, `noreuse-*`, `tune-*`,
`uni-*`, `di-lights-*`. Later cases within a process run up to 20% slower
than the first (the laptop GPU warms), so the ABBA pairs `di-lights-old-5`,
`old-5b`, `new-5`, `new-5b`, `new-default`, `new-defaultb` are the
comparison for the final change.

Reading: with the previous configuration ReSTIR cost 2.3–2.8 ms more than
the plain estimator on this 640×360 lattice. Removing the spatiotemporal
reuse removes 1.3–1.6 ms of that, the sixteen candidates about 0.5 ms, and
the fused pass itself about 0.3–0.4 ms. Within the reuse, the cost scales
with the spatial neighbour count (five neighbours cost 1.0 ms more than
one), bias correction accounts for 0.4–0.7 ms of the five-neighbour cost and
permutation sampling for none. Reading the light records with a uniform
index (a timing-only experiment that always evaluates light 0) saved
0.3–0.6 ms, which suggested that divergent constant-buffer indexing was part
of the reuse cost; moving the light records to storage-buffer copies of the
frame block did not reproduce that saving (storage tables with five
neighbours measured within noise of the constant-buffer version), so the
experiment's gain came from the single light's cheaper evaluation rather
than from the addressing. The storage-buffer tables are kept because the
reads are at least as fast and the addressing no longer depends on a
constant-bank pattern, and the default spatial neighbour count drops from
five to two (eight after a disocclusion), which brings ReSTIR at seven lights
from 3.8–4.4 ms to 3.5–3.7 ms. ReSTIR still costs about twice the plain
estimator at these light counts; the remaining cost is the fused pass with
its temporal reservoir, two neighbours and bias correction, and the
candidate loop.

`path_trace_rtxdi_sparse` fails five checks on both the previous and the
changed pack on this engine: the fixture reads the raw diffuse image, which
under Ray Reconstruction is no longer written since the ray programs trace
straight into the published images (`ray_targets()`), so its energy checks
see stale data. The fixture is updated to read the ray targets, like the RR
fixtures were. `path_trace_rtxdi_live` stops at "native SDK reports real RR
capability" on both packs, which needs the Ray Reconstruction runtime this
engine folder lacks.

## Refracted vertex light sampling

The first opaque surface of a refracted camera path evaluated every local
light in range exactly (up to four shadow rays, four stratified draws above
that) although it is reached through an interface like a reflected bounce.
It now uses the bounce estimator: one local light drawn in proportion to its
reach, plus the sun, with the same expected energy. Only the two transmission
ray programs change; the other 42 binaries are byte-identical. Many-light
river benchmark with `pt_refraction=1` under `--ei-pt-tuning` (RT GPU
medians, ABBA `refr-lights-*`):

| Lights | Previous | Refracted vertex draws one light |
| --- | ---: | ---: |
| 7 | 1.83–1.86 ms | 1.74–1.76 ms |
| 16 | 2.00–2.03 ms | 1.88–1.89 ms |
| 64, still | 2.56–2.65 ms | 2.38–2.46 ms |
| 64, one moving | 2.74–2.83 ms | 2.50–2.57 ms |

The still view already traces one refracted path per pixel, so the saving
is per path; a moving view with two paths saves twice as much per pixel.
`path_trace_transmission` (33) and `path_trace_transmission_occlusion` (21)
pass; the Beer, Snell and energy checks are unchanged because the estimator
is unbiased.

## Registered set on the day's head

All 77 registered rendered path-tracing cases except `path_trace_nrd_live`
(which the 1.34.0 engine stalls on at cold start) ran on the 1.34.0 engine
mirror with the pack built from the head after the refracted-vertex change
(`full2-*`): 61 pass. The 16 failures are the classes recorded earlier on
this workstation: the three option-panel cases report a 1280×720 UI extent
on this screen (`rtxdi_options`, `transmission_options`, with `water_options`
and `rr_options` passing their checks but logging the no-screen errors);
`travel_night` catches the camera at frame 69 against a limit of 60 as it
did on the unchanged pack; and the Ray Reconstruction runtime is not part of
the 1.34.0 engine folder, so `rr_live`, `rr_details`, `rr_unavailable`,
`rtxdi_live`, `travel_rr`, `travel_rr_night`, the four `rr_traversal_*`
routes and the four RR checks of `transmission_live` stop at the capability
check. Those RR cases are rerun on the verified 1.35.0 package below.

## Cliff projection memo

The cliff edge blend evaluates the hit cell and up to three neighbouring
cells with the same world projection; on uniform rock they carry the same
tile code and the projected colour was sampled again for each. The closest
hit now keeps up to four projected colours per hit, keyed by tile code, so a
repeated code costs no new atlas taps; the result is identical by
construction. River, Low, terrain and cliffs on, `--pt-case=path-2-low`,
ABBA (`cliff-river-*`): ray stage 0.590 / 0.664 / 0.616 / 0.617 ms before,
0.631 / 0.583 / 0.547 / 0.536 ms after, two blocks per run. The ranges
overlap and the mean moves from 0.62 to 0.57 ms, so the saving is at most a
few hundredths of a millisecond on this view; it is kept for the cliff-heavy
views where the edge blend covers more pixels. `path_trace_terrain` (120),
`path_trace_terrain_terminator` (93), `path_trace_grazing_normals` (44),
`path_trace_terrain_horizon` (25) and `path_trace_cover_receivers` (65) pass
on the changed pack.

The Ray Reconstruction cases were rerun on the verified 1.35.0 package with
the head pack (`rr135-*`): `path_trace_nrd_live` passes (12), but the RR
cases stopped at the same capability check because that run did not select
`rtx_upscaling=4` in the launch settings, which the DLSS runtime needs to be
active (as the earlier `rr2-*` and `rrc135rr` runs required). Those cases
remain to be rerun with upscaling selected; the RR fixtures that do not need
the runtime (`rr_raw`, `rr_resources`, `rr_presentation`, `rr_staging`,
`rr_handoff`) passed in the full set above.

Rerun with `rtx_upscaling=4` selected at launch (`rr135b-*`, 1.35.0 package,
head pack): `path_trace_rr_live` 38, `path_trace_rr_details` 67,
`path_trace_rtxdi_live` 44 and the four `path_trace_rr_traversal_*` routes 49
checks each pass. `path_trace_travel_rr` fails only the recorded native
output size (2560×1514 cannot be reached on this 1463×914 screen) and
`path_trace_travel_rr_night` that plus the catch-up frame count (63), the
near-field coverage at the destination and the held-ground hue check, the
same three it fails on the unchanged pack. `path_trace_transmission_live`
exited cleanly after 78 seconds without printing any check in this
configuration; its 21 runtime-independent checks pass on the 1.34.0 mirror,
and the cause of the silent exit with the RR runtime active is not
established.

## ReSTIR follow-up: pairwise MIS, candidates, bounce attribution

The research notes (RTXDI library defaults, HPG 2021 "Rearchitecting
Spatiotemporal Resampling") suggested pairwise bias correction and fewer
candidates. Measured on the many-light river with RTXDI forced
(`pair-lights-*`, `cand8-lights-*`; RT GPU medians, round 1 / round 2):

| Configuration | 7 lights | 64 lights, one moving |
| --- | ---: | ---: |
| Basic correction, 2 neighbours, 16 candidates (head) | 3.56 / 3.38, 3.42 / 3.49 ms | 3.95 / 3.96, 3.98 / 4.00 |
| Pairwise MIS, 2 neighbours, 16 candidates | 4.36 / 4.36, 4.35 / 4.35 ms | 4.78 / 4.81, 4.85 / 4.85 |
| Pairwise MIS, 1 neighbour | 3.61 / 3.58 ms | 4.09 / 4.09 |
| Pairwise shader, basic mode selected at runtime | 3.53 / 3.42 ms | 4.04 / 4.05 |
| Pairwise MIS, 8 candidates | 4.13 / 4.12 ms | 4.59 / 4.58 |

Pairwise MIS costs 0.8–0.9 ms more than the basic mode here: the SDK's
pairwise path evaluates the canonical sample at every neighbour and every
neighbour's sample at the canonical surface, which outweighs the basic mode's
second neighbour walk at two neighbours. The shader stays built for the basic
mode only. Eight candidates instead of sixteen save about 0.25 ms; eight is
the RTXDI library default and the temporal reservoir carries the effective
sample count, so eight becomes the default. ABBA with eight candidates on the
basic mode (`cand8-lights-*`): 3.15 / 3.23, 3.15 / 3.25 ms at seven lights
against 3.36 / 3.55, 3.41 / 3.60 ms, and 3.56–3.70 against 3.89–3.98 ms at
sixty-four with one moving. `path_trace_rtxdi` (27), `path_trace_rtxdi_sparse`
(37), the emitter deep SHaRC RTXDI case (15) and `path_trace_light_history`
(58) pass on that pack.

Bounce attribution on the river (`bounce-*`, Low, all detail features,
`--ei-pt-bounces=N`): one bounce 0.36–0.46 ms, two bounces 0.555–0.58 ms,
four bounces (the roulette variant) 0.83–0.89 ms. The primary surface with
its direct lighting and the first bounce is about two thirds of the Balanced
ray stage; bounces three and four add about 0.3 ms over Balanced.

Controller after the matrix decode and the cached globals and light list
(`pair-river-*`, two blocks per run): frame constants 0.076–0.088 ms against
0.090–0.095 ms, NRD native step 0.092–0.101 against 0.101–0.105 ms, totals
0.97–1.17 against 1.09–1.13 ms. The ray stage is unchanged. NRD device (26),
motion (42), directional (21), light history (58), RTXDI (27), RTXDI sparse
(37) and the emitter deep SHaRC RTXDI case (15) pass on that pack.

## Separate ReSTIR direct-light pass

Following the RTXDI sample's structure (resampling in a thin program over a
stored G-buffer, never fused with the path integrator; NVIDIA's HPG 2021
paper reports that fusing "was counterbalanced by increased register usage
and divergence"), the resampling, the final light evaluation and its
visibility ray moved out of the path raygen into a second ray-generation
dispatch (`PATH_DI_PASS`, programs `path_trace_raygen_di` and
`_no_emitters`). The path raygen stores the visible surface (48-byte record
with the exact offset and half-precision material) and publishes its path
terms unfloored with raw direction moments; the direct-light pass loads the
surface, resamples, traces one visibility ray, adds its light, applies the
ambient floor and encodes the moments. Many-light river with RTXDI forced
(`dipass2-lights-*`, RT GPU medians including both dispatches, ABBA against
the eight-candidate fused pack):

| Lights | Fused (eight candidates, two neighbours) | Separate pass |
| --- | ---: | ---: |
| 7 | 3.11–3.21 ms | 1.34–1.35 ms |
| 16 | 3.17–3.24 ms | 1.37–1.39 ms |
| 64, still | 3.58–3.65 ms | 1.50–1.55 ms |
| 64, one moving | 3.62–3.67 ms | 1.52–1.59 ms |

The plain estimator measured 1.49–1.51 ms at seven lights and 2.06–2.17 ms at
sixty-four in the same session, so ReSTIR is now cheaper than the exact sum
at every tested light count, where the fused version cost about twice as
much. The resampling work is unchanged; the saving is the path raygen's
occupancy, which the fused SDK code had been limiting for every ray of the
frame. `path_trace_rtxdi` (27), `path_trace_rtxdi_sparse` (37) and the
emitter deep SHaRC RTXDI case (15) pass, including the reservoir reuse and
energy parity checks. An earlier attempt bound only the resources the
direct-light program references; the library target keeps every declared
binding in the set layout, so the pass binds the same set as the path
programs without the SHaRC bindings.

## ReSTIR activation threshold

With the separate pass, ReSTIR at seven lights (1.34–1.35 ms) is cheaper than
the exact estimator at seven lights (1.49–1.51 ms), which from five lights
already draws four stratified proposals per frame instead of one ray per
light. The managed presets therefore activate ReSTIR from five local lights
(or any registered emitter) instead of eight; up to four lights keep the exact
sum with one shadow ray each and no reservoir allocation, and the legacy
seven-slot table, which carries no count, stays on the exact path.
`path_trace_rtxdi_sparse` now exercises the exact path at 0, 1 and 4 lights,
the activation at the fifth light and the return to four (37 checks);
`path_trace_rtxdi` (27), the emitter deep SHaRC RTXDI case (15),
`path_trace_bounce_lights` (17) and `path_trace_light_history` (58) pass on
the same pack (`thresh1-*`).

## Original comparison and limits

The original renderer has no roughness or metalness; its material records
only tint diffuse and emissive. The record ids were therefore used as the
artists' classification of each part, not as calibrated values. The specular
strength and power fields in `materials.res` (metal 0.988/8.5, crystal
0.847/16.5, wood 0.078/7.5, stone 0/16) were not adopted; a per-class mapping
of those values to a physical response remains open, as does id 24 (probably
`cristall.mat`, used by two water figures and one weapon).

No visual before/after capture was produced on this machine for the new
families; the material fixtures above verify the values that reach both
renderers. Flame, lava and teleport emission maps, unit emission in PT and the
authored normal/roughness maps for the newly classified atlases are
unchanged and remain future work.
