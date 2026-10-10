class_name EISky
extends RefCounted
## The original sky: the original draws the figure figures.res "nask0sky.fig"
## (object at CGame) with textures.res "Sky00" ("Sky01"
## caves, (0x3d, …)) every frame before the scene
## (: z-write off, culling off, specular ; puts it
## at the camera position − 16 m in height and, outside caves, turns it about
## the vertical axis by game ticks × 0.000333 rad). Its vertex colours come
##  (called by the daylight update): diffuse =
## the Lights [ambient] colour (texture × diffuse), specular rgb = [sunlight]
## × max(0, normal · light)² × 150 (the figure's stored normals, not turned
## with the dome, so the lit side turns with it), specular alpha (the D3D vertex fog factor)
## = sqrt(−normal.z) for vertices at height ≥ 1, else 0; the fog / clear colour
## is the Lights [sky] colour. In caves passes black ambient and
## sunlight, so the dome fades from black to the cave's sky colour.
##
## nask0sky.fig is an older figure format (version 0x12, 6 variants, faces of
## 13 u32: 3 vertex, 3 uv, 3 normal indices + 4 zero) the remake's EIFigure does
## not read. The dome is a surface of revolution of 7 rings (radius, height,
## v, mean normal z) and its u runs 0.996 → 0.004 over every 60° of azimuth (the
## texture repeats 6 times around); the values below are read from the file.
## The shader intersects the view ray with that ring profile, which gives the
## same mapping without the mesh, as a Godot sky (reflections, radiance).
##
## The sun direction is: azimuth = hour · π / 12, elevation
## 60° − |hour − 12| · 3.75° between 4 and 20 h, else rising from 30° to 75° at
## midnight (moonlight); light travels along (cos az cos el, sin az cos el,
## −sin el) in EI space.

