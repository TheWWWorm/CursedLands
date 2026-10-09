extends RefCounted
## Small opaque geometry, merged into one surface per streamed grass chunk.
## UV: root height / stable thinning seed. UV2: chunk-local root XZ.
## CUSTOM0: supporting cell x*2+triangle, cell y, barycentric b/c weights.
## CUSTOM1 (sea maps only): mean-water plane (X/Z slopes, intercept), depth coefficient.
const Pressure = preload("res://src/game/fx/vegetation_interaction.gd")
const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
const UNDERWATER := """
	if (CUSTOM1.w > 0.0) {
		float depth = max(dot(CUSTOM1.xy,VERTEX.xz)+CUSTOM1.z-VERTEX.y,0.0);
		ei_k = min(depth*depth*CUSTOM1.w,4.0);
		// The native diffuse already attenuates ambient/sun/point lights.
		// Thin-leaf transmission must not leave fully dark seabeds glowing.
		cover_leaf *= max(1.0-ei_k,0.0);
	}
"""
const SURFACE_UNIFORMS := """
uniform sampler2D terrain_tiles : filter_nearest, repeat_disable;
uniform sampler2D terrain_cells : filter_nearest, repeat_disable;
"""
const ATTACH := """
	if (CUSTOM0.x >= 0.0 && fade > 0.0) {
		int packed = int(CUSTOM0.x+0.5);
		ivec2 cell = ivec2(packed/2,int(CUSTOM0.y+0.5));
		bool upper = (packed%2) != 0;
		vec3 a = query_vertex(cell+(upper ? ivec2(1,0) : ivec2(0,1)));
		vec3 b = query_vertex(cell+(upper ? ivec2(0,1) : ivec2(1,0)));
		vec3 c = query_vertex(cell+(upper ? ivec2(1) : ivec2(0)));
		vec3 weights = vec3(1.0-CUSTOM0.z-CUSTOM0.w,CUSTOM0.zw);
		// Lift/compact the whole plant after wind/pressure/fade. Its root
		// follows the actual coarse or installed dense triangle, not a
		// continuous field that the visible mesh has not yet adopted.
		VERTEX.y += query_elevation(a,b,c,weights,cell)-(UV.x-0.008);
	}
"""
const SHADER := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
#define EI_GRASS_LIGHT
render_mode cull_disabled, ambient_light_disabled;
uniform vec3 view_position;
uniform float breeze = 0.0;
uniform float wind_phase = 0.0;
varying vec3 cover_colour;
varying vec3 cover_normal;
varying float cover_leaf;
varying vec3 ei_e;
varying float ei_k;
void vertex() {
	vec3 root = vec3(UV2.x,UV.x,UV2.y);
	vec3 origin = (MODEL_MATRIX*vec4(root,1.0)).xyz;
	float distance_to_view = distance(origin.xz,view_position.xz);
	float fade = 1.0-smoothstep(28.0,36.0,distance_to_view);
	// Stable per-plant thinning, eased rather than switched at chunk borders.
	float density = mix(1.0,step(UV.y,0.35),smoothstep(18.0,28.0,distance_to_view));
	fade *= density;
	float tip = clamp((VERTEX.y-root.y)/0.6,0.0,1.0)*COLOR.a;
	VERTEX = root+(VERTEX-root)*fade;
	VERTEX.xz += vec2(1.0,0.35)*sin(wind_phase+origin.x*0.8+origin.z*0.6+UV.y*4.0)*tip*tip*0.035*breeze*fade;
	// PRESSURE
	// SURFACE
	cover_normal = normalize((VIEW_MATRIX*vec4(MODEL_NORMAL_MATRIX*NORMAL,0.0)).xyz);
	NORMAL = normalize(mix(NORMAL,vec3(0.0,1.0,0.0),0.80*COLOR.a));
	cover_colour = COLOR.rgb;
	cover_leaf = COLOR.a*0.25;
	ei_e = vec3(0.0); ei_k = 0.0;
}
void fragment() {
	FOG = ei_fog_of(VERTEX,(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz);
	ALBEDO = OUTPUT_IS_SRGB ? cover_colour : ei_lin(cover_colour);
	NORMAL = normalize(cover_normal)*(FRONT_FACING ? 1.0 : -1.0);
	ROUGHNESS = 1.0; SPECULAR = 0.0; ei_leaf = cover_leaf;
}
"""
const DEFORM := """
	vec2 delta = abs(origin.xz-vegetation_focus);
	float area = 1.0-smoothstep(27.0,30.0,max(delta.x,delta.y));
	vec3 pressure = texture(vegetation_pressure,origin.xz/64.0).rgb;
	vec2 push = (pressure.rg*2.0-1.0)*area*step(0.001,pressure.b);
	VERTEX += transpose(MODEL_NORMAL_MATRIX)*vec3(push.x,0.0,push.y)*0.35*tip*tip*fade;
	VERTEX.y = root.y+(VERTEX.y-root.y)*(1.0-pressure.b*area*tip*0.50);
"""
static var _shaders := {}
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colours := PackedColorArray()
var uvs := PackedVector2Array()
var roots := PackedVector2Array()
var anchors := PackedFloat32Array()
var water_planes := PackedFloat32Array()
var water: RefCounted
var water_cache := {}
var chunk_origin := Vector2.ZERO
var submerged := false
var indices := PackedInt32Array()
var root := Vector3.ZERO
var transform := Transform3D.IDENTITY
var seed := 0.0
var mobile := 0.0
var anchor := Vector4(-1,0,0,0)


static func shader(interactive: bool, wind: bool, soft := false, aquatic := false) -> Shader:
	var key := int(aquatic)*8+int(soft)*4+int(interactive)*2+int(wind)
	if not _shaders.has(key):
		var code := SHADER
		if interactive or wind or soft: code = code.replace("sin(wind_phase+","sin(wind_phase+TIME*0.0+")
		if interactive:
			var deformation := "if (CUSTOM1.w <= 0.0) {"+DEFORM+"}" if aquatic else DEFORM
			code = code.replace("void vertex() {",Pressure.UNIFORMS+"\nvoid vertex() {").replace("// PRESSURE",deformation)
		if soft:
			code = code.replace("void vertex() {",SURFACE_UNIFORMS+GroundSurfaceShader.SOFT_UNIFORMS+GroundSurfaceShader.SOFT_FUNCTIONS+GroundSurfaceShader.TRIANGLE_QUERY+"\nvoid vertex() {")
			code = code.replace("// SURFACE",ATTACH)
		if aquatic: code = code.replace("ei_e = vec3(0.0); ei_k = 0.0;","ei_e = vec3(0.0); ei_k = 0.0;"+UNDERWATER)
		_shaders[key] = Gfx.make_shader(code,true,true)
	return _shaders[key]


func triangle(a: Vector3,b: Vector3,c: Vector3,colour: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	var at := vertices.size()
	for p: Vector3 in [a,b,c]:
		var position := transform*p+root
		vertices.append(position); normals.append(transform.basis*normal)
		colours.append(Color(colour.r,colour.g,colour.b,mobile))
		uvs.append(Vector2(root.y,seed)); roots.append(Vector2(root.x,root.z))
		anchors.append_array([anchor.x,anchor.y,anchor.z,anchor.w])
		if water:
			var plane := Vector4.ZERO
			if submerged:
				var point := Vector2(position.x,-position.z)+chunk_origin
				if not water_cache.has(point): water_cache[point] = water.sample(point)
				plane = water_cache[point]
				assert(plane.w>0.0) # The admitted complete footprint has water.
				plane.z += plane.x*chunk_origin.x-plane.y*chunk_origin.y
			water_planes.append_array([plane.x,plane.y,plane.z,plane.w])
	indices.append_array([at,at+1,at+2])


func ribbon(a: Vector3,b: Vector3,width: float,colour: Color) -> void:
	var side := (b-a).cross(Vector3(0.3,0.0,1.0)).normalized()*width
	triangle(a-side,b-side,a+side,colour); triangle(a+side,b-side,b+side,colour)


func leaf(centre: Vector3,length: float,width: float,angle: float,colour: Color) -> void:
	var turn := Basis(Vector3.UP,angle)
	var a := centre+turn*Vector3(0,0,-length*0.5); var b := centre+turn*Vector3(-width,0,0)
	var c := centre+Vector3(0,0.012,0); var d := centre+turn*Vector3(width,0,0); var e := centre+turn*Vector3(0,0,length*0.5)
	triangle(a,c,b,colour*0.9); triangle(a,d,c,colour); triangle(b,c,e,colour); triangle(c,d,e,colour*1.05)


func tuft(colour: Color,short: bool) -> void:
	for i in 5:
		var angle := i*2.39996+seed*2.0
		var direction := Vector3(sin(angle),0,cos(angle))
		var h := (0.37+0.12*sin(i*1.3+seed))*(0.45 if short else 1.0)
		var bend := direction*(0.11+0.05*cos(i))
		var a := direction*0.025; var b := Vector3(0,h*0.55,0)+bend*0.3; var c := Vector3(0,h,0)+bend
		ribbon(a,b,0.013,colour*0.85); ribbon(b,c,0.008,colour)


func reed(colour: Color, cattail: bool) -> void:
	var top := Vector3(0.07,1.25,0.03)
	ribbon(Vector3.ZERO,top,0.012,colour*0.85)
	for i in 4:
		var turn := Basis(Vector3.UP,i*2.39996+seed)
		var base := Vector3(0,0.12+i*0.11,0)
		var elbow := base+turn*Vector3(0,0.45,0.16)
		var tip := base+turn*Vector3(0,0.58,0.30)
		ribbon(base,elbow,0.025,colour*0.85); ribbon(elbow,tip,0.010,colour)
	if cattail:
		var brown := Color(0.30,0.21,0.12)
		var bottom := top-Vector3(0,0.14,0); var cap := top+Vector3(0,0.13,0)
		for i in 6:
			var a := Vector3(sin(i*TAU/6.0),0,cos(i*TAU/6.0))*0.043
			var b := Vector3(sin((i+1)*TAU/6.0),0,cos((i+1)*TAU/6.0))*0.043
			triangle(bottom+a,cap+a,bottom+b,brown); triangle(bottom+b,cap+a,cap+b,brown)
			triangle(cap,cap+b,cap+a,brown*0.8)
	else:
		for i in 5:
			var turn := Basis(Vector3.UP,i*2.39996)
			ribbon(top-Vector3(0,0.16-i*0.025,0),top+turn*Vector3(0,0.08,0.08),0.016,colour.lerp(Color(0.58,0.48,0.28),0.7))


func shell(colour: Color) -> void:
	var hinge := Vector3(0,0.015,-0.075)
	for i in 6:
		var a := -1.2+float(i)*0.4; var b := a+0.4
		var ridge := hinge+Vector3(sin((a+b)*0.5)*0.055,0.035,cos((a+b)*0.5)*0.09)
		var left := hinge+Vector3(sin(a)*0.10,0,cos(a)*0.16)
		var right := hinge+Vector3(sin(b)*0.10,0,cos(b)*0.16)
		triangle(hinge,ridge,left,colour*0.85); triangle(hinge,right,ridge,colour)
		triangle(left,ridge,right,colour*0.95)


func sea_grass(colour: Color, tall: bool) -> void:
	for i in 5:
		var turn := Basis(Vector3.UP,i*2.39996+seed)
		var height := (0.52+0.035*i)*(2.0 if tall else 1.0)
		var spread := 0.15 if not tall else 0.24
		var a := turn*Vector3(0,0,0.015)
		var b := turn*Vector3(0.025,height*0.45,spread*0.3)
		var c := turn*Vector3(-0.025,height*0.78,spread*0.7)
		var d := turn*Vector3(0,height,spread)
		ribbon(a,b,0.025,colour*0.85); ribbon(b,c,0.025,colour); ribbon(c,d,0.013,colour*1.05)


func build(records: Array[Dictionary], key: Vector2i, sea: RefCounted = null) -> Array:
	water = sea; chunk_origin = Vector2(key)*8.0
	for record: Dictionary in records:
		var p: Vector2 = record.p-Vector2(key)*8.0
		root = Vector3(p.x,float(record.height)+0.008,-p.y); seed = record.seed
		anchor = record.get("anchor",Vector4(-1,0,0,0))
		submerged = record.get("underwater",false)
		transform = Transform3D(Basis(Vector3.UP,record.angle).scaled(Vector3.ONE*float(record.scale)),Vector3.ZERO)
		if int(record.kind) in [2,3,4,5,9,10,13]:
			var n: Vector3 = record.normal
			if n.y < 0: n = -n
			transform.basis = Basis(Quaternion(Vector3.UP,n))*transform.basis
		var c: Color = record.colour
		mobile = 1.0 if int(record.kind) in [0,1,7,8,11,12] else 0.0
		match int(record.kind):
			0: # Flowers: green stem and a small five-petal head, two patch colours.
				var top := Vector3(0.04,0.49,0.02)
				ribbon(Vector3.ZERO,top,0.009,c*Color(0.9,1.12,0.82))
				leaf(Vector3(0,0.16,0),0.17,0.03,0.8,c); leaf(Vector3(0.02,0.28,0),0.14,0.025,2.4,c)
				var petal := Color(0.78,0.70,0.36) if record.flower < 0.5 else Color(0.69,0.61,0.77)
				for i in 5:
					var turn := Basis(Vector3.UP,i*TAU/5.0)
					triangle(top,top+turn*Vector3(-0.035,0.012,0.07),top+turn*Vector3(0.035,0.012,0.07),petal)
			1: tuft(c.lerp(Color(0.55,0.46,0.28),0.55) if not record.snow else Color(0.70,0.65,0.48),record.snow)
			2:
				var autumn := Color(0.40,0.29,0.14) if not record.cold else Color(0.28,0.24,0.19)
				leaf(Vector3(0,0.01,0),0.22,0.07,0,c.lerp(autumn,0.7))
			3:
				var tint := c.lerp(Color(0.23,0.22,0.13),0.65).lerp(Color(0.65,0.67,0.65),0.45 if record.snow else 0.0)
				for i in 5: ribbon(Vector3(-0.07+i*0.028,0.018,-0.10),Vector3(-0.02+i*0.024,0.022,0.11),0.005,tint)
			4:
				var bark := c.lerp(Color(0.26,0.21,0.15),0.7)
				ribbon(Vector3(-0.28,0.025,0),Vector3(0.28,0.05,0.05),0.025,bark)
				ribbon(Vector3(0,0.04,0.025),Vector3(0.16,0.06,-0.17),0.015,bark*0.9)
			5:
				var top := Vector3(0,0.08,0)
				for i in 5:
					var a := Vector3(sin(i*TAU/5.0)*0.09,0,cos(i*TAU/5.0)*0.07)
					var b := Vector3(sin((i+1)*TAU/5.0)*0.09,0,cos((i+1)*TAU/5.0)*0.07)
					triangle(a,top,b,c.lerp(Color(0.39,0.38,0.33),0.35))
			6:
				var bark := c.lerp(Color(0.30,0.24,0.15),0.55)
				for i in 4:
					var dir := Vector3(sin(i*2.4),0,cos(i*2.4))
					var elbow := Vector3(0,0.25,0)+dir*0.15
					ribbon(Vector3.ZERO,elbow,0.018,bark); ribbon(elbow,Vector3(0,0.55,0)+dir*0.3,0.008,bark)
			7,8: reed(c.lerp(Color(0.28,0.34,0.13),0.65),int(record.kind)==8)
			9:
				var kelp := c.lerp(Color(0.22,0.25,0.10),0.80)
				for i in 4:
					var turn := Basis(Vector3.UP,i*1.9+seed)
					var middle := turn*Vector3(0.02,0.035,0.10)
					ribbon(Vector3(0,0.008,0),middle,0.025,kelp*0.9)
					ribbon(middle,turn*Vector3(0.05,0.012,0.23),0.032,kelp)
			10,13: shell(c.lerp(Color(0.76,0.70,0.55),0.65))
			11,12: sea_grass(c.lerp(Color(0.16,0.30,0.19),0.80),int(record.kind)==12)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours; arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = roots; arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = anchors
	if water: arrays[Mesh.ARRAY_CUSTOM1] = water_planes
	return arrays
