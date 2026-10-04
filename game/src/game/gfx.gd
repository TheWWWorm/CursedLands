class_name Gfx
extends RefCounted
## Remake-only rendering on top of the original look (none of this is in the
## 2000 renderer; every part is switched by a "gfx_*" option, Options →
## Graphics): the sky additions (EISky), volumetric mist, ambient occlusion and
## bloom of the play view, and the shared procedural noise textures the water,
## terrain and heat-haze shaders use. Nothing is shipped: the noise is made
## here.

static var _noise_cache := {}


## ---------------------------------------------------------------- original lighting
## The 2000 renderer lights every vertex on the CPU and draws texture × vertex
## colour (D3DTOP_MODULATE) in plain sRGB values, no gamma
## correction, no tone mapping. Light colours come from config/Lights*.ini via
## the daylight update (sun = [sunlight], ambient = [ambient] or
## 0.8 × [sunlight] when the ambient key is black). Lights are combined with
## max(), not added:
##  - terrain (directional) and
##     (point lights): c = max(ambient, min(1, E + sun · max(0, n·L)))
##    every point light: max(c, min(1, E + col · a · f)), a = 1 − d² / r²
##    (light = 1/r²), f = 1 when the vertex faces the light, else n·L + 1
##    E = 0 on land, the map material's min(1, self-illumination × colour) on
##    water.
##  - figures: the T&L pipeline of 3dfpfpu.dll (GetTLPipeline, =
## called): c = max(ambient, sun · coeff · n·L
##    every point light col · coeff · a · n·L), + material emissive, clamped;
##    coeff = registry ObjectsLightingCoeff (default 1.0) ×
##    material diffuse.
## The shaders get ambient and sun as global uniforms (sRGB values) and do this
## in light(): max(ambient, sun · n·L, each omni light), followed by shadow
## darkening. The result is turned into the linear
## factor that reproduces tex_srgb × c after Godot's sRGB output.
## Units use the same path with EI_FIGURE_LIGHT (emissive after the max).
## The menu signpost and UI previews keep Godot's own Lambert lighting.

const GLOBALS := {
	&"ei_ambient": Color(0.506, 0.529, 0.49),
	&"ei_sun": Color(1.0, 1.0, 1.0),
	&"ei_fog_col": Color(0.18, 0.71, 0.85),
	&"ei_fog": Color(90.0, 100.0, 0.0),   # start, end (view depth, m)
	&"ei_border": Color(0.0, 0.0, 0.0),
	&"ei_sky": Color(0.18, 0.71, 0.85),
	&"ei_sun_dir": Color(0.0, 0.0, 0.0),   # world direction towards the sun (update_original)   # Lights [sky]: the clear colour   # map width, height (EI m), BorderFogDistance
	&"ei_surface_fx": Color(1.0, 1.0, 1.0),   # materials, leaf backlight, rain surfaces
	&"ei_weather": Color(0.0, 0.0, 0.0),   # wetness, current rain intensity, reserved
	&"ei_sun_pass": Color(0.0, 0.0, 0.0),   # 1: the sun is drawn in its own additive pass (GLES3, shadowed)
	&"ei_unit_sharp": Color(1.0, -0.5, 0.0),   # gfx_sharp_units: on, mip bias (EIUnitModel.SHARP_FETCH)
	&"ei_flash": Color(0.0, 0.0, 0.0),   # x: remake lightning sky brighten (ParticleFx soft flash, EISky)
}
## GLES3 (Compatibility) only: the original point lights nearest the view
## (update_pass_lights), so a shadowed local light's own pass can rebuild the
## colour already drawn under it. xyz world position, w radius (0 = unused);
## colour: sRGB light colour, w 1 = additive (flag 0x40).
const PASS_LIGHTS := 4

## Shader code shared by the terrain, water and map-object shaders. `WRAP`
## (terrain) gives point lights the terrain's back-face wrap. `ei_e` (vec3,
## sRGB) is the vertex's E term, `ei_k` the underwater attenuation (terrain).
const LIGHT_COMMON := """
global uniform vec3 ei_ambient;
global uniform vec3 ei_sun;
global uniform vec3 ei_fog_col;
global uniform vec3 ei_fog;
global uniform vec3 ei_border;
global uniform vec3 ei_sky;
global uniform vec3 ei_sun_dir;
global uniform vec3 ei_sun_pass;
global uniform vec4 ei_pl0;
global uniform vec4 ei_pl1;
global uniform vec4 ei_pl2;
global uniform vec4 ei_pl3;
global uniform vec4 ei_plc0;
global uniform vec4 ei_plc1;
global uniform vec4 ei_plc2;
global uniform vec4 ei_plc3;
global uniform vec3 ei_surface_fx;
global uniform vec3 ei_weather;
vec3 ei_lin(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
// The 3dfpfpu.dll fog: linear in view depth from start to end
// toward the Lights [sky] colour. Written to FOG it replaces Godot's radial
// depth fog, so the fog reaches 100 % exactly at the far plane. Border fog
// within BorderFogDistance B + 1 m of the map edge the vertex
// fogs by min(d, B) / B, d = the length of the distances into that band.
// `v` view-space, `w` world position.
vec4 ei_fog_of(vec3 v, vec3 w) {
	float f = clamp((-v.z - ei_fog.x) / max(ei_fog.y - ei_fog.x, 1e-3), 0.0, 1.0);
	if (ei_border.z > 0.0) {
		float b = ei_border.z + 1.0;
		vec2 p = vec2(w.x, -w.z);
		vec2 lo = min(p - b, vec2(0.0));
		vec2 hi = min(ei_border.xy - b - p, vec2(0.0));
		float d = sqrt(dot(lo, lo) + dot(hi, hi));
		float fb = min(d, ei_border.z) / ei_border.z;
		// the border always fades into the clear colour [sky] (equal to the
		// fog colour unless the far view option tints the distance fog)
		vec3 col = mix(ei_fog_col, ei_sky, fb / max(f + fb, 1e-4));
		return vec4(ei_lin(col), max(f, fb));
	}
	return vec4(ei_lin(ei_fog_col), f);
}
vec3 ei_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
// The linear diffuse factor that makes Godot output tex_srgb × c (c in sRGB units).
vec3 ei_factor(vec3 albedo, vec3 c) {
	return ei_lin(ei_srgb(albedo) * min(c, vec3(1.0))) / max(albedo, vec3(1e-4));
}
"""

