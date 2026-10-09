class_name GroundSurfaceShader
extends RefCounted
## Shared terrain sampling. Keep authored atlas rotation/borders and loose
## material displacement identical for land and ground-contact consumers.

const LAND_UNIFORMS := """uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// The original tile lookup. Vulkan (Forward+ / Mobile): explicit gradients
// and a whole layer number. On an Adreno 650 (Retroid Pocket 5) the implicit-
// LOD array lookup on the varying layer drew the land as one flat colour with
// black blocks, while gfx_terrain's textureGrad lookup drew correctly. The
// same texels and filtering as texture() everywhere else.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define EI_ATLAS(uv, layer) texture(atlases, vec3(uv, layer))
#else
#define EI_ATLAS(uv, layer) textureGrad(atlases, vec3(uv, floor(layer + 0.5)), dFdx(uv), dFdy(uv))
#endif
// Remake rendering (option gfx_terrain): padded tile filtering, restrained
// sharpening and relief derived from the painted texture, with finer noise.
uniform float detail = 0.0;
uniform float tiles_per_axis = 8.0;
uniform float atlas_padding = 0.0; // gutter / original tile size; 0 for original
uniform float source_texel = 0.001953125;
uniform sampler2D terrain_tiles : filter_nearest, repeat_disable; // code, ground type, loose thickness, compression
uniform bool blend_edges = true;
uniform sampler2D detail_nm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
// Cell data: base water height, land type, liquid type, liquid material.
uniform sampler2D terrain_cells : filter_nearest, repeat_disable;
// Highest solid cover per metre, rasterized from existing placed meshes.
// Rain cannot wet terrain or water underneath a roof / bridge deck.
uniform sampler2D rain_cover : filter_nearest, repeat_disable;
"""

const SOFT_UNIFORMS := """// Optional loose surface and dense tracks. R compacts, G displaces banks; all
// collision heights and the original undeformed sector meshes stay intact.
uniform bool soft_ground = false;
uniform bool soft_tracks = false;
uniform sampler2DArray soft_track_texture : filter_linear, repeat_disable;
uniform float soft_track_layer = 0.0;
uniform vec2 soft_track_origin;
uniform float soft_track_time = 0.0;
uniform float level[64];
"""

const SOFT_FUNCTIONS := """vec2 soft_ground_profile(ivec2 p) {
	// The tile texture's existing B/A channels carry thickness/compression.
	// Avoid replicating the type-ID branches at every displaced query vertex.
	return texelFetch(terrain_tiles, clamp(p, ivec2(0), textureSize(terrain_tiles, 0) - 1), 0).ba;
}
vec2 soft_surface(vec2 p, float height) {
	ivec2 tile = ivec2(floor(p * 0.5));
	vec2 profile = soft_ground_profile(tile);
	if (profile.x == 0.0) { return vec2(0.0); }
	// Soft materials of different thickness share the same border height.
	vec2 grid = p * 0.5 - 0.5;
	ivec2 base = ivec2(floor(grid));
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(grid));
	profile = mix(mix(soft_ground_profile(base), soft_ground_profile(base + ivec2(1, 0)), blend.x),
		mix(soft_ground_profile(base + ivec2(0, 1)), soft_ground_profile(base + ivec2(1, 1)), blend.x), blend.y);
	vec2 local = p - vec2(tile) * 2.0;
	// Taper to zero at hard material boundaries instead of opening cracks
	// between the loose layer and the original rock/road triangles.
	float mask = 1.0;
	if (soft_ground_profile(tile + ivec2(-1, 0)).x == 0.0) { mask *= smoothstep(0.0, 0.6, local.x); }
	if (soft_ground_profile(tile + ivec2(1, 0)).x == 0.0) { mask *= smoothstep(0.0, 0.6, 2.0 - local.x); }
	if (soft_ground_profile(tile + ivec2(0, -1)).x == 0.0) { mask *= smoothstep(0.0, 0.6, local.y); }
	if (soft_ground_profile(tile + ivec2(0, 1)).x == 0.0) { mask *= smoothstep(0.0, 0.6, 2.0 - local.y); }
	vec4 cell = textureLod(terrain_cells, p / vec2(textureSize(terrain_cells, 0)), 0.0);
	float water_y = cell.r + level[clamp(int(cell.a + 0.5), 0, 63)];
	return profile * mask * smoothstep(0.025, 0.10, height - water_y);
}
vec2 soft_uv(vec2 p) {
	// Both sector textures contain their common boundary sample exactly.
	return ((p - soft_track_origin) * (511.0 / 32.0) + 0.5) / 512.0;
}
float soft_height(vec2 track) {
	// A new crossing compacts the bank of an older trail too.
	return track.g * (1.0 - smoothstep(0.05, 0.30, track.r)) - track.r;
}
vec2 soft_sample(vec2 uv) {
	vec4 track = textureLod(soft_track_texture, vec3(uv, soft_track_layer), 0.0);
	// Coverage-normalized timestamps keep new track edges from inheriting
	// the zero timestamp of untouched texels late in a long map session.
	float age = max(soft_track_time - track.b / max(track.a, 1e-5), 0.0);
	return track.rg * clamp((240.0 - age) / 60.0, 0.0, 1.0);
}
"""

