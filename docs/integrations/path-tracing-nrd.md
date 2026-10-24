# NRD reconstruction and travel performance

The local 1.28.0 previews integrate NVIDIA NRD 4.18.0 REBLUR_DIFFUSE_SPECULAR
into the existing Windows DX12 and Linux Vulkan path tracer. The qualified
Godot engine binaries are unchanged. The published 1.27.0 release is unchanged.

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

History responds to real lighting changes and resets on camera cuts, resize,
geometry replacement and explicit mode changes. Newly visible/deformed surfaces
receive zero confidence. Sky pixels are cleared explicitly. Public output
textures retain stable handles; replacement pools are private until complete.
Still scene retains the custom exact progressive accumulator. Unsupported or
failed NRD initialization falls back to the existing custom reconstruction.

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
The cache releases on scene/RT teardown.

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
highlights are not copied onto grass. This is a ground-light approximation,
not individual ray-traced grass-blade geometry or self-shadowing.

The options are directly under Remake → Ray tracing / Path tracing. Keyboard
return navigation, pending settings, Apply/Cancel and EN/RU/DE labels and help
are preserved. Game setup, game files and exported reports remain reachable.

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

Measured results and runtime hashes: [2026-10-24 validation](../validation/path-tracing-nrd-2026-10-24.md).
