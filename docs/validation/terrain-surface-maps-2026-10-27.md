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

With **Surface materials** and **Remake terrain** on (Forward+ only), the land
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
- **Off / unsupported:** Surface materials off, original terrain, Mobile and
  Compatibility keep the established path; the array is released.
- The Surface materials help text mentions sand ripples in EN/RU/DE.

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

## Original-game comparison

Not applicable: the original renderer has no normal or roughness maps and no
path tracer. The atlases, tile rotations and ground types used here are the
original data; the original look remains available with Remake terrain off,
and Surface materials off restores the previous remake relief exactly.

## Limitations

- The slope is inferred from painted brightness; dark painted stains still
  read as shallow hollows (reduced, not removed, by the delighting step).
- Ripples are procedural and direction-fixed; the original has no wind data.
  They are deliberately subtle and fade out beyond a few metres.
