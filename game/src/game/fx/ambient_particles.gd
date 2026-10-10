extends MultiMeshInstance3D
## At most 192 world-anchored quads. Camera movement changes the admitted
## cells, never their seeds or animation phase. The shader has no wall clock.
const Habitats = preload("res://src/game/fx/ambient_habitats.gd")
const MAX_PARTICLES := 192
const SPACING := 8.0
const RANGE := 25.0
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float seconds = 0.0;
uniform vec4 environment = vec4(0.0);
uniform vec4 wind_state = vec4(1.0,0.0,0.0,0.0);
uniform vec3 focus;
uniform int threat_count = 0;
uniform vec4 threats[16];
varying float kind;
varying float presence;
varying vec3 world_point;

void vertex() {
	kind = INSTANCE_CUSTOM.g;
	float seed = INSTANCE_CUSTOM.r;
	float period = kind == 0.0 ? 30.0 : (kind == 1.0 ? 12.0 : (kind == 4.0 ? 4.0 : 18.0));
	float phase = fract(seconds / period + seed);
	// Pollen should drift, not orbit conspicuously beside the close camera.
	float wave = seconds * (kind == 0.0 ? 0.18 : 0.7) + seed * 31.0;
	float wander = kind == 0.0 ? 0.04 : 0.22;
	vec3 offset = vec3(sin(wave) * wander, 0.0, cos(wave * 0.8) * wander);
	float height = 0.3 + phase * 2.0;
	if (kind == 1.0) height = 0.15 + (1.0-phase) * 3.0;
	if (kind == 4.0) height = 0.10 + phase * 2.5;
	if (kind == 5.0) height = 0.15 + phase * 0.75;
	if (kind == 6.0) height = 0.3 + (1.0-phase) * 2.0;
	if (kind == 7.0) height = 0.8 + sin(wave * 0.4) * 0.35;
	if (kind != 7.0 && kind != 3.0) offset.xz += wind_state.xy * wind_state.z * (phase-0.5) * 1.2;
	offset.y = height;
	world_point = MODEL_MATRIX[3].xyz + offset;
	presence = smoothstep(0.0,0.12,phase) * (1.0-smoothstep(0.82,1.0,phase));
	presence *= 1.0-smoothstep(18.0,24.0,distance(world_point.xz,focus.xz));
	float night = environment.x;
	float rain = environment.y;
	float snow = environment.z;
	if (kind == 0.0) presence *= (1.0-0.8*night)*(1.0-0.95*rain)*(1.0-snow);
	if (kind == 1.0) presence *= (1.0-0.4*rain)*(1.0-0.8*snow);
	if (kind == 5.0) presence *= (1.0-0.97*rain)*(1.0-0.7*snow);
	if (kind == 6.0) presence *= (1.0-0.9*rain)*(1.0-0.9*snow);
	if (kind == 7.0) presence *= night*(1.0-rain)*(1.0-snow)*(0.45+0.55*sin(wave*1.3)*sin(wave*1.3));
	for (int i=0; i<threat_count; i++) {
		presence *= smoothstep(threats[i].w,threats[i].w+1.5,distance(world_point,threats[i].xyz));
	}
	float scale = INSTANCE_CUSTOM.b;
	vec3 camera_point = (VIEW_MATRIX * vec4(world_point,1.0)).xyz;
	MODELVIEW_MATRIX = mat4(vec4(1.0,0.0,0.0,0.0),vec4(0.0,1.0,0.0,0.0),vec4(0.0,0.0,1.0,0.0),vec4(camera_point,1.0));
	VERTEX *= scale;
}

