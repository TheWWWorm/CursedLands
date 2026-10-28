# Terrain surface maps — 27 October 2026

Local change on `feat/terrain-surface-maps`, based on local main
`9e6aa3a737f82bcdc372b9fd475a31bbf471d0c0` (1.33.0 candidate). Nothing was
pushed or published.

## Request

A player suggested that path-traced terrain needs normal maps or full PBR.
The path tracer already consumed object surface-detail maps, but terrain used
only colour-derived relief, one shared noise normal map and a fixed roughness
per ground type. Derived textures must not be shipped: everything is computed
from the player's installed original atlases.

## Change

With **Ground relief maps** (Terrain and vegetation, off by default), **Surface
materials** and **Remake terrain** on (Forward+ only), the land
builds one `rgba8` array matching the padded terrain atlas at load time, on
the rendering device (`TerrainSurfaceMaps`, about 30 ms for a two-layer test
atlas, including mips):

| Channel | Content |
| --- | --- |
| RG | Painted slope (finite difference of linear brightness) with the broad painted shading removed (an 8-texel mip is subtracted), so baked light is not embossed a second time. |
| B | Roughness: per-type base (stone 0.84, soil 0.98, grass 0.96, ice 0.25), slightly rougher cavities, smoother crests on stone. |
| A | Loose-sand weight (ground type 3). |

- **Raster land:** the map slope replaces brightness relief where the tile owns
  the pixel (transition coverage blends it over neighbours exactly as colour
  is blended). Sand gets its own relief scale, finer grain and procedural wind
  ripples that fade out before they alias (pixel footprint 5–11 cm). The
  material response uses the map roughness.
- **Path tracer:** the same array is bound at `binding 41`; terrain header bit
  1 enables it. Covered hits skip the four colour taps and use the map slope,
  rotated back into hit-UV axes; roughness and sand follow the raster rules.
- **Cliffs:** projected wall rock fades the map relief and roughness by its
  wall weight in both renderers, so a ground tile's roughness never lands on a
  vertical face.
- **Off / unsupported:** Ground relief maps off (the default), Surface
  materials off, original terrain, Mobile and Compatibility keep the
  established path; the array is released.
- **Ground relief maps** has its own label and help in EN/RU/DE; lower graphics
  tiers and Original look turn it off with Surface materials, whose help is
  unchanged from before this work.

## Strength (follow-up)

The first pass was judged too subtle in side-by-side captures. One strength
vector, `TerrainSurfaceMaps.tuning`, now drives raster (`surface_tuning`
uniform, synced to colour-cache materials) and PT (terrain header float4 at
offset 64; the header grew from 64 to 80 bytes and the snapshot version
includes the vector). Components: relief gain, ripple gain, ripple reach
(pixel footprint where ripples have faded), roughness contrast around each
type's base roughness (clamped 0.05–1).

Three levels were rendered under a 07:00 sun (about 41° elevation) on loose
sand and stone (zone 19), dirt and grass (zone 1) and a snow cliff (zone 11),
in raster and PT, against maps off:

| Level | Relief | Ripples | Reach | Roughness contrast |
| --- | --- | --- | --- | --- |
| first pass | 1.0 | 1.0 | 0.11 | 1.0 |
| **medium (selected)** | 1.6 | 2.5 | 0.25 | 2.0 |
| strong | 2.2 | 4.0 | 0.40 | 3.0 |

Medium was chosen by the owner. Strong left dark speckles on traced stone.
Projected cliff faces are unchanged by design (the maps fade by wall weight).
Sand normal detail at 1080p: maps off 0.0032, first pass 0.0172, medium 0.0408.
Comparison sheets: `local/validation/terrain-surface-20261027/captures/strength/`.

## Evidence

