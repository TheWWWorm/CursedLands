# Material maps and authored lighting for Cursed Lands path tracing

Research date: 22 October 2026. Source baseline: `a56d4484`, in the water/PT
experimental checkout. This expands the material and lighting recommendation in
the [graphics roadmap](path-tracing-roadmap-2026-10-22.md).

Implementation follow-through, 23 October: [equipment material maps](../validation/path-tracing-equipment-materials-2026-10-22/README.md)
and a [three-atlas authored surface pilot](../validation/path-tracing-authored-surfaces-2026-10-23/README.md)
now have separate implementation and validation records. This audit describes
the source baseline above; broader lighting work remains outstanding.
The [torch-history follow-through](../validation/path-tracing-torch-history-2026-10-23/README.md)
also verifies and addresses continuous resets from gentle flame flutter. Its
original-source inventory identifies which campaign caves already have torches
and which require authored source placement before removing legacy fill.
The [authored-lighting follow-through](../validation/path-tracing-authored-lighting-2026-10-23/README.md)
adds flame-sized PT sources, a calibrated fixed HDR display profile and matched
day/night/cave qualification. Per-zone source placement and broader color-art
cleanup remain content-authoring work.
The [object material families](../validation/object-materials-2026-10-28.md)
follow-through (28 October) replaces the short texture-name list with a family
table covering the placed props of both editions, uses the figure material
records as a classified fallback, and masks Lost in Astral's autumn trees.
The [GPU 1 control](../validation/path-tracing-gpu1-control-2026-10-23/README.md)
completes the remaining unmapped-scene performance qualification on an RTX 3090
Ti, separately from the mapped-content and lighting measurements.

The recommended first step is to carry the existing equipment material masks
into PT. Then establish one material format shared by raster and ray hits,
author a small representative material library, and light an outdoor area and
a cave against a controlled exposure. This should make metal, leather, wood and
stone respond differently to the same illumination, while preserving the
original game's palette and readability.

This is a source and asset audit with primary-source research. Findings below
identify current data flow and likely consequences; new rendering behavior,
performance gains and the torch/history interaction have not been measured in
a fresh game run. No renderer or game assets were changed for this research.

## What the project already has

| Finding | Evidence and consequence |
| --- | --- |
| Equipment already has per-pixel material information | [SurfaceMaterials](../../game/src/game/surface_materials.gd) defines metal, leather, cloth, skin and other responses. [UnitModel](../../game/src/ei/unit_model.gd) composes `surface_tex` with the same alpha and layer order as the equipment appearance. This is a useful starting point for material separation. |
| PT does not collect that equipment map | [WaterRaytraceScene](../../game/src/game/fx/water_raytrace_scene.gd), shared by the ray effects, collects albedo, original diffuse/emissive values and foliage masks. Its material version and packing paths do not collect `surface_tex`. A unit without the separate scalar `surface_profile` falls back to rough dielectric properties. [The PT shader](../../game/src/game/fx/shaders/path_trace.hlsl) traces the primary surface itself, so this affects primary lighting as well as secondary hits. |
| Most prop response is assigned per texture | Known stone and wood families receive scalar profiles and shallow luminance-derived relief. Mixed house/chest atlases deliberately remain dull pending authored masks. A single metallic value cannot correctly describe a wood-and-metal object. |
| Semantic information exists before image analysis | [FigureMaterial](../../game/src/ei/figure_material.gd) maps original FIG material IDs to leather, wood, metal, cloth, skin, stone and magic records. Combine those hints with equipment metadata and manually identified atlas regions. Original diffuse/emissive values are compatibility inputs, not calibrated PBR measurements. |
| Terrain and foliage already have special handling | [GroundSurfaceShader](../../game/src/game/fx/ground_surface_shader.gd), terrain data and PT terrain code retain atlas rotations, transitions and surface detail. Existing foliage masks distinguish leaf transmission from bark. Extend these paths without discarding their semantics. |
| Original lighting values need interpretation | [Gfx](../../game/src/game/gfx.gd) reproduces a legacy model based largely on maximum light contributions; remake fire/spell effects add their own contributions. PT adds light transport. Directly copying old brightness values into a new lighting rig does not preserve the same result. |

There is a related appearance-parity backlog: the collector also omits the
separate unit wound texture and `unit_emission`. Keep these in the shared
material design so a character's ray-hit appearance can match its raster
appearance. Equipment changes must invalidate material data without requiring
unnecessary geometry reconstruction. Respect the existing material-effects
option when defining the fallback and enabled paths.

