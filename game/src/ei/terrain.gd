class_name EITerrain
extends Node3D
## Builds terrain and water from a map's .mpr archive (header .mp + sector .sec files)
## and its tile atlases "<map>NNN.mmp" in textures.res.

const WaveState := preload("res://src/ei/water_waves.gd")

const MP_MAGIC := 0xCE4AF672
const SEC_MAGIC := 0xCF4BF774
const SECTOR := 32          # quads per sector side
const VERTS := 33           # vertices per sector side
const TILES := 16           # texture tiles per sector side (each covers 2x2 quads)
const NO_LIQUID := 0xFFFF
## Dedicated land receiver/caster identity; bit 18 remains the decal layer.
## Replacing default layer 1 lets the object-only shadow map exclude land.
const SHADOW_RECEIVER_LAYER := 1 << 17
# The original atlas tiles already contain an 8-pixel sampling border.
#  uses coordinates 8, tile_size / 2
# tile_size - 8, not half-texel corners of the full packed tile.
const TILE_BORDER := 8.0
# Rotations of the 3x3 UV grid of a tile, by rotation code.
const ROT_PERM := [
	[0, 1, 2, 3, 4, 5, 6, 7, 8],
	[2, 5, 8, 1, 4, 7, 0, 3, 6],
	[8, 7, 6, 5, 4, 3, 2, 1, 0],
	[6, 3, 0, 7, 4, 1, 8, 5, 2],
]

