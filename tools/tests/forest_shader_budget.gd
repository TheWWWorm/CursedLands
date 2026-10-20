extends Node
## Load actual foliage beyond the deliberately small test uniform pool.
## Run on Forward+ with rendering/limits/global_shader_variables/buffer_size=4096.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Engine.max_fps = 30
	check(RenderingServer.get_current_rendering_method()=="forward_plus","Forward+ shader-pool fixture")
	var budget := int(ProjectSettings.get_setting_with_override("rendering/limits/global_shader_variables/buffer_size"))
	check(budget==4096,"small shader pool is configured before engine startup")
	var vp := SubViewport.new(); vp.size = Vector2i(256,256); vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(vp)
	var cam := Camera3D.new(); vp.add_child(cam);cam.position=Vector3(25,40,60);cam.look_at(Vector3(25,0,25));cam.current=true
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);vp.add_child(sun)
	var count := 0
	var roots: Array[Node3D] = []
	for i in 300:
		var tree := EIFigure.instantiate("nafltr56","tree02",Vector3(0.5,0.5,0.5),PackedStringArray(),false,true)
		vp.add_child(tree);tree.position=Vector3((i%20)*2.5,0,(i/20)*2.5);roots.append(tree)
		count+=tree.find_children("*","MeshInstance3D",true,false).size()
		if i%40==0: await get_tree().process_frame
	check(count>budget/16,"real foliage exceeds the previous per-instance capacity")
	var fade := CameraFade.new();fade._nodes=[roots[0],roots[1]]
	fade._meshes=[roots[0].find_children("*","MeshInstance3D",true,false),roots[1].find_children("*","MeshInstance3D",true,false)]
	fade._set_alpha(0,0.5)
	for i in 12: await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image(); img.save_png("user://forest-shader-budget.png")
	check(not img.is_empty(),"dense foliage and camera fade render")
	fade._set_alpha(0,0.0)
	vp.queue_free()
	for i in 4: await get_tree().process_frame
	FileAccess.open("user://forest-shader-budget.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"parts":count,"buffer_vec4s":budget},"\t"))
	print("FOREST_SHADER_BUDGET ",checks," checks ",failures.size()," failures; ",count," parts")
	get_tree().quit(1 if failures else 0)