## A spatial shader with LIGHT_COMMON put before its first function (so the
## fragment can use ei_fog_of) and, if `lit`, light_code(wrap) appended.
## With gfx_volumetric on, the fragment's `FOG = ei_fog_of(…)` becomes the
## blended variant (_blend_fog), so Godot's volumetric fog reaches the land
## and the map objects too.
static func compose(code: String, lit := true, wrap := false) -> String:
	ensure_globals()
	var i := code.find("\nvoid ")
	var extra := "varying vec3 ei_surface;\nvarying float ei_leaf;\nvarying vec3 ei_vpos;\n" if lit else ""
	code = code.substr(0, i + 1) + LIGHT_COMMON + extra + code.substr(i + 1)
	if lit:
		# Fragment-to-light varyings: absent profiles keep the exact original
		# diffuse response. x = highlight strength, y = roughness, z = metal.
		code = code.replace("void fragment() {", "void fragment() {\n\tei_surface = vec3(0.0, 1.0, 0.0);\n\tei_leaf = 0.0;\n\tei_vpos = VERTEX;")
	code = code + light_code(wrap) if lit else code
	return _blend_fog(code, lit) if _vol_fog else code


## Shaders made by make_shader, recomposed when gfx_volumetric switches
## (the FOG write is compile-time: Godot skips volumetric fog for every
## material that writes FOG).
static var _made: Array = []   # [WeakRef(Shader), code, lit, wrap]
static var _vol_fog := false


static func make_shader(code: String, lit := true, wrap := false) -> Shader:
	if Portability.compatibility():
		code = code.replace("instance uniform", "uniform")
	_set_vol_fog(on("gfx_volumetric"))
	var sh := Shader.new()
	sh.code = compose(code, lit, wrap)
	_made.append([weakref(sh), code, lit, wrap])
	return sh


static func _set_vol_fog(v: bool) -> void:
	if v == _vol_fog:
		return
	_vol_fog = v
	var keep: Array = []
	for r: Array in _made:
		var sh := (r[0] as WeakRef).get_ref() as Shader
		if sh:
			sh.code = compose(r[1], r[2], r[3])
			keep.append(r)
	_made = keep


## gfx_volumetric: the original fog without writing FOG. The final colour
## Godot makes is (X · (1 − g) + C · g) · T + V (its depth fog g =
## smoothstep(start, end, |v|) in the [sky] colour C, set to the same range
## by update_original; the volumetric transmittance T and in-scatter V in
## front). X = (L · (1 − f) + F · f − C · g) / (1 − g) gives the original
## mix(L, F, f) behind the volumetric mist: the lit colour L is scaled by
## a = (1 − f) / (1 − g) (ALBEDO, EMISSION, and light() undoes it for the
## original's colour factor) and the rest added as emission. Same image as
## the FOG path when the volumetric mist is empty.
## Near Godot's fog end (1 − g → 0, sooner at the screen edges, where its
## radial distance runs ahead of the original's view depth) the exact factors
## grow without bound (up to 1000×); they are capped at BLEND_FOG_MAX there,
## where Godot's own fog hides almost all of X, so a pixel can never reach the
## glow as a huge HDR value. g is the smoothstep written out (defined for an
## empty fog range).
static func _blend_fog(code: String, _lit: bool) -> String:
	code = code.replace("FOG = ei_fog_of(", "vec4 ei_fogv = ei_fog_of(")
	var i := code.find("void fragment()")
	if i < 0 or not code.contains("ei_fogv"):
		return code
	i = code.find("{", i)
	var depth := 0
	var end := -1
	for k in range(i, code.length()):
		var ch := code[k]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				end = k
				break
	if end < 0:
		return code
	var tail := """	{
		const float BLEND_FOG_MAX = 8.0;
		float ei_g = clamp((length(VERTEX) - ei_fog.x) / max(ei_fog.y - ei_fog.x, 1e-3), 0.0, 1.0);
		ei_g = ei_g * ei_g * (3.0 - 2.0 * ei_g);
		float ei_t = max(1.0 - ei_g, 1e-3);
		float ei_a = min((1.0 - ei_fogv.a) / ei_t, BLEND_FOG_MAX);
		vec3 ei_add = clamp((ei_fogv.rgb * ei_fogv.a - ei_lin(ei_fog_col) * ei_g) / ei_t, vec3(-BLEND_FOG_MAX), vec3(BLEND_FOG_MAX));
		if (isnan(ei_a) || isinf(ei_a)) { ei_a = 1.0; }
		if (any(isnan(ei_add)) || any(isinf(ei_add))) { ei_add = vec3(0.0); }
"""
	# Unshaded: the colour is ALBEDO. Shaded (the EI light() or Godot's):
	# lit colour scaled, the fog added as emission, light() told the scale.
	var shaded := not code.contains("unshaded")
	if shaded:
		tail += """		ALBEDO *= ei_a;
		EMISSION = EMISSION * ei_a + ei_add;
		ei_fa = ei_a;
	}
"""
	else:
		tail += """		ALBEDO = ALBEDO * ei_a + ei_add;
	}
"""
	code = code.substr(0, end) + tail + code.substr(end)
	if shaded:
		code = code.replace("vec3 ei_lin(vec3 c) {", "varying float ei_fa;\nvec3 ei_lin(vec3 c) {")
		code = code.replace("/*EI_FA*/", "* ei_fa")
		code = code.replace("vec3 ei_alb = ALBEDO;", "vec3 ei_alb = ALBEDO / max(ei_fa, 1e-4);")
		code = code.replace("SPECULAR_LIGHT += ei_lin(min(col * a * f * uw, vec3(1.0))) * dim;",
			"SPECULAR_LIGHT += ei_lin(min(col * a * f * uw, vec3(1.0))) * dim * ei_fa;")
	return code


## Point lights with this light_specular (a marker: Godot passes nothing else
## per light to light()) are the original's flag-0x40 lights, added on top
## instead of max()ed in; hero (0) and other lights (0.5) are not.
const ADDITIVE_SPECULAR := 0.002
## Separate from original spell flag 0x40. LocalLighting marks only opted-in
## fires/spells/lava; their diffuse light accumulates without the old max().
## Godot delivers 2 * this value as SPECULAR_AMOUNT for positional lights.
const LOCAL_SPECULAR := 0.012
## The same light while it casts shadows on the Compatibility renderer: GLES3
## draws it in its own additive pass (set_local_shadow, light_code).
const LOCAL_SPECULAR_PASS := 0.0128
## Point lights the GLES3 pass correction may need (update_pass_lights).
const POINT_LIGHT_GROUP := &"ei_point_lights"