const SHADER := """
shader_type sky;
render_mode use_debanding;
// Colours stay in sRGB values as in the 2000 renderer (no gamma-correct
// blending); only the result goes to linear.
uniform sampler2D tex : filter_linear, repeat_enable;
uniform vec3 sky_col = vec3(0.18, 0.71, 0.85);
uniform vec3 ambient = vec3(0.5);
uniform vec3 sun_col = vec3(1.0);
uniform vec3 light_dir = vec3(-0.5, 0.0, -0.866);  // EI space, as the light travels
uniform float spin = 0.0;
uniform float fancy = 0.0;   // remake option gfx_sky
uniform float night = 0.0;
global uniform vec3 ei_flash;   // remake: lightning sky brighten (Gfx.set_lightning_flash)
global uniform vec4 ei_border;
global uniform vec3 ei_fog_col;

// nask0sky.fig rings: radius, height (dome origin = eye − 16 m), v, fog factor, normal z
const float RR[7] = float[](39.891, 39.109, 37.605, 34.610, 30.084, 24.531, 17.961);
const float ZZ[7] = float[](0.0, 6.958, 13.914, 20.871, 27.827, 33.746, 38.617);
const float VV[7] = float[](0.0047, 0.1684, 0.3336, 0.4972, 0.6614, 0.8288, 0.9941);
const float FF[7] = float[](0.0, 0.3673, 0.5521, 0.6871, 0.7856, 0.8641, 0.8962);
const float NZ[7] = float[](-0.1386, -0.1349, -0.3048, -0.4721, -0.6172, -0.7468, -0.8032);
const float EYE = 16.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 stars(vec3 d) {
	vec3 p = d * 130.0;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h < 0.988) {
		return vec3(0.0);
	}
	vec3 f = fract(p) - 0.5;
	vec3 o = vec3(hash13(c + 7.1), hash13(c + 3.7), hash13(c + 1.3)) - 0.5;
	float r = length(f - o * 0.6);
	float b = smoothstep(0.18, 0.0, r) * (0.4 + 0.6 * fract(h * 397.0));
	b *= 0.65 + 0.35 * sin(TIME * (1.5 + 3.0 * fract(h * 91.0)) + h * 60.0);
	return mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.75), fract(h * 53.0)) * b * 3.0;
}

vec3 to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// specular of a dome vertex of ring i at local azimuth (cos, sin) = cs
float spec(int i, vec2 cs, vec3 l) {
	float nr = sqrt(1.0 - NZ[i] * NZ[i]);
	vec3 n = vec3(-cs.x * nr, -cs.y * nr, NZ[i]);   // the normals point inward
	float k = max(dot(n, l), 0.0);
	return k * k * (150.0 / 255.0);
}

vec3 dome(int i, float s, vec2 cs, float u, vec3 l) {
	float v = mix(VV[i], VV[i + 1], s);
	vec3 c = texture(tex, vec2(u, v)).rgb * ambient;
	c += sun_col * mix(spec(i, cs, l), spec(i + 1, cs, l), s);
	return mix(sky_col, c, mix(FF[i], FF[i + 1], s));
}

void sky() {
	vec3 e = vec3(EYEDIR.x, -EYEDIR.z, EYEDIR.y);   // Godot → EI (z up)
	float rho = length(e.xy);
	float ca = cos(spin), sa = sin(spin);
	// into the turned dome's frame
	vec2 dl = vec2(ca * e.x + sa * e.y, -sa * e.x + ca * e.y);
	//  lights the figure's own (unturned) normals with the world
	// light, so the lit side turns with the dome
	vec3 l = light_dir;
	vec2 cs = rho > 1e-5 ? dl / rho : vec2(1.0, 0.0);
	float az = atan(cs.y, cs.x);
	float u = 0.996 - 0.992 * fract(az / (PI / 3.0));
	vec3 col = sky_col;   // the clear colour below and above the dome
	bool hit = false;
	for (int i = 0; i < 6; i++) {
		float zi = ZZ[i] - EYE;
		float den = (RR[i + 1] - RR[i]) * e.z - (ZZ[i + 1] - ZZ[i]) * rho;
		if (abs(den) < 1e-7) {
			continue;   // ray parallel to the ring band: no hit (avoids 0 / 0 = NaN)
		}
		float s = (zi * rho - RR[i] * e.z) / den;
		if (s >= 0.0 && s <= 1.0 && (RR[i] + s * (RR[i + 1] - RR[i])) * rho + (zi + s * (ZZ[i + 1] - ZZ[i])) * e.z > 0.0) {
			col = dome(i, s, cs, u, l);
			hit = true;
			break;
		}
	}
	if (fancy > 0.5) {
		// remake: the open top of the dome continues the last ring and fades
		// into the sky colour instead of a hard edge
		float top = atan(ZZ[6] - EYE, RR[6]);
		float el = atan(e.z, rho);
		if (!hit && el > top) {
			vec3 c = texture(tex, vec2(u, VV[6])).rgb * ambient + sun_col * spec(6, cs, l);
			col = mix(sky_col, c, FF[6] * (1.0 - smoothstep(top, top + 0.45, el)));
		}
		vec3 to_sun = -normalize(light_dir);
		vec3 sd = vec3(to_sun.x, to_sun.z, -to_sun.y);   // EI → Godot
		float mu = dot(EYEDIR, sd);
		float up = smoothstep(-0.02, 0.03, EYEDIR.y);
		if (night < 0.5) {
			col += sun_col * smoothstep(0.99965, 0.9999, mu) * 4.0 * up;   // sun disc
		} else if (!AT_CUBEMAP_PASS) {
			col += stars(EYEDIR) * up * (1.0 - smoothstep(0.0, 0.4, dot(col, vec3(0.33))));
			col += vec3(0.95, 0.97, 1.0) * smoothstep(0.99955, 0.99975, mu) * 1.4 * up;   // moon
		}
		// remake: a lightning strike lights the clouds (soft flash, ParticleFx)
		col = mix(col, vec3(0.78, 0.82, 0.9), ei_flash.x);
	}
	// The opaque map perimeter fades to ei_fog_col. Continue that same fog
	// into the lower sky, or dome clouds expose the outline of the map
	// even when its edge is fully fogged. The menu keeps its native dome.
	if (ei_border.z > 0.0 && ei_border.w > 0.5) {
		col = mix(ei_fog_col, col, smoothstep(0.0, 0.35, EYEDIR.y));
	}
	COLOR = to_linear(col);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// GLES3 draws the background sky without the linear → sRGB output step
	// the other renderers apply (measured: Compatibility showed exactly
	// to_linear() of the Forward+ colour), so give it the sRGB colour. The
	// radiance cubemap stays linear for reflections.
	if (!AT_CUBEMAP_PASS) {
		COLOR = col;
	}
	#endif
}
"""

