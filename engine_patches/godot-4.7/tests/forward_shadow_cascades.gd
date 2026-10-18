extends Node
## Paired-runtime image fixture: keep all four splits and their original PCF
## samples while moving receivers through the cascade blend boundaries.
var rows:=[]
func frames(n:int)->void:
	for i in n:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
func _ready()->void:
	var view:=SubViewport.new();view.size=Vector2i(640,480);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.current=true;camera.far=120;camera.near=.1
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.12,.18,.24)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.2,.2,.2)
	env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED;camera.environment=env
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.65,.55,.4);material.roughness=1
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(120,180);ground.mesh=plane
	ground.material_override=material;view.add_child(ground);ground.position.z=-35
	for z in range(-75,21,8):
		for x in [-8,0,8]:
			var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(2,3+posmod(z,5),2)
			mesh.mesh=box;mesh.material_override=material;view.add_child(mesh);mesh.position=Vector3(x,box.size.y*.5,z)
	var sun:=DirectionalLight3D.new();view.add_child(sun);sun.rotation_degrees=Vector3(-55,-25,0)
	sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance=100;sun.directional_shadow_split_1=.132;sun.directional_shadow_split_2=.396;sun.directional_shadow_split_3=.75
	RenderingServer.directional_shadow_atlas_set_size(1024,true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	var count:=0
	for quality in [RenderingServer.SHADOW_QUALITY_HARD,RenderingServer.SHADOW_QUALITY_SOFT_LOW,RenderingServer.SHADOW_QUALITY_SOFT_HIGH]:
		RenderingServer.directional_soft_shadow_filter_set_quality(quality)
		for splits in [DirectionalLight3D.SHADOW_ORTHOGONAL,DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS]:
			sun.directional_shadow_mode=splits
			for blend in [false,true]:
				sun.directional_shadow_blend_splits=blend
				for offset in [0.0,9.5,-18.0,28.0]:
					camera.position=Vector3(3,14,25+offset);camera.look_at(Vector3(0,0,-25+offset))
					await frames(16)
					var image:=view.get_texture().get_image();image.convert(Image.FORMAT_RGBA8)
					var name:="forward-shadow-%02d.png"%count;image.save_png("user://"+name)
					rows.append({"image":name,"blend":blend,"offset":offset,"quality":quality,"splits":splits});count+=1
	view.free();TexUpscale.shutdown();UnitWounds.shutdown()
	FileAccess.open("user://forward-shadow-cascades.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows},"\t"))
	print("FORWARD_SHADOW_CASCADES captures=",count);get_tree().quit()