## Material format to author

Use a documented material descriptor that references maps, defaults, UV set,
normal convention, alpha mode, physical detail scale and source fingerprint.
Both rendering paths should consume its meaning. A stock Godot material alone
will not update this project's custom shaders and ray-scene collector.

| Map | Convention | Purpose |
| --- | --- | --- |
| Base color and coverage | RGB sRGB; alpha is linear coverage | Pigment or metal reflectance color, with original cutout boundaries preserved. Remove directional lighting selectively. |
| Normal | Linear data; tangent-space OpenGL +Y | Grain, cracks, pores and small surface relief. Neutral normal when absent. |
| ORM | Linear data; R occlusion, G perceptual roughness, B metalness | Packed surface properties. Occlusion defaults to 1 and is optional in PT. |
| Emission | sRGB color map plus a separate linear intensity | Identify luminous pixels, their color and output independently from surface color. Default to black. |
| Optional masks/height | Linear data, explicitly named channels and units | Material regions, wetness eligibility, leaf transmission and authored relief. Add only where used. |

The color/data separation and roughness/metalness channels follow the
[Khronos glTF material convention](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html).
Godot documents [ORM packing and OpenGL normal maps](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html).
These conventions are a proposed asset contract, not a claim that the custom PT
pipeline already imports them.

**The existing `surface_tex` is not ORM.** Its channels mean highlight,
roughness and metalness. Convert it explicitly; do not interpret its red channel
as occlusion or copy the legacy highlight strength directly into a physical
reflectance parameter. Carry roughness and metalness first, and calibrate any
dielectric specular mapping separately. PT already squares perceptual roughness
inside GGX, so authoring/import must not square it again.
Its current 0.08 roughness floor also limits very polished surfaces; qualify any
change to that floor against noise and stability before authoring mirror-like
metal that assumes a lower value.

Treat exposed metal as metal and wood, skin, leather, paint and dirt as
dielectrics. Use a region mask for a rusty or painted metal object rather than
deriving metalness from image brightness. Roughness needs structured variation:
worn contact surfaces, grain, seams and accumulated dirt. Uniform gloss or
unrelated noise will not communicate those differences.

Do not multiply baked AO indiscriminately into path-traced illumination; the
traced scene already supplies geometric occlusion. Reserve any additional
micro-occlusion for unresolved detail with a defined, restrained treatment.
Normal maps improve surface shading but do not change silhouettes or cast the
shadows of actual displaced geometry.

## How to produce the maps

1. **Inventory and classify.** Record original texture name, dimensions, UV
   use, material IDs and common in-game views. Select important surfaces before
   increasing resolution. Read-only inspection of `res/textures.res` found
   `barrel00`, `bridge00`, `oak00` and `dgunisthouse00` at 256×256, `box00` at
   128×128 and `tree02` at 512×512. These are sampled assets, not a survey of
   the entire archive.
2. **Preserve the layout and identify materials.** Paint masks for wood,
   masonry, metal, leather and other regions, respecting UV islands and alpha.
   Reuse equipment composition and existing leaf/bark masks. Mixed building
   atlases require region-level work even when the overall object is stone.
3. **Separate pigment from painted lighting.** The inspected
   `dgunisthouse00` atlas mixes wall, wood and dark shaded regions. Review it
   under neutral lighting before removing anything. Preserve stains, painted
   decoration and intentional color variation; remove directional highlights
   and shadows only where their role is clear. Old color textures are not
   reliable height measurements.
4. **Author coherent surface detail.** Use a reusable procedural stone, wood
   or leather material for the small-scale structure, then mask and adapt it
   to the original atlas. Derive normals from authored height or bake them
   from a detailed model. Paint roughness and metalness from material identity.
   AI or image-to-material conversion can supply a draft that needs inspection.
5. **Bake and filter offline.** Export compact maps at a justified resolution.
   Preserve tile gutters, seams and alpha coverage through mip generation.
   Store source hashes, authoring parameters and a format version so caches
   rebuild when inputs change. The existing foliage cache already provides
   a source-fingerprint precedent.
6. **Review in a material test scene and in the actual game.** Rotate a neutral
   light over flat and curved samples, then check the material in daylight,
   shade and firelight. Review at the distances and camera angles used in play.
   Close-up appeal should survive minification without sparkling.

NVIDIA's [RTX Remix material guide](https://docs.omniverse.nvidia.com/kit/docs/rtx_remix/latest/docs/howto/learning-materials.html)
also identifies baked lighting in older textures as a problem when replacing
their material response. Its authoring lesson is relevant here; adopting the
Remix runtime is unnecessary for a renderer we can modify directly.