## Land: texture × the original vertex light (Gfx.light_code:
## combined with max). Vertex COLOR carries the terrain
## vertex's underwater terms: rgb = E (the water material's
## self-illuminated colour, 0 on dry land), a = k / 4, k = depth² / (15 (1 − alpha)).
const TERRAIN_SHADER := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
render_mode cull_disabled, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
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
uniform sampler2D terrain_tiles : filter_nearest, repeat_disable; // code, ground type
uniform bool blend_edges = true;
uniform sampler2D detail_nm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
// Cell data: base water height, land type, liquid type, liquid material.
uniform sampler2D terrain_cells : filter_nearest, repeat_disable;
// Highest solid cover per metre, rasterized from existing placed meshes.
// Rain cannot wet terrain or water underneath a roof / bridge deck.
uniform sampler2D rain_cover : filter_nearest, repeat_disable;
// Optional dense snow/sand tiles. R depresses, G raises a shallow rim; all
// collision heights and the original undeformed sector meshes stay intact.
uniform bool soft_tracks = false;
uniform sampler2D soft_track_texture : filter_linear, repeat_disable;
uniform vec2 soft_track_origin;
uniform float level[64];
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (soft_tracks) {
		int width = textureSize(terrain_tiles, 0).x;
		int id = int(UV2.y + 0.5);
		int g = int(texelFetch(terrain_tiles, ivec2(id % width, id / width), 0).g + 0.5);
		if (g == 3 || g == 9 || g == 12) {
			vec2 track_uv = (vec2(wpos.x, -wpos.z) - soft_track_origin) / 32.0;
			vec2 track = textureLod(soft_track_texture, track_uv, 0.0).rg;
			VERTEX.y += (track.g - track.r) * 0.04;
			wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		}
	}
	ei_e = COLOR.rgb;
	ei_k = COLOR.a * 4.0;
}
vec2 tile_turn(vec2 p, int rotation) {
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
float ground_height(vec3 colour) {
	// A shallow visual approximation, not geometry: painted bright ridges
	// rise above dark cracks. Work in perceptual brightness, not linear RGB.
	return sqrt(max(dot(colour, vec3(0.2126, 0.7152, 0.0722)), 0.0));
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec2 cell_uv = vec2(wpos.x, -wpos.z) / vec2(textureSize(terrain_cells, 0));
	vec4 cell = texture(terrain_cells, cell_uv);
	int ground = int(cell.g + 0.5);
	float grass = (ground == 0 || ground == 5 || ground == 11) ? 1.0 : 0.0;
	vec3 c;
	if (detail > 0.0) {
		int id = int(UV2.y + 0.5);
		int width = textureSize(terrain_tiles, 0).x;
		ivec2 tile = ivec2(id % width, id / width);
		int code = int(tile_info(tile).r + 0.5);
		float border = 8.0 * source_texel * tiles_per_axis;
		int packed_tile = code & 63;
		int per_row = int(tiles_per_axis);
		vec2 origin = vec2(float(packed_tile % per_row), float(per_row - 1 - packed_tile / per_row));
		// Use the known tile origin, not fract(): helper fragments outside a
		// triangle must retain smooth derivatives even at distant mip levels.
		vec2 local = (UV * tiles_per_axis - origin - border) / (1.0 - 2.0 * border);
		local = 0.5 + tile_turn(vec2(local.x, 1.0 - local.y) - 0.5, (4 - ((code >> 14) & 3)) % 4);
		vec2 dx = dFdx(local);
		vec2 dy = dFdy(local);
		vec4 traits;
		// The fragment's own sample stays in its own tile. GLES3 (web /
		// Android) interpolates UV a hair past the tile edge on some edge
		// pixels, and the shift to the neighbour then drew dotted lines along
		// the triangle edges. Derivatives keep the unclamped value.
		c = ground_sample(tile, clamp(local, vec2(0.0), vec2(0.99999)), dx, dy, traits);
		float stone = traits.x;
		float soft = traits.y;
		grass = traits.z;
		float relief = mix(mix(mix(0.13, 0.10, stone), 0.055, soft), 0.025, traits.w);
		float fade = detail * (1.0 - smoothstep(25.0, 70.0, length(VERTEX)));
		// The cotangent frame follows the original rotated/mirrored tile UVs
		// and sloping terrain, without changing mesh or navigation vertices.
		vec3 p2 = cross(dFdy(VERTEX), NORMAL);
		vec3 p1 = cross(NORMAL, dFdx(VERTEX));
		vec3 tangent = p2 * dx.x + p1 * dy.x;
		vec3 bitangent = p2 * dx.y + p1 * dy.y;
		float frame_scale = inversesqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1e-12));
		if (fade > 0.0) {
			vec2 step_uv = vec2(source_texel * tiles_per_axis * 1.5 / (1.0 - 2.0 * border), 0.0);
			vec4 unused_traits;
			vec3 left = ground_sample(tile, local - step_uv, dx, dy, unused_traits);
			vec3 right = ground_sample(tile, local + step_uv, dx, dy, unused_traits);
			vec3 down = ground_sample(tile, local - step_uv.yx, dx, dy, unused_traits);
			vec3 up = ground_sample(tile, local + step_uv.yx, dx, dy, unused_traits);
			vec2 slope = vec2(ground_height(right) - ground_height(left), ground_height(up) - ground_height(down));
			float painted_relief = mix(mix(mix(1.1, 2.4, stone), 0.35, soft), 0.15, traits.w);
			NORMAL = normalize(NORMAL - (tangent * slope.x + bitangent * slope.y) * frame_scale * painted_relief * fade);
			// Local contrast, bounded by nearby colours to avoid bright halos.
			vec3 average = (left + right + down + up) * 0.25;
			vec3 lo = min(c, min(min(left, right), min(down, up)));
			vec3 hi = max(c, max(max(left, right), max(down, up)));
			c = clamp(c + (c - average) * mix(0.38, 0.16, soft) * fade, lo, hi);
			vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
			// triplanar weights so steep slopes get relief too
			vec3 bw = pow(abs(wn), vec3(4.0));
			bw /= bw.x + bw.y + bw.z;
			vec2 a = texture(detail_nm, wpos.zy * 0.45).xy * 2.0 - 1.0;
			vec2 b = texture(detail_nm, wpos.xz * 0.45).xy * 2.0 - 1.0;
			vec2 e = texture(detail_nm, wpos.xy * 0.45).xy * 2.0 - 1.0;
			vec2 f = texture(detail_nm, wpos.xz * 1.7 + 0.37).xy * 2.0 - 1.0;
			vec2 fine = f * mix(0.25, 0.85, grass);
			vec3 pert = vec3(0.0, a.y, a.x) * bw.x + vec3(b.x + fine.x, 0.0, b.y + fine.y) * bw.y + vec3(e.x, e.y, 0.0) * bw.z;
			// Tangential perturbation keeps steep slopes' base normal intact.
			pert -= wn * dot(wn, pert);
			wn = normalize(wn + pert * relief * fade);
			NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		}
		// large, soft brightness variation that breaks up the tile repeats
		float mac = texture(macro_tex, wpos.xz * 0.012).r;
		c *= mix(1.0, 0.92 + 0.16 * mac, detail * (1.0 - soft * 0.6));
		// Damp banks follow the actual liquid layer, including SetWaterLevel.
		// Snow, ice and lava keep their own appearance.
		float water_y = cell.r + level[clamp(int(cell.a + 0.5), 0, 63)];
		float wet = 1.0 - smoothstep(0.02, 0.55, abs(wpos.y - water_y));
		if (int(cell.b + 0.5) == 13 || ground == 9 || ground == 10 || ground == 12) { wet = 0.0; }
		c *= 1.0 - wet * detail * mix(0.20, 0.08, grass);
	} else {
		c = EI_ATLAS(UV, UV2.x).rgb;
	}
	// Rain affects exposed ground independently of the terrain-detail option.
	// Snow, ice, lava and ground under water retain their own appearance.
	if (ei_surface_fx.z > 0.5 && ei_weather.x > 0.0 && ground != 9 && ground != 10 && ground != 12 && ground != 13 && int(cell.b + 0.5) != 13) {
		float cover_y = texture(rain_cover, cell_uv).r;
		float exposed = 1.0 - smoothstep(0.08, 0.40, cover_y - wpos.y);
		float water_y = cell.r + level[clamp(int(cell.a + 0.5), 0, 63)];
		float above_water = smoothstep(-0.04, 0.10, wpos.y - water_y);
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float wet = ei_weather.x * exposed * above_water * smoothstep(0.05, 0.65, abs(wn.y));
		c *= 1.0 - wet * mix(0.23, 0.08, grass);
		ei_surface = vec3(wet * mix(0.65, 0.15, grass), mix(0.35, 0.65, grass), 0.0);
	}
	if (soft_tracks && (ground == 3 || ground == 9 || ground == 12)) {
		vec2 uv = (vec2(wpos.x, -wpos.z) - soft_track_origin) / 32.0;
		vec2 step_uv = vec2(1.0 / 512.0, 0.0);
		vec2 a = texture(soft_track_texture, uv - step_uv).rg;
		vec2 b = texture(soft_track_texture, uv + step_uv).rg;
		vec2 d = texture(soft_track_texture, uv - step_uv.yx).rg;
		vec2 e = texture(soft_track_texture, uv + step_uv.yx).rg;
		vec2 slope = vec2((b.g - b.r) - (a.g - a.r), (e.g - e.r) - (d.g - d.r)) * 0.32;
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 track_normal = normalize(wn + vec3(-slope.x, 0.0, slope.y));
		// The original vertex-lit look has no per-pixel normal response.
		// Keep tracks legible when this independent option alone is enabled.
		if (ei_surface_fx.x < 0.5 && dot(ei_sun_dir, ei_sun_dir) > 0.5) {
			float relief = dot(track_normal - wn, normalize(ei_sun_dir));
			c *= clamp(1.0 + relief * 0.75, 0.65, 1.18);
		}
		wn = track_normal;
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""

## The original water: the liquid layer's vertices are lit like land with
## E = the map material's min(1, self-illumination × colour) (
## material) and drawn texture × vertex colour with the
## material alpha. Vertex waves (map flag 1 =
## EnableWaterWaves, default ; run by the map update each tick):
## with wind force w (DefaultWindForce 0.4) the amplitude is
## A = 0.3 · w · wave (material = the.mp record's "wave"), the phase
## s = sin(T · wave + p(v)) with T += −(π / 21) · w per tick (map)
## and p(v) a per-sector 33 × 33 grid of 40 random bumps; the
## vertex rises by s · A / 4 and sways by sin(column · π/4 + 0.05 · ticks) ·
## 3A in x and sin(row · π/4 + 0.05 · ticks) · 3A in y, and for s > 0 its
## specular colour is s · w · wave · 50 · rgb (bytes, added after the texture).
## The wind direction defaults to vertical (0, 0, 1), so no travelling phase.
## The CRT grid and sine-table lookup use the executed native float stores.
## Shared startup RNG history and explicit post-tick relight ordering remain
## distinct; wave time belongs to the map and stops with its paused world.
const WATER_SHADER := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
#define EI_WATER_WAVES
render_mode cull_disabled, blend_mix, ambient_light_disabled, depth_draw_always;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// The original tile lookup, as TERRAIN_SHADER's EI_ATLAS.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define EI_ATLAS(uv, layer) texture(atlases, vec3(uv, layer))
#else
#define EI_ATLAS(uv, layer) textureGrad(atlases, vec3(uv, floor(layer + 0.5)), dFdx(uv), dFdy(uv))
#endif
// SetWaterLevel offsets per map material (UV2.y = the tile's material), as the
// original shifts the water vertices of a material.
uniform float level[64];
uniform vec3 mat_e[64];
uniform float mat_a[64];
uniform float mat_wave[64];
uniform vec3 mat_rgb[64];
uniform int mat_type[64];
uniform float wave_phase = 6.2831854820251465;
uniform float wave_ticks = 0.0;
uniform float wave_amplitude = 0.12;
uniform vec2 wave_gradient = vec2(0.0);
uniform sampler2D sine_tex : filter_nearest, repeat_enable;
uniform float wind = 0.4;      // DefaultWindForce
uniform float waves = 1.0;     // EnableWaterWaves
uniform sampler2D phase_tex : filter_nearest, repeat_enable;   //  grid
varying float alpha;
varying vec3 spec;
float wave_sine(float angle) {
	int index = int(roundEven(angle * 81.48733086305042)) & 511;
	return texelFetch(sine_tex, ivec2(index, 0), 0).r;
}
float wave_fmod(float value) {
	return value - trunc(value / 6.2831854820251465) * 6.2831854820251465;
}
vec3 wave_specular(float sine_value, float wave, vec3 colour) {
	// Native FISTP writes bytes; do not replace the lookup with continuous sin.
	vec3 magnitude = roundEven(sine_value * (wind * wave * 50.0 * colour));
	return mod(magnitude, vec3(256.0)) / 255.0;
}
void vertex() {
	int mi = int(UV2.y + 0.5);
	int m = clamp(mi % 64, 0, 63);
	VERTEX.y += level[m];
	ei_e = mat_e[m];
	ei_k = 0.0;
	alpha = mat_a[m];
	spec = vec3(0.0);
	if (waves > 0.5) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 ei = vec2(wp.x, -wp.z);
		vec2 cr = mod(floor(ei + 0.5), 32.0);
		float p = texelFetch(phase_tex, ivec2(cr), 0).r;
		float wv = mat_wave[m];
		float a = wave_amplitude * wv;
		float travelling = wave_fmod(6.2831854820251465 + dot(ei, wave_gradient));
		float temporal = wave_fmod(wave_phase * wv);
		float s = wave_sine(travelling + temporal + p);
		float t2 = 0.05 * wave_ticks;
		if (mat_type[m] == 4) {
			// The original water record's sign bit is separate
			// land depth. Fresh records initialize it to zero (6c4ed0).
			if (mi >= 64) {
				VERTEX.x += s * a;
				VERTEX.z -= s * a;
			}
		} else {
			// EI (x, y, z) = Godot (x, -z, y).
			VERTEX.y += s * a * 0.25;
			VERTEX.x += wave_sine(cr.x * 0.7853981 + t2) * a * 3.0;
			VERTEX.z -= wave_sine(cr.y * 0.7853981 + t2) * a * 3.0;
		}
		if (s >= 0.0) {
			spec = wave_specular(s, wv, mat_rgb[m]);
		}
	}
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec4 t = EI_ATLAS(UV, UV2.x);
	ALBEDO = t.rgb;
	// Stage 0 (state block): colour = texture ×
	// diffuse, alpha = SELECTARG1 diffuse: the texture's alpha is not used.
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
"""

## Remake water (option gfx_water), built on the original water above: the
## same per-vertex material, vertex light (texture × the EI light model),
## material alpha over the land (whose underwater vertices the land shader
## already darkens by depth), vertex waves and vertex specular. On top, drawn
## so that the original colour stays the base:
## - where two liquid textures meet (bog and river tiles), the 2 × 2 m tile
##   textures are cross-faded along a noise-wobbled line instead of the
##   original's hard stair-stepped tile edge;
## - drifting procedural ripple normals (and rain rings) drive only the
##   reflection and glints, not the diffuse light;
## - Fresnel reflection of the sky colour and, with gfx_water_reflections,
##   screen-space reflections of the scene (Mirror: a stronger mix, capped);
## - sun glints whose peak is the original's vertex specular cap of 20/255;
## - a soft shore: the alpha fades over the last 0.25 m of depth;
## - breaking surf on explicitly identified sea coasts;
## - lava (liquid tiles of ground type 13) churns and glows.
## The reflection and glints replace / add light as alpha-blended colour:
## out = (1 − w) · (a · lit + (1 − a) · behind) + w · R + G. Keeps the
## per-material SetWaterLevel offsets. (Until 2026-10-03 this was a separate
## look: the material's rgb (in the original only E = self_illum × rgb, 0 for water
## and bog, and the wave specular) mixed in as a flat body colour per tile, Godot's own lighting with sky
## ambient and a screen refraction whose clarity grew with the view path: a
## milky, fog-like surface showing the dark seabed, hard blue / teal blocks
## where two materials meet, and Mirror's 60 % screen-space reflection put
## white bank streaks on rivers.)
const WATER_FX_SHADER := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
#define EI_WATER_WAVES
#define EI_WATER_FX
render_mode cull_disabled, blend_mix, ambient_light_disabled, depth_draw_always;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// The original tile lookup, as TERRAIN_SHADER's EI_ATLAS.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define EI_ATLAS(uv, layer) texture(atlases, vec3(uv, layer))
#else
#define EI_ATLAS(uv, layer) textureGrad(atlases, vec3(uv, floor(layer + 0.5)), dFdx(uv), dFdy(uv))
#endif
uniform float level[64];
uniform vec3 mat_e[64];
uniform float mat_a[64];
uniform float mat_wave[64];
uniform vec3 mat_rgb[64];
uniform int mat_type[64];
uniform float wave_phase = 6.2831854820251465;
uniform float wave_ticks = 0.0;
uniform float wave_amplitude = 0.12;
uniform vec2 wave_gradient = vec2(0.0);
uniform sampler2D sine_tex : filter_nearest, repeat_enable;
uniform float wind = 0.4;      // DefaultWindForce
uniform float waves = 1.0;     // EnableWaterWaves
uniform sampler2D phase_tex : filter_nearest, repeat_enable;   //  grid
uniform float lava[64];
uniform float surf[64];
uniform float ripple[64];
uniform bool reflections = true;
uniform float mirror = 1.0; // Mirror style; Natural uses 0
uniform bool blend_tiles = true;
// Liquid tile code per 2 x 2 m tile of the map (-1: none), as land_tile.
uniform sampler2D water_tiles : filter_nearest, repeat_disable;
uniform float tiles_per_axis = 8.0;
uniform float source_texel = 0.001953125;
uniform sampler2D terrain_cells : filter_nearest, repeat_disable;
uniform sampler2D rain_cover : filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
varying float alpha;
varying vec3 spec;
varying float ei_wave_scale;
varying vec3 wpos;
varying vec2 tgrid;
varying float is_lava;
varying float surf_amount;
varying float ripple_amount;
float wave_sine(float angle) {
	int index = int(roundEven(angle * 81.48733086305042)) & 511;
	return texelFetch(sine_tex, ivec2(index, 0), 0).r;
}
float wave_fmod(float value) {
	return value - trunc(value / 6.2831854820251465) * 6.2831854820251465;
}
vec3 wave_specular(float sine_value, float wave, vec3 colour) {
	// Native FISTP writes bytes; do not replace the lookup with continuous sin.
	vec3 magnitude = roundEven(sine_value * (wind * wave * 50.0 * colour));
	return mod(magnitude, vec3(256.0)) / 255.0;
}
void vertex() {
	int mi = int(UV2.y + 0.5);
	int m = clamp(mi % 64, 0, 63);
	VERTEX.y += level[m];
	// The tile grid position before the waves sway the vertex: the texture
	// rides on the vertices as with the original UVs.
	vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tgrid = vec2(w0.x, -w0.z) * 0.5;
	ei_e = mat_e[m];
	ei_k = 0.0;
	alpha = mat_a[m];
	spec = vec3(0.0);
	is_lava = lava[m];
	surf_amount = surf[m];
	ripple_amount = ripple[m];
	if (waves > 0.5) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 ei = vec2(wp.x, -wp.z);
		vec2 cr = mod(floor(ei + 0.5), 32.0);
		float p = texelFetch(phase_tex, ivec2(cr), 0).r;
		float wv = mat_wave[m];
		float a = wave_amplitude * wv;
		float travelling = wave_fmod(6.2831854820251465 + dot(ei, wave_gradient));
		float temporal = wave_fmod(wave_phase * wv);
		float s = wave_sine(travelling + temporal + p);
		float t2 = 0.05 * wave_ticks;
		if (mat_type[m] == 4) {
			// The original water record's sign bit is separate
			// land depth. Fresh records initialize it to zero (6c4ed0).
			if (mi >= 64) {
				VERTEX.x += s * a;
				VERTEX.z -= s * a;
			}
		} else {
			// EI (x, y, z) = Godot (x, -z, y).
			VERTEX.y += s * a * 0.25;
			VERTEX.x += wave_sine(cr.x * 0.7853981 + t2) * a * 3.0;
			VERTEX.z -= wave_sine(cr.y * 0.7853981 + t2) * a * 3.0;
		}
		if (s >= 0.0) {
			spec = wave_specular(s, wv, mat_rgb[m]);
		}
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
vec2 tile_turn(vec2 p, int rotation) {
	if (rotation == 1) { return vec2(-p.y, p.x); }
	if (rotation == 2) { return -p; }
	if (rotation == 3) { return vec2(p.y, -p.x); }
	return p;
}
// A tile of the atlases at p (0..1 over the tile, EI x / y), as _tile_uv
// maps it: the 8-texel border left out, the rotation code applied.
vec3 tile_sample(int code, vec2 p, vec2 dx, vec2 dy) {
	int tile = code & 63;
	int rotation = (code >> 14) & 3;
	int per_row = int(tiles_per_axis);
	float border = 8.0 * source_texel * tiles_per_axis;
	float interior = 1.0 - 2.0 * border;
	vec2 local = vec2(border) + (vec2(0.5) + tile_turn(p - 0.5, rotation)) * interior;
	local = clamp(vec2(local.x, 1.0 - local.y), vec2(0.0), vec2(1.0));
	vec2 origin = vec2(float(tile % per_row), float(per_row - 1 - tile / per_row));
	vec2 uv = (origin + local) / tiles_per_axis;
	vec2 gx = tile_turn(dx, rotation) * interior / tiles_per_axis;
	vec2 gy = tile_turn(dy, rotation) * interior / tiles_per_axis;
	return textureGrad(atlases, vec3(uv, float((code >> 6) & 255)), gx * vec2(1.0, -1.0), gy * vec2(1.0, -1.0)).rgb;
}
int tile_code(ivec2 c, int fallback) {
	float v = texelFetch(water_tiles, clamp(c, ivec2(0), textureSize(water_tiles, 0) - 1), 0).r;
	return v < 0.0 ? fallback : int(v + 0.5);
}
// The liquid texture with different neighbouring liquid tiles cross-faded
// over a wobbly line (the original changes texture at the tile edge).
// dx / dy: the tile grid's screen derivatives, taken in uniform control flow.
vec3 water_texture(vec3 own, vec2 dx, vec2 dy) {
	if (!blend_tiles) { return own; }
	vec2 g = tgrid;
	ivec2 home = ivec2(floor(g));
	int code = tile_code(home, -1);
	if (code < 0) { return own; }
	vec2 wob = vec2(textureLod(foam_tex, g * 0.23, 0.0).r, textureLod(foam_tex, g * 0.23 + vec2(0.37, 0.61), 0.0).r) - 0.5;
	vec2 gs = g + wob * 0.9;
	ivec2 c = ivec2(floor(gs));
	vec2 q = gs - vec2(c);
	ivec2 st = ivec2(q.x < 0.5 ? -1 : 1, q.y < 0.5 ? -1 : 1);
	int c0 = tile_code(c, code);
	int cx = tile_code(c + ivec2(st.x, 0), c0);
	int cy = tile_code(c + ivec2(0, st.y), c0);
	int cxy = tile_code(c + st, c0);
	if (c0 == code && cx == code && cy == code && cxy == code) { return own; }
	vec2 w = 0.5 * (1.0 - smoothstep(vec2(0.0), vec2(0.5), min(q, 1.0 - q)));
	vec2 p = fract(g);
	vec3 a = c0 == code ? own : tile_sample(c0, p, dx, dy);
	vec3 b = cx == c0 ? a : tile_sample(cx, p, dx, dy);
	vec3 d = cy == c0 ? a : tile_sample(cy, p, dx, dy);
	vec3 e = cxy == c0 ? a : tile_sample(cxy, p, dx, dy);
	return mix(mix(a, b, w.x), mix(d, e, w.x), w.y);
}
vec3 scene_pos(vec2 uv, mat4 inv_proj) {
	float z = textureLod(depth_tex, uv, 0.0).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	z = z * 2.0 - 1.0;
	#endif
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
	return v.xyz / v.w;
}
// One short-lived expanding ring per 0.8 m cell. Its full radius fits in
// the 3 x 3 neighbourhood, so seams are continuous with exactly nine taps.
vec2 rain_rings(vec2 p, float now) {
	vec2 grid = p * 1.25;
	vec2 base = floor(grid);
	vec2 sum = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base + vec2(float(x), float(y));
			vec3 h = fract(sin(vec3(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)), dot(cell, vec2(419.2, 371.9)))) * 43758.5453);
			float cycle = now * 0.85 + h.z;
			float age = fract(cycle);
			vec2 delta = grid - cell - (0.2 + h.xy * 0.6);
			float distance = length(delta);
			float ring = distance - age * 0.80;
			float envelope = (1.0 - smoothstep(0.0, 0.075, abs(ring))) * smoothstep(0.02, 0.10, age) * (1.0 - age) * (1.0 - age);
			sum += delta / max(distance, 0.001) * sin(ring * 41.89) * envelope;
		}
	}
	return sum;
}
// Screen-space reflection traced through the opaque depth / colour copy
// (Godot's own SSR pass runs before transparent water). Alpha = confidence,
// faded at the screen edge and the ray limit.
vec4 water_ssr(vec3 origin, vec3 normal, mat4 proj, mat4 inv_proj, mat4 inv_view) {
	vec3 ray = reflect(normalize(origin), normal);
	vec3 start = origin + normal * 0.08;
	float previous = 0.0;
	const float reach = 45.0;
	const int steps = 40;
	for (int i = 0; i < steps; i++) {
		float f = float(i + 1) / float(steps);
		float travel = 0.15 + reach * f * f;
		vec3 p = start + ray * travel;
		if (p.z > -0.1) { break; }
		vec4 clip = proj * vec4(p, 1.0);
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (any(lessThanEqual(uv, vec2(0.001))) || any(greaterThanEqual(uv, vec2(0.999)))) { break; }
		vec3 hit = scene_pos(uv, inv_proj);
		if (hit.z - p.z > 0.0) {
			float lo = previous;
			float hi = travel;
			for (int j = 0; j < 6; j++) {
				float mid = (lo + hi) * 0.5;
				vec3 mp = start + ray * mid;
				vec4 mc = proj * vec4(mp, 1.0);
				vec2 mu = mc.xy / mc.w * 0.5 + 0.5;
				if (scene_pos(mu, inv_proj).z > mp.z) { hi = mid; } else { lo = mid; }
			}
			p = start + ray * hi;
			clip = proj * vec4(p, 1.0);
			uv = clip.xy / clip.w * 0.5 + 0.5;
			hit = scene_pos(uv, inv_proj);
			float gap = hit.z - p.z;
			float tolerance = 0.18 + hi * 0.012;
			vec3 world_hit = (inv_view * vec4(hit, 1.0)).xyz;
			// Not the bed or the banks under the surface.
			if (gap < 0.0 || gap > tolerance || world_hit.y < wpos.y + 0.03) { return vec4(0.0); }
			vec2 edge = min(uv, vec2(1.0) - uv);
			float confidence = smoothstep(0.0, 0.08, min(edge.x, edge.y));
			confidence *= 1.0 - smoothstep(30.0, reach, hi);
			confidence *= 1.0 - smoothstep(tolerance * 0.5, tolerance, gap);
			return vec4(textureLod(screen_tex, uv, 0.0).rgb, confidence);
		}
		previous = travel;
	}
	return vec4(0.0);
}
void fragment() {
	ei_wave_scale = 1.0;
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec4 own = EI_ATLAS(UV, UV2.x);
	vec3 t = water_texture(own.rgb, dFdx(tgrid), dFdy(tgrid));
	vec3 gn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 q = wpos.xz;
	if (is_lava > 0.5) {
		float n1 = texture(foam_tex, q * 0.045 + TIME * vec2(0.006, 0.004)).r;
		float n2 = texture(foam_tex, q * 0.11 - TIME * vec2(0.004, 0.009)).r;
		float heat = smoothstep(0.35, 0.85, n1 * 0.6 + n2 * 0.6 - 0.1);
		ALBEDO = t * 0.35;
		EMISSION = t * (0.6 + 2.2 * heat) * vec3(1.0, 0.75, 0.55) + vec3(1.0, 0.35, 0.05) * heat * heat * 0.8;
		ALPHA = 1.0;
	} else {
		vec2 cells_uv = vec2(wpos.x, -wpos.z) / vec2(textureSize(terrain_cells, 0));
		bool swamp = int(texture(terrain_cells, cells_uv).b + 0.5) == 14;
		// Ripples: two normal maps drifting across each other (world space).
		vec3 na = texture(wave_a, q * 0.055 + TIME * vec2(0.010, 0.006)).rgb * 2.0 - 1.0;
		vec3 nb = texture(wave_b, q * 0.13 + TIME * vec2(-0.008, 0.012)).rgb * 2.0 - 1.0;
		vec2 slope = (na.xy * 0.6 + nb.xy * 0.4) * (swamp ? 0.18 : ripple_amount) * 0.35;
		// Raindrops on open water; subpixel rings fade out with distance.
		vec2 rain_slope = vec2(0.0);
		float rain = ei_surface_fx.z * ei_weather.y;
		if (rain > 0.001) {
			float exposed = 1.0 - smoothstep(0.08, 0.40, texture(rain_cover, cells_uv).r - wpos.y);
			float near = 1.0 - smoothstep(18.0, 45.0, length(VERTEX));
			if (exposed * near > 0.001) {
				rain_slope = rain_rings(q, TIME) * rain * exposed * near * 0.28;
			}
		}
		vec3 wn = normalize(gn + vec3(slope.x + rain_slope.x, 0.0, slope.y + rain_slope.y));
		vec3 rn = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		// Depth below the surface along the vertical (opaque depth copy):
		// the soft shore and the surf band.
		vec3 vdir = normalize(VERTEX);
		float thick = max(length(scene_pos(SCREEN_UV, INV_PROJECTION_MATRIX)) - length(VERTEX), 0.0);
		float vdepth = thick * abs((INV_VIEW_MATRIX * vec4(vdir, 0.0)).y);
		float shore = smoothstep(0.0, 0.25, vdepth);
		float a = clamp(alpha, 0.0, 1.0) * shore;   // vertex alpha only, as the original
		float foam = 0.0;
		if (surf_amount > 0.0 && !swamp) {
			float band = 1.0 - smoothstep(0.0, 0.45, vdepth);
			float fn = texture(foam_tex, q * 0.32 + TIME * vec2(0.015, -0.01)).r;
			float fn2 = texture(foam_tex, q * 0.7 - TIME * vec2(0.01, 0.02)).r;
			foam = smoothstep(0.55, 0.75, fn * 0.6 + fn2 * 0.5 + band * 0.45 - 0.25) * band * surf_amount;
			foam *= smoothstep(0.0, 0.06, vdepth);
			t = mix(t, vec3(0.85), foam * 0.7);
			a = mix(a, 0.9, foam * 0.7);
		}
		// Reflection weight: Schlick's Fresnel term without its 2 % floor,
		// so the game's steep view keeps the original colour (2 % of the
		// bright [sky] colour turned the dark bog cyan) and the reflection
		// grows only toward grazing views; rain rings catch more of the sky.
		// Mirror strengthens the scene reflection, capped so the water's
		// own colour always stays.
		float fres = pow(1.0 - clamp(dot(rn, VIEW), 0.0, 1.0), 5.0);
		vec3 R = ei_lin(ei_sky);
		float w = fres + min(length(rain_slope) * 0.6, 0.18);
		if (reflections) {
			// Mirror: a calmer surface for the traced ray, so reflected
			// trees and cliffs stay recognisable.
			vec3 sn = normalize(gn + vec3(slope.x * mix(1.0, 0.25, mirror) + rain_slope.x, 0.0, slope.y * mix(1.0, 0.25, mirror) + rain_slope.y));
			vec4 r = water_ssr(VERTEX, normalize((VIEW_MATRIX * vec4(sn, 0.0)).xyz), PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
			float wm = min(fres * mix(2.0, 6.0, mirror), mix(0.2, 0.35, mirror));
			R = mix(R, r.rgb, r.a);
			w = mix(w, max(w, wm), r.a);
		}
		w *= (1.0 - foam) * shore;
		// Sun glint, peak 20/255 of the sun colour like the original vertex
		// specular, so it never reaches the bloom threshold.
		// The original adds it to the sRGB colour; × 0.4 is that step on the dark
		// water (sRGB ≈ 0.2) in linear light.
		vec3 L = ei_sun_dir;
		vec3 G = vec3(0.0);
		// No glint on the bog: its liquid texture is a duckweed-green mat.
		if (dot(L, L) > 0.5 && L.y > 0.0 && !swamp) {
			vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
			vec3 H = normalize(L + V);
			G = ei_lin(min(ei_sun, vec3(1.0))) * (0.4 * 20.0 / 255.0) * pow(max(dot(wn, H), 0.0), 900.0) * (1.0 - foam) * shore;
		}
		float A = 1.0 - (1.0 - a) * (1.0 - w);
		float k = (1.0 - w) * a / max(A, 1e-3);
		ALBEDO = t * k;
		ei_wave_scale = k;
		EMISSION = (w * R + G) / max(A, 1e-3);
		ALPHA = A;
	}
}
"""


var map_name := ""
## Internal .mp/.sec and atlas basename; renamed .mpr files can differ.
var resource_prefix := ""
var max_altitude := 0.0
var sectors_x := 0
var sectors_y := 0
var texture_size := 512
var tile_size := 64
## Map materials from the .mp header: {type, color: Color}
var materials: Array[Dictionary] = []
## Ground heights (EI z) on the global vertex grid.
var heights := PackedFloat32Array()
var grid_w := 0
## Water surface height per terrain cell (EI z), -INF where there is no water.
## Includes the SetWaterLevel offset of the cell's material (water_base + offset).
var water := PackedFloat32Array()
## Water height per cell as read from the .sec files.
var water_base := PackedFloat32Array()
## Map material of the liquid tile per cell, 255 = none.
var water_mat := PackedByteArray()
## SetWaterLevel: current level offset (EI z) per map material.
var water_offsets := {}
## Walkable-surface heights from objects like bridges, -INF where none.
var surface := PackedFloat32Array()
## Ground type per cell (tiledesc.reg: 0 grass .. 13 lava, 14 swamp, 15 high rock).
var ground := PackedByteArray()
## .mp id array: ground type of every atlas tile.
var tile_types := PackedInt32Array()
## Ground type of the liquid tile per cell (from its water texture), 255 = none.
var liquid_ground := PackedByteArray()
## Tile codes per 2 x 2-cell tile (land; liquid or -1), for the outer landscape.
var land_tile := PackedInt32Array()
## Land vertex xy jitter (EI metres) and normal (Godot space) per grid vertex.
var land_xy := PackedVector2Array()
var land_n := PackedVector3Array()
var water_tile := PackedInt32Array()
const LAVA := 13
## Render layer of the surfaces ground marks are projected onto (terrain and
## walkable object surfaces; GroundMarks' and ContactShadows' decals cull
## everything else). Layer 19 (bit 18): bit 19 is GameUnit.OFFSCREEN_LAYER,
## and sharing it put the decals on far figures.
const DECAL_LAYER := 1 << 18

var _atlases: Texture2DArray
var _detail_atlases: Texture2DArray
var _atlas_hd := false
const TERRAIN_GUTTER := 8
var _water_mat: ShaderMaterial
var _waves := WaveState.new()
var _land_mat: ShaderMaterial
var _level := PackedFloat32Array()
var _lava := PackedFloat32Array()
var _surf := PackedFloat32Array()
var _ripple := PackedFloat32Array()
var _height_tex: ImageTexture
var _cell_tex: ImageTexture
var _tile_tex: ImageTexture
var _water_tile_tex: ImageTexture
var _rain_cover: ImageTexture
var details: TerrainDetails
static var _land_shader: Shader
static var _water_shader: Shader
static var _water_fx_shader: Shader

## The .mp format has generic liquid materials, not ocean/river/lake tags.
## Only confirmed sea materials get breaking surf. On the starting map,
## 2 is the western sea, 0 the inland stream, 1 the bog. Unknown water stays
## calm; neither touching a map edge nor having waves proves it is a sea.
## Profiles are local to the remake; the original material shader is intact.
const SEA_MATERIALS := {"zone1": [2]}


static func load_map(name: String) -> EITerrain:
	var arc := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % name))
	if arc == null:
		return null
	var prefix := resolve_map_prefix(arc, name)
	if prefix.is_empty():
		push_error("No unambiguous .mp header in %s.mpr" % name)
		return null
	var t := EITerrain.new()
	t.name = "Terrain"
	t.map_name = name
	t.resource_prefix = prefix
	if not t._parse_header(arc.read(prefix + ".mp")):
		push_error("Bad .mp header in %s" % name)
		t.free()
		return null
	t._load_atlases()
	t._build(arc)
	return t


