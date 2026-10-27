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

## Evidence

| Check | Result |
| --- | --- |
| `terrain_surface_maps` (40 checks) | Slope signs, delit ramp (0.502/0.498 against 0.532 brightness-only), per-type roughness, sand flag, padded-slot isolation (max leak 0.002), production GLSL rotation reference: correlation 0.944 at all four rotations, 0.005 for a quarter turn, negative control detects a wrong inverse rotation; cliff, transition, caustic and baked land variants compile with the maps. |
| `terrain_surface_live` 1920×1080 (23 checks) | Zone 19 open sand clear of objects: normal detail 0.0032 → 0.0172; lit A/B differs; restoring is exact; PT binds the maps, header bit set, output finite; option off clears raster and PT; EN/RU/DE help. |
| `terrain_surface_live_1440` / `_2160` (23 checks each) | Same contract at 2560×1440 (0.0023 → 0.0166) and 3840×2160 (0.0027 → 0.0169). |
| `terrain_surface_help` (37 checks) | Changed help translated, complete and inside the window in its actual row, EN/RU/DE at 720p, 1440p and 4K. |
| Path-tracer binaries | `build_water_rt_shaders.py --check` reproduces all 36 binaries. |
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

Retained captures and run summaries: `local/validation/terrain-surface-20261027/`.

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