### Practical authoring tools

Use **Material Maker** for the reusable procedural material library. It is
[MIT-licensed and supports procedural textures and model painting](https://github.com/rodzill4/material-maker).
Its [export workflow produces image maps](https://rodzill4.github.io/material-maker/doc/export.html).
Import those maps through the proposed descriptor; its engine export does not
solve integration with our custom shaders.

Use Blender for UV inspection and geometric baking, and a layer-based image
editor for masks and selective cleanup. These are authoring roles, not new
runtime dependencies. Optional [Adobe Substance 3D Sampler Image to Material](https://experienceleague.adobe.com/en/docs/substance-3d-sampler/using/filters/tools/image-to-material)
can estimate multiple maps and reduce embedded shadows/highlights. Such results
remain estimates, particularly on tiny mixed atlases. [Poly Haven's CC0
materials](https://polyhaven.com/license) can provide reference surfaces or
reusable detail, adapted to the original palette and scale.

## Highest-value initial materials

| Target | Work to prioritize | Intended visible result |
| --- | --- | --- |
| Equipped characters | Connect existing roughness/metalness masks; retain skin, cloth and equipment boundaries | Weapons and armor catch light differently from leather and exposed skin. |
| Barrels, bridges and mixed props | Wood grain normals, material masks and restrained wear roughness | Wood remains matte while real metal fittings respond to highlights. Confirm each atlas region before classifying it. |
| Masonry and cave stone | Authored cracks/joints, dry/damp roughness, selective albedo cleanup | Torchlight reveals relief; damp areas have broader environmental reflections. |
| Cliff rock, soil and grass | Distinct detail scale and response, matched to existing terrain blends | Less uniform terrain lighting without turning vegetation into glossy stone. |
| Bark and leaves | Preserve bark/leaf separation; restrained normals and existing transmission | Leaves admit light while trunks retain solid, rough surface shading. |
| Fire, lava and magical surfaces | Localized emission masks and calibrated intensity | The visible source and surrounding illumination agree. |

Start with roughly eight material families and a small set of representative
objects. This is an authoring scope proposal, not a claim that eight textures
cover every original asset. Prioritize roughness and material separation before
blanket resolution increases.

The saved [cliff capture](../validation/path-tracing-shader-optimization-2026-10-22/cliff-noon.png)
also shows angular silhouettes and stretched surface patterns. Better maps can
improve their light response; mesh/UV work is a separate requirement for those
shape and mapping defects. Check a close-view rock detail projection experiment
only after confirming parity with the existing terrain shader.

## Authored lighting workflow

**Establish a stable reference.** Use fixed exposure and neutral reference
surfaces to tune the material response first. Then author light direction,
color, source size and intensity. Add tone mapping and restrained bloom only
after highlights and shadow detail are under control. The original environment
uses linear tone mapping with exposure 1, so a new display transform requires
comparison across the complete scene, including UI and emissive effects.

**Preserve the regional palette.** The original configuration has hourly sun,
ambient and sky colors for Gipat, Ingos and Suslanger, plus cave variants.
[EILights](../../game/src/ei/lights.gd) already loads them. Build PT lighting
profiles from this art direction: dawn, noon, dusk and night anchors with smooth
interpolation, plus local interior overrides. Reuse original hues while
calibrating their new intensity relationships.

**Give interiors identifiable sources.** Place torch/fire lights within the
visible source, using the existing flame offset as a starting point; check that
the bowl or wall does not accidentally block all illumination. Use plausible
source size for soft shadows and enough bounced light to reveal nearby stone.
Supply outdoor spill only through real openings. The current
[PT sky](../../game/src/game/fx/path_trace_sky.gd) correctly removes the outdoor
sky contribution in caves; inspect directional sun eligibility separately for
enclosed interiors. Avoid using a uniform ambient floor to compensate for
missing sources.

**Classify light intent explicitly.** The current PT collector selects at most
seven local lights by proximity to the camera's light ranges. The same group
contains world lights, scripted lights and optional character assistance lights.
[Character lights](../../game/src/game/game.gd) request no specular and no
shadows, but the PT payload does not retain those flags. Define which sources
participate in physical transport and which implement a readability setting.
Preserve the setting and scripted lifetimes; an assistance lamp should not
silently consume the same scarce budget with unintended shadow/specular
behavior. Keep the first pilot within the supported world-light budget and
make omissions visible in diagnostics.

**Account for each emitter once.** A visible flame may have an emissive surface,
a point light and a halo. Define whether the point light represents the same
source, supplements a nontraced particle, or is a deliberate artistic addition.
When introducing emissive maps, update emitter selection weights and scene
invalidation consistently; simply making the shader brighter can misallocate
light samples. Detailed flame transport and many-light sampling can follow the
initial art pass.

**Treat flicker stability as a prerequisite for judging torchlight.**
[LocalLighting](../../game/src/game/fx/local_lighting.gd) varies fire energy every
frame when enhanced fire is enabled. [SceneRaytrace](../../game/src/game/fx/scene_raytrace.gd)
includes selected light energies in its signature and invalidates PT history
when lighting changes. These paths imply that a selected flickering torch can
repeatedly restart accumulation. Verify this with counters and video. Calibrate
with a constant reference source, then qualify actual flicker using temporal
handling that rejects stale illumination without indiscriminately discarding
all useful history. Permanently freezing gameplay effects is not the proposed
solution.

Physical units can help future cross-tool consistency, but the current PT
point-light falloff and BRDF scaling are custom compatibility choices. Godot
explicitly documents that [physical units require coordinated light, camera
and environment setup](https://docs.godotengine.org/en/stable/tutorials/3d/physical_light_and_camera_units.html).
Changing the project setting alone cannot calibrate this shader. Use a
consistent relative intensity scale for the first pilot; a later physical
conversion needs world-scale, attenuation and exposure decisions together.

## Renderer integration and cost

The original meshes lack a tangent stream. Choose one tangent convention for
baking and both renderers. Generate compatible tangents, or qualify a shared
UV-derived basis; handle mirrored UVs, degenerate UV triangles, transforms and
deformed characters. Rotate terrain normal directions with the existing tile
rotations. Continue using geometric normals for ray offsets and keep shading
normals in the valid geometric hemisphere.

New maps must participate in material versioning, texture residency, mip/LOD
selection and both primary and secondary hits. Current ordinary ray-scene
textures are resized to 512×512 and converted to RGBA8; detailed terrain also
uses its existing atlas path. Merely dropping a 2K replacement into the asset
folder will not deliver 2K ray-hit detail. Extend the layout deliberately and
budget per material class.

For scale, one 512×512 RGBA8 layer with a full mip chain is about 1.33 MiB.
Three fully populated 192-layer arrays for color, normal and ORM would be about
768 MiB, before emission, terrain and other resources. This is an illustrative
uncompressed allocation, not measured current VRAM usage. Use shared default
layers and sparse allocation; evaluate suitable GPU compression only after
checking support in the custom resource path. File compression alone does not
reduce this decoded allocation.

Additional maps cost bandwidth, but baked normals may replace some existing
multi-tap relief calculations. Measure the net result. Authoring roughness mips
against normal variance can reduce specular shimmer; Godot documents
[normal-aware roughness filtering](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).
The custom PT upload path must preserve or reproduce it rather than assuming
standard import settings reach these arrays.

## Implementation order and acceptance

| Stage | Deliverable | Acceptance condition |
| --- | --- | --- |
| 1. Recover existing data | Equipment surface maps in PT; explicit conversion and material invalidation | Skin stays dielectric; changing equipment updates the correct regions in direct and reflected views. |
| 2. Establish the shared material path | Normal/ORM/emission support plus one mixed prop and one rock sample | Both rendering paths agree on regions, color space, UV orientation and alpha coverage. |
| 3. Author the pilot | A small outdoor area and torchlit cave, using the initial material library | Improved surface distinction and readable paths/characters at fixed comparison exposure. |
| 4. Qualify and expand | Stable flicker, regional/time profiles, measured resource budget | Moving-image quality and GPU cost justify scaling authoring to more assets. |

Capture material-only, lighting-only and combined comparisons from identical
cameras. Include a rotating light, a moving character, equipment changes,
mixed-metal props, leaf edges, a wet/dry boundary, terrain tile seams and a torch
seen in reflection. Check day/night and interior/exterior transitions, close
and distant views, and the supported gameplay camera modes. Compare assistance
lighting enabled and disabled, preserving its intended readability.

Record tracing/composition GPU time, texture memory and history-reset counts,
alongside short videos that reveal shimmer, ghosting and exposure pumping.
Require a visible improvement at the same tracing preset before expanding the
asset batch. New controls, if eventually needed, require EN/RU/DE labels,
choices and help. Any future validation runs must use the isolated development
profile with free cursor, FPS shown and all three audio volumes muted.
