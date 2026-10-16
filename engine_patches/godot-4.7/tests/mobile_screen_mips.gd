extends Node
## Compare level-zero consumers with a forced full-mip reference, while real
## mip consumers appear, disappear and change shaders. Also run on the prior
## engine and compare captures to catch stale/black mip levels in both paths.
const BACKGROUND := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float phase = 0.0;
void fragment() {
 float cell=mod(floor(FRAGCOORD.x/7.0)+floor(FRAGCOORD.y/9.0),2.0);
 ALBEDO=mix(vec3(0.08+phase*0.6,0.2,0.85-phase*0.6),vec3(0.9,0.7-phase*0.4,0.1),cell);
}
"""
const SCREEN := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D copied : hint_screen_texture, FILTER, repeat_disable;
uniform float level = 0.0;
void fragment() { ALBEDO=textureLod(copied,SCREEN_UV,level).rgb; ALPHA=1.0; }
"""
var checks := 0
var failures := 0
var rows := []

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 12) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func difference(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var changed := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		peak=maxi(peak,d); changed+=int(d>0)
	return {"peak":peak,"changed_pixels":changed}

func material(code: String) -> ShaderMaterial:
	var result := ShaderMaterial.new(); var shader := Shader.new(); shader.code=code; result.shader=shader; return result

func quad(view: Node,size: Vector2,pos: Vector3,mat: Material) -> MeshInstance3D:
	var draw := MeshInstance3D.new(); var mesh := QuadMesh.new(); mesh.size=size
	draw.mesh=mesh; draw.material_override=mat; view.add_child(draw); draw.position=pos; return draw

func _ready() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		printerr("MOBILE_SCREEN_MIPS requires Mobile GPU draws"); get_tree().quit(2); return
	var view := SubViewport.new(); view.size=Vector2i(512,256); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=4; camera.position.z=5
	view.add_child(camera); camera.current=true
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR; camera.environment=env
	var background := material(BACKGROUND); quad(view,Vector2(8,4),Vector3.ZERO,background)
	var linear := material(SCREEN.replace("FILTER","filter_linear"))
	var full := material(SCREEN.replace("FILTER","filter_linear_mipmap"))
	var left := quad(view,Vector2(3.8,3.6),Vector3(-2,0,1),linear)
	var right_mat := material(SCREEN.replace("FILTER","filter_linear_mipmap")); right_mat.set_shader_parameter("level",3.0)
	var right := quad(view,Vector2(3.8,3.6),Vector3(2,0,1),right_mat)
	var multi := MultiMeshInstance3D.new(); var mm := MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D
	var mesh := QuadMesh.new(); mesh.size=Vector2(3.8,3.6); mm.mesh=mesh; mm.instance_count=1
	mm.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(2,0,1))); multi.multimesh=mm
	multi.material_override=right_mat; view.add_child(multi); mm.visible_instance_count=0
	var states := ["zero-only","mixed","hidden","reappear","shader-zero","shader-mip","culled","unculled","multi-empty","multi-visible","multi-empty-again","next-pass"]
	for index in states.size():
		var state: String=states[index]
		background.set_shader_parameter("phase",float(index%3)*.4)
		right.visible=state not in ["zero-only","hidden","multi-empty","multi-visible","multi-empty-again"]
		right.position.x=30 if state=="culled" else 2
		mm.visible_instance_count=1 if state=="multi-visible" else 0
		right_mat.shader.code=SCREEN.replace("FILTER","filter_linear" if state in ["shader-zero","next-pass"] else "filter_linear_mipmap")
		right_mat.set_shader_parameter("level",0.0 if state in ["shader-zero","next-pass"] else 3.0)
		var chain := material(SCREEN.replace("FILTER","filter_linear_mipmap")); chain.set_shader_parameter("level",4.0)
		right_mat.next_pass=chain if state=="next-pass" else null
		left.material_override=linear; await frames(24)
		var actual := view.get_texture().get_image()
		left.material_override=full; await frames(24)
		var reference := view.get_texture().get_image()
		left.material_override=linear; await frames()
		var repeat := view.get_texture().get_image()
		var delta := difference(actual,reference); var stable := difference(actual,repeat)
		check(delta.changed_pixels==0,"mip demand preserves pixels "+state)
		check(stable.changed_pixels==0,"reference stable "+state)
		actual.save_png("user://mobile-screen-mips-"+state+".png")
		rows.append({"state":state,"candidate":delta,"repeat":stable})
	view.free()
	FileAccess.open("user://mobile-screen-mips.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"native_mip_demand":OS.has_feature("ei_mobile_screen_mip_demand"),"rows":rows},"\t"))
	print("MOBILE_SCREEN_MIPS checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