const TILE_FUNCTIONS := """vec2 tile_turn(vec2 p, int rotation) {
	if (rotation == 1) { return vec2(-p.y, p.x); }
	if (rotation == 2) { return -p; }
	if (rotation == 3) { return vec2(p.y, -p.x); }
	return p;
}
vec4 tile_info(ivec2 cell) {
	return texelFetch(terrain_tiles, clamp(cell, ivec2(0), textureSize(terrain_tiles, 0) - 1), 0);
}
// stone, soft ground, grass, ice. Blend these with the colour so relief and
// sharpening cannot introduce another hard line at a material boundary.
vec4 tile_traits(float type) {
	int g = int(type + 0.5);
	return vec4((g == 2 || g == 4 || g == 15) ? 1.0 : 0.0,
		(g == 3 || g == 9 || g == 12) ? 1.0 : 0.0,
		(g == 0 || g == 5 || g == 11) ? 1.0 : 0.0, g == 10 ? 1.0 : 0.0);
}
// p is in the unrotated, visible 48/64 tile interior. Samples from a
// neighbour can extend into its authored border, never an unrelated tile.
vec3 tile_sample(float packed, vec2 p, vec2 dx, vec2 dy) {
	int code = int(packed + 0.5);
	int tile = code & 63;
	int rotation = (code >> 14) & 3;
	int per_row = int(tiles_per_axis);
	float border = 8.0 * source_texel * tiles_per_axis;
	float interior = 1.0 - 2.0 * border;
	vec2 local = vec2(border) + (vec2(0.5) + tile_turn(p - 0.5, rotation)) * interior;
	local = clamp(vec2(local.x, 1.0 - local.y), vec2(0.0), vec2(1.0));
	vec2 tile_origin = vec2(float(tile % per_row), float(per_row - 1 - tile / per_row));
	float span = 1.0 + 2.0 * atlas_padding;
	vec2 uv = (tile_origin + (local + atlas_padding) / span) / tiles_per_axis;
	vec2 gx = tile_turn(dx, rotation) * interior / (tiles_per_axis * span);
	vec2 gy = tile_turn(dy, rotation) * interior / (tiles_per_axis * span);
	return textureGrad(atlases, vec3(uv, float((code >> 6) & 255)), gx * vec2(1.0, -1.0), gy * vec2(1.0, -1.0)).rgb;
}
#ifdef EI_BAKED_TERRAIN
uniform sampler2D baked_ground : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 bake_origin;
uniform vec2 bake_span;
vec3 ground_sample(ivec2 cell, vec2 p, vec2 dx, vec2 dy, out vec4 traits) {
 ivec2 shift=ivec2(floor(p)); cell+=shift; p-=vec2(shift);
 traits=tile_traits(tile_info(cell).g);
 if(blend_edges) {
  vec2 edge=min(p,1.0-p);
  vec2 weight=0.5*(1.0-smoothstep(vec2(0.0),vec2(0.12),edge));
  ivec2 step_cell=ivec2(p.x<0.5 ? -1:1,p.y<0.5 ? -1:1);
  vec4 tx=tile_traits(tile_info(cell+ivec2(step_cell.x,0)).g);
  vec4 ty=tile_traits(tile_info(cell+ivec2(0,step_cell.y)).g);
  vec4 txy=tile_traits(tile_info(cell+step_cell).g);
  traits=mix(mix(traits,tx,weight.x),mix(ty,txy,weight.x),weight.y);
 }
 return textureGrad(baked_ground,(vec2(cell)+p-bake_origin)/bake_span,dx/bake_span,dy/bake_span).rgb;
}
#else
vec3 ground_sample(ivec2 cell, vec2 p, vec2 dx, vec2 dy, out vec4 traits) {
	// Gradient taps may cross an edge. Resolve their actual owner first, so
	// both sides derive the same colour AND height gradient at the join.
	ivec2 shift = ivec2(floor(p));
	cell += shift;
	p -= vec2(shift);
	vec4 info = tile_info(cell);
	vec3 c = tile_sample(info.r, p, dx, dy);
	traits = tile_traits(info.g);
	if (!blend_edges) { return c; }
	vec2 edge = min(p, 1.0 - p);
	vec2 weight = 0.5 * (1.0 - smoothstep(vec2(0.0), vec2(0.12), edge));
	ivec2 step_cell = ivec2(p.x < 0.5 ? -1 : 1, p.y < 0.5 ? -1 : 1);
	if (weight.x > 0.0) {
		info = tile_info(cell + ivec2(step_cell.x, 0));
		c = mix(c, tile_sample(info.r, p - vec2(float(step_cell.x), 0.0), dx, dy), weight.x);
		traits = mix(traits, tile_traits(info.g), weight.x);
	}
	if (weight.y > 0.0) {
		info = tile_info(cell + ivec2(0, step_cell.y));
		vec3 other = tile_sample(info.r, p - vec2(0.0, float(step_cell.y)), dx, dy);
		vec4 other_traits = tile_traits(info.g);
		if (weight.x > 0.0) {
			info = tile_info(cell + step_cell);
			other = mix(other, tile_sample(info.r, p - vec2(step_cell), dx, dy), weight.x);
			other_traits = mix(other_traits, tile_traits(info.g), weight.x);
		}
		c = mix(c, other, weight.y);
		traits = mix(traits, other_traits, weight.y);
	}
	return c;
}
#endif

"""

