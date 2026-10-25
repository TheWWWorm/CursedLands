# PT lighting, camera continuity and performance — 2026-10-25

Runtime source: `d8248af0ced24388d1492b9425903a7887212b38`. Game tree:
`1deae90d960592b374d3f1f8d9c3b29d8e045249`. Local development build based on 1.28.0, including
the upstream Windows hotfix `bab580bd`. No release or tag has been published.

## Torso lighting across camera changes

First person replaces the original torso with a closed-collar mesh. Previously,
returning to third person restored the original raster mesh while PT masked its
old closed-collar instance until a full world rebuild completed. The torso then
used conventional fallback lighting beside limbs still receiving PT.

The ray scene now retains both registered torso variants and switches their
existing instance masks immediately. Only one is active for the camera. History
matching distinguishes both mesh identities, and leaving first person explicitly
restores the authored transform and clears its lighting offset, including idle
poses that do not otherwise notify the native tracker. Actual equipment changes
still invalidate geometry. No additional rays or shader passes are introduced.

The previous build fails 20 assertions in the camera-variant regression. Both
native and script paths now pass repeated switches, exactly one active torso,
placement/lighting-offset restoration, unique history mapping and real equipment
replacement. The real rainy rear view is checked before any pending world
rebuild and with Low PT/DLSS Performance and a converged reference. Unlit albedo
captures show that the remaining garment folds are authored texture shading;
the isolated diffuse pass distinguishes them from the actual lighting.

The coverage fixture excludes HUD icons and accounts for filmic grading of its
green/magenta output. Its initial absolute-RGB classifier was invalid and is not
counted as a passing test. The corrected fixture retains the 2% missing-coverage
limit. The final movement fixtures also count missing torso receivers every
sampled frame, rather than checking only transforms of instances already present.

## Other included corrections


The desktop sun now carries the same sunlight identity used by the receiver
shader. Previously that identity was assigned only to the held-sun path, so
nearby grass removed traced direct sun without adding its native shadowed sun
back. This caused a near/far colour mismatch. Terrain now consumes the same
separate direct-sun signal as grass and passes only that component through
native grass shadows, fading out over 18–24 metres. Indirect and glossy light
remain in PT. No extra rays, grass acceleration-structure geometry or shadow
maps were added.

Static scenery could enter the tree before delayed window setup enabled global
physics interpolation. In this Godot build, pending static transforms then
missed their ordinary renderer upload. PT read the correct Node3D placements,
while raster bounds/draws stayed stale: these were real scene objects, not phantom
PT geometry. Interpolation is now established before startup scenes load; enabling
it later first flushes pending Node3D transforms. The baseline fails five of eight
startup/toggle checks; both corrected APIs pass all eight. The fix covers the
demonstrated direct-start/toggle order, not a claim that every menu launch failed.

Flame flutter previously shortened NRD history over the entire view. At 30 FPS
its fractional 1.8-frame budget was truncated to one. The pack shader now applies
lighting confidence per receiver from finite local-light influence, preserving
normal history on unrelated surfaces. Nearby flame response follows the rendered
frame-rate budget; slow weather transitions retain two samples. NRD history
repair ends at the corresponding short local history length, avoiding repeated
spatial replacement of already valid local light. Abrupt changes/extinguishing
still clear stale illumination. A specialization guard keeps the application
pack/resolve SPIR-V on the same unmodified path as the SDK passes; the unguarded
dynamic-light-table variant triggered a Vulkan driver shader-compiler crash.

Queued scene gathering also skips nodes removed from the tree or meshes cleared
between collection and packing. The live cave diagnostic traced invalid global
transform reads to this deferred step; its stronger regression additionally
crashed the preceding build when a queued mesh was cleared. Native/script
first-person updates now ignore detached models and parts until reattachment. Godot can report is_visible_in_tree=true for a detached
node; native and script trackers now also require actual tree membership.

First-person camera clearance moves the visible body by a few centimetres while
its complete shadow/GI copies remain at the authored pose. Rays from the shifted
surface could start inside that hidden body, producing black arms and torso.
The PT device now keeps a small per-instance world-space lighting offset and
evaluates illumination at the matching authored surface. Camera depth, material
sampling and motion reprojection stay at the displayed surface; complete body
shadows and reflections remain available to the world. Offsets are cleared on
camera-mode/lifecycle changes and uploaded only when changed. The allocation is
16 bytes per instance (at most 64 KiB); it adds no ray or acceleration geometry.
An analytic overlap fixture checks sunlight/sky restoration, unchanged camera
depth, real external occlusion and offset removal on both APIs.

