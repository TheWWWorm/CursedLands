# Cave wall mapping and repetition

The reported view is the Gipath cave entrance (`zone5_1`, campaign `gz5g`).
The fixed camera is at `(20.15,17.51792,-76.1)`, looking toward the party at
`(14.15,10.51792,-83.1)`, in a 1920×1080 window. The task branch includes SHaRC,
sparse scene uploads, and local main through `fa5c65e8`; neither this work nor
its test artifacts were published.

## Reproduction and original comparison

The original projection gate rejected mixed stone/dirt/grass tiles. It also
used authored lighting normals: several photographed wall faces have actual
upness around 0.08 while their lighting normals have upness around 0.85. Thus
even some classified plain stone walls retained stretched top-down UVs.

Ten camera-ray probes identify the visible back wall. Before the change only
two had supported material identities. None of the 15 selected steep two-rock
transition tiles was admitted. The actual cave regression fails five of its
15 assertions against the pre-fix pack: missing transition coverage, missing
corner payload, unchanged striped output and insufficient vertical detail.

Original `game.exe` SHA-256:
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
Ghidra 12.1.4 observations are saved in [original-mesh.json](original-mesh.json)
and [original-uv.json](original-uv.json). At `0x6c1bc0`, the mesh builder decodes
the tile index and quarter-turn, calls `0x6c5380`, and copies nine UV pairs with
V inversion into its 3×3 terrain grid. The lookup has no vertex-height input.
The inference is that a fixed authored UV span covers taller wall triangles;
this is decompiler evidence, not recovered original source.

The unmodified original executable was also run under Wine 11.20 in GPU Lab,
using a dedicated prefix and a copied save. Console travel reached `gz5g` and
showed vertically stretched cave textures. [original-wine.png](original-wine.png)
records that observation. Its camera orientation differs from the remake
fixture, so it is not a pixel-matched visual reference. The remake's periodic
wallpaper artifact was introduced by the first projection fix and has no
corresponding original implementation to compare.

## Final mapping

Cliff admission follows actual triangle slope, without changing terrain
vertices, collision, authored lighting normals or tile codes. Flat ground and
unsupported artwork retain their original sampling. Verified mixed tiles use
four rotated material corners and plain donors actually present on the map.
Donors are chosen by usage count, with stable slot-order ties. Existing plain
tiles keep their own variant and rotation. Conflicting corner identities,
missing donors, unknown images, water and snow/ice are rejected.

The cave supplement is tied to three exact original-image fingerprints and
the pinned editor metadata in renderer commit
`0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`. Its stone, dirt and swamp identities
are independently reproduced by `tools/benchmarks/check_cave_cliff_metadata.py`.
The source table credits ei-mapper-endurance `af24d45`; it is editor metadata,
not original game source. Modified/modded images do not acquire these rules.

Simply wrapping the same donor every two metres fixed the vertical stretching
but produced the reported wallpaper effect. The final sampler instead blends
two differently oriented, mirrored projections. A gentle continuous warp and
an irregular blend vary their appearance in world space. Mirroring keeps the
non-seamless original tile edges continuous. The pattern stays fixed when the
camera moves; it needs no generated artwork or new texture allocation.

Raster and PT use the same integer noise hash, material weights and mapping.
Raster derivatives include the warp and mirror direction; PT adjusts its
footprint and retains the atlas gutter limit. Projected PT relief samples the
same material. Projection calculations are shared across corner donors and
neighbouring cells. Four donor codes travel in an optional aligned terrain
payload, flagged per tile; plain snapshots retain their earlier layout.

## Final PT cost

Final static cave measurements use an RTX 3090 Ti at a 1920×1080 window,
Off/On/On/Off order, 40 warm-up and 120 measured frames per block. Values
average the two block medians and include tracing, cache update/resolve and
reconstruction. Low uses 50% resolution and one sample/pixel; High uses full
resolution and four samples/pixel. Actor animation is paused. These are PT
GPU times, not claims about gameplay FPS or scenes with frequent cache resets.

