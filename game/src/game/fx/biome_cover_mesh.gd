extends RefCounted
## Small opaque geometry, merged into one surface per streamed grass chunk.
## UV: root height / stable thinning seed. UV2: chunk-local root XZ.
const Pressure = preload("res://src/game/fx/vegetation_interaction.gd")
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
var indices := PackedInt32Array()
var root := Vector3.ZERO
var transform := Transform3D.IDENTITY
var seed := 0.0
var mobile := 0.0


static func shader(interactive: bool, wind: bool) -> Shader:
	var key := int(interactive)*2+int(wind)
	if not _shaders.has(key):
		var code := SHADER
		if interactive or wind: code = code.replace("sin(wind_phase+","sin(wind_phase+TIME*0.0+")
		if interactive: code = code.replace("void vertex() {",Pressure.UNIFORMS+"\nvoid vertex() {").replace("// PRESSURE",DEFORM)
		_shaders[key] = Gfx.make_shader(code,true,true)
	return _shaders[key]


func triangle(a: Vector3,b: Vector3,c: Vector3,colour: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	var at := vertices.size()
	for p: Vector3 in [a,b,c]:
		vertices.append(transform*p+root); normals.append(transform.basis*normal)
		colours.append(Color(colour.r,colour.g,colour.b,mobile))
		uvs.append(Vector2(root.y,seed)); roots.append(Vector2(root.x,root.z))
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


func build(records: Array[Dictionary], key: Vector2i) -> Array:
	for record: Dictionary in records:
		var p: Vector2 = record.p-Vector2(key)*8.0
		root = Vector3(p.x,float(record.height)+0.008,-p.y); seed = record.seed
		transform = Transform3D(Basis(Vector3.UP,record.angle).scaled(Vector3.ONE*float(record.scale)),Vector3.ZERO)
		if int(record.kind) in [2,3,4,5]:
			var n: Vector3 = record.normal
			if n.y < 0: n = -n
			transform.basis = Basis(Quaternion(Vector3.UP,n))*transform.basis
		var c: Color = record.colour
		mobile = 1.0 if int(record.kind) in [0,1] else 0.0
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
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours; arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = roots; arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