## Switches a LocalLighting light's shadow and keeps its marker in step.
static func set_local_shadow(l: Light3D, enabled: bool) -> void:
	l.shadow_enabled = enabled
	if is_equal_approx(l.light_specular, LOCAL_SPECULAR) or is_equal_approx(l.light_specular, LOCAL_SPECULAR_PASS):
		l.light_specular = LOCAL_SPECULAR_PASS if enabled and Portability.compatibility() else LOCAL_SPECULAR


## GLES3 only, once per frame: the PASS_LIGHTS original (max()ed or additive)
## point lights that reach nearest to `focus`, for light_code's local-light
## pass correction. Enhanced (local) lights are left out.
static func update_pass_lights(tree: SceneTree, focus: Vector3) -> void:
	if not Portability.compatibility():
		return
	ensure_globals()
	var found: Array = []
	for n: Node in tree.get_nodes_in_group(POINT_LIGHT_GROUP):
		var l := n as OmniLight3D
		if l == null or not l.is_visible_in_tree() or l.light_energy <= 0.0:
			continue
		var marker := l.light_specular
		if is_equal_approx(marker, LOCAL_SPECULAR) or is_equal_approx(marker, LOCAL_SPECULAR_PASS):
			continue
		var p := l.global_position
		found.append([maxf(p.distance_to(focus) - l.omni_range, 0.0), l])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in PASS_LIGHTS:
		var pos := Vector4.ZERO
		var col := Vector4.ZERO
		if i < found.size():
			var l: OmniLight3D = found[i][1]
			var p := l.global_position
			pos = Vector4(p.x, p.y, p.z, l.omni_range)
			# light_code's col = min(srgb(LIGHT_COLOR / π), 1)
			var c := (l.light_color.srgb_to_linear() * l.light_energy).linear_to_srgb()
			col = Vector4(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0 if is_equal_approx(l.light_specular, ADDITIVE_SPECULAR) else 0.0)
		RenderingServer.global_shader_parameter_set(StringName("ei_pl%d" % i), pos)
		RenderingServer.global_shader_parameter_set(StringName("ei_plc%d" % i), col)


static func mark_additive(l: Light3D) -> void:
	l.light_specular = ADDITIVE_SPECULAR