## Exact drawn-surface lookup, including authored xy offsets, folded cells
## and the installed (not merely requested) footprint tessellation.
const TRIANGLE_QUERY := """
uniform sampler2D query_vertices : filter_nearest, repeat_disable;
uniform sampler2D query_tiles : filter_nearest, repeat_disable;
uniform sampler2DArray query_tracks : filter_linear, repeat_disable;
// Runtime loop bounds limit replication of the displaced terrain sampler
// by GL compilers. Consumers keep these at nine cells / three vertices;
// these are internal bounds, not quality knobs.
uniform int query_cell_count = 9;
uniform int query_vertex_count = 3;
const bool query_bilinear = false;
const bool query_undeformed = false;
const bool query_no_tracks = false;
const bool query_first_hit = false;
const bool query_implicit_gradients = false;
uniform sampler2D query_clock : filter_nearest, repeat_disable;
// Data uses EI xy; returned vertices use Godot xyz.
vec3 query_vertex(ivec2 p) {
	vec3 data = texelFetch(query_vertices, p, 0).rgb;
	return vec3(float(p.x) + data.x, data.y, -float(p.y) - data.z);
}
bool query_weights(vec2 p, vec3 a, vec3 b, vec3 c, out vec3 w) {
	vec2 x = b.xz - a.xz;
	vec2 y = c.xz - a.xz;
	vec2 q = vec2(p.x, -p.y) - a.xz;
	float d = x.x * y.y - x.y * y.x;
	if (abs(d) < 1e-10) { w = vec3(-1.0); return false; }
	float u = (q.x * y.y - q.y * y.x) / d;
	float v = (x.x * q.y - x.y * q.x) / d;
	w = vec3(1.0 - u - v, u, v);
	return min(min(w.x, w.y), w.z) >= -1e-5;
}
float query_displace(vec3 p, vec2 origin, float layer) {
	if (!soft_ground || query_undeformed) { return p.y; }
	vec2 profile = soft_surface(vec2(p.x, -p.z), p.y);
	float h = p.y + profile.x;
	if (layer >= 0.0 && !query_no_tracks) {
		vec2 uv = ((vec2(p.x, -p.z) - origin) * (511.0 / 32.0) + 0.5) / 512.0;
		vec4 track = textureLod(query_tracks, vec3(uv, layer), 0.0);
		float age = max(textureLod(query_clock, vec2(0.5), 0.0).r - track.b / max(track.a, 1e-5), 0.0);
		vec2 value = track.rg * clamp((240.0 - age) / 60.0, 0.0, 1.0);
		h += soft_height(value) * profile.y;
	}
	return h;
}
vec3 query_point(vec3 a, vec3 b, vec3 c, vec2 uv) {
	return a * (1.0 - uv.x - uv.y) + b * uv.x + c * uv.y;
}
mat3 query_subdivision(vec3 w, out vec3 blend) {
	vec2 q = w.yz * 16.0;
	vec2 lo = floor(q);
	vec2 f = q - lo;
	vec2 u; vec2 v; vec2 z;
	if (f.x + f.y <= 1.0) {
		u = lo; v = lo + vec2(1.0,0.0); z = lo + vec2(0.0,1.0);
		blend = vec3(1.0 - f.x - f.y, f.x, f.y);
	} else {
		u = lo + vec2(1.0,0.0); v = lo + vec2(1.0); z = lo + vec2(0.0,1.0);
		blend = vec3(1.0 - f.y, f.x + f.y - 1.0, 1.0 - f.x);
	}
	u /= 16.0; v /= 16.0; z /= 16.0;
	return mat3(vec3(1.0-u.x-u.y,u), vec3(1.0-v.x-v.y,v), vec3(1.0-z.x-z.y,z));
}
float query_elevation(vec3 a, vec3 b, vec3 c, vec3 w, ivec2 cell) {
	vec2 state = texelFetch(query_tiles, clamp(cell / 2, ivec2(0), textureSize(query_tiles, 0) - 1), 0).rg;
	vec2 origin = vec2(cell / 32) * 32.0;
	float layer = state.x - 1.0;
	mat3 points = mat3(a,b,c);
	vec3 blend = w;
	if (soft_ground && state.y > 0.5 && !query_undeformed) {
		// Reconstruct the installed 16-way subdivision in the ORIGINAL
		// triangle's barycentric coordinates, not a regular world xy grid.
		points *= query_subdivision(w, blend);
	}
	float height = 0.0;
	for (int i = 0; i < query_vertex_count; i++) {
		height += blend[i] * query_displace(points[i], origin, layer);
	}
	return height;
}
"""

