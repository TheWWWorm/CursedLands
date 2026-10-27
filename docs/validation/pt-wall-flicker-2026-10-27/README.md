# Moving-camera PT wall flicker

The trailer report identified intermittent dark patches around 13, 24 and
31 seconds, usually on walls and nearby surfaces. The fix changes the shared
ray-traced receiver reconstruction in `scene_raytrace_shader.gd`; it applies
to gameplay throughout the game, without a scene-specific override.

## Confirmed cause

An unchanged 1.33.0 Linux build reproduced the snowy fort wall flashes under
the trailer's moving camera. Holding that camera still was stable. Readbacks
showed steady traced diffuse/direct/specular lighting, while a diagnostic
receiver shader showed whole wall facets intermittently reverting to ordinary
lighting. A second diagnostic isolated the rejection to the world-plane depth
test, rather than material or normal matching.

The receiver unprojected a near-plane point, divided by homogeneous W, then
subtracted the camera's world position. With the 0.05 m near plane and map
coordinates hundreds of metres from the origin, this subtraction lost
precision. Scaling the small resulting vector to the wall's depth amplified
the error beyond the matching tolerance as the camera moved.

Perspective reconstruction now uses the far endpoint in homogeneous space.
Subtracting `eye * w` before depth scaling avoids the near-point cancellation
and also avoids dividing by a small or zero far-endpoint W. Orthographic
reconstruction, receiver rejection tolerances, material boundaries, lighting
history, and ray transport are unchanged.

## Regression evidence

`path_trace_perspective_receivers` renders the production receiver shader
against an independently generated analytic wall guide, including FP16 depth.
It samples 24 moving camera poses at the origin and at the snow-fort world
coordinates, with 320- and 640-pixel trace grids. The grazing wall's measured
interior remains within the normal receiver radius. The test requires green
matched coverage, so missing/black output also fails.

The released build fails three of 97 checks; at pose 85, about 73.5% of the
measured wall falls back. The fixed build passes all 97, with zero fallback
in every measured region. The existing orthographic receiver test is now
registered as well. Related results:

| Registered case | Checks | Failures with fix |
| --- | ---: | ---: |
| `path_trace_perspective_receivers` | 97 | 0 |
| `path_trace_receivers` | 19 | 0 |
| `path_trace_material_receivers` | 7 | 0 |
| `path_trace_cover_receivers` | 65 | 0 |

The 180-frame 1920×1080 snow-fort replay uses identical camera motion before
and after. In the fixed wall ROI (x=500, y=80, width=60, height=200), the largest
one-frame downward deviation from both neighbours falls from 0.0619869 to
0.0000873 in normalized grayscale. This is a targeted wall metric, not a
whole-scene image-quality or performance benchmark.

A full 300-frame 3840×2160 replay, with a 1920×1080 PT trace grid, keeps PT
active on every frame. Against the original 4K trailer source, the equivalent
wall ROI's largest one-frame dip falls from 0.0835972 to 0.0000259. The retained
replay is encoded at 60 fps from fixed-step capture; it is not a real-time FPS
measurement.

The rainy tower replay retains matched PT coverage over all 180 frames of
the measured wall, with native rain and wet surfaces active. A separate
180-frame first-person traversal keeps PT active throughout. Its upper-cliff
region has no pixels more than 20/255 darker than both adjacent frames after
allowing a two-pixel neighbourhood for camera motion. The first-person bow
is excluded from that wall measurement because its normal animation enters
and leaves the lower-right foreground.

The night settlement replay also keeps PT active for all 180 frames. Its
measured cliff region has no downward outliers above 8/255 under the same
motion-neighbourhood check. Native fire animation remains present.

Tests and captures run through GPU Lab with automatic GPU assignment and
isolated muted profiles. Local reports, reproduction scripts, diagnostic
images and a synchronized before/after video are retained under
`local/validation/pt-black-flicker-20261027/` in the EI workspace.

## Original comparison and scope

Original-game parity is inapplicable to this calculation: the original game
has no remake PT/NRD receiver path. The unchanged released remake and the
analytic plane are the controls; no new original-game Wine comparison is
claimed. Original assets and gameplay are unchanged. This is a source fix,
not a published release or a re-edit of the existing trailer.