## Lost in Astral reuses maps under new filenames but retains their internal
## names. Prefer the requested header; only fall back when there is one .mp.
static func resolve_map_prefix(arc: EIResArchive, requested: String) -> String:
	if arc.has(requested + ".mp"):
		return requested
	var headers := arc.names_with_suffix(".mp")
	return headers[0].get_basename() if headers.size() == 1 else ""


## Terrain height (EI z) at EI world x, y using bilinear interpolation.
func height_at(x: float, y: float) -> float:
	var gh := sectors_y * SECTOR + 1
	x = clampf(x, 0.0, grid_w - 1.001)
	y = clampf(y, 0.0, gh - 1.001)
	var ix := int(x)
	var iy := int(y)
	var fx := x - ix
	var fy := y - iy
	var i := iy * grid_w + ix
	var a := lerpf(heights[i], heights[i + 1], fx)
	var b := lerpf(heights[i + grid_w], heights[i + grid_w + 1], fx)
	return lerpf(a, b, fy)


func size_ei() -> Vector2:
	return Vector2(sectors_x * SECTOR, sectors_y * SECTOR)


func _parse_header(d: PackedByteArray) -> bool:
	if d.size() < 38 or d.decode_u32(0) != MP_MAGIC:
		return false
	max_altitude = d.decode_float(4)
	sectors_x = d.decode_u32(8)
	sectors_y = d.decode_u32(12)
	texture_size = d.decode_u32(20)
	tile_size = d.decode_u32(28)
	var mat_count := d.decode_u16(32)
	for i in mat_count:
		var p := 38 + i * 44
		materials.append({
			"type": d.decode_u32(p),
			"color": Color(d.decode_float(p + 4), d.decode_float(p + 8), d.decode_float(p + 12), d.decode_float(p + 16)),
			"self_illum": d.decode_float(p + 20),
			"wave": d.decode_float(p + 24),
			"warp": d.decode_float(p + 28),
		})
	var textures_count := d.decode_u32(16)
	set_meta("textures_count", textures_count)
	var tiles_count := d.decode_u32(24)
	var ids_at := 38 + mat_count * 44
	if ids_at + tiles_count * 4 <= d.size():
		tile_types = d.slice(ids_at, ids_at + tiles_count * 4).to_int32_array()
	grid_w = sectors_x * SECTOR + 1
	heights.resize(grid_w * (sectors_y * SECTOR + 1))
	land_xy.resize(heights.size())
	land_n.resize(heights.size())
	water.resize(sectors_x * SECTOR * sectors_y * SECTOR)
	water.fill(-INF)
	surface.resize(water.size())
	surface.fill(-INF)
	ground.resize(water.size())
	liquid_ground.resize(water.size())
	liquid_ground.fill(255)
	water_mat.resize(water.size())
	water_mat.fill(255)
	land_tile.resize(sectors_x * TILES * sectors_y * TILES)
	water_tile.resize(land_tile.size())
	water_tile.fill(-1)
	return true


