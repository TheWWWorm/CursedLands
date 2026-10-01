class_name EITerrain
extends Node3D
## Builds terrain and water from a map's .mpr archive (header .mp + sector .sec files)
## and its tile atlases "<map>NNN.mmp" in textures.res.

const MP_MAGIC := 0xCE4AF672
const SEC_MAGIC := 0xCF4BF774
const SECTOR := 32          # quads per sector side
const VERTS := 33           # vertices per sector side
const TILES := 16           # texture tiles per sector side (each covers 2x2 quads)
const NO_LIQUID := 0xFFFF
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
render_mode cull_disabled, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Remake rendering (option gfx_terrain): fine procedural relief on the
// ground up close (world-space triplanar noise normals, faded out with
// distance) and a soft large-scale brightness variation against tiling.
uniform float detail = 0.0;
uniform sampler2D detail_nm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ei_e = COLOR.rgb;
	ei_k = COLOR.a * 4.0;
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 c = texture(atlases, vec3(UV, UV2.x)).rgb;
	if (detail > 0.0) {
		float fade = detail * (1.0 - smoothstep(25.0, 70.0, length(VERTEX)));
		if (fade > 0.0) {
			vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
			// triplanar weights so steep slopes get relief too
			vec3 bw = pow(abs(wn), vec3(4.0));
			bw /= bw.x + bw.y + bw.z;
			vec2 a = texture(detail_nm, wpos.zy * 0.45).xy * 2.0 - 1.0;
			vec2 b = texture(detail_nm, wpos.xz * 0.45).xy * 2.0 - 1.0;
			vec2 e = texture(detail_nm, wpos.xy * 0.45).xy * 2.0 - 1.0;
			vec2 f = texture(detail_nm, wpos.xz * 1.7 + 0.37).xy * 2.0 - 1.0;
			vec3 pert = vec3(0.0, a.y, a.x) * bw.x + vec3(b.x + f.x * 0.6, 0.0, b.y + f.y * 0.6) * bw.y + vec3(e.x, e.y, 0.0) * bw.z;
			wn = normalize(wn + pert * 0.3 * fade);
			NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		}
		// large, soft brightness variation that breaks up the tile repeats
		float mac = texture(macro_tex, wpos.xz * 0.012).r;
		c *= mix(1.0, 0.86 + 0.24 * mac, detail);
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
## **Approx.**: the bump grid is not the original's rand sequence; material type 4
## (moves x / y only for flagged vertices) is treated like the others.
const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, blend_mix, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// SetWaterLevel offsets per map material (UV2.y = the tile's material), as the
// original shifts the water vertices of a material.
uniform float level[64];
uniform vec3 mat_e[64];
uniform float mat_a[64];
uniform float mat_wave[64];
uniform vec3 mat_rgb[64];
uniform float wind = 0.4;      // DefaultWindForce
uniform float waves = 1.0;     // EnableWaterWaves
uniform sampler2D phase_tex : filter_nearest, repeat_enable;   //  grid
varying float alpha;
varying vec3 spec;
// Outer landscape (EIOuterLand): its liquid has material + 64; while it is on
// (outer_edge) the map's own liquid is not drawn over the border cliff rows.
uniform float outer_edge = 0.0;
varying flat float cut;
varying vec3 cut_w;
void vertex() {
	int mi = int(UV2.y + 0.5);
	int m = clamp(mi % 64, 0, 63);
	cut = (outer_edge > 0.5 && mi < 64) ? 1.0 : 0.0;
	cut_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += level[m];
	ei_e = mat_e[m];
	ei_k = 0.0;
	alpha = mat_a[m];
	spec = vec3(0.0);
	if (waves > 0.5) {
		float ticks = TIME / 0.055;
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 ei = vec2(wp.x, -wp.z);
		vec2 cr = mod(floor(ei + 0.5), 32.0);   // column, row in the sector
		float p = texelFetch(phase_tex, ivec2(cr), 0).r;
		float wv = mat_wave[m];
		float a = 0.3 * wind * wv;
		float T = 6.2831853 - 3.1415927 / 21.0 * wind * ticks;
		float s = sin(T * wv + p);
		float t2 = 0.05 * ticks;
		// EI (x, y, z) = Godot (x, −z, y)
		VERTEX.y += s * a * 0.25;
		VERTEX.x += sin(cr.x * 0.7853981 + t2) * a * 3.0;
		VERTEX.z -= sin(cr.y * 0.7853981 + t2) * a * 3.0;
		if (s > 0.0) {
			spec = min(s * wind * wv * 50.0 * mat_rgb[m] / 255.0, vec3(1.0));
		}
	}
}
void fragment() {
	if (cut > 0.5) {
		vec2 e = vec2(cut_w.x, -cut_w.z);
		if (e.x < 2.0 || e.y < 2.0 || e.x > ei_border.x - 2.0 || e.y > ei_border.y - 2.0) {
			discard;
		}
	}
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec4 t = texture(atlases, vec3(UV, UV2.x));
	EMISSION = ei_lin(spec);   // the vertex specular, added after the texture
	ALBEDO = t.rgb;
	ALPHA = clamp(alpha * t.a, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
"""

## Remake water (option gfx_water): the original colour and texture mix as the
## water's body colour, two drifting procedural normal maps, refraction of the
## ground below (screen texture), absorption by depth toward the body colour,
## shore foam where the water is shallow, sky reflection and sun glints from
## Godot's lighting. Lava materials (liquid tiles of ground type 13) glow and
## churn instead. Keeps the per-material SetWaterLevel offsets.
const WATER_FX_SHADER := """
shader_type spatial;
render_mode cull_disabled, blend_mix;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float level[64];
uniform float lava[64];
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
varying float is_lava;
// Outer landscape (EIOuterLand): its liquid has material + 64; while it is on
// (outer_edge) the map's own liquid is not drawn over the border cliff rows.
uniform float outer_edge = 0.0;
varying flat float cut;
void vertex() {
	int mi = int(UV2.y + 0.5);
	int m = clamp(mi % 64, 0, 63);
	cut = (outer_edge > 0.5 && mi < 64) ? 1.0 : 0.0;
	VERTEX.y += level[m];
	is_lava = lava[m];
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float scene_dist(vec2 uv, mat4 inv_proj) {
	float z = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
	return length(v.xyz / v.w);
}
void fragment() {
	if (cut > 0.5) {
		vec2 e = vec2(wpos.x, -wpos.z);
		if (e.x < 2.0 || e.y < 2.0 || e.x > ei_border.x - 2.0 || e.y > ei_border.y - 2.0) {
			discard;
		}
	}
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 t = texture(atlases, vec3(UV, UV2.x)).rgb;
	vec3 gn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (is_lava > 0.5) {
		vec2 q = wpos.xz;
		float n1 = texture(foam_tex, q * 0.045 + TIME * vec2(0.006, 0.004)).r;
		float n2 = texture(foam_tex, q * 0.11 - TIME * vec2(0.004, 0.009)).r;
		float heat = smoothstep(0.35, 0.85, n1 * 0.6 + n2 * 0.6 - 0.1);
		vec3 crust = t * 0.35;
		vec3 wn = normalize(gn + vec3(n1 - 0.5, 0.0, n2 - 0.5) * 0.5);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		ALBEDO = crust;
		EMISSION = t * (0.6 + 2.2 * heat) * vec3(1.0, 0.75, 0.55) + vec3(1.0, 0.35, 0.05) * heat * heat * 0.8;
		ROUGHNESS = 0.7;
		SPECULAR = 0.2;
		ALPHA = 1.0;
	} else {
		vec3 body = mix(COLOR.rgb, t, 0.4);
		// waves: two normal maps drifting across each other, in world space
		vec2 q = wpos.xz;
		vec3 na = texture(wave_a, q * 0.055 + TIME * vec2(0.010, 0.006)).rgb * 2.0 - 1.0;
		vec3 nb = texture(wave_b, q * 0.13 + TIME * vec2(-0.008, 0.012)).rgb * 2.0 - 1.0;
		vec2 slope = na.xy * 0.6 + nb.xy * 0.4;
		vec3 wn = normalize(gn + vec3(slope.x, 0.0, slope.y) * 0.35);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		float wd = length(VERTEX);
		float d0 = scene_dist(SCREEN_UV, INV_PROJECTION_MATRIX);
		float thick = max(d0 - wd, 0.0);
		// refraction, damped in the shallows; not where the offset lands on
		// something in front of the water
		vec2 ruv = SCREEN_UV + slope * 0.035 * clamp(thick * 0.5, 0.0, 1.0);
		float d1 = scene_dist(ruv, INV_PROJECTION_MATRIX);
		if (d1 < wd) {
			ruv = SCREEN_UV;
			d1 = d0;
		}
		thick = max(d1 - wd, 0.0);
		vec3 under = textureLod(screen_tex, ruv, 0.0).rgb;
		// Transparent-pass objects (alpha-to-coverage foliage, units) are not
		// in the screen copy (black there): blend over them instead.
		bool missing = max(under.r, max(under.g, under.b)) < 1e-4;
		if (missing && ruv != SCREEN_UV) {
			under = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
			missing = max(under.r, max(under.g, under.b)) < 1e-4;
		}
		// vertical depth below the surface for foam
		float vdepth = thick * abs(dot(normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz), vec3(0.0, 1.0, 0.0)));
		float dens = mix(0.18, 0.55, COLOR.a);
		vec3 trans = exp(-thick * dens * (vec3(1.15) - body) * 1.6);
		float clarity = exp(-thick * dens * 0.55);
		vec3 seen = under * trans;
		float foam = 0.0;
		float shore = 1.0 - smoothstep(0.0, 0.45, vdepth);
		float fn = texture(foam_tex, q * 0.32 + TIME * vec2(0.015, -0.01)).r;
		float fn2 = texture(foam_tex, q * 0.7 - TIME * vec2(0.01, 0.02)).r;
		foam = smoothstep(0.55, 0.75, fn * 0.6 + fn2 * 0.5 + shore * 0.45 - 0.25) * shore;
		foam *= smoothstep(0.0, 0.06, vdepth);
		ALBEDO = mix(body * (1.0 - clarity) * 0.9, vec3(0.92), foam * 0.7);
		EMISSION = seen * clarity * (1.0 - foam * 0.7);
		ROUGHNESS = mix(0.04, 0.6, foam);
		SPECULAR = 0.5;
		ALPHA = 1.0;
		if (missing) {
			ALBEDO = body;
			EMISSION = vec3(0.0);
			ALPHA = clamp(COLOR.a * 0.8, 0.0, 1.0);
		}
	}
}
// Lambert diffuse as Godot's default, plus a sun / torch glint whose peak is
// kept below the bloom threshold (Godot's own GGX at roughness 0.04 reached
// hundreds and bloomed the low sunset sun into a red blob cluster on the
// sea: bloom is only for fire and magic).
void light() {
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * nl * ATTENUATION;
	vec3 h = normalize(LIGHT + VIEW);
	float e = mix(900.0, 24.0, clamp(ROUGHNESS / 0.6, 0.0, 1.0));
	float fr = 0.04 + 0.96 * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
	float g = pow(max(dot(NORMAL, h), 0.0), e) * (e + 8.0) / 8.0 * fr * nl * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR / PI * min(g, 0.7) * SPECULAR_AMOUNT /*EI_FA*/;
}
"""

var map_name := ""
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
var _water_mat: ShaderMaterial
var _land_mat: ShaderMaterial
var _level := PackedFloat32Array()
var _lava := PackedFloat32Array()
static var _land_shader: Shader
static var _water_shader: Shader
static var _water_fx_shader: Shader


static func load_map(name: String) -> EITerrain:
	var arc := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % name))
	if arc == null:
		return null
	var t := EITerrain.new()
	t.name = "Terrain"
	t.map_name = name
	if not t._parse_header(arc.read(name + ".mp")):
		push_error("Bad .mp header in %s" % name)
		return null
	t._load_atlases()
	t._build(arc)
	return t


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
	var images: Array[Image] = []
	for i in int(get_meta("textures_count")):
		var img := GameData.load_image("%s%03d" % [map_name, i])
		if img == null or img.get_width() != texture_size:
			push_warning("Missing terrain atlas %s%03d" % [map_name, i])
			var n := texture_size * (2 if Gfx.on("gfx_hd_textures") else 1)
			img = Image.create(n, n, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
		elif Gfx.on("gfx_hd_textures"):
			img = TexUpscale.up2(img, false)   # option gfx_hd_textures (UVs are normalised)
		img.generate_mipmaps()
		images.append(img)
	_atlases = Texture2DArray.new()
	_atlases.create_from_images(images)


func _tile_uv(f: int, dx: int, dy: int) -> Array:
	var tile := f & 63
	var atlas := (f >> 6) & 255
	var k: int = ROT_PERM[(f >> 14) & 3][dy * 3 + dx]
	var per_row := texture_size / tile_size
	var half := tile_size * 0.5
	var u := (tile % per_row) * tile_size + clampf((k % 3) * half, 0.5, tile_size - 0.5)
	var v := (tile / per_row) * tile_size + clampf((k / 3) * half, 0.5, tile_size - 0.5)
	# Atlas tile rows are counted from the bottom of the stored image.
	return [Vector2(u / texture_size, 1.0 - v / texture_size), atlas]


func _build(arc: EIResArchive) -> void:
	if _land_shader == null:
		Gfx.ensure_globals()
		_land_shader = Gfx.make_shader(TERRAIN_SHADER, true, true)
		_water_shader = Gfx.make_shader(WATER_SHADER, true, true)
		_water_fx_shader = Gfx.make_shader(WATER_FX_SHADER, false)
	Gfx.set_border(size_ei())
	var land_mat := ShaderMaterial.new()
	land_mat.shader = _land_shader
	land_mat.set_shader_parameter("atlases", _atlases)
	_land_mat = land_mat
	var wmat := ShaderMaterial.new()
	wmat.shader = _water_shader
	_water_mat = wmat
	_level.resize(64)
	_lava.resize(64)

	for sy in sectors_y:
		LoadingScreen.tick()
		for sx in sectors_x:
			var d := arc.read("%s%03d%03d.sec" % [map_name, sx, sy])
			if d.size() < 5 or d.decode_u32(0) != SEC_MAGIC:
				push_warning("Missing sector %d,%d" % [sx, sy])
				continue
			var liquids := d[4] != 0
			var land := _read_vertices(d, 5, sx, sy, true)
			var tex_off := 5 + VERTS * VERTS * 8 * (2 if liquids else 1)
			var land_tex := _read_u16s(d, tex_off)
			_record_ground(land_tex, sx, sy)
			if liquids:
				land.append(_underwater(land[0], _read_vertices(d, 5 + VERTS * VERTS * 8, sx, sy, false)[0],
					_read_u16s(d, tex_off + 1024)))
			var mi := _make_mesh(land, land_tex, PackedInt32Array(), land_mat)
			mi.name = "Sector_%d_%d" % [sx, sy]
			mi.layers |= DECAL_LAYER
			add_child(mi)
			if liquids:
				var wverts := _read_vertices(d, 5 + VERTS * VERTS * 8, sx, sy, false)
				var water_tex := _read_u16s(d, tex_off + 512)
				var water_mats := _read_u16s(d, tex_off + 1024)
				_record_water(wverts[0], water_mats, sx, sy)
				_record_liquid_ground(water_tex, water_mats, sx, sy)
				var wm := _make_mesh(wverts, water_tex, water_mats, wmat)
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
	apply_gfx()


## Remake rendering options (gfx_water, gfx_terrain) on the terrain and water
## materials; parameters are set again after a shader swap.
func apply_gfx() -> void:
	if _water_mat == null:
		return
	# Deferred: the menu screen sets its border after building the map.
	_update_outer.call_deferred()
	var fx := GameData.option("gfx_water") != 0
	_water_mat.shader = _water_fx_shader if fx else _water_shader
	_water_mat.set_shader_parameter("atlases", _atlases)
	_water_mat.set_shader_parameter("level", _level)
	if not fx:
		var me := PackedVector3Array()
		var ma := PackedFloat32Array()
		me.resize(64)
		ma.resize(64)
		for i in mini(materials.size(), 64):
			var e := material_e(i)
			me[i] = Vector3(e.r, e.g, e.b)
			ma[i] = (materials[i].color as Color).a
		_water_mat.set_shader_parameter("mat_e", me)
		_water_mat.set_shader_parameter("mat_a", ma)
		var mw := PackedFloat32Array()
		var mc := PackedVector3Array()
		mw.resize(64)
		mc.resize(64)
		for i in mini(materials.size(), 64):
			mw[i] = float(materials[i].get("wave", 0.0))
			var c: Color = materials[i].color
			mc[i] = Vector3(c.r, c.g, c.b)
		_water_mat.set_shader_parameter("mat_wave", mw)
		_water_mat.set_shader_parameter("mat_rgb", mc)
		_water_mat.set_shader_parameter("phase_tex", wave_phase_texture())
	if fx:
		_water_mat.set_shader_parameter("lava", _lava)
		_water_mat.set_shader_parameter("wave_a", Gfx.noise("wave_a", 256, 0.018, 4, true, 5.0))
		_water_mat.set_shader_parameter("wave_b", Gfx.noise("wave_b", 256, 0.03, 3, true, 4.0))
		_water_mat.set_shader_parameter("foam_tex", Gfx.noise("foam", 256, 0.03, 4))
	var det := GameData.option("gfx_terrain") != 0
	_land_mat.set_shader_parameter("detail", 1.0 if det else 0.0)
	if det:
		_land_mat.set_shader_parameter("detail_nm", Gfx.noise("ground", 512, 0.02, 5, true, 3.0))
		_land_mat.set_shader_parameter("macro_tex", Gfx.noise("macro", 256, 0.015, 3))


var _outer: EIOuterLand


## Remake option gfx_outer_land (Gfx.outer_land_active): the land ring beyond
## the map edge, built on first use.
func _update_outer() -> void:
	var want := Gfx.outer_land_active()
	if want and _outer == null:
		_outer = EIOuterLand.build(self, _land_mat, _water_mat)
		add_child(_outer)
	elif _outer:
		_outer.visible = want
	_water_mat.set_shader_parameter("outer_edge", 1.0 if want else 0.0)


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
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func water_at(x: float, y: float) -> float:
	var cx := int(x)
	var cy := int(y)
	if cx >= 0 and cy >= 0 and cx < sectors_x * SECTOR and cy < sectors_y * SECTOR:
		return water[cy * sectors_x * SECTOR + cx]
	return -INF


## Rasterizes upward-facing triangles of an object (e.g. a bridge deck) as walkable surface.
func add_surface(mesh_owner: Node3D) -> void:
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


## The per-sector wave phase grid: 33 × 33 values, 40 random
## bumps of radius² (1..5)² each adding (1 − d² / r²) · π / 2, then the last
## row / column averaged with the first so sectors tile (cached; here 32 × 32
## repeating). **Approx.**: a fixed seed, not the original's rand sequence.
static var _phase_tex: ImageTexture


static func wave_phase_texture() -> ImageTexture:
	if _phase_tex:
		return _phase_tex
	var g := PackedFloat32Array()
	g.resize(33 * 33)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 40:
		var cx := float(rng.randi() % 33)
		var cy := float(rng.randi() % 33)
		var r2 := float(rng.randi() % 5 + 1)
		r2 *= r2
		for y in 33:
			for x in 33:
				var d2 := (x - cx) * (x - cx) + (y - cy) * (y - cy)
				if d2 < r2:
					g[y * 33 + x] += (1.0 - d2 / r2) * PI * 0.5
	for i in range(1, 32):
		var a := (g[i] + g[32 * 33 + i]) * 0.5
		g[i] = a
		g[32 * 33 + i] = a
		var b := (g[i * 33] + g[i * 33 + 32]) * 0.5
		g[i * 33] = b
		g[i * 33 + 32] = b
	var c := (g[0] + g[32] + g[32 * 33] + g[32 * 33 + 32]) * 0.25
	g[0] = c
	var img := Image.create(32, 32, false, Image.FORMAT_RF)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, Color(g[y * 33 + x], 0, 0))
	_phase_tex = ImageTexture.create_from_image(img)
	return _phase_tex


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
## **Approx.**: the vertex's material is that of the first liquid tile touching
## it (the original walks a vertex → tile table).
func _underwater(land_pos: PackedVector3Array, water_pos: PackedVector3Array, mats: PackedInt32Array) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(VERTS * VERTS)
	out.fill(Color(0, 0, 0, 0))
	for vi in VERTS * VERTS:
		var vx := vi % VERTS
		var vy := vi / VERTS
		var m := NO_LIQUID
		for ty in [mini(vy / 2, TILES - 1), maxi(vy - 1, 0) / 2]:
			for tx in [mini(vx / 2, TILES - 1), maxi(vx - 1, 0) / 2]:
				var mm := mats[ty * TILES + tx]
				if m == NO_LIQUID and mm != NO_LIQUID and mm < materials.size():
					m = mm
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


func _read_u16s(d: PackedByteArray, off: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(TILES * TILES)
	for i in TILES * TILES:
		out[i] = d.decode_u16(off + i * 2)
	return out


## Returns [positions (Godot space), normals] for one 33x33 vertex block.
func _read_vertices(d: PackedByteArray, off: int, sx: int, sy: int, is_land: bool) -> Array:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(VERTS * VERTS)
	nrm.resize(VERTS * VERTS)
	var scale := max_altitude / 65535.0
	for i in VERTS * VERTS:
		var p := off + i * 8
		var ox: float = d.decode_s8(p) if is_land else d.decode_u8(p)
		var oy: float = d.decode_s8(p + 1) if is_land else d.decode_u8(p + 1)
		var z := d.decode_u16(p + 2) * scale
		var gx := sx * SECTOR + i % VERTS
		var gy := sy * SECTOR + i / VERTS
		pos[i] = EISpace.pos(gx + ox / 254.0, gy + oy / 254.0, z)
		var n := d.decode_u32(p + 4)
		nrm[i] = EISpace.vec(Vector3((((n >> 11) & 0x7FF) - 1000.0) / 1000.0,
				((n & 0x7FF) - 1000.0) / 1000.0, (n >> 22) / 1000.0)).normalized()
		if is_land:
			heights[gy * grid_w + gx] = z
			land_xy[gy * grid_w + gx] = Vector2(ox, oy) / 254.0
			land_n[gy * grid_w + gx] = nrm[i]
	return [pos, nrm]


## Builds a mesh with 9 unique vertices per 2x2-quad tile so each tile gets its own UVs.
## If `tile_mats` is given, tiles marked NO_LIQUID are skipped and vertex colors
## come from the map materials (used for water).
func _make_mesh(verts: Array, tex: PackedInt32Array, tile_mats: PackedInt32Array, mat: Material) -> MeshInstance3D:
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
					uv2.append(Vector2(tuv[1], tile_mats[t] if water else 0))
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
