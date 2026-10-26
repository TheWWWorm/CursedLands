extends Node
const Dielectric=preload("res://src/game/fx/path_trace_dielectric.gd")
var checks:=0
var failures:=[]
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func frames() -> void:
	for i in 8:await get_tree().process_frame
func _ready() -> void:run.call_deferred()
func run() -> void:
	Gfx.ensure_globals();GameData.options.pt_refraction=1;GameData.options.pt_mode=1
	check(RenderingServer.get_current_rendering_method()!="forward_plus","fallback fixture uses a renderer without the PT integration")
	var view:=SubViewport.new();view.size=Vector2i(160,160);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.position=Vector3(0,0,4);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.7,.5,.3);view.add_child(env)
	var glass:=MeshInstance3D.new();glass.mesh=QuadMesh.new();view.add_child(glass)
	glass.material_override=Dielectric.material(1.5,Color(.7,.8,1),1,true,.01)
	await frames();await RenderingServer.frame_post_draw
	var im:=view.get_texture().get_image();var c:=im.get_pixel(80,80)
	check(c.r+c.g+c.b>.3,"glass fallback draws visible tinted background through its unshaded albedo")
	check(c.r>c.b,"fallback retains the warm background hue")
	var sources: Array[String]=[EITerrain.WATER_SHADER,EITerrain.WATER_FX_SHADER,preload("res://src/game/fx/water_wave_shader.gd").source(EITerrain.WATER_FX_SHADER)]
	for source in sources:
		if Portability.compatibility():source=source.replace("instance uniform","uniform")
		var material:=ShaderMaterial.new();material.shader=Gfx.make_shader(source,true,true)
		check(not material.shader.get_shader_uniform_list().is_empty(),"composed water fallback shader parses")
		glass.material_override=material;await frames();await RenderingServer.frame_post_draw
		check(not view.get_texture().get_image().is_empty(),"water fallback compiles and draws on the active renderer")
	view.queue_free();await frames();TexUpscale.shutdown()
	print("PT_TRANSMISSION_FALLBACK ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
