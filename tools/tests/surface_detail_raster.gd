extends Node
## Draw the changed solid and cutout object shaders on raster-only backends.
## Keep this focused: unrelated terrain/contact GLSL variants can take minutes
## to compile on the compatibility driver.
var failures:=[]
var checks:=0

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func frames(count:=4) -> void:
	for i in count:await get_tree().process_frame

func _ready() -> void:
	var out:="user://surface-detail-raster"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.pt_mode=0;Gfx._vol_fog=false;Gfx.ensure_globals()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.position.z=4;camera.current=true
	var light:=DirectionalLight3D.new();viewport.add_child(light)
	var mesh:=MeshInstance3D.new();mesh.mesh=QuadMesh.new();viewport.add_child(mesh)
	var albedo:=GameData.get_texture("stone03",true)
	var detail:=SurfaceDetail.texture_for("stone03",albedo)
	check(detail!=null,"authored map is available to the raster backend")
	for cutout: bool in [false,true]:
		for enabled: int in [0,1]:
			GameData.options.gfx_materials=enabled
			var shader:=Gfx.make_shader(EIFigure.OBJECT_A2C_SHADER if cutout else EIFigure.OBJECT_SHADER,true,false)
			var material:=ShaderMaterial.new();material.shader=shader
			material.set_shader_parameter("albedo_tex",albedo)
			material.set_shader_parameter("surface_detail_tex",detail)
			material.set_shader_parameter("surface_detail_enabled",true)
			material.set_shader_parameter("surface_profile",SurfaceMaterials.object_profile("stone03"))
			mesh.material_override=material
			var names:=shader.get_shader_uniform_list().map(func(u):return String(u.name))
			check(names.has("surface_detail_tex") and names.has("surface_detail_enabled"),"data uniforms compile "+str([cutout,enabled]))
			await frames(2);RenderingServer.force_draw();await frames(2)
			var image:=viewport.get_texture().get_image()
			check(image!=null and image.get_size()==Vector2i(320,240),"production object variant draws "+str([cutout,enabled]))
			image.save_png(out.path_join("object-%d-%d.png"%[int(cutout),enabled]))
	mesh.material_override=null;viewport.queue_free();await frames(12);TexUpscale.shutdown()
	FileAccess.open(out.path_join("surface-detail-raster.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"driver":RenderingServer.get_current_rendering_driver_name()},"\t"))
	print("SURFACE_DETAIL_RASTER ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
