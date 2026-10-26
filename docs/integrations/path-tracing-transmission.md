# Water and glass refraction

The current player Quality preset enables refraction; Balanced leaves it off.
The individual control below is available for renderer diagnostics with
`-- --ei-pt-tuning`; see the [player preset contract](path-tracing-experiment.md#controls).

`Remake > Ray tracing / Path tracing > PT refraction` is optional and defaults
to Off. It follows both Responsive and Still path tracing. The option and help
are translated into English, Russian and German.

When enabled, the main PT scene also gathers the finite water meshes, excluding
lava. Their original triangle boundaries, individual pool heights and current
`SetWaterLevel` offsets define the optical surfaces. Clear water has IOR 1.333
and RGB absorption coefficients `(0.12, 0.035, 0.018)` per world unit. Swamp
water uses `(0.48, 0.22, 0.6)`; these coefficients are artistic defaults, not
measurements of the original game. Existing water pigment, sediment, foam,
glints and the selected reflection method retain their composition. The new
radiance replaces the transmitted background portion.

A second ray dispatch borrows the main scene's acceleration structures,
material textures and lighting buffers. It traces Snell refraction, dielectric
Fresnel decisions and Beer attenuation `exp(-sigma_a * distance)`. Solid glass
tracks up to four nested media and sixteen interface events. Radiance transport
includes the squared relative IOR factor; it cancels across a parallel solid
slab. A thin pane uses its declared thickness, lateral displacement and the
analytic series of internal reflections, including absorption. Total internal
reflection stays in the current medium. Exhausting the bounded path contributes
zero; invalid unmatched glass exits fall back to the raster material.

Opaque hits reached through glass or water use the shared PT lighting integrator,
including sunlight, local lights, emissive surfaces and the configured opaque
bounce count. Environment misses use the current directional sky. The primary
water Fresnel split is still composed by the existing artistic water shader.

## Glass authoring

No original window texture or crystal equipment is automatically reclassified.
The original material IDs do not identify physically closed glass volumes.
Explicit new scenery can use:

```gdscript
const Dielectric = preload("res://src/game/fx/path_trace_dielectric.gd")
# RGB transmission after one world unit, in linear light.
mesh.material_override = Dielectric.material(1.5, Color(0.25, 0.8, 0.95), 1.0)
# A parallel pane with a stated thickness, rather than an open solid volume.
pane.material_override = Dielectric.material(1.5, Color(0.9, 0.98, 1), 1.0, true, 0.01)
```

Use a single closed mesh surface with consistent outward normals per solid
volume. Thin panes use two-sided geometry. Glass added outside ordinary world
objects must be a descendant of a root in `GameWorld.RAYTRACE_GEOMETRY_GROUP`.
The material carries an explicit `pt_dielectric` profile; the scene collector
watches profile changes and visibility. Turn off ordinary raster shadow casting
on glass scenery when using raster shadows; coloured glass shadows are outside
this implementation. The fallback is a tinted screen background, also available
when PT is off or the surface is outside the traced region.

## Reconstruction and cost

The dielectric pass has a separate traversal mask and colour/normal-depth
outputs. It does not replace the opaque primary receiver or modify NRD/RR
material guides. Raster water and glass accept only nearby matching interface
samples. The pass uses two samples per pixel and accumulates up to 32 stationary
frames; camera, geometry, lighting, resize and jitter changes discard history.
It does not reproject opaque motion vectors through a refractive surface.
Under RR, raster receivers undo the API clip-space conversion to match the
current jittered ray camera. Public texture bindings change only on allocation;
the PRE_OPAQUE callback writes existing images without replacing prepared
material bindings.

The scene BVH is shared. Three RGBA16F images cost 24 bytes per trace pixel,
plus 32 bytes per geometry and a small control buffer: about 47.5 MiB at a
1920×1080 trace grid. No additional full scene copy is made. Off releases these
resources. The extra dispatch can materially cost GPU time; no FPS improvement
is claimed or inferred from correctness runs.

This is camera-path transmission with smooth dielectric interfaces. Small water
waves remain raster detail. Rough glass, dispersion, volumetric in-scattering,
light-focused caustics, coloured shadow rays and dielectric transport in the
opaque integrator's secondary bounces are not included. Moving transparent
surfaces can be noisy. Starting the camera inside several nested glass volumes
does not reconstruct the containing-medium stack; author such views with a
single containing medium. NRD remains responsible for opaque lighting, and DLSS RR
still receives opaque material guides; transparent reconstruction has the same
approximation that applies to the existing transparent water layer.

## Basis and validation

The optical model follows the definitions in [PBRT's dielectric BSDF](https://pbr-book.org/4ed/Reflection_Models/Dielectric_BSDF)
and [homogeneous-medium transmittance](https://pbr-book.org/4ed/Volume_Scattering/Transmittance).
These are model references, not a claim to have integrated PBRT code. The pass
reuses the project's existing attributed path sampler.

The original game has no matching path-traced water/glass transport mode, so a
Wine image cannot serve as an optical ground truth for this new feature. The
analytic regression compares GPU intersection positions and attenuation against
Snell/Beer calculations, two-interface glass and nested-medium distances.
Existing water/material/lifetime regressions protect the original off path.
Campaign tests exercise actual raster receivers, explicit glass, changing water
levels, native 1440p/4K extents and the standard DX12 RR callback. See the
[validation record](../validation/pt-transport-2026-10-26/transmission-validation.md).
