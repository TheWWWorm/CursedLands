# Cave wall contours

The tall natural wall faces now bend between their original anchors, reducing
the broad vertical lighting bands in the `zone5_1` cave. The change extends
the existing optional cliff treatment and retains its material classification,
world-space projection and shading relief. Raster, PT and SHaRC use the same
retained wall patches.

## Reproduction and original comparison

The previous `2b8103e7` build has visible rock detail but still produces broad
light/dark columns. The fixed-camera regression measures the lit output,
rather than assuming that more normal-map detail removes the bands. The
unchanged executable with the preserved old pack fails four of its fourteen
assertions: PT, cached PT, raster band contrast, and the required improvement
relative to a straight-face control. The other assertions still pass.

The camera and hero match the previous cave fixtures: camera
`(20.15,17.51792,-76.1)`, hero `(14.15,10.51792,-83.1)`, FOV 65, 1920×1080.
The region `x=660..1179, y=80..239` covers the tall back wall. Each column's
mean RGB value is divided by a 129-column local mean; the standard deviation
measures band contrast after removing exposure and broad lamp falloff. Simply
darkening the wall cannot pass. The corrected and straight-face raster
captures retain the same materials, lighting and settings. Their difference
therefore confirms that wall contour changes address these bands.

The original-code/decompiler and Wine observations are retained in the
[original comparison](../cave-wall-2026-10-25/README.md#reproduction-and-original-comparison).
Original `game.exe` SHA-256 is
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
The nine-vertex terrain grid and fixed UV lookup are confirmed by the saved
decompiler evidence, and the original cave's stretched walls were observed
under Wine 11.20. Its camera is not pixel-matched. Curving the remake's visual
wall mesh is an enhancement; it does not reproduce an original smoothing
algorithm. The original collision and navigation heightfield remains exact.

## Geometry and lifetime

Only classified natural-rock triangles spanning more than three metres in
height are subdivided. Shared filtered height and gradient fields bend their
interiors toward a smooth horizontal contour, with offsets limited to 0.6 m.
Original vertices and heights stay fixed. Short edges, flat ground and edges
touching unsupported tiles remain stationary. Eligibility uses the original
tile address, including when signed MPR offsets shift an anchor past a metre
rounding boundary. Normals blend toward the contour while preserving their
authored values along stationary edges.

Each patch retains its tile identity, atlas data and material attributes.
The patches are prepared once and reused by whole sectors, culled pieces,
snow deformation and ray tracing. Snow keeps its original contiguous input
layout; toggling cliffs preserves active footprints and updates the retained
source mesh used when they expire. Ray-tracing snapshots and ground caches
invalidate when the cliff owner changes, including water-only ray tracing.
Disabling the option restores the exact original terrain/contact pixels.

Small overhangs are possible between fixed anchors. The geometry regression
checks true 3D face orientation and horizontal cross-section intersections;
XZ projected area alone would incorrectly classify an overhang as an inverted
wall. Shared-edge continuity, bounded offsets, unsupported boundaries, floor
positions, material identities and deterministic rebuilds are also checked.

## Regression interpretation

The existing composed-effects test formerly cleared only the GPU eligibility
texture. It now supplies the same empty eligibility to the CPU mesh builder
as well. Its exact-pixel unsupported/restoration assertions are unchanged.
This exercises both consumers of the classification instead of leaving the
new geometry active in a supposed unsupported-terrain control.

A new shifted-boundary fixture fails on the first contour implementation
(nine boundary vertices moved), then passes after using logical tile
addresses. The registered sun-shadow fixture has fourteen assertions; its
new manifest entry was corrected from an initial count of sixteen. No
sun-shadow assertion was removed or relaxed.

Graphical checks use GPU Lab with automatic GPU assignment, isolated profiles,
free cursors, FPS enabled and muted audio. Windows checks use a dedicated Wine
prefix and the DirectX 12 backend. These capped screenshots are visual
evidence, not performance benchmarks. The additional wall triangles have a
rendering and acceleration-structure cost; earlier SHaRC timings do not
measure this geometry change. No new shader binary or artwork is introduced.

## Final visual results

| Lit output | Previous pack | Final Vulkan | Final DX12 |
| --- | ---: | ---: | ---: |
| Raster band contrast | 0.348979 | 0.139467 | 0.139459 |
| PT band contrast | 0.359049 | 0.174307 | 0.174401 |
| SHaRC band contrast | 0.359636 | 0.174352 | 0.174437 |
| Floor mean absolute difference | 0 | 0 | 0 |

Band contrast falls about 60% in raster and 51% in PT/SHaRC in this view.
Natural large folds remain; this is not a claim that every vertical formation
has disappeared. The straight-face control still reproduces the old bands.
[Before](before-sharc.png), [after](after-sharc.png), and
[final raster](after-raster.png) captures are unedited engine output.
Raw values are saved for [Vulkan](vulkan-metrics.json) and
[DirectX 12](dx12-metrics.json).

The fixed PT snapshot contains 126,141 terrain triangles, versus 33,010 before.
It fits the existing scene limit of 320,000 triangles, but this geometry costs
more than the original mesh. No FPS improvement or unchanged performance is
claimed. Both ordinary PT and cached PT retain NRD, valid authored material
identities, and successful scene preparation.

## Completed checks

| Suite | Backend | Passing checks |
| --- | --- | ---: |
| Contours, unsupported/shifted edges, snow lifecycle | Headless | 31 |
| Actual lit cave bands and straight-face control | Vulkan / DX12 | 14 / 14 |
| Existing cave material, relief and floor checks | Vulkan / DX12 | 16 / 16 |
| Raster/PT material and normal agreement | Vulkan | 117 |
| SHaRC lifecycle, NRD and fallback | Vulkan | 25 |
| Cliff material classification and exclusions | Headless | 82 |
| Pattern, relief continuity and camera anchoring | OpenGL | 17 |
| Sector attributes, culling and retained meshes | Headless | 17,966 |
| Native/script snow mesh agreement | Headless | 3,044 |
| Terrain/contact/water/cloud/weather composition | Vulkan / OpenGL | 87 / 20 |
| Terrain sunlight shadows | Vulkan | 14 |
| PT topology / topology budget / source cache | Vulkan | 130 / 13 / 12 |
| Regression runner unit tests | CPU | 8 |

All fifteen registered native suites pass against the same exported pack.
The [full receipts](regressions.json), [geometry receipts](mesh-results.json)
and [summary](summary.json) record their engine, pack and source hashes.
The Windows [contour](dx12-contours-receipt.json) and
[existing-cave](dx12-cave-receipt.json) receipts identify the DirectX 12
commands and matching Windows pack. Changed production scripts were compared
byte-for-byte with the export staging tree; their hashes are recorded in
[source-hashes.json](source-hashes.json).