| Check | Result |
| --- | --- |
| `terrain_surface_maps` (47 checks) | Slope signs, delit ramp (0.502/0.498 against 0.532 brightness-only), per-type roughness, sand flag, padded-slot isolation (max leak 0.002), production GLSL rotation reference: correlation 0.944 at all four rotations, 0.005 for a quarter turn, negative control detects a wrong inverse rotation; cliff, transition, caustic and baked land variants compile with the maps and default to the selected strength; raster relief, ripples and roughness follow it. |
| `terrain_surface_live` 1920×1080 (29 checks) | Zone 19 open sand clear of objects: normal detail 0.0032 → 0.0408 (unit strength 0.0172, must be exceeded by 15 %); strength reaches every land material and restores exactly; PT header carries the strength and rebuilds when it changes; lit A/B differs; restoring is exact; PT binds the maps, header bit set, output finite; option off clears raster and PT; EN/RU/DE help. |
| `terrain_surface_live_1440` / `_2160` (29 checks each) | Same contract at 2560×1440 (0.0027 → 0.0405, unit strength 0.0169) and 3840×2160 (0.0023 → 0.0402, unit 0.0166). |
| `terrain_surface_help` (37 checks) | Changed help translated, complete and inside the window in its actual row, EN/RU/DE at 720p, 1440p and 4K. |
| Path-tracer binaries | `build_water_rt_shaders.py --check` reproduces all 36 binaries; `build_path_sharc.py` / `build_path_rtxdi.py --check` reproduce all 13 / 16 (byte-identical: those stages carry no terrain material code). Their manifests' `path_trace.hlsl` hash had been left at the pre-feature source by `cda6b0b6` and is now current; `test_path_trace_build_inputs` passes. |
| `check_translations.py` | 0 errors. |

Related existing regressions on the same candidate pack (first run): 23 of 25 pass —
`path_trace_terrain` (120), `path_trace_terrain_horizon`,
`path_trace_terrain_collect`, `path_trace_ground_irradiance` (97),
`path_trace_surface_maps`, `terrain_cliff_pattern`, `terrain_wall_contours`,
`terrain_cave_wall`, `terrain_cliff_disk_rendered`, `terrain_desert_cliffs`,
`terrain_desert_live`, `terrain_sun_shadows`, `terrain_shader_selection` (65),
`terrain_color_native` (3,300), `terrain_color_reuse`, `terrain_color_lifecycle`,
`terrain_color_loading`, `save_load_render_cache` (+ raster),
`shader_compilation_scene` (62), `water_caustics`, `chest_surface_material`,
`chest_surface_live`.

The two others failed identically on unchanged local main and are now fixed on this branch: a baseline pack
built from `9e6aa3a7` with the same engine, data and runner gives the same
results (as did the earlier recorded baseline `34a17e14`), so they were not
caused by this change:

- `terrain_cliff_composed`: 69 checks, 0 failures, below the manifest minimum
  of 87. Cause: `310edbb2` admitted desert cliff families, moving the test's
  zone11 site to a view with 16 resident colour-cache sectors instead of 22;
  the test asserted per sector. Fixed in a separate commit on this branch: one
  assertion per property over every resident sector (equally strict),
  minimum 24. Now 24/0.
- `terrain_cliff_composed_gl` (Compatibility, where derived maps are never
  created): "unsupported tiles preserve exact pixels in enabled source zone11".
  Not fixed: 26 contact-band pixels on the test box differ by up to 10 because
  the NVIDIA GL compiler generates different floating-point code for the cliff
  contact program even when its projection body never executes (isolation
  table in `local/validation/terrain-surface-20261027/gl-contact-diagnosis/`).
  The check asserted bit-identical output from two distinct GL programs,
  which the platform does not guarantee. On Compatibility only, it now keeps
  every pixel outside the test box's screen rectangle (plus 3 px of AA reach)
  bit-exact and bounds the box's own contact pixels to a peak delta of 16;
  Forward+ keeps the full-frame exact check. Now 21/0.

Final run on the candidate pack: all 34 cases pass (the 25 related cases,
the five new terrain surface cases, and `ground_contact_native`,
`vegetation_interaction`, `foliage_feature_combinations`,
`water_wave_render` for the contact-shader investigation), 6,380 checks,
0 failures.

After the strength change (80-byte PT header), `path_trace_terrain` and
`path_trace_terrain_collect` fixtures follow the new layout: the hand-built
buffer reserves the full header (its tile table previously began at 64, where
the strength now lives), and the byte-layout assertions are expressed relative
to the 80-byte header with the same exact values plus a check of the stored
strength (12 checks). The same 34 cases rerun on the rebuilt pack: 33 pass in
the suite run; `path_trace_terrain_collect` failed there on the old absolute
offsets and passes 12/0 after the fixture update. 6,406 checks, 0 failures
(`runs/strength-suite.json`, `runs/strength-collect-fix.json`).

Retained captures and run summaries: `local/validation/terrain-surface-20261027/`.

## Performance