void fragment() {
	vec2 p = UV*2.0-1.0;
	if (kind == 1.0) p.x *= 1.8;
	float edge = 1.0-smoothstep(0.35,1.0,dot(p,p));
	vec3 colour = vec3(0.72,0.68,0.46);
	if (kind == 1.0) colour = vec3(0.45,0.36,0.12);
	if (kind == 2.0) colour = vec3(0.43,0.47,0.46);
	if (kind == 3.0) colour = vec3(0.46,0.43,0.39);
	if (kind == 4.0) colour = vec3(1.0,0.34,0.035);
	if (kind == 5.0) colour = vec3(0.60,0.46,0.27);
	if (kind == 6.0) colour = vec3(0.76,0.85,0.89);
	if (kind == 7.0) colour = vec3(0.66,0.87,0.25);
	float lit = kind == 4.0 || kind == 7.0 ? 1.0 : mix(1.0,0.30,environment.x);
	ALBEDO = colour * lit;
	ALPHA = edge * presence * (kind == 5.0 ? 0.11 : (kind == 1.0 ? 0.75 : 0.38));
	FOG = ei_fog_of(VERTEX,world_point);
}
"""
var material: ShaderMaterial
var records: Array[Dictionary] = []
var _cell := Vector2i(0x7fffffff,0x7fffffff)


func _init() -> void:
	name = "RegionalParticles"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new(); material.shader = Gfx.make_shader(SHADER,false)
	material.render_priority = 2
	material_override = material
	multimesh = MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var quad := QuadMesh.new(); quad.size = Vector2.ONE
	multimesh.mesh = quad; multimesh.instance_count = MAX_PARTICLES; multimesh.visible_instance_count = 0


func rebuild(field: Habitats, centre: Vector2, force := false) -> void:
	var cell := Vector2i((centre/SPACING).floor())
	if cell==_cell and not force: return
	_cell = cell; records.clear()
	for y in range(cell.y-3,cell.y+4):
		for x in range(cell.x-3,cell.x+4):
			var key := Vector2i(x,y)
			for lane in 4:
				var p := Vector2(key)*SPACING+Vector2(field.random(key,100+lane*5),field.random(key,101+lane*5))*SPACING
				# The outermost corners have already faded completely.
				if p.distance_to((Vector2(cell)+Vector2.ONE*0.5)*SPACING)>RANGE: continue
				var hit := field.habitat(p)
				var kinds := Habitats.particles(field.region,field.biome,hit,0.0)
				for kind in Habitats.particles(field.region,field.biome,hit,1.0):
					if not kind in kinds: kinds.append(kind)
				if kinds.is_empty(): continue
				var seed := field.random(key,102+lane*5)
				var kind := int(kinds[mini(int(seed*kinds.size()),kinds.size()-1)])
				var size := 0.055 if kind not in [1,5] else (0.13 if kind==1 else 0.60)
				records.append({"key":Vector3i(x,y,lane),"point":Vector3(p.x,float(hit.height),-p.y),"kind":kind,"seed":seed,"size":size})
				if records.size()>=MAX_PARTICLES: break
			if records.size()>=MAX_PARTICLES: break
		if records.size()>=MAX_PARTICLES: break
	var bounds := AABB()
	for i in records.size():
		var row: Dictionary = records[i]
		var box := AABB((row.point as Vector3)-Vector3(1.25,0.1,1.25),Vector3(2.5,3.6,2.5))
		bounds = box if i==0 else bounds.merge(box)
		multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,row.point))
		multimesh.set_instance_custom_data(i,Color(row.seed,row.kind,row.size,0))
	multimesh.custom_aabb = bounds
	multimesh.visible_instance_count = records.size()


func update(seconds: float, centre: Vector3, environment: Vector4, wind: Vector4, threats: PackedVector4Array) -> void:
	material.set_shader_parameter("seconds",seconds)
	material.set_shader_parameter("focus",centre)
	material.set_shader_parameter("environment",environment)
	material.set_shader_parameter("wind_state",wind)
	var padded := threats.duplicate(); padded.resize(16)
	material.set_shader_parameter("threat_count",mini(threats.size(),16))
	material.set_shader_parameter("threats",padded)
