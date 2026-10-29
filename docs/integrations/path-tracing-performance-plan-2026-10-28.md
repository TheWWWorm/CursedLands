# Path-tracing cost audit and performance plan — 28 October 2026

Source audit of the 1.35.0 path tracer (`c166495c`) on the Windows workstation
(RTX 4090 Laptop, Direct3D 12). The official DXC v1.9.2609 Windows release
(`dxc_2026_09_29.zip`, SHA-256
`ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1`, the same
`01b62ad4` commit as the pinned Linux library) reproduces every committed
path-tracing, RTXDI and SHaRC binary byte for byte, so shader changes could be
built and verified here. Proposals 1, 2 (in a reduced form), 4 and the alpha
footprint item are implemented below; the others remain proposals with the
evidence that motivates them.

## Where the GPU time goes

Effective budgets in the two player presets (`path_trace_settings.gd`):

| Setting | Balanced | Quality |
| --- | --- | --- |
| Trace lattice | 50% × 50% of the internal size, 1 sample | same |
| Continuation bounces | 2 | 4, with compensated roulette |
| Local lights per path vertex | every in-range light up to 7; 4 stratified draws above 7 | same |
| ReSTIR DI | off | with emitters or more than 7 lights |
| Ray Reconstruction | traces at the full DLSS input size, 1 sample | same |

Rays per sample in a scene with seven local lights: 28 at two bounces (21 of
them point-light shadow rays), 48 at four bounces. Every path vertex pays one
sun ray, one shadow ray per in-range light, one emitter next-event ray and the
continuation ray. All visibility rays already use
`ACCEPT_FIRST_HIT_AND_END_SEARCH | SKIP_CLOSEST_HIT_SHADER`; opaque geometry
skips any-hit; emitter MIS traces no duplicate ray.

Measured references from the retained records:

| Scene | Configuration | PT GPU |
| --- | --- | ---: |
| River, RTX 3090 Ti, native Vulkan | 2 bounces, Medium | 3.04 ms |
| River, RTX 3090 Ti, native Vulkan | 4 bounces, High | 11.51 ms |
| River, 640×360, 2 bounces, ~1 light | Low | 0.84–0.87 ms |
| Same, 7 lights | Low | 2.10–2.18 ms |
| Same, 16 lights (4 draws) | Low | 2.56–2.61 ms |
| Same, 64 lights (4 draws) | Low | 3.96–4.07 ms |
| Foothills, 4K output, 1080p internal, NRD, RTX 4090 Laptop | Ultra | 1.7–2.1 ms of a 13.3–13.8 ms frame |

The 4K Foothills frame is bound by the main thread, not the tracer. Sixteen
lights cost more than seven although they trace fewer shadow rays, which points
at the two O(N) weight loops in `direct_light` rather than the rays themselves.
Detailed terrain adds roughly 45–55% to four-bounce PT time (3.74/14.42 ms with
the earlier simple terrain against 5.85/20.7 ms, separate runs).

The single hit group runs the terrain closest-hit program for every hit. A
terrain hit samples 8–11 atlas texels on flat interior ground, 12–18 at tile
edges and transitions, and more than 30 near projected cliff corners. The same
evaluation runs for continuation hits, which outnumber primary hits by up to
eight to one at four bounces.

## Shader proposals, in order

1. **One shadow ray per secondary vertex.** Replace the exhaustive ≤7 loop
   and the four-draw scheme at continuation vertices with resampled importance
   sampling over all local lights, using the unshadowed `point_light`
   contribution as the target, then trace one shadow ray. Keep the exact sum
   at the primary vertex. Two bounces with seven lights drop from 28 to about
   15 rays per sample. Validate with `path_trace_light_performance.gd`,
   `path_trace_many_lights.gd` and `path_trace_optimization.gd`; the first
   asserts the current reset behaviour and must keep passing unchanged.
2. **Cheaper terrain material on continuation hits.** When the payload cone is
   positive the hit is a continuation hit: use the owner tile colour, the
   vertex normal, the macro tap and the per-type roughness; skip transitions,
   junctions, cliff projection, relief and detail normals. The detailed-terrain
   delta bounds the gain at 15–30% of PT time on terrain-heavy views. This
   contradicts the comment at the terrain material entry that evaluates the
   same fields for primary and secondary rays; the raster-parity fixtures
   (`path_trace_terrain`, `path_trace_terrain_terminator`,
   `path_trace_grazing_normals`) need review for secondary-hit expectations.
