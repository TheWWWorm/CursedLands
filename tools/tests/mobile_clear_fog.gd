extends Node
## Compare the final fog blend with the independent original function, at
## distance/border thresholds, outside maps and with menu/linear borders.
var checks := 0
var failures := 0

func _ready() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		printerr("MOBILE_CLEAR_FOG requires the Mobile renderer"); get_tree().quit(2); return
	Gfx.ensure_globals(); Gfx._skip_clear_mobile_fog = true
	var view := SubViewport.new(); view.size = Vector2i(128,96); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0; camera.position.z = 2.0; view.add_child(camera); camera.make_current()
	var draw := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = Vector2(8.0/3.0,2.0)
	draw.mesh = quad; view.add_child(draw)
	var material := ShaderMaterial.new(); draw.material_override = material
	var source := Gfx.compose("""shader_type spatial;
render_mode unshaded, fog_disabled;
void fragment() {
 int id=int(FRAGCOORD.y)*128+int(FRAGCOORD.x);
 const float positions[12]=float[12](-20.0,-0.001,0.0,1.0,16.9999,17.0,17.0001,40.0,62.9999,63.0,99.0,120.0);
 const float depths[8]=float[8](-10.0,0.0,20.0,49.999,50.0,75.0,120.0,300.0);
 vec3 world=vec3(positions[id%12],0.0,-positions[(id/12)%12]);
 vec3 vertex=vec3(0.0,0.0,-depths[(id/144)%8]);
 vec4 expected=reference_fog(vertex,world);
 vec4 actual=ei_fog_of(vertex,world);
 vec3 surface=vec3(float(id%17)/16.0,float(id%7)/6.0,float(id%5)/4.0);
 // Both direct FOG and the volumetric bridge consume fog.rgb * fog.a.
 vec3 before=mix(surface,expected.rgb,expected.a);
 vec3 after=mix(surface,actual.rgb,actual.a);
 bool ok=abs(expected.a-actual.a)<=0.000001
     && all(lessThanEqual(abs(before-after),vec3(0.000001)))
     && !any(isnan(actual)) && !any(isinf(actual));
 ALBEDO=ok ? vec3(0.0,1.0,0.0) : vec3(1.0,0.0,0.0);
}
""",false)
	var start := Gfx.LIGHT_COMMON.find("vec4 ei_fog_of(")
	var end := Gfx.LIGHT_COMMON.find("\n}",start)+2
	var reference := Gfx.LIGHT_COMMON.substr(start,end-start).replace("ei_fog_of(","reference_fog(")
	source = source.replace("void fragment() {",reference+"\nvoid fragment() {")
	var shader := Shader.new(); shader.code = source; material.shader = shader
	var cases := [
		[Vector4(100,80,16,1),Vector3(50,100,0)],
		[Vector4(100,80,0,1),Vector3(90,130,0)],
		[Vector4(100,80,30,0),Vector3(50,100,0)],
		[Vector4(20,20,16,.5),Vector3(-10,50,0)],
		[Vector4(2000,1000,16,1),Vector3(0,120,0)],
		[Vector4(100,80,16,1),Vector3(50,50,0)]]
	var rows := []
	for i in cases.size():
		RenderingServer.global_shader_parameter_set(&"ei_border",cases[i][0])
		RenderingServer.global_shader_parameter_set(&"ei_fog",cases[i][1])
		RenderingServer.global_shader_parameter_set(&"ei_fog_col",Vector3(.08+.17*i,.4,.65-.1*i))
		RenderingServer.global_shader_parameter_set(&"ei_sky",Vector3(.6,.2,.4))
		await get_tree().create_timer(.5).timeout
		for frame in 8: await RenderingServer.frame_post_draw
		var pixels := view.get_texture().get_image(); var failed := 0
		for y in 96:
			for x in 128:
				var pixel := pixels.get_pixel(x,y); checks += 1
				if pixel.g < .99 or pixel.r > .01: failed += 1
		failures += failed; rows.append({"case":i,"failures":failed})
		pixels.save_png("user://mobile-clear-fog-%d.png" % i)
	view.free()
	FileAccess.open("user://mobile-clear-fog.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("MOBILE_CLEAR_FOG checks=",checks," failures=",failures)
	get_tree().quit(int(failures > 0))