## light() of the original model. Needs varyings `ei_e` (vec3) and `ei_k` (float).
static func light_code(wrap: bool) -> String:
	return ("""
vec3 ei_light_value(vec3 ambient, vec3 contribution, vec3 emissive) {
#ifdef EI_FIGURE_LIGHT
	// Figure TLP 1000d910: emissive is added after the per-channel maximum.
	return min(max(ambient, contribution) + emissive, vec3(1.0));
#else
	// Terrain: the material E term belongs inside the maximum (0068d2d0).
	return max(ambient, min(emissive + contribution, vec3(1.0)));
#endif
}
// GLES3 only: one of the original point lights near the view (Gfx.
// update_pass_lights) as the point-light branch below evaluates it, in sRGB
// units; w = 1 where it reaches. `vpos` view-space position, `n` normal.
vec4 ei_pass_light(vec4 pl, vec4 plc, vec3 n, vec3 vpos, mat4 view, mat4 inv_view, float kw) {
	if (pl.w <= 0.0) { return vec4(0.0); }
	vec3 lv = (view * vec4(pl.xyz, 1.0)).xyz - vpos;
	float dist = length(lv);
	float pa = max(1.0 - dist * dist / (pl.w * pl.w), 0.0);
	if (pa <= 0.0) { return vec4(0.0); }
	vec3 ld = lv / max(dist, 1e-4);
	float k = dot(n, ld);
	float f = WRAP_TERM;
	float plz = (inv_view * vec4(ld, 0.0)).y;
	float puw = max(1.0 - plz * plz * kw, 0.0);
	return vec4(min(plc.rgb * pa * f * puw, vec3(1.0)), 1.0);
}
void light() {
	vec3 ei_alb = ALBEDO;
	vec3 c = vec3(0.0);
	bool add = false;
	float lz = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;   // world up component
	float uw = max(1.0 - lz * lz * ei_k, 0.0);   // under water
	vec3 amb = ei_ambient * max(1.0 - ei_k, 0.0);
	bool local_light = !LIGHT_IS_DIRECTIONAL && SPECULAR_AMOUNT > 0.02 && SPECULAR_AMOUNT < 0.03;
	if (local_light) {
		// ATTENUATION includes the shadow map. Do not invert it as the old
		// unshadowed point lights do. Accumulate in the post-texture channel
		// so later original max() passes cannot erase this contribution.
		float nl = max(dot(NORMAL, LIGHT), 0.0);
		vec3 loc = ei_alb * LIGHT_COLOR / PI * nl * ATTENUATION * 0.75 /*EI_FA*/;
		if (SPECULAR_AMOUNT > 0.0245) {
			// Gfx.LOCAL_SPECULAR_PASS: a shadowed light that GLES3 draws in
			// its own additive pass. The passes are summed as stored (sRGB-
			// encoded) colours, which made the light pool wider and flatter
			// than on the other renderers. Rebuild the colour already drawn
			// here (the original model: sun and the nearest original point
			// lights, Gfx.update_pass_lights) and write only the sRGB step
			// that adding the light in linear space makes (approx.: the sun's
			// figure shadow and other local lights are not known here).
			vec3 v = ei_light_value(amb, vec3(0.0), ei_e);
			if (dot(ei_sun_dir, ei_sun_dir) > 0.5) {
				vec3 sl = (VIEW_MATRIX * vec4(ei_sun_dir, 0.0)).xyz;
				float uws = max(1.0 - ei_sun_dir.y * ei_sun_dir.y * ei_k, 0.0);
				v = ei_light_value(amb, ei_sun * max(dot(NORMAL, sl), 0.0) * uws, ei_e);
			}
			vec3 extra = vec3(0.0);
			vec4 pls[4] = vec4[4](ei_pl0, ei_pl1, ei_pl2, ei_pl3);
			vec4 plc[4] = vec4[4](ei_plc0, ei_plc1, ei_plc2, ei_plc3);
			for (int i = 0; i < 4; i++) {
				vec4 pv = ei_pass_light(pls[i], plc[i], NORMAL, ei_vpos, VIEW_MATRIX, INV_VIEW_MATRIX, ei_k);
				if (pv.w <= 0.0) { continue; }
				if (plc[i].w > 0.5) {
					extra += ei_lin(pv.rgb);
				} else {
					v = max(v, ei_light_value(amb, pv.rgb, ei_e));
				}
			}
			vec3 base = ei_lin(ei_srgb(ei_alb) * min(v, vec3(1.0))) + extra;
			loc = ei_lin(max(min(ei_srgb(base + loc), vec3(1.0)) - ei_srgb(base), vec3(0.0)));
		}
		SPECULAR_LIGHT += loc;
		add = true;
	} else if (LIGHT_IS_DIRECTIONAL) {
		// Vertex light without shadow, then
		// the figure shadows as the 2000 renderer draws them: a silhouette
		// texture laid over the lit ground with vertex colour
		// i.e. the lit colour
		// halved where the shadow falls.
		float d = max(dot(NORMAL, LIGHT), 0.0);
		#ifdef EI_TERRAIN_LIGHT
		// Land: the sun's map holds only figures (the land casts nothing,
		// Gfx.setup_sun_casters: no self-shadowing in the original), and
		// the original lays a figure's silhouette over every ground triangle
		// under its projected rectangle whichever way it faces (
		// gathers them with no facing test): halved on sun-facing and
		// averted slopes alike, on every renderer.
		float sh = mix(0.5, 1.0, ATTENUATION);
		#else
		// Figures and objects: Godot also shadows them, which the original
		// does not. Faces turned from the sun (n · L < 0.15) already show
		// only ambient and are not darkened again.
		float sh = mix(1.0, mix(0.5, 1.0, ATTENUATION), smoothstep(0.0, 0.15, d));
		#endif
		vec3 v = ei_light_value(amb, ei_sun * d * uw, ei_e);
		if (ei_sun_pass.x > 0.5) {
			// GLES3 draws this shadowed sun in its own pass, the only one
			// that knows the figure shadow. The nearest original point
			// lights are max()ed in here (and left out of their own pass,
			// below), so the shadow halves them as in the original.
			vec4 pls[4] = vec4[4](ei_pl0, ei_pl1, ei_pl2, ei_pl3);
			vec4 plc[4] = vec4[4](ei_plc0, ei_plc1, ei_plc2, ei_plc3);
			for (int i = 0; i < 4; i++) {
				if (plc[i].w > 0.5) { continue; }
				vec4 pv = ei_pass_light(pls[i], plc[i], NORMAL, ei_vpos, VIEW_MATRIX, INV_VIEW_MATRIX, ei_k);
				if (pv.w > 0.0) {
					v = max(v, ei_light_value(amb, pv.rgb, ei_e));
				}
			}
		}
		c = v * sh;
	} else {
		float k = dot(NORMAL, LIGHT);
		float f = %s;
		// Godot's omni falloff with attenuation 0 is (1 − (d/r)^4)²: back to 1 − (d/r)²
		float a = 1.0 - sqrt(max(1.0 - sqrt(clamp(ATTENUATION, 0.0, 1.0)), 0.0));
		vec3 col = min(ei_srgb(LIGHT_COLOR / PI), vec3(1.0));
		// Point lights are max()ed into the vertex colour before the shadow
		// is laid over it, so they are halved in a shadow
		// too. Godot shadows only the sun pass, which runs first: the
		// shadow factor is the shadowed / unshadowed sun value so far
		// (approx. where two point lights overlap in a shadow).
		float dim = 1.0;
		vec3 v_un = ei_light_value(amb, vec3(0.0), ei_e);
		bool sun_in_diffuse = ei_sun_pass.x < 0.5;   // else it has its own pass (below)
		if (dot(ei_sun_dir, ei_sun_dir) > 0.5) {
			vec3 sl = (VIEW_MATRIX * vec4(ei_sun_dir, 0.0)).xyz;
			float uws = max(1.0 - ei_sun_dir.y * ei_sun_dir.y * ei_k, 0.0);
			v_un = ei_light_value(amb, ei_sun * max(dot(NORMAL, sl), 0.0) * uws, ei_e);
			vec3 sa = ei_srgb(ei_alb);
			const vec3 W = vec3(0.299, 0.587, 0.114);
			if (sun_in_diffuse && dot(sa, W) > 0.02 && dot(v_un, W) > 0.01) {
				vec3 v_now = ei_srgb(DIFFUSE_LIGHT * ei_alb) / max(sa, vec3(1e-3));
				dim = clamp(dot(v_now, W) / dot(v_un, W), 0.5, 1.0);
			}
		}
		if (SPECULAR_AMOUNT > 0.0 && SPECULAR_AMOUNT < 0.01) {
			// flag 0x40 lights (spells 0x840, quest light): into the vertex
			// specular colour, which D3D adds after the texture
			SPECULAR_LIGHT += ei_lin(min(col * a * f * uw, vec3(1.0))) * dim;
			add = true;
		} else {
			c = max(v_un, ei_light_value(amb, col * a * f * uw, ei_e)) * dim;
			// GLES3 draws the shadowed sun in its own additive pass after
			// this one, so the sun is not in DIFFUSE_LIGHT here (dim would
			// read 0.5) and would be added a second time on top of v_un
			// (blown-out white blocks around the hero light). Write only what
			// the point light adds over the unshadowed sun value; with the
			// sun pass this sums to max(sun, point light) in the light
			// (approx. in a figure shadow: half the sun plus the excess,
			// where the original halves both).
			bool in_sun_pass = false;
			if (!sun_in_diffuse) {
				// One of the lights the sun pass already max()es in?
				vec4 pls[4] = vec4[4](ei_pl0, ei_pl1, ei_pl2, ei_pl3);
				vec4 plc[4] = vec4[4](ei_plc0, ei_plc1, ei_plc2, ei_plc3);
				for (int i = 0; i < 4; i++) {
					if (pls[i].w <= 0.0 || plc[i].w > 0.5) { continue; }
					vec3 lv = (VIEW_MATRIX * vec4(pls[i].xyz, 1.0)).xyz - ei_vpos;
					if (dot(lv / max(length(lv), 1e-6), LIGHT) > 0.99999 && abs(length(lv) / pls[i].w - sqrt(max(1.0 - a, 0.0))) < 0.01) {
						in_sun_pass = true;
					}
				}
			}
			if (in_sun_pass) {
				add = true;
			} else if (!sun_in_diffuse && dot(ei_sun_dir, ei_sun_dir) > 0.5) {
				// The passes are summed as stored (sRGB-encoded) colours,
				// so the excess is taken in sRGB: texture × (max − sun).
				vec3 mx = max(v_un, ei_light_value(amb, col * a * f * uw, ei_e));
				vec3 over = ei_lin(ei_srgb(ei_alb) * max(min(mx, vec3(1.0)) - min(v_un, vec3(1.0)), vec3(0.0)))
					/ max(ei_alb, vec3(1e-4));
				DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, over);
				add = true;
			}
		}
	}
	if (!add) {
		DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, ei_factor(ei_alb, c));
	}
	// Optional material response, shared by objects, equipment and wet land.
	// A bounded lobe suits the painted assets and linear output without
	// producing HDR sparkles or turning every surface into polished plastic.
	if (ei_surface.x > 0.001 && (LIGHT_IS_DIRECTIONAL || SPECULAR_AMOUNT > 0.0)) {
		// safe normalize: LIGHT = −VIEW gives a zero vector, and a NaN here
		// (× a zero n·L is still NaN) would reach the bloom and spread
		vec3 hv = LIGHT + VIEW;
		vec3 h = hv * inversesqrt(max(dot(hv, hv), 1e-12));
		float r = clamp(ei_surface.y, 0.2, 1.0);
		float power = mix(128.0, 10.0, r * r);
		float highlight = pow(max(dot(NORMAL, h), 0.0), power) * max(dot(NORMAL, LIGHT), 0.0);
		vec3 tint = mix(vec3(0.4), clamp(ei_alb * 1.8, vec3(0.06), vec3(0.9)), ei_surface.z);
		SPECULAR_LIGHT += min(LIGHT_COLOR / PI, vec3(1.5)) * tint * highlight * ATTENUATION * ei_surface.x * 0.22 /*EI_FA*/;
	}
	if (ei_leaf > 0.001) {
		float transmission = pow(max(dot(-NORMAL, LIGHT), 0.0), 1.5);
		SPECULAR_LIGHT += ei_alb * LIGHT_COLOR / PI * transmission * ATTENUATION * ei_leaf * 0.22 /*EI_FA*/;
	}
}
""" % [_wrap_term(wrap)]).replace("WRAP_TERM", _wrap_term(wrap))