3. **Shadow-ray roulette for tiny contributions.** Tried and reverted. A
   contribution-bounded roulette (threshold 0.02 radiance, unbiased, survivor
   contribution bounded by the threshold) on the local-light and emitter rays
   leaving continuation vertices passed every fixture but measured
   1.577 / 1.566 ms at 7 lights against 1.495 / 1.510 ms without it, and no
   change in the Foothills ray stage. After the one-light selection the
   remaining bounce shadow rays are cheaper than the extra estimate and
   random draw per vertex.
4. **Bounce texture footprint.** Implemented as `bounce_cone` (below). The
   remaining part of the proposal, accumulating the width along the path and
   bounding the detail fade by path length, is open.
5. **Transmission primary pass.** Implemented in three parts (below): the
   pass traces its camera ray against the dielectric mask alone and tests
   opaque occlusion with a bounded visibility ray; a reused still frame skips
   pixels that saw no dielectric and traces one refracted path instead of two
   for the others, with the history limit doubled to 63 frames so the
   accumulated noise is unchanged; and lighting constants left the pass's
   reuse signature, so daylight drift and flame flutter no longer reset the
   refraction every frame.
6. **Roulette in the two-bounce variant.** Balanced has no roulette; starting
   luminance-based roulette at depth 1 removes the second continuation ray and
   its 1 + N + 1 shadow rays for weak paths.
7. **RTXDI candidate radiance.** Implemented as a cheap target function:
   while candidates are generated and reservoirs are reused, an emitter's
   sample uses the material's constant emission (two buffer loads) instead
   of three vertex loads, the cutout alpha tap and the emission tap. The
   final shading of the selected sample (`di_exact`) still evaluates the
   textured, cutout-tested emitter, so the resampled estimate stays unbiased
   for any target function. Measurements are in the validation record.

8. **Ray Reconstruction output copies.** Implemented: under RR the ray
   programs write the four published images directly (`_ray_targets` in
   `path_trace_device.gd`), the RR pass and the ground helper read those
   images, and the per-frame copies in `reconstruct` are gone. The published
   RIDs stay stable; the presentation handoff binds the adopted images, and a
   same-size switch between RR and the denoiser rebuilds the ray descriptor
   set. `path_trace_rr_raw` and `path_trace_rr_resources` now assert the
   direct contract instead of byte-equal copies. Measurements are in the
   validation record.
9. **Controller CPU.** At 4K the Foothills frame is main-thread bound. Under
   `--ei-profile-rt` the controller now records `update_detail` (model
   replacement, presented first-person views, the native transform tracker,
   morph poses) and `cpu_frame_ms` / `cpu_render_ms`, so the next step can
   target the measured phase. The native tracker itself cannot be rebuilt on
   this workstation (no C++ toolchain). First step taken: the frame-constant
   phase builds the light tables from the present lights only and skips the
   per-light history comparison for unchanged tables (0.12–0.23 ms down to
   0.08–0.20 ms per frame depending on the light count; measurements in the
   validation record). Second step: the render-submission phase was almost
   entirely the NRD step, and most of that was a plan cache that missed every
   frame because REBLUR alternates its history pools; plans keyed by pipeline
   and resource list bring render submission from 0.48 to 0.34 ms. Scene
   update (about 0.45 ms, mostly the native tracker) and the native dispatch
   description (0.1 ms) are the remaining controller costs.

Not worth changing: visibility ray flags, sky and cloud evaluation, light
array indexing and the multi-sample loop (the presets use one sample).

## Temporal consistency

Whole-frame history resets remain the main flicker and noise-burst source
under NRD. Any moved local light, light-list change, hue change or intensity
change above 10% clears NRD, the direct filter, RTXDI reservoirs and the ground
helper. A carried torch or a spell projectile therefore restarted accumulation
every frame. Implemented now in the controller: a local light that moves up
to a tenth of its range per frame with an unchanged range is classified like
flame flutter (`_small_light_motion`), so the frame keeps its history with
the three-frame local limit and the existing NRD pack confidence shortens
history only where current local lights reach. Larger jumps, range changes,
hue changes, new or extinguished sources and list changes still reset the
frame. `path_trace_light_history`, `path_trace_many_lights` and the
many-light benchmark carry the new contract, including the jump cases. Fireflies have no
radiance clamp from depth 1 on; a per-vertex indirect luminance clamp is the
standard, biased remedy.

