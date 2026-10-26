# NRD reconstruction and travel performance

The local 1.28.0 previews integrate NVIDIA NRD 4.18.0 REBLUR_DIFFUSE_SPECULAR
into the existing Windows DX12 and Linux Vulkan path tracer. NRD itself does not require
an engine change; the combined Windows preview also includes the separate DLSS
engine integration. Published 1.27.0 artifacts remain unchanged.

## Renderer boundary

`PathNrd`, a small GDExtension, runs the upstream CPU dispatch planner. Godot's
RenderingDevice owns the shader pipelines, descriptors, textures, barriers and
GPU dispatches. No second graphics device, NRI layer or driver-specific runtime
is created. The native library loads only when constructing a path-tracing
device on supported x86-64 desktop platforms.

Responsive accumulation supplies unfiltered diffuse and indirect specular
radiance, secondary hit distances, world-space rigid motion, linear view depth,
world normals, roughness and deformation confidence. The pack and resolve
shaders use NRD's actual material-factor and radiance-packing functions.
Primary camera distance is never used as the secondary hit distance. Direct
sun/point-light specular highlights are restored after denoising: their known
lighting direction must not inherit an unrelated secondary reflection's blur
or motion. Diffuse light, including soft shadows, remains denoised.

History responds to real lighting changes and resets on camera cuts, resize
and explicit mode changes. Compatible responsive region replacements transfer
the same NRD instance and permanent textures, rebinding only boundary inputs.
Stable mesh/material surfaces retain their last visible transforms and history.
Changed, newly visible and deformed surfaces receive zero confidence. Sky pixels are cleared explicitly. Public output
textures retain stable handles; replacement pools are private until complete.
Still scene retains the custom exact progressive accumulator. Unsupported or
failed NRD initialization falls back to the existing custom reconstruction.

## Directional SH/SG mode

The RT/PT options page offers **PT denoising: Radiance / Directional**. Radiance
keeps the established `REBLUR_DIFFUSE_SPECULAR` path and is the saved-setting
default. Directional selects the SDK's `REBLUR_DIFFUSE_SPECULAR_SH` planner,
packs both SH0/SH1 pairs with `REBLUR_FrontEnd_PackSh`, and resolves the filtered
signals with `NRD_SG_ResolveDiffuse` and `NRD_SG_ResolveSpecular`. The existing
Still scene accumulator and failure fallback remain independent of this choice.

The tracer records two additional RGBA16F targets. Each contains a
radiance-weighted mean light direction and its energy, using NRD's YCoCg
luminance weights. Local diffuse lights and primary emissive-light proposals
use their actual sampled directions. Every contribution after the first
continuation, including SHaRC cache results, uses that first continuation's
direction at the receiver. Multiple samples retain the magnitude of their
first moment; opposing directions are never normalized into a false sharp
lobe. The cave ambient floor has no directional moment. Sun diffuse and
analytic specular stay in their existing separate direct-light reconstruction.
Misses clear both new targets.

The native adapter describes both modes explicitly. Changing modes releases
and rebuilds NRD pools, and a region replacement cannot adopt another mode's
history. Both sets of shader permutations are built from the same pinned SDK.
`--ei-pt-nrd-radiance` provides a same-build diagnostic override. The production
controller passes the selected mode through its render-thread update packet;
the `nrd_directional` statistic reports an active directional denoiser.

SG resolve is an approximation and can change brightness. It resolves at the
PT tracing resolution, before the existing presentation upsampling. The first
moment is luminance-only; material demodulation scales the colour signal and
does not recompute a separate angular distribution for each colour channel.
The controlled off-axis lamp regression measured 0.496 mean diffuse brightness
with SH/SG versus 0.588 with the radiance mode on the tested Vulkan runtime.
Directional mode also allocates four additional external NRD images and the
SDK's SH history pools. These costs are reasons to keep the choice explicit.

`path_trace_nrd_directional.gd` exercises real traced directions, opposing
lights, both planner modes, glossy sky transport, sky clearing, odd-size resize
and disposal. Related NRD motion, light-response, fallback, SHaRC and exact
resource-lifetime regressions cover the shared paths. The settings regression
checks all choices and help in EN/RU/DE, including 2560×1440 and 3840×2160.

Godot 4.7's optional Vulkan re-spirv optimizer corrupts one REBLUR temporal
stabilization shader on the qualified NVIDIA driver. The build generates a
default-true specialization guard for NRD entry points. Godot preserves the
original SPIR-V for these compute shaders. This was isolated with per-shader
compilation and independently validated SPIR-V; no global debug setting or
engine patch is required. SDK checkouts remain unchanged, apart from the
upstream-style generated NRDConfig header.

## Travel and grass