func _load_atlases() -> void:
	_atlas_hd = Gfx.on("gfx_hd_textures") # applies on zone load, also for lazy detail
	var images: Array[Image] = []
	for i in int(get_meta("textures_count")):
		var img := GameData.load_image("%s%03d" % [resource_prefix, i])
		if img == null or img.get_width() != texture_size:
			push_warning("Missing terrain atlas %s%03d" % [resource_prefix, i])
			var n := texture_size * (2 if _atlas_hd else 1)
			img = Image.create(n, n, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
		elif _atlas_hd:
			img = TexUpscale.up2(img, false)   # option gfx_hd_textures (UVs are normalised)
		img.generate_mipmaps()
		images.append(img)
	_atlases = Texture2DArray.new()
	_atlases.create_from_images(images)


## Edge-extruded gutters isolate packed tiles during upscale and filtering.
## Keep this separate from the original atlases used by water / detail off.
static func padded_atlas(source: Image, tile: int, gutter: int) -> Image:
	var src := source.duplicate() as Image
	src.clear_mipmaps()
	src.convert(Image.FORMAT_RGBA8)
	var count := src.get_width() / tile
	var stride := tile + gutter * 2
	var out := Image.create(count * stride, count * stride, false, Image.FORMAT_RGBA8)
	for ty in count:
		for tx in count:
			var origin := Vector2i(tx * tile, ty * tile)
			var dest := Vector2i(tx * stride + gutter, ty * stride + gutter)
			out.blit_rect(src, Rect2i(origin, Vector2i(tile, tile)), dest)
			# Extend both vertical edges, then the full top/bottom rows so
			# corners are filled too. Image operations avoid per-pixel GDScript.
			for p in gutter:
				out.blit_rect(src, Rect2i(origin, Vector2i(1, tile)), dest - Vector2i(p + 1, 0))
				out.blit_rect(src, Rect2i(origin + Vector2i(tile - 1, 0), Vector2i(1, tile)), dest + Vector2i(tile + p, 0))
			var top := out.get_region(Rect2i(dest - Vector2i(gutter, 0), Vector2i(stride, 1)))
			var bottom := out.get_region(Rect2i(dest + Vector2i(-gutter, tile - 1), Vector2i(stride, 1)))
			for p in gutter:
				out.blit_rect(top, Rect2i(0, 0, stride, 1), dest - Vector2i(gutter, p + 1))
				out.blit_rect(bottom, Rect2i(0, 0, stride, 1), dest + Vector2i(-gutter, tile + p))
	return out


func _ensure_detail_atlases() -> void:
	if _detail_atlases != null:
		return
	var images: Array[Image] = []
	for i in int(get_meta("textures_count")):
		var source := GameData.load_image("%s%03d" % [resource_prefix, i])
		if source == null or source.get_width() != texture_size:
			source = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
			source.fill(Color.MAGENTA)
		var img := padded_atlas(source, tile_size, TERRAIN_GUTTER)
		if _atlas_hd:
			img = TexUpscale.up2(img, false)
		img.generate_mipmaps()
		images.append(img)
	_detail_atlases = Texture2DArray.new()
	_detail_atlases.create_from_images(images)


func _tile_uv(f: int, dx: int, dy: int) -> Array:
	var tile := f & 63
	var atlas := (f >> 6) & 255
	var k: int = ROT_PERM[(f >> 14) & 3][dy * 3 + dx]
	var per_row := texture_size / tile_size
	var half := tile_size * 0.5
	var u := (tile % per_row) * tile_size + clampf((k % 3) * half, TILE_BORDER, tile_size - TILE_BORDER)
	var v := (tile / per_row) * tile_size + clampf((k / 3) * half, TILE_BORDER, tile_size - TILE_BORDER)
	# Atlas tile rows are counted from the bottom of the stored image.
	return [Vector2(u / texture_size, 1.0 - v / texture_size), atlas]


func _build(arc: EIResArchive) -> void:
	if _land_shader == null:
		Gfx.ensure_globals()
		_land_shader = Gfx.make_shader(TERRAIN_SHADER, true, true)
		_water_shader = Gfx.make_shader(WATER_SHADER, true, true)
		_water_fx_shader = Gfx.make_shader(WATER_FX_SHADER, true, true)
	Gfx.set_border(size_ei())
	var land_mat := ShaderMaterial.new()
	land_mat.shader = _land_shader
	land_mat.set_shader_parameter("atlases", _atlases)
	_land_mat = land_mat
	var wmat := ShaderMaterial.new()
	wmat.shader = _water_shader
	#  draws the liquids after the figures and
	# before the effects, with z writes on: particles under the surface stay
	# hidden. Godot draws units (alpha-to-coverage) in its transparent pass,
	# so the water goes after them and before ParticleFx.RENDER_PRIORITY,
	# and writes depth for the particles' depth test.
	wmat.render_priority = ParticleFx.RENDER_PRIORITY - 1
	_water_mat = wmat
	_level.resize(64)
	_lava.resize(64)

	for sy in sectors_y:
		NetStatus.keep_alive()
		for sx in sectors_x:
			var d := arc.read("%s%03d%03d.sec" % [resource_prefix, sx, sy])
			if d.size() < 5 or d.decode_u32(0) != SEC_MAGIC:
				push_warning("Missing sector %d,%d" % [sx, sy])
				continue
			var liquids := d[4] != 0
			var land := _read_vertices(d, 5, sx, sy, true)
			var tex_off := 5 + VERTS * VERTS * 8 * (2 if liquids else 1)
			var land_tex := _read_u16s(d, tex_off)
			_record_ground(land_tex, sx, sy)
			var wverts := []
			var water_mats := PackedInt32Array()
			var vert_mats := PackedInt32Array()
			if liquids:
				water_mats = _read_u16s(d, tex_off + 1024)
				vert_mats = _vertex_materials(water_mats)
				wverts = _read_vertices(d, 5 + VERTS * VERTS * 8, sx, sy, false)
				_liquid_xy(wverts[0], land[0], water_mats, sx, sy)
				land.append(_underwater(land[0], wverts[0], vert_mats))
			var mi := _make_mesh(land, land_tex, PackedInt32Array(), land_mat, Vector2i(sx * TILES, sy * TILES))
			mi.name = "Sector_%d_%d" % [sx, sy]
			mi.layers = SHADOW_RECEIVER_LAYER | DECAL_LAYER
			add_child(mi)
			if liquids:
				var water_tex := _read_u16s(d, tex_off + 512)
				_record_water(wverts[0], water_mats, sx, sy)
				_record_liquid_ground(water_tex, water_mats, sx, sy)
				var wm := _make_mesh(wverts, water_tex, water_mats, wmat, Vector2i.ZERO, vert_mats)
				if wm:
					wm.name = "Water_%d_%d" % [sx, sy]
					wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					wm.extra_cull_margin = 8.0   # SetWaterLevel moves it in the shader
					add_child(wm)
	water_base = water.duplicate()
	# Lava: map materials whose liquid tiles are of ground type 13.
	for i in water_mat.size():
		if water_mat[i] < 64 and liquid_ground[i] == LAVA:
			_lava[water_mat[i]] = 1.0
	_build_surface_data()
	apply_gfx()


## Shared data for view-independent surf depth and material-specific ground
## detail. Original atlases, collision and navigation are never altered.
func _build_surface_data() -> void:
	var tiles := PackedFloat32Array()
	tiles.resize(land_tile.size() * 4)
	for i in land_tile.size():
		var code := land_tile[i]
		var type_id := code & 0x3fff
		tiles[i * 4] = code
		tiles[i * 4 + 1] = tile_types[type_id] if type_id < tile_types.size() else 0
	_tile_tex = ImageTexture.create_from_image(Image.create_from_data(sectors_x * TILES,
		sectors_y * TILES, false, Image.FORMAT_RGBAF, tiles.to_byte_array()))
	var wtiles := PackedFloat32Array()
	wtiles.resize(water_tile.size())
	for i in water_tile.size():
		wtiles[i] = water_tile[i]
	_water_tile_tex = ImageTexture.create_from_image(Image.create_from_data(sectors_x * TILES,
		sectors_y * TILES, false, Image.FORMAT_RF, wtiles.to_byte_array()))
	_height_tex = ImageTexture.create_from_image(Image.create_from_data(
		grid_w, sectors_y * SECTOR + 1, false, Image.FORMAT_RF, heights.to_byte_array()))
	var cells := PackedFloat32Array()
	cells.resize(water.size() * 4)
	for i in water.size():
		cells[i * 4] = water_base[i] if is_finite(water_base[i]) else -10000.0
		cells[i * 4 + 1] = ground[i]
		cells[i * 4 + 2] = liquid_ground[i]
		cells[i * 4 + 3] = water_mat[i] if water_mat[i] < 64 else 0
	_cell_tex = ImageTexture.create_from_image(Image.create_from_data(
		sectors_x * SECTOR, sectors_y * SECTOR, false, Image.FORMAT_RGBAF, cells.to_byte_array()))
	# Until SurfaceWeather scans the placed solids, the map is uncovered.
	# This also keeps standalone terrain viewers and original-water fixtures
	# usable without a Game or weather controller.
	var uncovered := Image.create(1, 1, false, Image.FORMAT_RF)
	uncovered.fill(Color(-10000.0, 0.0, 0.0))
	_rain_cover = ImageTexture.create_from_image(uncovered)
	_surf.resize(64)
	_surf.fill(0.0)
	_ripple.resize(64)
	_ripple.fill(0.35)
	for m in mini(materials.size(), 64):
		_ripple[m] = clampf(0.25 + float(materials[m].get("wave", 0.0)) * 0.65, 0.25, 1.0)
		if m in SEA_MATERIALS.get(resource_prefix, []) and _lava[m] == 0.0:
			_surf[m] = 1.0
			_ripple[m] = 1.0


## Remake rendering options (gfx_water, gfx_terrain) on the terrain and water
## materials; parameters are set again after a shader swap.
func apply_gfx() -> void:
	if _water_mat == null:
		return
	var fx := GameData.option("gfx_water") != 0
	_water_mat.shader = _water_fx_shader if fx else _water_shader
	_water_mat.set_shader_parameter("atlases", _atlases)
	_water_mat.set_shader_parameter("level", _level)
	_land_mat.set_shader_parameter("level", _level)
	_land_mat.set_shader_parameter("terrain_cells", _cell_tex)
	_land_mat.set_shader_parameter("terrain_tiles", _tile_tex)
	_land_mat.set_shader_parameter("rain_cover", _rain_cover)
	# The original water's terms (also the base of the remake water).
	var me := PackedVector3Array()
	var ma := PackedFloat32Array()
	var mw := PackedFloat32Array()
	var mc := PackedVector3Array()
	var mt := PackedInt32Array()
	me.resize(64)
	ma.resize(64)
	mw.resize(64)
	mc.resize(64)
	mt.resize(64)
	for i in mini(materials.size(), 64):
		var e := material_e(i)
		me[i] = Vector3(e.r, e.g, e.b)
		var c: Color = materials[i].color
		ma[i] = c.a
		mw[i] = float(materials[i].get("wave", 0.0))
		mc[i] = Vector3(c.r, c.g, c.b)
		mt[i] = int(materials[i].get("type", 0))
	_water_mat.set_shader_parameter("mat_e", me)
	_water_mat.set_shader_parameter("mat_a", ma)
	_water_mat.set_shader_parameter("mat_wave", mw)
	_water_mat.set_shader_parameter("mat_rgb", mc)
	_water_mat.set_shader_parameter("mat_type", mt)
	_water_mat.set_shader_parameter("sine_tex", wave_sine_texture())
	_update_wave_parameters()
	_water_mat.set_shader_parameter("phase_tex", wave_phase_texture())
	if fx:
		_water_mat.set_shader_parameter("lava", _lava)
		_water_mat.set_shader_parameter("surf", _surf)
		_water_mat.set_shader_parameter("ripple", _ripple)
		_water_mat.set_shader_parameter("water_tiles", _water_tile_tex)
		_water_mat.set_shader_parameter("tiles_per_axis", float(texture_size) / tile_size)
		_water_mat.set_shader_parameter("source_texel", 1.0 / texture_size)
		_water_mat.set_shader_parameter("terrain_cells", _cell_tex)
		_water_mat.set_shader_parameter("rain_cover", _rain_cover)
		_water_mat.set_shader_parameter("reflections", Gfx.on("gfx_water_reflections"))
		_water_mat.set_shader_parameter("mirror", 1.0 if GameData.option("gfx_water_reflections") == 2 else 0.0)
		_water_mat.set_shader_parameter("wave_a", Gfx.noise("wave_a", 256, 0.018, 4, true, 5.0))
		_water_mat.set_shader_parameter("wave_b", Gfx.noise("wave_b", 256, 0.03, 3, true, 4.0))
		_water_mat.set_shader_parameter("foam_tex", Gfx.noise("foam", 256, 0.03, 4))
	var det := GameData.option("gfx_terrain") != 0
	_land_mat.set_shader_parameter("detail", 1.0 if det else 0.0)
	if det:
		_ensure_detail_atlases()
		_land_mat.set_shader_parameter("detail_nm", Gfx.noise("ground", 512, 0.02, 5, true, 3.0))
		_land_mat.set_shader_parameter("macro_tex", Gfx.noise("macro", 256, 0.015, 3))
	_land_mat.set_shader_parameter("atlases", _detail_atlases if det else _atlases)
	_land_mat.set_shader_parameter("tiles_per_axis", float(texture_size) / tile_size)
	_land_mat.set_shader_parameter("atlas_padding", float(TERRAIN_GUTTER) / tile_size if det else 0.0)
	_land_mat.set_shader_parameter("source_texel", 1.0 / texture_size)
	if not is_instance_valid(details) and (Gfx.on("gfx_grass") or Gfx.on("gfx_soft_ground")):
		details = TerrainDetails.create(self)
	elif is_instance_valid(details):
		details.apply_options()


## SurfaceWeather's static cover map affects rendering only. Keep it across
## water shader switches; water-level changes are evaluated in the shader.
func set_rain_cover(image: Image) -> void:
	if image == null or image.is_empty():
		return
	_rain_cover = ImageTexture.create_from_image(image)
	if _land_mat:
		_land_mat.set_shader_parameter("rain_cover", _rain_cover)
	if _water_mat and _water_mat.shader == _water_fx_shader:
		_water_mat.set_shader_parameter("rain_cover", _rain_cover)
	if is_instance_valid(details) and is_instance_valid(details.soft_ground):
		details.soft_ground.refresh_rain_cover()


func _record_ground(tex: PackedInt32Array, sx: int, sy: int) -> void:
	var tw := sectors_x * TILES
	for ty in TILES:
		for tx in TILES:
			land_tile[(sy * TILES + ty) * tw + sx * TILES + tx] = tex[ty * TILES + tx]
	if tile_types.is_empty():
		return
	var per_tex := (texture_size / tile_size) * (texture_size / tile_size)
	var cells_w := sectors_x * SECTOR
	for ty in TILES:
		for tx in TILES:
			var f := tex[ty * TILES + tx]
			var idx := ((f >> 6) & 255) * per_tex + (f & 63)
			var type := tile_types[idx] if idx < tile_types.size() else 0
			for dy in 2:
				for dx in 2:
					ground[(sy * SECTOR + ty * 2 + dy) * cells_w + sx * SECTOR + tx * 2 + dx] = type


func _record_liquid_ground(tex: PackedInt32Array, mats: PackedInt32Array, sx: int, sy: int) -> void:
	var tw := sectors_x * TILES
	for ty in TILES:
		for tx in TILES:
			if mats[ty * TILES + tx] != NO_LIQUID:
				water_tile[(sy * TILES + ty) * tw + sx * TILES + tx] = tex[ty * TILES + tx]
	if tile_types.is_empty():
		return
	var per_tex := (texture_size / tile_size) * (texture_size / tile_size)
	var cells_w := sectors_x * SECTOR
	for ty in TILES:
		for tx in TILES:
			if mats[ty * TILES + tx] == NO_LIQUID:
				continue
			var f := tex[ty * TILES + tx]
			var idx := ((f >> 6) & 255) * per_tex + (f & 63)
			var type := tile_types[idx] if idx < tile_types.size() else 0
			for dy in 2:
				for dx in 2:
					liquid_ground[(sy * SECTOR + ty * 2 + dy) * cells_w + sx * SECTOR + tx * 2 + dx] = type


## Ground type under a mark (the original): the liquid tile's type
## where its surface is above the ground, else the land tile's; 8 (the unnamed
## prints.db row) off the map.
func mark_ground(x: float, y: float) -> int:
	var cx := int(roundf(x))
	var cy := int(roundf(y))
	if cx < 0 or cy < 0 or cx >= sectors_x * SECTOR or cy >= sectors_y * SECTOR:
		return 8
	var i := cy * sectors_x * SECTOR + cx
	if liquid_ground[i] != 255 and water[i] > height_at(x, y):
		return liquid_ground[i]
	return ground[i]


func ground_type(x: float, y: float) -> int:
	var cx := int(x)
	var cy := int(y)
	if cx >= 0 and cy >= 0 and cx < sectors_x * SECTOR and cy < sectors_y * SECTOR:
		return ground[cy * sectors_x * SECTOR + cx]
	return 0


## Walking speed factor of the ground at a point (1 on grass and roads).
func speed_at(x: float, y: float) -> float:
	return maxf(0.3, ground_value(ground_type(x, y), "Speed", 1024.0) / 1024.0)


## A tiledesc.reg value of a ground type (GameData.ground_types).
static func ground_value(type: int, key: String, fallback: float) -> float:
	return float(GameData.ground_types.get(type, {}).get(key, fallback))


## Footstep noise factor of the ground (tiledesc.reg StepSound / 100, used by
## swamp 1.3, lava 0).
func step_sound_at(x: float, y: float) -> float:
	return ground_value(ground_type(x, y), "StepSound", 100.0) / 100.0


func _record_water(pos: PackedVector3Array, mats: PackedInt32Array, sx: int, sy: int) -> void:
	var cells_w := sectors_x * SECTOR
	for ty in TILES:
		for tx in TILES:
			if mats[ty * TILES + tx] == NO_LIQUID:
				continue
			for dy in 2:
				for dx in 2:
					var vi := (ty * 2 + dy) * VERTS + tx * 2 + dx
					var level := maxf(pos[vi].y, pos[vi + VERTS + 1].y)
					var gx := sx * SECTOR + tx * 2 + dx
					var gy := sy * SECTOR + ty * 2 + dy
					water[gy * cells_w + gx] = level
					water_mat[gy * cells_w + gx] = mini(mats[ty * TILES + tx], 254)


## Ground height (EI z) a walking unit stands on: terrain, or a bridge/floor above it.
func ground_at(x: float, y: float) -> float:
	var h := height_at(x, y)
	var cx := int(x)
	var cy := int(y)
	if cx >= 0 and cy >= 0 and cx < sectors_x * SECTOR and cy < sectors_y * SECTOR:
		h = maxf(h, surface[cy * sectors_x * SECTOR + cx])
	return h


## ground_at over given arrays, the same sums (height_at, then the surface
## cell): ParticleFx's per-tick snapshot FxGround samples the ground with it
## on worker threads, without touching this node.
static func ground_in(hs: PackedFloat32Array, surf: PackedFloat32Array, gw: int, cw: int, ch: int,
		x: float, y: float) -> float:
	var xc := clampf(x, 0.0, gw - 1.001)
	var yc := clampf(y, 0.0, ch + 1 - 1.001)
	var ix := int(xc)
	var iy := int(yc)
	var fx := xc - ix
	var fy := yc - iy
	var i := iy * gw + ix
	var h := lerpf(lerpf(hs[i], hs[i + 1], fx), lerpf(hs[i + gw], hs[i + gw + 1], fx), fy)
	var cx := int(x)
	var cy := int(y)
	if cx >= 0 and cy >= 0 and cx < cw and cy < ch:
		h = maxf(h, surf[cy * cw + cx])
	return h


## SetWaterLevel (the original): moves the water of map
## material `mat` to `offset` (EI z) above its level in the map files. The
## surface moves in the water shader; the per-cell levels (water) follow.
## Returns the cell rect whose water changed (empty when none).
func set_water_offset(mat: int, offset: float) -> Rect2i:
	if absf(float(water_offsets.get(mat, 0.0)) - offset) < 1e-6:
		return Rect2i()
	water_offsets[mat] = offset
	if _water_mat and mat >= 0 and mat < 64:
		_level = PackedFloat32Array()
		_level.resize(64)
		for m in water_offsets:
			if m >= 0 and m < 64:
				_level[m] = water_offsets[m]
		_water_mat.set_shader_parameter("level", _level)
		_land_mat.set_shader_parameter("level", _level)
	var cells_w := sectors_x * SECTOR
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for i in water_mat.size():
		if water_mat[i] == mat:
			water[i] = water_base[i] + offset
			var c := Vector2i(i % cells_w, i / cells_w)
			lo = lo.min(c)
			hi = hi.max(c)
	if hi.x < 0:
		return Rect2i()
	if is_instance_valid(details):
		details.water_changed()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func water_at(x: float, y: float) -> float:
	var cx := int(x)
	var cy := int(y)
	if cx >= 0 and cy >= 0 and cx < sectors_x * SECTOR and cy < sectors_y * SECTOR:
		return water[cy * sectors_x * SECTOR + cx]
	return -INF


var surface_rev := 0   # add_surface count (GameUnit._sync_transform's placement memo)


## Rasterizes upward-facing triangles of an object (e.g. a bridge deck) as walkable surface.
func add_surface(mesh_owner: Node3D) -> void:
	surface_rev += 1
	var cells_w := sectors_x * SECTOR
	for mi: MeshInstance3D in mesh_owner.find_children("*", "MeshInstance3D", true, false):
		mi.layers |= DECAL_LAYER
		var xf := NavGrid._local_xf(mi, mesh_owner)
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size() - 2, 3):
				var a: Vector3 = xf * v[idx[t]]
				var b: Vector3 = xf * v[idx[t + 1]]
				var c: Vector3 = xf * v[idx[t + 2]]
				var n := (b - a).cross(c - a)
				if n.length_squared() < 1e-8 or absf(n.normalized().y) < 0.6:
					continue
				var tri := PackedVector2Array([Vector2(a.x, -a.z), Vector2(b.x, -b.z), Vector2(c.x, -c.z)])
				var r := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
				for gy in range(maxi(0, int(r.position.y)), mini(sectors_y * SECTOR, int(r.end.y) + 1)):
					for gx in range(maxi(0, int(r.position.x)), mini(cells_w, int(r.end.x) + 1)):
						var q := Vector2(gx + 0.5, gy + 0.5)
						if Geometry2D.point_is_inside_triangle(q, tri[0], tri[1], tri[2]):
							var bc := _bary(q, tri)
							var h := a.y * bc.x + b.y * bc.y + c.y * bc.z
							var i := gy * cells_w + gx
							surface[i] = maxf(surface[i], h)