## Implemented now: one local shadow ray per continuation vertex

`direct_light_bounce` replaces the exhaustive local-light loop at every
continuation vertex (and in the SHaRC update pass after its first vertex).
It draws one light with probability proportional to its unshadowed reach at
the vertex (luminance times the finite-range falloff, the same weight the
four-draw scheme used above seven lights), traces one shadow ray and divides
by the selection probability, so the estimator stays unbiased. The primary
vertex keeps the exact sum, which the reconstruction sees directly. The
compact seven-light table and the extended table share the accessors, so
fixtures that build frames with either table behave the same.

Measured with `path_trace_light_performance.gd` (original river, probe
lights, two bounces, Low, 1280×720, NRD, 90 frames per block, two rounds in
ABBA order) on the RTX 4090 Laptop through Direct3D 12, PT GPU medians:

| Lights | Unchanged shaders | One bounce shadow ray | Change |
| --- | ---: | ---: | ---: |
| 7 | 2.479 / 2.472 ms | 1.890 / 1.895 ms | −24% |
| 16 | 2.743 / 2.746 ms | 1.999 / 2.000 ms | −27% |
| 64, static | 3.315 / 3.351 ms | 2.404 / 2.444 ms | −27% |
| 64, one moving | 3.369 / 3.370 ms | 2.454 / 2.462 ms | −27% |

Both rounds agree to within 0.04 ms. The unchanged pack also carries the
previous controller scripts, so the comparison is shaders plus the terrain
sunlight tolerance; the latter did not register on the river benchmark.

The new `path_trace_bounce_lights` fixture (registered, rendered) lights a
wall only through the floor and compares the all-lights estimate with the
sum of single-light renders for two, seven and sixteen sources.

## Implemented now: bounce-only material shortcuts

- Continuation hits skip the detail, painted and cliff relief normals on
  terrain and the painted relief and authored detail normals on objects
  (`terrain_material` and the closest-hit main). Colour, cliff projection,
  roughness and metalness are unchanged, so the material response at the
  bounce is the same; only the normal detail that belongs to a per-pixel
  footprint is left out. Proposal 2's larger step, a separate cheap colour
  path without transitions and cliff projection, is not implemented.
- `bounce_cone` widens the continuation footprint for diffuse lobes to
  0.15 rad, keeping the narrow `max(0.002, 0.02·roughness)` cone for glossy
  and metal lobes through the specular probability. Diffuse bounces now
  sample the mips the integrator would otherwise average over many samples.
- The any-hit alpha test uses that footprint's mip for continuation rays
  and, through `shadow_cone`, for the shadow and emitter rays that leave a
  continuation vertex. Camera rays and the visible surface's shadow rays
  still test mip zero, matching the raster scissor.

Measurements for these three changes are recorded in
[the object-material validation](../validation/object-materials-2026-10-28.md).

## Implemented now: terrain colour shortcut and lighter visible-surface loop

- Continuation hits on terrain keep each cell's authored owner tile and skip
  the edge, corner, transition, junction and cliff-neighbour colour blends
  (`continuation_hit` in the closest-hit program). Those blends hide seams at
  the visible surface; bounce lighting averages the seams over its cone, and
  each skipped blend saved two to six atlas taps per terrain hit.
- The triplanar detail normal skips planes below 2% of the n⁴ weight and
  renormalises, so flat ground pays one tap instead of three.
- The visible surface evaluates every local light exactly only up to four
  sources; five to seven now use the four stratified importance draws that
  crowded scenes already used above seven lights. The reported
  `local_light_shadow_samples` statistic follows the same threshold.

A trial that compared morph weights in place instead of allocating a weight
array per node each frame measured the same 0.11 ms morph-scan time, so the
cost is the per-node property calls, not the allocation; the trial was
reverted. The NRD dispatch loop, which assembled uniform objects and string
descriptor keys for every denoiser pass each frame, now keeps a per-slot plan
keyed by the pass's pipeline and resource references and only updates the
constants buffer while that key repeats (`_plans` in `path_trace_nrd.gd`);
its measurement is in the validation record. The remaining GDScript phases (render submission 0.54 ms, frame
constants 0.20 ms, presentation 0.16 ms) are spread over many engine calls
rather than one hotspot.

