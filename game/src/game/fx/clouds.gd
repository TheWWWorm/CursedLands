extends RefCounted
## Optional shared cloud layer: a bounded alternative to R1's full ray march.
## Integrate wind displacement, never multiply a changing wind by total time.
## Each seamless layer has its own double-precision reduced phase.
const Wind = preload("res://src/game/fx/weather_wind.gd")
const Volume = preload("res://src/game/fx/cloud_volume.gd")
const VolumeNoise = preload("res://src/game/fx/cloud_volume_noise.gd")
const ShadowField = preload("res://src/game/fx/cloud_shadow_field.gd")
const HEIGHT := 160.0
const COMMON := """
global uniform sampler2D ei_cloud_noise : filter_linear_mipmap, repeat_enable;
global uniform vec4 ei_cloud_state; // threshold, shadow strength, height, enabled
global uniform vec4 ei_cloud_phases;
global uniform vec2 ei_cloud_twinkle;
float ei_cloud_density(vec2 p) {
	float cloud_coarse = textureLod(ei_cloud_noise,p/384.0+ei_cloud_phases.xy,2.0).r;
	float cloud_detail = textureLod(ei_cloud_noise,vec2(p.y,-p.x)/128.0+ei_cloud_phases.zw,1.0).r;
	return smoothstep(ei_cloud_state.x-0.14,ei_cloud_state.x+0.14,cloud_coarse*0.75+cloud_detail*0.25);
}
vec3 ei_cloud_sky(vec3 cloud_base, vec3 cloud_origin, vec3 cloud_ray, vec3 cloud_ambient, vec3 cloud_sunlight) {
	if (ei_cloud_state.w<0.5 || cloud_ray.y<=0.03 || cloud_origin.y>=ei_cloud_state.z) { return cloud_base; }
	vec2 cloud_projected = cloud_origin.xz+cloud_ray.xz*max(ei_cloud_state.z-cloud_origin.y,0.0)/max(cloud_ray.y,0.08);
	float cloud_amount = ei_cloud_density(cloud_projected)*smoothstep(0.03,0.2,cloud_ray.y);
	vec3 cloud_colour = clamp(cloud_ambient*0.65+cloud_sunlight*0.45,vec3(0.08,0.1,0.14),vec3(0.94));
	return mix(cloud_base,cloud_colour,cloud_amount*0.82);
}
"""
const SHADOW := """
float ei_cloud_sun(vec3 p) {
	if (ei_cloud_state.w<0.5 || ei_cloud_state.y<=0.0 || ei_sun_dir.y<0.12 || p.y>=ei_cloud_state.z) { return 1.0; }
	vec2 projected = p.xz+ei_sun_dir.xz*max(ei_cloud_state.z-p.y,0.0)/max(ei_sun_dir.y,0.18);
	return 1.0-ei_cloud_density(projected)*ei_cloud_state.y;
}
"""
const SKY := """
	// The same world-space sheet casts the ground shadow and appears in the
	// radiance cubemap. Blend away grazing rays to preserve perimeter fog.
	col = ei_cloud_sky(col,POSITION,EYEDIR,ambient,sun_col);
"""
var clock := -1.0
var phase_x := 0.0
var phase_z := 0.0
var detail_x := 0.0
var detail_z := 0.0
var frame := {"state":Vector4.ZERO,"phases":Vector4.ZERO,"twinkle":Vector2.ZERO}
var _identity := ""
var _sheltered := false
var volume := Volume.new()


static func mode() -> int:
	var value := clampi(GameData.option("gfx_clouds"),0,3)
	return mini(value,1) if value>1 and not VolumeNoise.supported() else value


static func shadows_enabled() -> bool:
	return mode()>0 and GameData.option("gfx_cloud_shadows")>0


static func reflections_enabled() -> bool:
	return mode()>0 and GameData.option("gfx_cloud_reflections")>0 and GameData.option("gfx_water")>0


static func common_source(view_bounds := false) -> String:
	if mode()<2: return COMMON
	return COMMON.replace("vec3 ei_cloud_sky(","vec3 ei_cloud_sheet(")+(Volume.sky_source() if view_bounds else Volume.COMMON)+"""
vec3 ei_cloud_sky(vec3 base,vec3 origin,vec3 ray,vec3 cloud_ambient,vec3 sun) {
	if(ei_cv_storm.z<.5){return ei_cloud_sheet(base,origin,ray,cloud_ambient,sun);}
	vec4 cloud=cv_march(origin,ray,ei_sun_dir,cloud_ambient,sun,64,3,.5);
	return cv_composite(base,cloud,ray,cloud_ambient,sun);
}
"""


static func shadow_source() -> String:
	if mode()<2: return SHADOW
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		return SHADOW.replace("ei_cloud_sun(","ei_cloud_sheet_sun(")+ShadowField.LOOKUP+"""
float ei_cloud_sun(vec3 p){
	return ei_cv_storm.z<.5?ei_cloud_sheet_sun(p):cv_shadow_field(p);
}
"""
	return SHADOW.replace("ei_cloud_sun(","ei_cloud_sheet_sun(")+"""
float ei_cloud_sun(vec3 p){
	return ei_cv_storm.z<.5?ei_cloud_sheet_sun(p):cv_shadow(p,ei_sun_dir);
}
"""