const QUERY_SHADER := TRIANGLE_QUERY + """
bool query_surface(vec2 p, out float height, out vec2 grid, out ivec2 tile, out mat2 jacobian) {
	height = -1e10; grid = vec2(0.0); tile = ivec2(0);
	jacobian = mat2(1.0);
	bool found = false;
	// Some authored offsets fold cells over each other. The first enclosing
	// triangle is NOT always the one seen by the depth buffer. Examine both
	// triangles of all nine candidate cells and retain the highest surface.
	ivec2 offsets[9] = ivec2[9](ivec2(0), ivec2(-1,0), ivec2(1,0), ivec2(0,-1), ivec2(0,1),
		ivec2(-1,-1), ivec2(1,-1), ivec2(-1,1), ivec2(1,1));
	for (int i = 0; i < query_cell_count; i++) {
		if (found && query_first_hit) { break; }
		ivec2 cell = ivec2(floor(p)) + offsets[i];
		if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, textureSize(query_vertices, 0) - 1))) { continue; }
		vec3 va = query_vertex(cell);
		vec3 vb = query_vertex(cell + ivec2(1,0));
		vec3 vc = query_vertex(cell + ivec2(0,1));
		vec3 vd = query_vertex(cell + ivec2(1));
		for (int side = 0; side < 2; side++) {
			if (found && query_first_hit) { break; }
			vec3 a = side == 0 ? vc : vb;
			vec3 b = side == 0 ? vb : vc;
			vec3 c = side == 0 ? va : vd;
			vec3 w;
			if (!query_weights(p, a, b, c, w)) { continue; }
			float h = query_elevation(a,b,c,w,cell);
			if (h <= height) { continue; }
			height = h; found = true; tile = cell / 2;
			vec2 ga = vec2(cell) + (side == 0 ? vec2(0,1) : vec2(1,0));
			vec2 gb = vec2(cell) + (side == 0 ? vec2(1,0) : vec2(0,1));
			vec2 gc = vec2(cell) + (side == 0 ? vec2(0) : vec2(1));
			grid = ga * w.x + gb * w.y + gc * w.z;
			// Screen derivatives of the selected UV can straddle two different
			// terrain triangles. Use this triangle's affine transform, matching
			// the extrapolated helper fragments of the actual mesh draw.
			mat2 world_edges = mat2((b.xz - a.xz) * vec2(1.0,-1.0), (c.xz - a.xz) * vec2(1.0,-1.0));
			jacobian = mat2(gb - ga, gc - ga) * inverse(world_edges);
		}
	}
	if (found && query_bilinear) {
		ivec2 at = clamp(ivec2(floor(p)), ivec2(0), textureSize(query_vertices, 0) - 2);
		vec2 f = clamp(p - vec2(at), vec2(0.0), vec2(1.0));
		height = mix(mix(query_vertex(at).y, query_vertex(at + ivec2(1,0)).y, f.x),
			mix(query_vertex(at + ivec2(0,1)).y, query_vertex(at + ivec2(1)).y, f.x), f.y);
	}
	return found;
}
"""