## Implemented now: terrain sunlight cache tolerance

The shared terrain self-visibility cache (`path_trace_terrain_sun.gd`)
retraced every terrain sample whenever the sun direction bytes changed. The
campaign clock advances the sun about 0.005 degrees per frame (one game hour
is 49.5 s), so the whole cache was re-dispatched every frame while nothing
visible changed. The cache now keeps its values until the direction has turned
0.1 degrees; reach and angular radius are still compared exactly, so radius
changes refresh immediately as before. A 0.1 degree turn moves a terminator
cast from 50 m by under 9 cm, below the reconstruction footprint.

`path_trace_terrain_sun_radius` gained three checks: a 0.03 degree drift reuses
the cached values byte for byte, a 0.23 degree turn refreshes them, and
returning to the point sun still refreshes.

Measured on the Foothills first-person location benchmark (4K output, 1080p
internal, NRD, Ultra, two processes per pack in base/changed/base/changed
order, six 180-frame blocks each): PT GPU medians 1.73–2.20 ms unchanged and
1.77–2.20 ms changed, frame medians 9.4–10.6 ms unchanged and 8.9–9.8 ms
changed. The cache dispatch is below the benchmark's resolution on this GPU;
the frame difference overlaps with ordering noise and is not claimed as a
gain. The change is retained because it removes a per-frame dispatch whose
cost scales with terrain sample count, not because of this measurement.

## Implemented now: refraction pass

The Quality preset enables `pt_refraction`, and any scene with water or glass
then runs the transmission raygen over the whole trace lattice every frame.
Three changes, measured with the new `path_trace_transmission_performance.gd`
(original river, Low, two bounces, 1280×720, `--ei-pt-tuning`, 90-frame
blocks in ABBA order on the RTX 4090 Laptop through Direct3D 12):

| Case | Previous shaders | Refraction changes |
| --- | ---: | ---: |
| Refraction off (control) | 0.60–0.79 ms | 0.60–0.82 ms |
| Refraction on, still view | 1.06–1.14 ms | 0.75–0.89 ms |
| Refraction on, camera turning every frame | 1.08–1.13 ms | 1.08–1.12 ms |

Ray-stage medians over four runs per pack. The still-view saving is the
one-path reuse: the refraction cost over the opaque pass drops from about
0.45 ms to 0.15–0.25 ms. The turning view traces two paths with no history,
as before, and is unchanged within noise.

- **Dielectric-only camera ray.** Dielectric placements already live on
  instance mask 8 alone. The pass now traces its camera ray with that mask
  and, only when it finds a dielectric, asks a bounded accept-first
  visibility ray on the opaque mask whether anything stands in front. Pixels
  without water or glass no longer traverse the opaque placements. The river
  view is mostly water, so this part did not register there; it bounds the
  cost of the pass in views with a single pane of glass.
- **Reused still frames.** The pass already keeps a per-pixel running mean
  while the view and scene are unchanged. Such a frame now skips every pixel
  whose terminal kind was zero last frame (its outputs already hold zeros)
  and traces one refracted path instead of two for the rest. The history
  limit rose from 31 to 63 frames: a 1/64 running mean of one path has the
  same steady-state variance as a 1/32 mean of two, so still water keeps its
  noise level. A fresh view still traces two paths. Invalid bounded paths
  keep their dielectric kind in the terminal image so they are traced again
  rather than frozen black.
- **Lighting outside the reuse signature.** The signature covered the whole
  frame block except the previous-frame matrices and counters, so the
  advancing campaign sun, a fluttering torch colour or a moving cloud phase
  reset the refraction history every frame in ordinary daylight play; the
  accumulation only ever engaged in frozen scenes. The signature is now the
  camera and projection, the trace settings, the region and the bounce count;
  lighting changes blend into the running mean, and abrupt changes arrive
  through the frame's history flag, which the controller clears exactly when
  its own lighting caches reset.

`path_trace_transmission_occlusion` (new, registered) builds water behind a
half-width opaque wall and checks the occlusion classification, the reuse of
still frames, the 63-frame limit, that sun, sky and local-light changes keep
the history while the cleared flag resets it, and that hiding or moving the
wall or moving the camera retraces every pixel in the same frame.