static func _bary(p: Vector2, t: PackedVector2Array) -> Vector3:
	var v0 := t[1] - t[0]
	var v1 := t[2] - t[0]
	var v2 := p - t[0]
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return Vector3(1, 0, 0)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


## Native per-sector CRT phase grid. Shared original startup call history is
## not reconstructed; both weather and water own explicit local CRT states.
static var _phase_tex: ImageTexture
static var _sine_tex: ImageTexture

static func wave_phase_texture() -> ImageTexture:
	if _phase_tex:
		return _phase_tex
	var grid := WaveState.phase_grid()
	var data := PackedFloat32Array()
	data.resize(32*32)
	for y in 32:
		for x in 32:
			data[y*32+x] = grid[y*33+x]
	_phase_tex = ImageTexture.create_from_image(Image.create_from_data(
		32,32,false,Image.FORMAT_RF,data.to_byte_array()))
	return _phase_tex

static func wave_sine_texture() -> ImageTexture:
	if _sine_tex == null:
		_sine_tex = ImageTexture.create_from_image(Image.create_from_data(
			512,1,false,Image.FORMAT_RF,WaveState.sine_table().to_byte_array()))
	return _sine_tex

func _process(dt: float) -> void:
	var world := get_parent() as GameWorld
	if world and world.session and world.session.lmp_travel \
			and not world.session.lmp_travel.can_tick(world):
		return
	_waves.advance(dt)
	_update_wave_parameters()