Packaged candidate, RTX 3090, GPU Lab `workload=heavy`, uncapped, vsync off,
zone 19 open loose sand filling the screen (a terrain-only worst case: sand
also runs the ripple path). Maps off/on alternated over four rounds in one
process per resolution; medians of 300 frames per round, then of the rounds.
"Gameplay" is a high view (18 m up), "close" the live-test view. In PT mode the
viewport GPU time covers the raster pass only; wall time is the full frame.

| Mode / view | 3840×2160 off → on | 2560×1440 off → on |
| --- | --- | --- |
| Raster gameplay, GPU | 5.97 → 6.46 ms (+0.49) | 3.14 → 3.41 ms (+0.27) |
| Raster close, GPU | 5.16 → 5.55 ms (+0.39) | 2.70 → 2.88 ms (+0.17) |
| PT gameplay, frame | 27.86 → 29.61 ms (+1.75) | 13.43 → 14.26 ms (+0.82) |
| PT close, frame | 24.51 → 26.29 ms (+1.77) | 11.26 → 12.33 ms (+1.06) |

About 6–10 % of a terrain-filled frame in either renderer; every 4K round
moved the same way. Deriving the maps on load: about 1 ms for this region's
8-layer 640×640 atlas (0.7 ms when repeated). Script, launcher and raw rows:
`local/validation/terrain-surface-20261027/perf/` (a first 4K run whose PT
state switch was not yet confirmed before measuring is kept for reference).

### Where the cost went, and the fused walk (28 October)

A diagnostic profile (same site, 4K, RTX 3090 Ti, four alternating rounds)
swapped one part of the raster shader at a time:

| Variant | Raster GPU cost over maps off |
| --- | --- |
| Maps on (production) | +0.42 ms |
| Ripples disabled | +0.39 ms |
| Anisotropic map filtering disabled | +0.44 ms |
| Map read from the centre tile only (no edge blend) | +0.10 ms |

Ripples cost about 0.03 ms and anisotropic filtering nothing measurable.
Most of the cost was a second walk over the neighbouring tiles near each
tile edge: the colour and the map each resolved the same owners, rotations,
weights and UVs separately. The path tracer did the same, and walked the
original sample twice more inside junctions.

The map texel is now read inside the colour walk from the same tile
coordinates, with the same weights and mixes (`ground_sample_mapped` /
`land_original_mapped` in GLSL; `original_walk` in `path_trace.hlsl`, whose
junction path now reuses one original sample). Transition variants get the
mapped walk by copying their `ground_sample` body with the original call
replaced. Bodies that do not have exactly one call before the first return
keep the previous separate read.

Equivalence:
- GPU compute (`terrain_surface_maps`): colour, traits and surface are
  bit-identical to the separate calls over all rotations, tile interiors,
  edges and two gradient scales, with maps on and off. A negative control
  catches a one-weight change.
- Rendered (`terrain_surface_live`): the sand site rendered with the old
  separate walks and with the fused walk is byte-identical, outside the FPS
  counter, at 1080p, 1440p and 2160p.
- Packs before and after: raster captures identical. PT differs by at most
  5–17/255 at a 1e-4 mean, within the old pack's own run-to-run noise (peak
  8/255, mean 1.1e-4).

A/B, packs built before and after, two alternating runs each, 4K, RTX 3090
Ti, GPU Lab `workload=heavy`. Each value is the median of four rounds; the
range covers the two runs:

| Measure | Separate walks | Fused walk |
| --- | --- | --- |
| Raster, GPU cost of maps | +0.40 to 0.41 ms (8.8 to 9.1 %) | +0.09 to 0.12 ms (1.9 to 2.6 %) |
| PT, frame cost of maps | +1.29 to 1.42 ms (6.1 to 6.8 %) | +0.55 to 0.56 ms (2.6 to 2.7 %) |
| PT, raster pass GPU cost | +0.41 to 0.44 ms | +0.10 to 0.11 ms |

Times with maps off are unchanged between these two builds. Both "off" states
still carried the map code behind runtime switches, so these deltas
understate the full cost against the established program; see the next
section for that comparison. Profile script and raw rows:
`local/validation/terrain-surface-20261027/perf/fused/`.