## The point-light facing term f(k), k = n · l: terrain wraps round the back
## (: 1 if facing, else n · l + 1), figures and objects do not.
static func _wrap_term(wrap: bool) -> String:
	return "(k > 0.0 ? 1.0 : max(k + 1.0, 0.0))" if wrap else "max(k, 0.0)"


## Registers the global uniforms (before any shader using them is compiled).
static var _globals := false


static func ensure_globals() -> void:
	if _globals:
		return
	_globals = true
	for k: StringName in GLOBALS:
		var c: Color = GLOBALS[k]
		RenderingServer.global_shader_parameter_add(k, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(c.r, c.g, c.b))
	for i in PASS_LIGHTS:
		RenderingServer.global_shader_parameter_add(StringName("ei_pl%d" % i), RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
		RenderingServer.global_shader_parameter_add(StringName("ei_plc%d" % i), RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	apply_surface_options()


static func apply_surface_options() -> void:
	ensure_globals()
	apply_unit_sharpness()
	RenderingServer.global_shader_parameter_set(&"ei_surface_fx", Vector3(
		float(on("gfx_materials")), float(on("gfx_foliage_light")), float(on("gfx_weather_surfaces"))))
	if not on("gfx_weather_surfaces"):
		set_surface_weather(0.0, 0.0)


## Option gfx_sharp_units: the unit texture fetch (EIUnitModel.SHARP_FETCH),
## world figures and UI previews alike; a uniform, so no shader rebuilds.
static func apply_unit_sharpness() -> void:
	if not _globals:
		return   # ensure_globals sets it
	var on_ := on("gfx_sharp_units")
	RenderingServer.global_shader_parameter_set(&"ei_unit_sharp",
		Vector3(1.0 if on_ else 0.0, EIUnitModel.SHARP_MIP_BIAS if on_ else 0.0, 0.0))


## Remake (gfx_sky): how much a lightning strike brightens the sky dome now
## (ParticleFx._update_flashes; 0 = none).
static func set_lightning_flash(v: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(&"ei_flash", Vector3(clampf(v, 0.0, 1.0), 0.0, 0.0))


static func set_surface_weather(wetness: float, rain: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(&"ei_weather", Vector3(clampf(wetness, 0.0, 1.0), clampf(rain, 0.0, 1.0), 0.0))


## Per-frame light colours (sRGB, as read from the Lights file).
## The current sun colour (sRGB 0..1), for the effects that take the scene
## light's colour (the tornado dust, FxTypes 0x200a).
static var sun := Color.WHITE


static var ambient := Color(0.5, 0.5, 0.5)


static func set_light(amb: Color, sun_col: Color) -> void:
	sun = sun_col
	ambient = amb
	ensure_globals()
	RenderingServer.global_shader_parameter_set(&"ei_ambient", Vector3(amb.r, amb.g, amb.b))
	RenderingServer.global_shader_parameter_set(&"ei_sun", Vector3(sun_col.r, sun_col.g, sun_col.b))


## Fog start: FogDayStartDistance (90) from 6 to 18 h
## FogNightStartDistance (50) from 22 to 2 h, linear in between; the fog ends
## at FarClipDistance (100), the far plane.
## Registry defaults. The 3dfpfpu.dll pipeline (
## ) fogs by view depth, linearly from start to end, toward the
## Lights [sky] colour (the D3D fog colour, puVar6[5]).
const FOG_DAY := 90.0
const FOG_NIGHT := 50.0
const FAR_CLIP := 100.0
const NEAR_CLIP := 2.0
## Remake option gfx_far_view: the far plane at FAR_VIEW and the fog stretched
## from fog_start × FAR_VIEW_FOG to it (a long, soft fade instead of the
## original 10 m one); off = the original 100 m.
const FAR_VIEW := 260.0
const FAR_VIEW_FOG := 1.4


## BorderFogDistance (default 32 m).
const BORDER_FOG := 32.0


## The loaded map's size for the border fog (the map loader
##  sets all map flags, so it is ).
## The main menu screen sets it to 6 m and restores it on leaving
##
## In play the original has no band: is 0 in the original's.data and
## only ever written by the main menu (6 m) and
## the screen (4 m, restored), each restoring the old
## value; the registry BorderFogDistance (settings) is read and saved but
## never copied into it. With B = 0 returns 0xff (no fog), so the
## map ends at its edge cliff over the clear colour [sky]. (does
## keep the smaller of this alpha and the depth fog.) The remake options
## gfx_edge_fade (fade the last EDGE_FADE metres, the menu's own 6 m) is not
## original and defaults off.
const EDGE_FADE := 6.0
static var _border_size := Vector2.ZERO
static var _border_menu := -1.0


static func set_border(size_ei: Vector2, menu_dist := -1.0) -> void:
	ensure_globals()
	_border_size = size_ei
	_border_menu = menu_dist
	refresh_border()


static func refresh_border() -> void:
	if not _globals:
		return
	var size_ei := _border_size
	var dist := _border_menu
	if dist < 0.0:
		dist = EDGE_FADE if on("gfx_edge_fade") else 0.0
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector3(size_ei.x, size_ei.y, dist))


const HORIZON_V := 0.383
const HORIZON_FOG := 0.59
static var _horizon := Color(-1, 0, 0)


## Mean colour of the Sky00 row at HORIZON_V (sRGB), cached.
static func _sky_horizon() -> Color:
	if _horizon.r >= 0.0:
		return _horizon
	_horizon = Color(0.25, 0.45, 0.7)
	var tex := GameData.get_texture("sky00") if GameData.textures else null
	if tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var y := clampi(int(HORIZON_V * img.get_height()), 0, img.get_height() - 1)
			var c := Color(0, 0, 0)
			for x in img.get_width():
				c += img.get_pixel(x, y)
			_horizon = c / float(img.get_width())
	return _horizon


static func far_clip() -> float:
	return FAR_VIEW if on("gfx_far_view") else FAR_CLIP


## Fog (start, end) in metres of view depth for `hour`.
static func fog_range(hour: float, cave: bool) -> Vector2:
	var st := fog_start(hour, cave)
	if on("gfx_far_view"):
		return Vector2(st * FAR_VIEW_FOG, FAR_VIEW)
	return Vector2(st, FAR_CLIP)


static func fog_start(hour: float, cave: bool) -> float:
	if cave:
		return FOG_DAY
	hour = fposmod(hour, 24.0)
	if hour >= 6.0 and hour <= 18.0:
		return FOG_DAY
	if hour >= 22.0 or hour <= 2.0:
		return FOG_NIGHT
	if hour > 18.0:
		return FOG_DAY - (FOG_DAY - FOG_NIGHT) * (hour - 18.0) / 4.0
	return (FOG_DAY - FOG_NIGHT) * (hour - 2.0) / 4.0 + FOG_NIGHT


## The environment set up as the 2000 renderer: no tone mapping (the output is
## the clamped colour), linear depth fog in the sky colour, no sky light.
static func setup_original_env(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_curve = 1.0
	env.fog_depth_begin = FOG_DAY
	env.fog_depth_end = FAR_CLIP
	env.fog_aerial_perspective = 0.0
	env.fog_sun_scatter = 0.0
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED


## Per-frame: light colours and fog of the hour. `env` ambient / sun are for
## materials that do not use the original model (e.g. the menu signpost).
static func update_original(env: Environment, sun_light: DirectionalLight3D, lights: EILights, hour: float, cave: bool) -> void:
	var sun := lights.sample("sunlight", hour) if lights else Color.WHITE
	var amb := lights.sample("ambient", hour) if lights else Color(0.506, 0.529, 0.49)
	var sky := lights.sample("sky", hour) if lights else Color(0.18, 0.71, 0.85)
	if cave:
		#  cave branch: the hour-0 colours, light (0.5, 0.5, −0.7071)
		sun = lights.sample("sunlight", 0.0) if lights else sun
		amb = lights.sample("ambient", 0.0) if lights else amb
		sky = lights.sample("sky", 0.0) if lights else sky
	if amb.r == 0.0 and amb.g == 0.0 and amb.b == 0.0:
		amb = sun * 0.8
	amb.a = 1.0
	set_light(amb, sun)
	if sun_light:
		sun_light.light_color = sun
		sun_light.light_energy = 1.0
		var to_sun := sun_light.global_transform.basis.z.normalized() if sun_light.is_inside_tree() else sun_light.basis.z.normalized()
		RenderingServer.global_shader_parameter_set(&"ei_sun_dir", to_sun)
		sync_sun_pass(sun_light)
	env.ambient_light_color = amb
	env.ambient_light_energy = 1.0
	RenderingServer.global_shader_parameter_set(&"ei_sky", Vector3(sky.r, sky.g, sky.b))
	if not cave and on("gfx_far_view"):
		# remake: fade into the dome's own colour at the horizon (EISky: the
		# view ray at elevation 0 meets the dome between rings 2 and 3, Sky00
		# row v ≈ 0.383 × [ambient], fog factor ≈ 0.59 toward [sky]) so distant
		# hills melt into the sky instead of standing out in the flat fog colour
		var row := _sky_horizon()
		sky = sky.lerp(Color(row.r * amb.r, row.g * amb.g, row.b * amb.b), HORIZON_FOG)
		sky.a = 1.0
	env.fog_light_color = sky
	var fr := fog_range(hour, cave)
	env.fog_depth_begin = fr.x
	env.fog_depth_end = fr.y
	RenderingServer.global_shader_parameter_set(&"ei_fog_col", Vector3(sky.r, sky.g, sky.b))
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(fr.x, fr.y, 0.0))


## A seamless procedural noise texture (generated by FastNoiseLite, cached).
## `normal`: as a normal map.
static func noise(key: String, size := 256, freq := 0.012, octaves := 4, normal := false, bump := 6.0) -> NoiseTexture2D:
	var k := "%s/%d/%s" % [key, size, normal]
	if _noise_cache.has(k):
		return _noise_cache[k]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = key.hash() & 0xffff
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.seamless_blend_skirt = 0.2
	t.generate_mipmaps = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	_noise_cache[k] = t
	return t


static func on(name: String) -> bool:
	if name == "gfx_volumetric" and RenderingServer.get_current_rendering_method() != "forward_plus":
		return false
	return GameData.option(name) != 0


## Sun shadow casters: everything but the land, on every renderer. The 2000
## renderer has no terrain self-shadowing by default (the height march
##   runs only with map flag 0x10, which
##  clears unless the registry EnableSelfShadowing is set, default
## 0); only figure shadows darken the ground. Godot's map
## the coarse land also made hard bands and patches on hills. Bridges also sit
## on layer 1, so they still cast. Keeps the caller's other exclusions.
## GLES3 (Compatibility) renders a shadowed directional light in a separate
## additive pass after the base pass that holds the point lights; light_code's
## max()ed point lights then write only their excess over the sun.
static func sync_sun_pass(sun: DirectionalLight3D) -> void:
	ensure_globals()
	var separate := Portability.compatibility() and sun.shadow_enabled and sun.visible
	RenderingServer.global_shader_parameter_set(&"ei_sun_pass", Vector3(float(separate), 0.0, 0.0))


static func setup_sun_casters(sun: DirectionalLight3D) -> void:
	sun.shadow_caster_mask &= ~(EITerrain.SHADOW_RECEIVER_LAYER | EITerrain.DECAL_LAYER)


## Remake render quality (Options → remake effects, rows 6..9; defaults = the
## highest setting, which earlier builds had fixed in project.godot): anti-
## aliasing q_aa (0 off, 1 SMAA, 2 MSAA 4×, 3 MSAA 4× + SMAA, 4 TAA, 5 FSR 2,
## whose upscaler mode GameData._apply_window sets), shadow filter and atlas
## size q_shadows (0..3), anisotropic filtering q_aniso (0 off .. 4 = 16×).
## None of them changes a colour. Called by GameData._apply_window.
static func apply_quality(vp: Viewport) -> void:
	var aa := GameData.option("q_aa")
	vp.msaa_3d = Viewport.MSAA_4X if aa == 2 or aa == 3 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if (aa == 1 or aa == 3) and not Portability.compatibility() else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 4 and RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.anisotropic_filtering_level = clampi(GameData.option("q_aniso"), 0, 4) as Viewport.AnisotropicFiltering
	apply_unit_sharpness()
	var q := clampi(GameData.option("q_shadows"), 0, 3)
	var filt: Array[RenderingServer.ShadowQuality] = [RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]
	RenderingServer.directional_soft_shadow_filter_set_quality(filt[q])
	RenderingServer.positional_soft_shadow_filter_set_quality(filt[q])
	var atlas: int = [1024, 2048, 2048, 4096][q] if Portability.constrained() else [2048, 4096, 8192, 8192][q]
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	vp.positional_shadow_atlas_size = atlas


## Option q_shadow_fit: the sun's four cascades span what can be seen, the
## far plane (Gfx.far_clip: 100 m, or 260 m with gfx_far_view) or the zone's
## diagonal if smaller, at least 60 m and at most the old fixed 220 m; the
## first two splits stay at about 13 m and 40 m so near shadows keep (or,
## with a shorter range, gain) resolution. Off: the fixed 220 m split
## 0.06 / 0.18 / 0.45.
static func fit_shadows(sun: DirectionalLight3D, zone_size: Vector2) -> void:
	var md := 220.0
	if on("q_shadow_fit"):
		md = far_clip()
		if zone_size.x > 0.0:
			md = minf(md, zone_size.length())
		md = clampf(md, 60.0, 220.0)
	sun.directional_shadow_max_distance = md
	sun.directional_shadow_split_1 = 13.2 / md
	sun.directional_shadow_split_2 = 39.6 / md
	sun.directional_shadow_split_3 = minf(99.0, md * 0.75) / md


## SSAO High at half resolution; volumetric fog froxels (width / height, depth).
const SSAO_QUALITY := RenderingServer.ENV_SSAO_QUALITY_HIGH
const VOL_FOG_SIZE := Vector2i(64, 48)
const GLOW_LUMINANCE_CAP := 8.0


## The play view's environment switches (Options → Graphics).
static func apply_env(env: Environment) -> void:
	apply_surface_options()
	refresh_border()
	# Enhanced water uses the live sky as SSR's off-screen fallback. The
	# original terrain/figure/unit shaders disable ambient light and radiance.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if on("gfx_water") else Environment.REFLECTION_SOURCE_DISABLED
	env.ssao_enabled = on("gfx_ssao")
	env.glow_enabled = on("gfx_bloom")
	# No pixel feeds the bloom with more than this (Godot's default is 12):
	# the brightest wanted sources (fire × GLOW_BOOST, lava, bolts) stay
	# below it, a stray huge HDR value cannot bloom over the screen.
	env.glow_hdr_luminance_cap = GLOW_LUMINANCE_CAP
	env.volumetric_fog_enabled = on("gfx_volumetric")
	_set_vol_fog(on("gfx_volumetric"))
	if not Portability.compatibility():
		# Cheaper than project.godot's Ultra / 128 × 96 / bicubic glow at no
		# visible loss (measured at 1440p on an RTX 3090: SSAO 1.7 → 0.9 ms,
		# volumetric fog at night 0.8 → 0.4 ms, bloom 0.6 → 0.1 ms; the
		# rest of SSAO and the fog is fixed cost).
		RenderingServer.environment_set_ssao_quality(SSAO_QUALITY, true, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size(VOL_FOG_SIZE.x, VOL_FOG_SIZE.y)
		RenderingServer.environment_glow_set_use_bicubic_upscale(false)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for l: Node in tree.get_nodes_in_group(&"gfx_torch_glow"):
			(l as Light3D).light_volumetric_fog_energy = torch_fog_energy()
		for v: Node in tree.get_nodes_in_group(&"gfx_torch_fog"):
			(v as Node3D).visible = on("gfx_torch_glow")
		for d: Node in tree.get_nodes_in_group(&"gfx_contact_shadows"):
			(d as Node3D).visible = on("gfx_contact_shadows")
		for u: Node in tree.get_nodes_in_group(&"severed_units"):   # option gfx_severed_limbs
			u.call(&"refresh_severed")
		for m: Node in tree.get_nodes_in_group(&"detailed_heads"):   # option gfx_detailed_heads
			m.call(&"refresh_detailed_head")


## Option gfx_torch_glow: fire and spell lights scatter strongly in the
## volumetric mist (Godot's default 1 is barely visible in the thin mist).
const TORCH_FOG := 8.0


static func torch_fog_energy() -> float:
	return TORCH_FOG if on("gfx_torch_glow") else 1.0


## Option gfx_torch_glow: a soft additive halo round a fire / spell light
## (a camera-facing quad in the light's colour, faded where it meets
## geometry), shown from dusk to dawn and in caves, so the light glows in the
## night air. (Godot's volumetric fog does not reach the terrain and map
## objects: their shaders write the original fog to FOG, which replaces it.)
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 col = vec3(1.0);
uniform float strength = 0.55;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform vec3 ei_sun;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
#endif
void vertex() {
	float k = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * k, INV_VIEW_MATRIX[1] * k, INV_VIEW_MATRIX[2] * k, MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = pow(max(1.0 - r, 0.0), 1.8);
	float depth = texture(depth_tex, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp((-v.z / v.w - (-VERTEX.z)) / 1.5, 0.0, 1.0);
	float night = 1.0 - smoothstep(0.45, 0.78, (ei_sun.r + ei_sun.g + ei_sun.b) / 3.0);
	vec3 h = col * a * strength * night * soft;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// GLES3 adds this to the stored sRGB colour as it is, while the other
	// renderers add it in linear space before the sRGB output, which there
	// makes the same halo wider and whiter over the dark night ground. Write
	// the sRGB step over the colour under the halo instead, so the sum is
	// the same as on Forward+ / Mobile.
	vec3 b = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 bl = mix(b / 12.92, pow((b + 0.055) / 1.055, vec3(2.4)), step(0.04045, b));
	vec3 t = clamp(bl + h, 0.0, 1.0);
	h = max(mix(t * 12.92, 1.055 * pow(t, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, t)) - b, 0.0);
	#endif
	ALBEDO = h;
}
"""
static var _halo_shader: Shader
static var _halo_mesh: QuadMesh


static func torch_halo(radius: float, color: Color) -> MeshInstance3D:
	ensure_globals()
	if _halo_shader == null:
		_halo_shader = Shader.new()
		_halo_shader.code = HALO_SHADER
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = _halo_shader
	m.set_shader_parameter("col", Vector3(color.r, color.g, color.b))
	var mi := MeshInstance3D.new()
	mi.mesh = _halo_mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d := clampf(radius * 0.9, 2.5, 9.0)
	mi.scale = Vector3(d, d, d)
	mi.visible = on("gfx_torch_glow")
	mi.add_to_group(&"gfx_torch_fog")
	return mi


## Option gfx_lit_particles: the light on smoke / dust / blood particles,
## min(1, ambient + sun) per channel (1 in daylight: the original look; night
## and cave light darken them instead of their glowing unlit).
static func particle_tint() -> Color:
	if not on("gfx_lit_particles"):
		return Color.WHITE
	var c := ambient + sun
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))


## Option gfx_hd_textures: map-object / foliage textures 2x upscaled
## (TexUpscale), else the original (GameData.get_texture).
static var _hd := {}


static func texture_3d(name: String) -> Texture2D:
	if name == "" or not on("gfx_hd_textures"):
		return GameData.get_texture(name) if name != "" else null
	var key := name.to_lower()
	if not _hd.has(key):
		var img := GameData.load_image(key)
		var tex: Texture2D = null
		if img:
			var big := TexUpscale.up2(img, true)
			big.generate_mipmaps()
			tex = ImageTexture.create_from_image(big)
		_hd[key] = tex
	return _hd[key]


static func setup_volumetric(env: Environment) -> void:
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.2
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true


## How much "day" the [sunlight] colour of Lights*.ini shows (0 at night,
## when the light is the bluish moonlight, 1 in full white sun) and how warm
## it is (dawn / dusk), for the sky and the mist.
static func sun_day(c: Color) -> float:
	return smoothstep(0.5, 0.78, (c.r + c.g + c.b) / 3.0)


static func sun_warm(c: Color) -> float:
	return clampf((c.r - c.b) * 1.5, 0.0, 1.0)


## Per-frame mist: thicker at dawn / dusk and a little at night, thin at noon.
## (Lighter since the mist reaches the land and objects, see _blend_fog: the
## original colours stay readable under it.)
static func update_volumetric(env: Environment, sun: Color, cave: bool) -> void:
	if not env.volumetric_fog_enabled:
		return
	env.volumetric_fog_density = 0.0005 + 0.0015 * sun_warm(sun) + 0.0007 * (1.0 - sun_day(sun)) \
		+ (0.0015 if cave else 0.0)


## Heat haze (option gfx_heat_haze): a camera-facing quad above a fire that
## bends the picture behind it with rising procedural noise.
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 1.0;
void vertex() {
	// cylindrical billboard: faces the camera, stays upright
	vec3 up = MODEL_MATRIX[1].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 side = cross(up, to_cam);   // zero when seen straight from above: no NaN quad
	vec3 right = side * inversesqrt(max(dot(side, side), 1e-12)) * length(MODEL_MATRIX[0].xyz);
	vec3 w = MODEL_MATRIX[3].xyz + right * VERTEX.x + up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}
void fragment() {
	float y = 1.0 - UV.y;   // 0 at the flame, 1 at the top
	vec2 q = vec2(UV.x * 0.6, y * 0.8 - TIME * 0.55);
	vec2 n = vec2(texture(noise_tex, q).r, texture(noise_tex, q + vec2(0.37, 0.11)).r) - 0.5;
	float m = (1.0 - smoothstep(0.15, 0.5, abs(UV.x - 0.5))) * smoothstep(0.0, 0.15, y) * (1.0 - smoothstep(0.45, 1.0, y));
	float k = strength * m * 0.02 / max(length(VERTEX) * 0.08, 1.0);
	// Pixels of transparent-pass objects (alpha-to-coverage foliage) are not
	// in the screen copy yet (still the black clear colour): leave them be.
	vec3 c = textureLod(screen_tex, SCREEN_UV + n * k * 2.0, 0.0).rgb;
	if (max(c.r, max(c.g, c.b)) < 1e-4) {
		c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	}
	ALBEDO = c;
	ALPHA = max(c.r, max(c.g, c.b)) < 1e-4 ? 0.0 : clamp(m * 1.5, 0.0, 1.0);
}
"""
static var _haze_mat: ShaderMaterial


static func heat_haze(width: float) -> MeshInstance3D:
	if _haze_mat == null:
		_haze_mat = ShaderMaterial.new()
		# The screen copy contains opaque geometry only. Draw its distortion
		# before transparent flames/halos, or it paints the background over them.
		_haze_mat.render_priority = -50
		_haze_mat.shader = Shader.new()
		_haze_mat.shader.code = HAZE_SHADER
		_haze_mat.set_shader_parameter("noise_tex", noise("haze", 128, 0.06, 3))
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 2.0)
	q.center_offset = Vector3(0.0, 1.0, 0.0)
	mi.mesh = q
	mi.scale = Vector3.ONE * width
	mi.material_override = _haze_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	mi.add_to_group(&"gfx_heat_haze")
	mi.visible = heat_haze_on()
	return mi


## gfx_heat_haze, Forward+ / Mobile only. On the Compatibility renderer the
## haze's screen copy lacks the units (alpha-to-coverage, transparent pass) and
## it painted the ground over a unit standing behind a fire.
static func heat_haze_on() -> bool:
	return on("gfx_heat_haze") and not Portability.compatibility()
