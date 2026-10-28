# Terrain sunlight reconstruction

The terrain's authored smooth normals describe a contour that differs from its
coarse physical triangles. Per-pixel geometric sun rejection and self-shadow
rays can expose those triangles as dark interior bands. Increasing the ray
offset alone does not remove the bands and can lose nearby object contacts.

Terrain now reconstructs its own sunlight visibility from shared world-space
vertices. Triangles connected by an exact shared position belong to the same
component, including connections across terrain placements. Vertex samples
trace that component and interpolate visibility across each triangle. Only
nearby back-face exits within the authored contour's support are ignored; front
entries and distant terrain remain shadow casters. The support is two metre-grid
cells plus both 0.6 m contour offsets, scaled conservatively by the instance
transform. The normal used for the sun's hemisphere test follows the terrain's
shading normal. Other lights and path continuation retain their geometric tests.

Object shadows and disconnected terrain shadows still use the original
per-pixel receiver and geometric offset. Separate object/terrain instance bits
preserve the existing primary, shadow and indirect masks. Multiple terrain
components use an any-hit filter; the common single active component avoids that
extra query. Hidden or non-shadow-casting terrain cannot bridge active components.
Dielectric visibility retains its separate mask and transmission pass.

A finite sun uses a fixed positive seven-sample disk quadrature at each shared
vertex. Point sunlight uses one sample. Direction, radius, reach, terrain poses,
transforms and casting masks invalidate the appropriate cache state. Main
material sampling, object penumbrae and BRDF direction sampling remain unchanged.
This is a spatial approximation of terrain self visibility, not an unbiased
reference path tracer. It preserves full shared-edge interpolation; arbitrary
nonconforming mesh edges are not claimed to be analytically continuous.

Private scene replacements prepare connectivity and sample packing on a dedicated
CPU thread while ordinary scene resources are built. The worker owns immutable
value snapshots and never accesses scene nodes or RenderingDevice. Cancellation
joins it after a small bounded work slice. GPU allocation and uploads remain on
the render thread within the existing scene-build scheduler; a failed thread
start retains the bounded synchronous fallback. Buffers reserve enough capacity
for changed connectivity without invalidating descriptors. Main,
SHaRC and transmission descriptors are released before the cache buffers; cached
shader programs keep the existing shared lifetime. No engine extension is needed.

## Build and regression coverage

The cache has four ray-tracing stages in both DXIL and SPIR-V:

```sh
python3 tools/build_water_rt_shaders.py --shader path_trace_terrain_sun --dxc /path/to/dxc
python3 tools/build_water_rt_shaders.py --shader path_trace_terrain_sun --check --dxc /path/to/dxc
```

Rebuild the ordinary path, SHaRC and RTXDI shader families when their shared
`path_trace.hlsl` changes. Their manifests retain source, compiler and output
hashes. The cache uses bindings 42–44 and keeps the main 96-byte payload layout.

Registered tests cover the reported terrain terminator, a captured real cliff
edge, independent terrain walls, thin object contacts, finite sunlight, posed and
hidden components, bounded CPU preparation, and sparse-light RTXDI selection.
Related resource, transmission, water, terrain and camera-travel regressions
remain part of validation. The original game has no hardware path tracer or
corresponding shadow-reconstruction algorithm, so a Wine parity comparison is
inapplicable. Original terrain assets and the remake's conventional renderer
provide geometric and visual controls; original-renderer parity is not claimed.