Tests for the opt-in default (pack built from the merged branch): the
36-case suite plus `options_rows_reachable`, `options_rows_reachable_ui` and
`unavailable_graphics_ui`. 37 of 39 passed on the first run; the two live
cases failed only on a help check still pointing at Surface materials. After
moving that check to Ground relief maps, all three live cases pass, 39/0 each
(`runs/opt-in-suite.json`, `runs/opt-in-live-rerun.json`). The new live and
maps tests do not run on the previous build `c5cf84b4`, which lacks the option
and transform (`runs/opt-in-negative-control.log`). Unregistered GPU tests on
the same pack: sampling 96/0 on Forward+ and Mobile, transitions 75/0,
Mobile junctions 60/0; the stale Forward+ junction harness is unchanged
(45 of 60 failing, as before).

Related tests on the fused pack:
- The 34-case suite plus `path_trace_cover_receivers` and
  `terrain_color_reuse_compatibility`: 36/36 pass, 6,513 checks
  (`runs/fused-suite.json`).
- Unregistered GPU tests: `terrain_sampling`, Forward+ 96/0 and Mobile 96/0;
  `terrain_transitions` 75/0; `terrain_junctions_shader` on Mobile 60/0,
  covering the generic junction variant through the mapped walk.
- The Forward+ `terrain_junctions_shader` (45 of 60 failing) and
  `terrain_junctions` (1 of 7,515 failing) fail identically on the pack
  before this change. Their harness still calls the pre-`3bc93406`
  `transition_junction_sample` signature. Both tests are unregistered, and
  the failures predate this work.

### Off by default, and free while off (28 October)

The owner asked whether the maps cost anything while off; if not, the feature
should merge with Ground relief maps off by default. Measured first against
local main `cccf554c` (same 4K sand view, default options, RTX 3090 Ti, two
alternating runs per build), the first opt-in build still cost about 5 % with
the option off: raster GPU 4.23–4.25 → 4.45–4.50 ms, PT frame 20.2–20.3 →
21.0–21.5 ms. The land program and the path-tracer hit program carried the
map code, behind runtime switches, even when no map was bound.

Now the map code is compiled in only while the option is on:
- Raster: `EITerrain.TERRAIN_SHADER` is main's text again. With the option on,
  `GroundSurfaceShader.land_with_maps()` adds the maps (and the `tile_coord`
  split) before cliff, transition, caustic and colour-cache sources are
  applied. Off, every land variant is composed from main's text; on, the
  transform reproduces the previously tested fused program byte for byte
  (apart from its `#define EI_SURFACE_MAPS`).
- Path tracer: the map changes in `path_trace.hlsl` are under
  `PATH_TERRAIN_SURFACE_MAPS`, with main's code in each `#else`. The builder
  adds `closest_hit_{terrain,transitions}_maps` (and transmission) programs,
  selected only when the terrain header's map bit is set. All 65 existing
  binaries rebuild byte-identical to local main's; the 8 new ones are
  byte-identical to the tested fused hit programs.
- Mobile and Compatibility never request maps, so they now run main's land
  program again (including Mobile's compact centre sample).

Same benchmark after the change (alternating runs, two per build):

| 4K sand view | Local main | Option off | Option on |
| --- | --- | --- | --- |
| Raster GPU | 4.21–4.26 ms | 4.31–4.32 ms | 4.61 ms |
| PT raster pass GPU | 5.17–5.20 ms | 5.16–5.20 ms | 5.45–5.46 ms |
| PT frame | 19.9–20.1 ms | 20.1–20.3 ms | 21.3–21.9 ms |

The off programs are identical to main's; the remaining 0.05–0.10 ms raster
and 0.2 ms frame differences are within this view's run-to-run spread (about
0.1 ms raster and 0.4 ms PT frame between runs of one build). Benchmark
script and rows: `local/validation/terrain-surface-20261027/perf/opt-in/`
(the first opt-in attempt's rows in `first-attempt/`).

Against local main, the option on costs about 0.30–0.37 ms raster GPU (7–9 %)
and 1.1–1.6 ms PT frame (6–8 %) at this terrain-filled 4K view; the fused walk
removed about 0.3 ms raster and 0.9 ms PT of a cost that was higher before.

## Original-game comparison

Not applicable: the original renderer has no normal or roughness maps and no
path tracer. The atlases, tile rotations and ground types used here are the
original data; the original look remains available with Remake terrain off,
and Ground relief maps off (the default) or Surface materials off restores the
previous remake relief exactly.

## Limitations

- The slope is inferred from painted brightness; dark painted stains still
  read as shallow hollows (reduced, not removed, by the delighting step).
- Ripples are procedural and direction-fixed; the original has no wind data.
  They are deliberately subtle and fade out beyond a few metres.
