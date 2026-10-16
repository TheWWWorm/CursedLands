extends Node
## Actual GPU comparison of omitted point lights, including mixed surfaces,
## index repacking, empty lists, and ordinary materials in the same instance.
var checks := 0
var failures := 0
var rows := []
const BODY := """
shader_type spatial;
render_mode ambient_light_disabled;
uniform vec3 baked = vec3(0.0);
void fragment() { ALBEDO = vec3(.6); ROUGHNESS = 1.0; }
void light() {
	if (LIGHT_IS_DIRECTIONAL || !(dot(LIGHT_COLOR,baked) > .1)) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL,LIGHT),0.0) / PI;
	}
}
"""
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
func diff(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var over := 0
	for i in aa.size():
		var delta := absi(aa[i]-bb[i]); peak=maxi(peak,delta); over+=int(delta>2)
	return {"peak":peak,"channels_over_2":over}
func shader(code: String) -> Shader:
	var s := Shader.new(); s.code=code; return s
func _ready() -> void:
	check(OS.has_feature("ei_mobile_baked_omni_lighting"),"native capability present")
	check(RenderingServer.get_current_rendering_method()=="mobile","Mobile backend")
	if failures: get_tree().quit(1);return
	var view := SubViewport.new();view.size=Vector2i(192,128);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.0
	view.add_child(camera);camera.position=Vector3(0,0,4);camera.current=true
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.03,.04,.05)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.1,.1,.1)
	env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED;camera.environment=env
	var sun:=DirectionalLight3D.new();sun.light_energy=.2;view.add_child(sun)
	var mesh:=ArrayMesh.new()
	for x in [-.9,.9]:
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in [Vector2(-.65,-1),Vector2(-.65,1),Vector2(.65,1),Vector2(-.65,-1),Vector2(.65,1),Vector2(.65,-1)]:
			surface.set_normal(Vector3(0,0,1));surface.add_vertex(Vector3(x+p.x,p.y,0))
		surface.commit(mesh)
	var material:=ShaderMaterial.new();material.shader=shader(BODY)
	var ordinary:=StandardMaterial3D.new();ordinary.albedo_color=Color(.6,.6,.6);ordinary.roughness=1
	mesh.surface_set_material(0,material);mesh.surface_set_material(1,ordinary)
	var object:=MeshInstance3D.new();object.mesh=mesh;view.add_child(object)
	var lights:Array[OmniLight3D]=[]
	for colour in [Color.RED,Color.GREEN,Color.BLUE]:
		var light:=OmniLight3D.new();light.light_color=colour;light.omni_range=8;view.add_child(light)
		lights.append(light)
	var reference:=shader(BODY)
	var optimized:=shader(BODY.replace("render_mode ","render_mode skip_custom_baked_omni_lights, ").replace("dot(LIGHT_COLOR,baked) > .1","false"))
	var visible_check:=false
	for alpha in [false,true]:
		var body:=BODY.replace("ROUGHNESS = 1.0;","ROUGHNESS = 1.0; ALPHA = .8;") if alpha else BODY
		reference.code=body
		optimized.code=body.replace("render_mode ","render_mode skip_custom_baked_omni_lights, ").replace("dot(LIGHT_COLOR,baked) > .1","false")
		for mask in [0,1,2,3,7,4,0]:
			for i in 3:
				lights[i].position=Vector3((i-1)*.3,.2,1.0+float((i+mask)%3)*.2)
				lights[i].call("set_custom_baked",false)
			material.shader=reference
			material.set_shader_parameter("baked",Vector3(float(bool(mask&1)),float(bool(mask&2)),float(bool(mask&4))))
			await frames(8)
			var before:=view.get_texture().get_image();before.convert(Image.FORMAT_RGBA8)
			if not visible_check:
				visible_check=true
				check(before.get_pixel(48,64).r>.2 and before.get_pixel(144,64).r>.2,"both mixed surfaces visibly render")
			material.shader=optimized
			for i in 3:lights[i].call("set_custom_baked",bool(mask&(1<<i)))
			await frames(8)
			var after:=view.get_texture().get_image();after.convert(Image.FORMAT_RGBA8)
			var difference:=diff(before,after)
			check(difference.channels_over_2==0,"custom omission preserves ordinary surface alpha=%s mask=%d"%[alpha,mask])
			rows.append({"alpha":alpha,"mask":mask,"difference":difference})
			if mask==7:after.save_png("user://mobile-baked-lights-%s.png"%alpha)
	view.free();TexUpscale.shutdown();UnitWounds.shutdown()
	FileAccess.open("user://mobile-baked-lights.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("MOBILE_BAKED_LIGHTS checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
