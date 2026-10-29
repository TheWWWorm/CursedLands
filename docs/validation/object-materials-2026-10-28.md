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