static func coverage(allod: String, rain: float, snow: float) -> float:
	var fair := 0.62
	match allod.to_lower():
		"ingos": fair=0.55
		"suslanger": fair=0.45
	return lerpf(fair,0.88,clampf(maxf(rain,snow),0.0,1.0))


static func daylight(hour: float) -> float:
	var h := fposmod(hour,24.0)
	return smoothstep(4.0,6.0,h)*(1.0-smoothstep(18.0,20.0,h))


func reset(identity: String) -> void:
	_identity=identity; clock=-1.0
	var seed_value := Wind.map_seed(identity)
	volume.reset(seed_value)
	phase_x=Wind.lattice(seed_value,0); phase_z=Wind.lattice(seed_value,1)
	detail_x=Wind.lattice(seed_value,2); detail_z=Wind.lattice(seed_value,3)
	frame={"state":Vector4.ZERO,"phases":Vector4(phase_x,phase_z,detail_x,detail_z),"twinkle":Vector2.ZERO}


func sample(seconds: float, identity: String, allod: String, wind: Vector4,
		rain: float, snow: float, hour: float, sheltered: bool) -> Dictionary:
	if not is_finite(seconds) or not wind.is_finite(): return frame
	if identity!=_identity or clock<0 or seconds<clock: reset(identity)
	# Weather/audio may tick under a held Game parent. A repeated terrain
	# clock freezes cloud motion, shape and coverage, including precipitation.
	if seconds==clock and sheltered==_sheltered: return frame
	var dt := maxf(0.0,seconds-clock) if clock>=0 else 0.0
	clock=seconds; _sheltered=sheltered
	var storm := clampf(maxf(rain,snow*0.8),0.0,1.0)
	var speed := 10.0+6.0*clampf(wind.z,0.0,1.0)+10.0*storm
	var dx := wind.x*speed*dt; var dz := wind.y*speed*dt
	phase_x=fposmod(phase_x-dx/384.0,1.0)
	phase_z=fposmod(phase_z-dz/384.0,1.0)
	detail_x=fposmod(detail_x-dz/128.0+dt*0.0007,1.0)
	detail_z=fposmod(detail_z+dx/128.0+dt*0.0004,1.0)
	var amount := coverage(allod,rain,snow)
	frame={"state":Vector4(0.8-amount*0.5,0.28*daylight(hour),HEIGHT,0.0 if sheltered else 1.0),
		"phases":Vector4(phase_x,phase_z,detail_x,detail_z),
		"twinkle":Vector2(fposmod(seconds*1.5,TAU),fposmod(seconds*4.5,TAU)),
		"volume":volume.sample(dt,wind,storm,coverage(allod,0,0),allod)}
	return frame


static func sky_source(original: String) -> String:
	var quality := mode()
	var common := COMMON if quality<2 else "global uniform vec3 ei_sun_dir;\n"+common_source(quality==3)
	var source := original.replace("float hash13(vec3 p) {",common+"\nfloat hash13(vec3 p) {")
	# The legacy fancy sky twinkles in shader TIME. In cloud mode use two
	# independently wrapped game-clock phases, including during paused nights.
	source=source.replace("sin(TIME * (1.5 + 3.0 * fract(h * 91.0)) + h * 60.0)",
		"mix(sin(ei_cloud_twinkle.x+h*60.0),sin(ei_cloud_twinkle.y+h*60.0),fract(h*91.0))")
	var marker := "\t// The opaque map perimeter fades to ei_fog_col."
	assert(source.contains(marker),"cloud sky insertion point changed")
	if quality<2: return source.replace(marker,SKY+"\n"+marker)
	# A background-only sky still gets an octmap update in Godot. Its volume
	# is unused unless the owning environment enables a radiance consumer.
	# Unknown callers keep the complete sky, including baked panoramas.
	source=source.replace("void sky() {","uniform bool cloud_radiance = true;\nvoid sky() {")
	var half := quality==3
	var pass_flag := "AT_HALF_RES_PASS" if half else "AT_QUARTER_RES_PASS"
	var pass_colour := "HALF_RES_COLOR" if half else "QUARTER_RES_COLOR"
	source=source.replace("render_mode use_debanding;","render_mode use_debanding, "+("use_half_res_pass" if half else "use_quarter_res_pass")+";")
	var low_pass := """
	if (%s) {
		// Dense midpoint quadrature remains stable without temporal history
		// or the structured grain of a sparsely jittered paused sky.
		vec4 clouds=vec4(0,0,0,1);
		if (!AT_CUBEMAP_PASS || cloud_radiance) {
			clouds=cv_march(POSITION,EYEDIR,ei_sun_dir,ambient,sun_col,%d,%d,.5);
		}
		COLOR=clouds.rgb;ALPHA=clouds.a;
	} else {
""" % [pass_flag,192 if half else 96,5 if half else 3]
	# Godot's sky processor cannot return early. Keep the original dome and
	# final composition in the other branch of the subpass selection.
	source=source.insert(source.rfind("}"),"\t}\n")
	source=source.replace("void sky() {","void sky() {\n"+low_pass)
	return source.replace(marker,"""
	if(ei_cv_storm.z>.5) {
		vec4 clouds=%s;
		col=cv_composite(col,clouds,EYEDIR,ambient,sun_col);
	} else {
		col=ei_cloud_sheet(col,POSITION,EYEDIR,ambient,sun_col);
	}
""" % pass_colour+"\n"+marker)