func _update_wave_parameters() -> void:
	if _water_mat == null:
		return
	_water_mat.set_shader_parameter("wave_phase",_waves.phase)
	_water_mat.set_shader_parameter("wave_ticks",_waves.time_ticks())
	_water_mat.set_shader_parameter("wave_amplitude",_waves.amplitude)
	_water_mat.set_shader_parameter("wave_gradient",_waves.gradient)
	_water_mat.set_shader_parameter("wind",_waves.force)


## E of a map material: min(1, self-illumination × colour) (
## material..).
func material_e(i: int) -> Color:
	var m: Dictionary = materials[i]
	var c: Color = m.color
	var k: float = m.get("self_illum", 0.0)
	return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0))


## Underwater terms of the land vertices: a land
## vertex below a liquid vertex takes that material's E and is dimmed by
## k = depth² / (15 · (1 − alpha)) (= 1 / 15, material =
## 1 / (1 − alpha)); the ambient becomes ambient · max(0, 1 − k), the sun
## sun · max(0, 1 − Lz² k). Returns per-vertex Color(E, k / 4).
## `vert_mats`: the vertex materials of _vertex_materials.
func _underwater(land_pos: PackedVector3Array, water_pos: PackedVector3Array, vert_mats: PackedInt32Array) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(VERTS * VERTS)
	out.fill(Color(0, 0, 0, 0))
	for vi in VERTS * VERTS:
		var m := vert_mats[vi]
		if m == NO_LIQUID:
			continue
		var depth := water_pos[vi].y - land_pos[vi].y
		if depth < 0.0:
			continue
		var a: float = (materials[m].color as Color).a
		var k := depth * depth / (15.0 * maxf(1.0 - a, 1e-3))
		var e := material_e(m)
		out[vi] = Color(e.r, e.g, e.b, minf(k * 0.25, 1.0))   # k / 4 (8-bit vertex colour)
	return out


