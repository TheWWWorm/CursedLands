# Path-traced lighting in water reflections

With **Water reflections: Ray traced (test)** and path tracing enabled, water
uses the shared path integrator for its reflected scene. With path tracing off,
the existing RT reflection remains available. The selected two/four-bounce mode,
sky and cave palette, emissive sampling, material evaluation, cloud shadows and
up-to-64 local-light table apply to the reflected view too. This adds indirect
illumination and glossy transport at the surfaces visible in water; the outer
water surface still uses the established planar reflection lookup and wave
distortion. It is not a separate rough-water microfacet path integrator.

`PathWaterDevice` extends `PathDevice`. The new ray-generation permutations
reuse its existing closest-hit, terrain/transition, alpha-test and miss stages.
The first reflected camera ray starts just above the water plane. Scene
collection retains underwater geometry for subsequent transport and shadow
rays, with the same primary/GI/shadow instance masks as the main path tracer.
Close-view presentation meshes remain excluded; reflection-body meshes remain
included. The original water material and analytic reflected sky are retained.

## Sampling and reconstruction

Each pixel retains the established four fixed primary sample locations. Each
location traces a continuation path with the selected bounce count. Water
quality continues to set 50%, 75% or 100% of the window dimensions; it does not
multiply these four paths by the main view's sample setting. High therefore
allocates a native 3840×2160 reflection when the window is 4K.

The shader averages shaded diffuse colour before demodulation and supplies
the matching averaged albedo for composition. Interior pixels use the shared
NRD radiance or directional SH/SG reconstruction, or the existing progressive
accumulator for Still scene. Direct sunlight/specular retain their separate
reconstruction. Primary emission is added exactly once after reconstruction.

Pixels spanning a miss, distinct placement, substantially different normal or
material use their raw four-sample colour average. This preserves fractional
coverage and prevents temporal/spatial reconstruction from blending a tree
edge into the sky. Indirect lighting at these mixed edges can remain noisy;
this is an explicit tradeoff, not a claim of noise-free reflections. Directional
SH/SG retains the brightness/memory limitations described in
[the NRD integration](path-tracing-nrd.md).

The composed output is a separate, stable RGBA16F texture: scene-linear HDR,
premultiplied coverage, distance fade and fog. Misses clear colour and alpha.
Resizing retains the previous published image until a complete replacement
frame is available. The water material binds this composed texture, never the
main integrator's demodulated diffuse-light output. Failed optional NRD setup
uses the existing reconstruction fallback.

The water plane/fog constants have their own small uniform block. The shared
material stages retain the original 2816-byte frame interface on both APIs.
Two additional images carry emission/coverage and the raw mixed-edge result;
the composition image is also additional to the ordinary PT/NRD resources.

Each live or pending reflected generation owns an independent frame/history
producer. It reuses the main controller's frame-generation logic without
joining the scene tree, processing another scene, or publishing main-view
light globals. Plane/mode changes, cuts, lighting changes and moving geometry
invalidate history through that same contract. Producers are freed when a
candidate is cancelled, a generation retires, or RT mode is restored. The
reflected path uses exact continuation rather than creating a second SHaRC
cache; main-view SHaRC remains independent.

## Verification and limits

`path_trace_water.gd` executes the actual ray and compute passes on Vulkan and
DX12. A white bank receives red light from an emissive ceiling with no sun or
ambient; the same bank stays black under the original RT direct-light shader.
The test also covers underwater emission and its blocker, immediate emitter
extinction, HDR primary emission, fractional coverage, sky clearing, both NRD
modes, fog, orthographic projection, native 4K resize and complete teardown.

`path_trace_water_live.gd` exercises the production controller in the original
gz3g river scene: RT/PT transitions, full material/underwater collection, the
composed binding, directional NRD, ten local lights, four-bounce selection,
Still scene, streamed replacement and return to RT. The test does not infer
illumination correctness from animated screenshot differences. Controlled
readbacks provide that evidence; retained campaign images check presentation.

`path_trace_water_options.gd` checks the updated water help in English, Russian
and German at 720p, 1440p and 4K. Existing water edge-quality, character motion,
replacement/failure, main-view directional NRD and exact resource-lifetime
regressions cover the adjacent paths. See the
[validation receipt](../validation/pt-transport-2026-10-26/water-results.json).

These are feature checks, not a performance benchmark. Both PT views cost GPU
time and memory, and cold pipeline compilation can still stall. The original
game has no equivalent path-traced reflection implementation, so an original
Wine comparison cannot establish PT ground truth. Original terrain, textures,
material intent and the existing RT path are preserved and tested. Water/glass
refraction and absorption, RTXDI direct-light reuse and DLSS Ray Reconstruction
are separate work; this component does not claim to implement them.
