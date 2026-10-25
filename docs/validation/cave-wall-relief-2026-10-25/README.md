# Cave wall shading relief

This follow-up to `56774890` addresses the smooth vertical lighting bands left
on the Gipat cave entrance after correcting its texture projection. It uses
the same `zone5_1` / `gz5g` camera and isolated GPU Lab profiles as the
[previous validation](../cave-wall-2026-10-25/README.md).

## Diagnosis and original comparison

The previous build already had detail along both texture axes. Removing
lighting exposes that detail in [diagnostic-albedo.png](diagnostic-albedo.png).
Replacing the colour with gray retains long, smooth lighting bands in
[diagnostic-gray.png](diagnostic-gray.png). The wall's shading normals have
little variation vertically: the new actual-scene regression measures
0.003661 mean channel difference over a 24-pixel vertical offset. It fails
that assertion against the preserved `56774890` pack while all 15 earlier
assertions continue to pass. [before-result.json](before-result.json) records
the exact executable, pack, fixture and failing check.

The [geometry view](diagnostic-geometry.png) also shows elongated original
triangles. Their shape contributes genuine vertical folds; this change adds
surface shading relief, not geometry displacement or a new silhouette.

The original code/decompiler and Wine comparison is retained in the
[earlier evidence](../cave-wall-2026-10-25/README.md#reproduction-and-original-comparison).
The original executable uses its authored terrain UVs and lighting data and
visibly stretches the cave textures. The additional projected wall material
and its missing raster relief are remake features, so there is no original
implementation of this relief to reproduce. The original Wine camera was
not pixel-matched; it is a behavioural comparison, not an image oracle.

## Implementation

Eligible cliff surfaces now use two scales of world-space rock relief. The
coarser ridged field supplies broad contours; a smaller field breaks up those
contours. Both use analytic derivatives of the existing deterministic noise.
Rounded ridges retain continuous normals. Projection follows the same wall
axes as the albedo. No new texture or GPU allocation is needed.

The perturbation is tangential, bounded, and constrained to remain inside
both the geometric face and viewing hemispheres. Each scale fades as its
footprint becomes unresolved; the existing distance and cliff eligibility
fades still apply. Ground contacts reconstruct the same relief, including
orthographic viewing directions. Raster, Vulkan PT and DX12 PT share the
same field and limits. Terrain vertices, collision, authored normals, tile
codes, albedo sampling and floor appearance remain unchanged.

PT previously evaluated four complete projected donor fields to obtain a
small colour-derived bump. The common analytic relief replaces those reads,
so the visible receiver and traced material use the same shading. Ordinary
terrain keeps its existing colour-derived and procedural detail.

## Validation

The final actual-scene normal variation is 0.030408, versus 0.003661 before.
The floor's mean colour difference is 0.000000817. These are targeted checks
for the reported failure and floor preservation, not a general beauty score.

| Suite | Backend | Passing checks |
| --- | --- | ---: |
| Actual cave, PT, SHaRC/NRD, floor and geometry | Vulkan / DX12 | 16 / 16 |
| Independent raster/PT colour and normal comparison | Vulkan / DX12 | 117 / 117 |
| Pattern, relief continuity and camera anchoring | OpenGL | 17 |
| Contacts, water, clouds and weather | Vulkan / OpenGL | 87 / 20 |
| Material identities and exclusions | Headless | 82 |
| Runner / PT qualification unit tests | CPU | 8 / 24 |

SHaRC's 25 lifecycle/fallback checks also passed after adding the relief;
the subsequent change only rounded the relief ridges. The final actual cave
tests and benchmark additionally exercise cache creation, use and teardown.
Both shader manifests and all three closest-hit SPIR-V modules validate.

The registered rendered suites include the actual cave, the independent
raster/PT material comparison and the wall pattern/relief continuity fixture.
The new tests cover broad vertical normal variation, outward unit normals,
noise-cell/ridge continuity, world anchoring during camera movement, flat
surfaces, distance fading and unresolved footprints. Existing atlas rotation,
mip, donor corner, material lifecycle, floor and geometry checks remain.

An initial ridge width failed the continuity limit (0.105882 versus 0.1).
Increasing the ridge rounding reduced the maximum adjacent-pixel jump to
0.070588; the test limit was retained. A fixture variable-name parse error
was corrected before the passing runs. These exploratory failures are not
counted as passing validation.

Final receipts, source hashes, numerical results and timings are in
[summary.json](summary.json). Screenshots use a capped visual-inspection
session; their FPS counters are not benchmarks. The performance runs use
GPU Lab's exclusive heavy workload, with Low and High measured on the same
automatically assigned device, 40 warm-up and 120 measured frames per ABBA
block at two and four bounces. All profiles keep the cursor free, show FPS,
and mute sound. No package has been published.

## Final PT cost

On the RTX 3090 Ti, at a 1920×1080 window:

| Quality | Bounces | SHaRC Off | SHaRC On | SHaRC change |
| --- | ---: | ---: | ---: | ---: |
| Low | 2 | 5.326 ms | 5.908 ms | +10.9% |
| Low | 4 | 6.232 ms | 6.515 ms | +4.5% |
| High | 2 | 129.242 ms | 87.027 ms | -32.7% |
| High | 4 | 137.109 ms | 90.387 ms | -34.1% |

Low traces at 50% resolution with one sample/pixel; High traces at full
resolution with four. Values average the two block medians, including cache
update/resolve and reconstruction. Both quality runs pass all 26 checks.

The previous same-camera, same-device High results were 220.502/234.061 ms
with SHaRC Off and 151.051/155.536 ms with it On. This relief version is
substantially cheaper in that scene. The comparison uses separate runs,
not a general FPS promise. SHaRC still helps this High-quality workload,
while its overhead slightly outweighs the saving at Low; it remains optional
and Off by default. Raw [Low](cave-low-performance.json) and
[High](cave-high-performance.json) results are retained.