## The material of each of a sector's 33 × 33 liquid vertices (vertex
## ): the first liquid tile of the vertex → tile table (map
## built; 20-byte entries {n, tile[4]}): column
## x/2 − 1 then x/2 for an even x, x/2 for an odd one, column outer, rows the
## same way, tiles outside 0..15 left out; the first with a liquid material
## (map ≠ −1) wins, NO_LIQUID if none. The original keeps one vertex
## grid point, so tiles of two materials share their edge vertices: the
## vertex alpha (material) and E, the wave (reads
##  material) and SetWaterLevel's shift (moves the
## vertices whose is the material) all follow this one material.
func _vertex_materials(mats: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(VERTS * VERTS)
	out.fill(NO_LIQUID)
	for vi in VERTS * VERTS:
		var vx := vi % VERTS
		var vy := vi / VERTS
		var m := NO_LIQUID
		for tx in range(vx / 2 - 1 + (vx & 1), vx / 2 + 1):
			if tx < 0 or tx >= TILES or m != NO_LIQUID:
				continue
			for ty in range(vy / 2 - 1 + (vy & 1), vy / 2 + 1):
				if ty < 0 or ty >= TILES:
					continue
				var mm := mats[ty * TILES + tx]
				if mm != NO_LIQUID and mm < materials.size():
					m = mm
					break
		out[vi] = m
	return out


func _read_u16s(d: PackedByteArray, off: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(TILES * TILES)
	for i in TILES * TILES:
		out[i] = d.decode_u16(off + i * 2)
	return out


## The liquid layer's x / y (second pass): the vertex's
## material is the liquid tile with the smallest wave in the vertex
## (tile table as in _underwater, first one on a tie). Material type 4 takes
## the land vertex's x / y, every other liquid stays on the 1 m grid: the
## file's x / y bytes of a liquid vertex are not read. (They are not jitter:
## read as offsets they pushed vertices up to 1 m across their neighbours and
## folded water triangles over, black back-facing slivers on the surface.)
func _liquid_xy(pos: PackedVector3Array, land_pos: PackedVector3Array, mats: PackedInt32Array, sx: int, sy: int) -> void:
	for vi in VERTS * VERTS:
		var vx := vi % VERTS
		var vy := vi / VERTS
		var m := NO_LIQUID
		for tx in range(vx / 2 - 1 + (vx & 1), vx / 2 + 1):
			if tx < 0 or tx >= TILES:
				continue
			for ty in range(vy / 2 - 1 + (vy & 1), vy / 2 + 1):
				if ty < 0 or ty >= TILES:
					continue
				var mm := mats[ty * TILES + tx]
				if mm == NO_LIQUID or mm >= materials.size():
					continue
				if m == NO_LIQUID or float(materials[mm].get("wave", 0.0)) < float(materials[m].get("wave", 0.0)):
					m = mm
		var g := EISpace.pos(sx * SECTOR + vx, sy * SECTOR + vy, 0.0)
		if m != NO_LIQUID and int(materials[m].type) == 4:
			g = land_pos[vi]
		pos[vi] = Vector3(g.x, pos[vi].y, g.z)


## Returns [positions (Godot space), normals] for one 33x33 vertex block.
func _read_vertices(d: PackedByteArray, off: int, sx: int, sy: int, is_land: bool) -> Array:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(VERTS * VERTS)
	nrm.resize(VERTS * VERTS)
	var scale := max_altitude / 65535.0
	for i in VERTS * VERTS:
		var p := off + i * 8
		# Land: signed x / y jitter, char · 0.5 / 126 m (saved
		# back). Liquid vertices ignore the bytes: _liquid_xy.
		var ox: float = d.decode_s8(p) if is_land else 0.0
		var oy: float = d.decode_s8(p + 1) if is_land else 0.0
		var z := d.decode_u16(p + 2) * scale
		var gx := sx * SECTOR + i % VERTS
		var gy := sy * SECTOR + i / VERTS
		pos[i] = EISpace.pos(gx + ox / 252.0, gy + oy / 252.0, z)
		var n := d.decode_u32(p + 4)
		nrm[i] = EISpace.vec(Vector3((((n >> 11) & 0x7FF) - 1000.0) / 1000.0,
				((n & 0x7FF) - 1000.0) / 1000.0, (n >> 22) / 1000.0)).normalized()
		if is_land:
			heights[gy * grid_w + gx] = z
			land_xy[gy * grid_w + gx] = Vector2(ox, oy) / 252.0
			land_n[gy * grid_w + gx] = nrm[i]
	return [pos, nrm]


## Builds a mesh with 9 unique vertices per 2x2-quad tile so each tile gets its own UVs.
## If `tile_mats` is given, tiles marked NO_LIQUID are skipped and vertex colors
## come from the map materials (used for water). UV2.y carries the water material
## (per vertex from `vert_mats`, _vertex_materials, else the tile's), or the
## global land-tile address for seamless map-neighbour sampling.
func _make_mesh(verts: Array, tex: PackedInt32Array, tile_mats: PackedInt32Array, mat: Material, tile_origin := Vector2i.ZERO, vert_mats := PackedInt32Array()) -> MeshInstance3D:
	var src_pos: PackedVector3Array = verts[0]
	var src_nrm: PackedVector3Array = verts[1]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var water := not tile_mats.is_empty()
	for ty in TILES:
		for tx in TILES:
			var t := ty * TILES + tx
			var color := Color(0, 0, 0, 0)
			if water:
				var m := tile_mats[t]
				if m == NO_LIQUID or m >= materials.size():
					continue
				color = materials[m].color
			var base := pos.size()
			for dy in 3:
				for dx in 3:
					var vi := (ty * 2 + dy) * VERTS + tx * 2 + dx
					pos.append(src_pos[vi])
					nrm.append(src_nrm[vi])
					if not water and verts.size() > 2:
						color = verts[2][vi]
					var tuv: Array = _tile_uv(tex[t], dx, dy)
					uv.append(tuv[0])
					var tile_id := (tile_origin.y + ty) * sectors_x * TILES + tile_origin.x + tx
					var vm := tile_mats[t] if water else tile_id
					if water and not vert_mats.is_empty() and vert_mats[vi] != NO_LIQUID:
						vm = vert_mats[vi]
						color = materials[vm].color
					uv2.append(Vector2(tuv[1], vm))
					col.append(color)
			for qy in 2:
				for qx in 2:
					var a := base + qy * 3 + qx
					var b := a + 1
					var c := a + 3
					var e := a + 4
					idx.append_array([c, b, a, b, c, e])
	if pos.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