Scene snapshots cache mesh surface/blend arrays and normalized source textures
on the CPU with weak source watches, invalidation on mesh/texture changes and a conservative 128 MiB budget.
Godot's surface-array getter reads vertex, attribute and index buffers back
from the GPU. Repeating this for hundreds of retained meshes while PT renders
serializes scene gathering with GPU work. Neighboring snapshots now reuse
those source arrays and images. Mutable image updates invalidate cached pixels.
The cache releases on scene/RT teardown. Immutable ray shaders and pipelines
also remain shared for that controller lifetime. Replacement geometry builds
at most 16 acceleration structures or approximately 1.5 ms of build submission
per step, then builds its top-level structure. The previous region continues
to render until its replacement has produced a valid image. Resource creation
and single native driver operations can still exceed that submission budget.

Scene snapshots also share a bounded cache of immutable terrain sectors with
the same snow/sand lift used by raster rendering. Rebuilding a nearby RT region
no longer recalculates every retained sector's lift. Terrain surface-table
replacement, terrain identity and the soft-ground option invalidate the cache;
turning RT off or leaving the world releases it. Up to 128 sectors and a bounded
vertex-profile working set are retained. Collision/source arrays are untouched.
Live snapshot gathering uses a 1.5 ms target budget instead of the 6 ms loading
budget. A single indivisible mesh can exceed that target; this is not a hard
upper bound on every frame.

Procedural grass and ground cover inherit traced diffuse light at their planted
roots. A four-tap lookup checks the ground normal, plane and distance before
accepting light. It rejects foreground walls and avoids searching 29 pixels
for a raised blade absent from the acceleration structure. Ground specular
highlights are not copied onto grass. A separate direct-sun output lets the
existing local grass shadow map attenuate sunlight without darkening traced
indirect illumination. This applies fully within 18 metres of the camera and
fades out by 24 metres. It adds no grass geometry or extra rays to the RT scene.
Ground-mark shaders and their exact vertex layout are warmed during loading
before the first walking or blood mark is drawn.

The options are directly under Remake → Ray tracing / Path tracing. Keyboard
return navigation, pending settings, Apply/Cancel and EN/RU/DE labels and help
are preserved. Game setup, game files and exported reports remain reachable.

## Rendered-frame target

**PT rendered frame target** is available in responsive accumulation, with Off,
30, 45 and 60 FPS choices. Off preserves exact manual quality. The controller
measures completed PT and viewport GPU work, never generated display frames.
It changes the PT lattice in 5% steps between 65% and 100% of the selected RT
quality. Half-second median windows, cooldowns and six seconds of recovery
headroom limit oscillation. Loading, pause, replacement preparation and long
CPU frames do not request a quality reduction. A target cannot guarantee a
frame rate when simulation, raster rendering or the minimum PT resolution is
the limiting cost. Samples and bounce count remain manually selected.

## Rebuilding

Run `python3 tools/build_path_nrd.py --help`. Supply `--deps`, `--build`,
`--dxc` (DXC 1.9.2609) and `--godot-cpp` (qualified Godot 4.7 bindings at
507ed9d840c01a3c5b2a39af8bb4000bfac30bf5). Build once natively on Linux and
once with the MinGW `--toolchain`. The tool fetches and verifies pinned NRD,
MathLib and ShaderMake commits and builds only the requested shader variants.
`python3 tools/build_path_nrd.py --check` verifies both native binaries, sources,
SDK revisions and all 16 compute binaries. The ray integrator is reproduced
with `tools/build_water_rt_shaders.py --shader path_trace --dxc ...`.

The shader manifest records exact inputs and outputs. Desktop packaging must
copy `src/native/bin/libpath_nrd.so` or `.dll` next to the PCK, preserving that
relative path, and distribute `NATIVE_NRD_NOTICES.txt`. The `.cfg` descriptor is
intentionally lazy, so exporting a PCK alone does not collect this library.
The desktop packaging tools include the binary and notice explicitly.

NRD uses NVIDIA's RTX SDK license and is separate from the application's
license. Full SDK, MathLib and ShaderMake notices are shipped; the binding and
compiler-runtime notices accompany the other native helpers.

## Qualification

Dedicated NRD tests execute the actual planner and GPU passes, verify rigid
motion and disocclusion, resize, return from progressive accumulation, changed
lighting and teardown. Custom-filter motion and injected-failure tests retain
explicit coverage of the fallback's private history resources. Glossy tests
compare moving analytic highlights and stationary noise against independent
references. Grass tests render the production shader with controlled lit and
shadowed roots and reject a foreground wall.

The walking benchmark uses a fresh, muted profile, free cursor, FPS counter,
4K output, half-resolution two-bounce PT, AA off, the supplied report's full
effect settings, live simulation and repeated camera travel/recentering. GPU
readback is kept outside measured segments. Results are workstation evidence;
they do not substitute for a test on the reported RTX 4090 Laptop GPU.

Measured results and runtime hashes: [travel, history and presentation validation](../validation/pt-five-targets-2026-10-24.md)
and the [original NRD integration validation](../validation/path-tracing-nrd-2026-10-24.md).