Original caves include passages without lamps and rely on their authored ambient
lighting. PT previously dropped that term along with the outdoor sky, making the
entrance almost black. Cave palette channels now carry the original ambient
colour as a diffuse minimum, applied once at the primary receiver. Sky misses
remain black; the minimum is neither recursively bounced nor added on top of
stronger traced light. A raw transport test verifies coloured ambient, a truly
black level when no ambient is supplied, and unchanged brighter/outdoor lighting.
The live cave capture is checked alongside the conventional rendering. The
corrected walking-body capture removes the black self-occlusion stripe.


## Exact final-pack verification

**1187 checks pass** on the final Linux/Windows exports, with
runtime and fixture hashes in the companion JSON. The shader/native binaries are
unchanged from the preceding illumination revision; the final change is in scene
membership and instance updates. All graphical runs use isolated GPU Lab jobs;
profiles keep the cursor free, FPS visible and game audio muted.

The export stage matches tracked sources except Godot's generated UID/default
normalization of the bridge00, columnruins01 and stone03 PNG import descriptors.
Their compression/mipmap settings are unchanged. The pinned NRD/source check
verifies 16 SDK shader binaries; the PT shader check verifies all 18 binaries.
Shared fixture manifests in the JSON retain the exact per-file hashes without
duplicating the same complete manifest for every run.

| Run | Checks |
| --- | ---: |
| `linux-path_trace_topology` | 130 |
| `linux-water_raytrace_native` | 291 |
| `linux-path_trace_nrd_motion` | 42 |
| `linux-path_trace_body_illumination` | 13 |
| `linux-path_trace_authored_ambient` | 7 |
| `linux-path_trace_grass_receivers` | 12 |
| `linux-path_trace_contacts` | 59 |
| `windows-path_trace_topology` | 130 |
| `windows-water_raytrace_native` | 291 |
| `windows-path_trace_nrd_motion` | 42 |
| `windows-path_trace_body_illumination` | 13 |
| `windows-path_trace_authored_ambient` | 7 |
| `windows-path_trace_grass_receivers` | 12 |
| `windows-path_trace_contacts` | 59 |
| `back-rain-dx12-dlss-v2` | 23 |
| `walk-cave-vulkan` | 27 |
| `walk-swamp-dx12-dlss` | 29 |

| Live route / API | Actual travel | Sampled frames | PT loss / NRD loss / pose mismatch / missing torso |
| --- | ---: | ---: | --- |
| `gz5g` / vulkan | 56.6 m | 2008 | 0 / 0 / 0 / 0 |
| `gz4g` / d3d12 | 70.6 m | 2236 | 0 / 0 / 0 / 0 |

Routes use real movement, first/third-person changes and looking down. The swamp
includes rain, direct input and crouch/prone/standing changes. These 30 FPS capture
runs are not performance measurements. The separate rainy rear diagnostic freezes
one pose, camera and scene lighting for material/lighting comparisons.

The previous illumination revision passed 1367 checks,
including daylight, dynamic lights, both 30/60 Hz torch response tests, scenery
startup, front skin/face, grass-caster comparisons, dark body and cave references.
Those results have different pack hashes and are retained under
`previous_revision_qualification_not_final_pack`; they are not added to the final
count. Earlier waterfall and dead-city routes are likewise identified separately.

## Performance

One GPU Lab heavy allocation runs A/B/B/A on
`NVIDIA GeForce RTX 3090 Ti`. Windows EXE plus the original DLSS SR SDK,
4K output, DLSS Performance, 1920×1080 raster, 960×540 Low PT, two bounces,
one sample per pixel and frame generation off. Fixed forward/ground views,
uncapped rendering, frozen simulation, live flame illumination; 1,080 measured
frames per variant/view. Values are medians of six round medians.

| View | Baseline frame ms | Final frame ms | Change |
| --- | ---: | ---: | ---: |
| forward | 10.278 | 9.950 | -3.19% |
| ground | 9.809 | 9.852 | +0.44% |

The baseline already contains sun identity and scenery placement fixes. This
comparison covers the subsequent grass-shadow, denoising, body/cave illumination
and torso-continuity changes. CPU/GPU breakdowns, p95s and round ranges are in the
JSON. These measurements describe these views on this GPU, not all game scenes.

## Scope

The Windows EXE and original DLSS Super Resolution SDK were tested via
Proton/VKD3D on Linux. Native Windows and DLSS Frame Generation remain untested
here. No modified or withdrawn NVIDIA package is included. Test assets are
checked with `tools/check_release_assets.py` before delivery. No new player text
or options were introduced. The covered routes do not establish that every
possible artifact or shimmer has been eliminated.