## The figure turns by ticks × 0.000333 rad; one tick is 55 ms.
const SPIN_PER_SECOND := 0.00033333333 / 0.055
const Clouds = preload("res://src/game/fx/clouds.gd")


static func material(cave: bool) -> ShaderMaterial:
	Gfx.ensure_globals()   # ei_flash
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SHADER
	m.set_meta("clouds",false)
	var tex := GameData.get_texture("sky01" if cave else "sky00") if GameData.textures else null
	if tex:
		m.set_shader_parameter("tex", tex)
	return m


## Sun (light) direction in EI space at `hour`.
static func light_dir_ei(hour: float) -> Vector3:
	var el: float
	if hour >= 4.0 and hour <= 20.0:
		el = (2.0 - absf(hour - 12.0) / 8.0) * 30.0
	elif hour < 4.0:
		el = (4.0 - hour) / 4.0 * 45.0 + 30.0
	else:
		el = (hour - 20.0) / 4.0 * 45.0 + 30.0
	el = deg_to_rad(el)
	var az := hour / 12.0 * PI
	return Vector3(cos(az) * cos(el), sin(az) * cos(el), -sin(el))


## Per-frame colours from the Lights file (ambient, sunlight, sky at `hour`);
## caves get black ambient and sunlight as.
static func update(m: ShaderMaterial, lights: EILights, hour: float, cave: bool, fancy: bool, env: Environment = null) -> void:
	if m == null:
		return
	var clouds := Clouds.mode() if not cave else 0
	if int(m.get_meta("clouds",0)) != clouds:
		m.shader.code = Clouds.sky_source(SHADER) if clouds>0 else SHADER
		m.set_meta("clouds",clouds)
	if clouds >= 2:
		m.set_shader_parameter("cloud_radiance", radiance_needed(env))
	var sky := lights.sample("sky", hour) if lights else Color(0.18, 0.71, 0.85)
	var amb := lights.sample("ambient", hour) if lights else Color(0.5, 0.53, 0.49)
	var sun := lights.sample("sunlight", hour) if lights else Color.WHITE
	if cave:
		amb = Color.BLACK
		sun = Color.BLACK
	# as Vector3: a Color would reach the shader converted to linear
	m.set_shader_parameter("sky_col", Vector3(sky.r, sky.g, sky.b))
	m.set_shader_parameter("ambient", Vector3(amb.r, amb.g, amb.b))
	m.set_shader_parameter("sun_col", Vector3(sun.r, sun.g, sun.b))
	m.set_shader_parameter("light_dir", light_dir_ei(hour))
	m.set_shader_parameter("fancy", 1.0 if fancy and not cave else 0.0)
	m.set_shader_parameter("night", 1.0 if Gfx.sun_day(sun) < 0.25 else 0.0)


## Conservative opt-out: colour ambient alone cannot sample the sky. Fog can
## still sample it even with AMBIENT_SOURCE_COLOR, so retain its full volume.
## Read the environment, not options: menus and gameplay configure it differently.
static func radiance_needed(env: Environment) -> bool:
	if env == null:
		return true
	if env.reflected_light_source != Environment.REFLECTION_SOURCE_DISABLED:
		return true
	if env.ambient_light_source not in [Environment.AMBIENT_SOURCE_COLOR, Environment.AMBIENT_SOURCE_DISABLED]:
		return true
	return env.volumetric_fog_enabled or env.sdfgi_enabled \
		or (env.fog_enabled and env.fog_aerial_perspective > 0.0)


static func set_spin(m: ShaderMaterial, angle: float) -> void:
	if m:
		m.set_shader_parameter("spin", fmod(angle, TAU))