| Quality | Bounces | SHaRC Off | SHaRC On | Change |
| --- | ---: | ---: | ---: | ---: |
| Low | 2 | 9.597 ms | 9.993 ms | +4.1% |
| Low | 4 | 11.192 ms | 10.809 ms | -3.4% |
| High | 2 | 220.502 ms | 151.051 ms | -31.5% |
| High | 4 | 234.061 ms | 155.536 ms | -33.5% |

SHaRC saves about 31–34% of PT GPU time in this expensive High-quality cave.
Low is close to break-even and two bounces are slightly slower with the cache.
The setting therefore remains optional and Off by default.

Correcting formerly skipped walls, sampling mixed materials and removing
repetition adds work relative to the old stretched mapping. This is a visual
quality correction, not a claim that the combined change is universally faster
than that old rendering. The original SHaRC table used the earlier materials
and different GPU assignments; its absolute cave times should not be compared
as a controlled wall-cost benchmark. On the same RTX 3090 Ti, sharing projection
calculations reduced the first anti-repetition attempt's Low two-bounce Off
result from 18.796 ms to 9.597 ms, with unchanged albedo and passing parity tests.

Raw final runs are in [cave-low-performance.json](cave-low-performance.json)
and [cave-high-performance.json](cave-high-performance.json). GPU Lab jobs:
`9c351b1228384608` (Low), `09aaf7b100414edb` (High).

## Regression evidence

- `terrain_cliff_blends`: 82 assertions, including the existing five-map
  coverage, four rotations, material boundaries, invalid geometry, conflicting
  metadata, missing donors and modified-atlas rejection.
- `terrain_cliff_pattern`: 10 rendered assertions. A deliberately non-seamless
  diagnostic texture checks wrap continuity, retained contrast, nonidentical
  patches at two/four-metre offsets and exact world anchoring after camera
  translation. The wallpaper version fails seven assertions. The registered
  runner also executes this fixture successfully.
- `path_trace_terrain`: 108 assertions on Vulkan and DX12/Wine, comparing
  actual traced albedo with the raster sampler, including all rotations,
  multiple atlas sizes, coarse mips, six corner masks, four materials,
  misleading lighting normals and distant/negative world coordinates.
- `terrain_cave_wall`: 15 assertions on the real photographed scene, covering
  all ten wall probes, all 15 selected transition tiles, PT payload bytes,
  ordinary PT, SHaRC/NRD, raster, floor preservation, disable/restore and
  unchanged geometry. The registered fixture specifies Forward+ because its
  PT checks cannot run with the runner's default Compatibility renderer.
- Related contact/water/cloud/weather checks pass in Forward+ (87 assertions)
  and OpenGL (20); SHaRC's GPU lifecycle/fallback regression passes 25.
- CPU runner tests pass 8 assertions and PT qualification tests pass 24.
  All three cave metadata tables reproduce. Both shader manifests validate,
  and all three closest-hit SPIR-V modules pass Vulkan validation.

An intermediate HLSL form with dynamic vector writes crashed the NVIDIA
Vulkan compiler while DX12 passed. Fixed-lane donor merging avoids that
failure and is covered on both backends. One pre-optimization combined-effects
run timed out before producing its first capture; the final shared-projection
version completed all 87 checks in 39 seconds. An attempted debugger attach
was unavailable under the workstation's ptrace policy. No driver or system
settings were changed; a definitive cause for that intermediate timeout was
not established.

All graphical work uses GPU Lab with automatic GPU assignment, isolated
profiles, visible/free cursor, FPS enabled and muted audio. Performance jobs
run exclusively on their assigned GPU. Screenshots taken during warm-up or
concurrent visual tests are not FPS benchmarks. Machine-readable results,
final images and timing details are retained alongside this report.
