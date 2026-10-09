extends RefCounted
## The shell keeps the authored triangle positions, material ownership and
## the complete original displacement program. Only its normal lift and foam
## fragment differ. In particular, a steep wave never leaves foam inside rock.
const FOAM := """
uniform float fall_clock = 0.0;
float fall_hash(vec2 p) {
	p = mod(p, vec2(64.0));
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float fall_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(fall_hash(i),fall_hash(i+vec2(1.0,0.0)),f.x),
		mix(fall_hash(i+vec2(0.0,1.0)),fall_hash(i+vec2(1.0)),f.x),f.y);
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float flow = (UV.y - fall_clock) * 4.0;
	float ribbons = fall_noise(vec2(UV.x*2.4,flow));
	float bubbles = fall_noise(vec2(UV.x*7.0,flow*2.0));
	float foam = smoothstep(0.28,0.8,ribbons*0.65+bubbles*0.35);
	ALBEDO = mix(vec3(0.64,0.77,0.80),vec3(0.96,0.99,1.0),foam);
	ALPHA = clamp(COLOR.a * (0.08+foam*0.58),0.0,0.68);
	ROUGHNESS = 1.0;
}
"""


static func shell() -> Shader:
	var code := EITerrain.WATER_SHADER.get_slice("void fragment() {",0)
	code = code.replace("depth_draw_always", "depth_draw_never")
	code = Gfx._function_tail(code,"vertex","\n\tVERTEX += NORMAL * 0.045;\n\tspec = vec3(0.0);\n")
	return Gfx.make_shader(code+FOAM,true,true)


## Fixed, bounded billboards: each vertex carries its immutable emitter,
## seed and role. Periods divide 16 s, including the shader noise period.
## No TIME, particles' independent clock, frame allocation or random restart.
const SPRAY := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;
uniform float fall_clock = 0.0;
varying float fall_opacity;
void vertex() {
	float role = floor(COLOR.b*3.0+0.5);
	float seed = COLOR.r;
	float period = role > 1.5 ? 8.0 : (role > 0.5 ? 2.0 : 4.0);
	float age = mod(fall_clock+seed*period,period);
	float life = role > 1.5 ? 3.0 : (role > 0.5 ? 0.7 : 0.8);
	float t = min(age,life), fade = max(0.0,1.0-age/life);
	vec3 centre = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec3 direction = vec3(NORMAL.x,0.0,NORMAL.z);
	vec3 across = vec3(-direction.z,0.0,direction.x);
	float spread = (fract(seed*17.7)-0.5);
	float extent;
	if (role > 1.5) {
		centre += direction*t*0.35 + across*spread*t*0.7 + vec3(0.0,t*0.35,0.0);
		extent = 0.3+t*0.28;
		fall_opacity = fade*min(age*3.0,1.0)*0.12;
	} else if (role > 0.5) {
		centre += direction*t*0.6 + across*spread*t*2.0 + vec3(0.0,t*2.6-4.9*t*t,0.0);
		extent = 0.045+seed*0.065;
		fall_opacity = fade*0.6;
	} else {
		centre += direction*t*1.6 + across*spread*t*0.6 + vec3(0.0,t*0.3-4.9*t*t,0.0);
		extent = 0.055+seed*0.065;
		fall_opacity = fade*0.5;
	}
	vec4 view = VIEW_MATRIX * vec4(centre,1.0);
	VERTEX = view.xyz+vec3((UV*2.0-1.0)*extent,0.0);
	NORMAL = vec3(0.0,0.0,1.0);
}
void fragment() {
	FOG = ei_fog_of(VERTEX,(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz);
	vec2 q = UV*2.0-1.0;
	float soft = max(0.0,1.0-dot(q,q)); soft *= soft;
	ALBEDO = vec3(0.85,0.94,1.0)*clamp(ei_ambient+ei_sun*0.6,vec3(0.0),vec3(1.0));
	ALPHA = clamp(soft*fall_opacity,0.0,0.6);
}
"""


static func spray() -> Shader:
	return Gfx.make_shader(SPRAY,false)
