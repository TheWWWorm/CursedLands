extends "res://tools/tests/path_trace_resolution.gd"
## The far edge of path-traced lighting follows the camera. Moving within one
## snapshot, and publishing the recentred snapshot, must not move that edge
## relative to the eye. Terrain draws its PT blend and eye distance for analysis.
var coverage_rows := []

func debug_terrain() -> int:
	var count:=0
	for node: Node in t.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if mesh.material_override!=null and mesh.material_override.has_meta("pt_coverage_debug"):count+=1;continue
		var material:=mesh.get_active_material(0) as ShaderMaterial
		if material==null or not material.shader.code.contains("ei_pt_blend"):continue
		var copy:=material.duplicate() as ShaderMaterial
		var shader:=Shader.new()
		shader.code=Gfx._function_tail(material.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment",
			"ALBEDO=vec3(ei_pt_blend,clamp(length(VERTEX)/128.0,0.0,1.0),1.0);EMISSION=vec3(0);FOG=vec4(0);")
		copy.shader=shader;copy.set_meta("pt_coverage_debug",true)
		mesh.material_override=copy;count+=1
	return count

## Eye distance of the 50% PT blend: the mean distance of pixels in the fade band.
func boundary(label: String) -> float:
	var debugged:=debug_terrain()
	await frames(20);await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBF)
	var total:=0.0;var count:=0;var traced:=0
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			var c:=image.get_pixel(x,y).srgb_to_linear()
			if c.b<0.95:continue
			if c.r>0.9:traced+=1
			if c.r>0.3 and c.r<0.7:total+=c.g*128.0;count+=1
	image.save_png(out.path_join("coverage-%s.png"%label))
	var result:=total/count if count>0 else -1.0
	coverage_rows.append({"case":label,"boundary_m":result,"band_pixels":count,"traced_pixels":traced,
		"terrain_meshes":debugged,"center":str(camera.global_position-get_owner_center())})
	print("PT_COVERAGE_ROW ",JSON.stringify(coverage_rows.back()))
	return result

var _owner: Node
func get_owner_center() -> Vector3: return _owner._center

func place(position: Vector3,direction: Vector3) -> void:
	position.y=t.height_at(position.x,-position.z)+7.0
	camera.global_position=position
	camera.look_at(position+direction+Vector3(0,-0.22,0))

func await_center(owner: Node,near: Vector3,seconds := 90.0) -> bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<until:
		await frames(1)
		if owner.stats.get("active",false) and owner.device!=null and owner.device.output_ready() \
			and Vector2(owner._center.x-near.x,owner._center.z-near.z).length()<1.0:return true
	return false

func run() -> void:
	var context:=await configure_resolution_game();var game: Game=context[1]
	var owner: Node=game.get_node("SceneRaytrace");_owner=owner
	# Ground only, read back without tone mapping, glow, grading or fog.
	GameData.options.merge({"gfx_grass":0,"gfx_biome_cover":0},true);t.apply_gfx()
	var env: Environment=game._env
	env.background_mode=Environment.BG_COLOR;env.background_color=Color.BLACK
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR;env.tonemap_exposure=1.0;env.tonemap_white=1.0
	env.glow_enabled=false;env.adjustment_enabled=false;env.fog_enabled=false;env.volumetric_fog_enabled=false
	if not owner.stats.get("active",false):get_tree().quit(1);return
	var direction:=-camera.global_transform.basis.z;direction.y=0.0;direction=direction.normalized()
	var start:=camera.global_position
	place(start,direction)
	owner._poll=0
	check(await await_center(owner,camera.global_position),"PT snapshot is centred on the starting camera")
	var at_center:=await boundary("at-centre")
	check(at_center>30.0,"terrain shows the PT fade band ahead of the camera")
	var center: Vector3=owner._center
	place(start+direction*14.0,direction)
	await frames(10)
	check(owner._center==center,"14 m of travel keeps the same snapshot")
	var travelled:=await boundary("travelled-14m")
	check(absf(travelled-at_center)<3.0,"PT boundary stays at the same eye distance within one snapshot (%.1f m vs %.1f m)"%[travelled,at_center])
	place(start+direction*22.0,direction)
	check(await await_center(owner,camera.global_position),"travel beyond the recentre step publishes a new snapshot")
	var recentred:=await boundary("recentred")
	check(absf(recentred-travelled)<3.0,"publishing the recentred snapshot does not move the PT boundary (%.1f m vs %.1f m)"%[recentred,travelled])
	FileAccess.open(out.path_join("path-receiver-coverage.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"rows":coverage_rows,"stats":owner.stats.duplicate(true)},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_RECEIVER_COVERAGE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
