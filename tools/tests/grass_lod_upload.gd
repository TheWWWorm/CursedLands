extends "grass_chunks.gd"
## Bulk upload followed by repeated LOD swaps must retain exactly the scalar
## transforms, colour/custom channels, bounds, and rendered pixels.
var images := []

func draw_frames() -> void:
	for i in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _ready() -> void:
	GameData.options.merge({"vsync":0,"fps_limit":0,"auto_graphics":0,"confine_mouse":0},true)
	Gfx.ensure_globals()
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var view := SubViewport.new();view.size=Vector2i(640,480);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var d := fixture();view.add_child(d.terrain);d.terrain.set_process(false)
	d.terrain.add_child(d);d.set_process(false);d.prepare_grass()
	var key := Vector2i(2,2)
	var data := d.instances(key)
	check(data.transforms.size()>100,"nonempty authored-shape fixture")
	d._install_chunk(key,data)
	var candidate: TerrainDetails.Chunk=d._chunks[key]
	var reference := MultiMeshInstance3D.new();reference.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.use_custom_data=true
	mm.mesh=d._mesh;mm.instance_count=data.transforms.size()
	for i in mm.instance_count:
		mm.set_instance_transform(i,data.transforms[i]);mm.set_instance_color(i,data.colours[i]);mm.set_instance_custom_data(i,data.custom[i])
	reference.multimesh=mm;view.add_child(reference)
	var material := ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 colour;
void vertex() {
 VERTEX.y *= 0.5 + INSTANCE_CUSTOM.r;
 VERTEX.x += INSTANCE_CUSTOM.b * UV.y;
 colour = COLOR.rgb * vec3(0.5 + INSTANCE_CUSTOM.g / 28.0, INSTANCE_CUSTOM.a, 1.0);
}
void fragment() { ALBEDO = colour; }
"""
	candidate.material_override=material;reference.material_override=material
	var camera := Camera3D.new();view.add_child(camera)
	camera.position=Vector3(20,13,-11);camera.look_at(Vector3(20,5,-20));camera.current=true
	# Do not call buffer/instance getters until after the swaps: they can
	# themselves create a CPU cache and would mask the production upload path.
	for step in 16:
		var mesh := d._mesh if step%2==0 else d._far_mesh
		candidate.multimesh.mesh=mesh;reference.multimesh.mesh=mesh
		reference.hide();candidate.show();await draw_frames()
		var actual := view.get_texture().get_image()
		candidate.hide();reference.show();await draw_frames()
		var expected := view.get_texture().get_image()
		check(actual.get_data()==expected.get_data(),"bulk/scalar pixels after LOD swap "+str(step))
		check(candidate.multimesh.get_aabb().is_equal_approx(mm.get_aabb()),"bulk/scalar bounds after LOD swap "+str(step))
		if step<2:
			actual.save_png("user://grass-lod-"+str(step)+".png")
			images.append(actual.get_data())
	check(images[0]!=images[1],"LOD comparison exercises different visible geometry")
	check(candidate.multimesh.buffer==mm.buffer,"bulk/scalar packed data after repeated swaps")
	var empty := {"transforms":[] as Array[Transform3D],"colours":[] as Array[Color],"custom":[] as Array[Color],"buffer":PackedFloat32Array()}
	d._install_chunk(Vector2i(0,0),empty)
	check(d._chunks[Vector2i.ZERO].multimesh.instance_count==0,"empty chunk needs no scalar seed")
	var roots := d._chunks.values()
	d._clear_grass();await draw_frames()
	check(d._chunks.is_empty() and not is_instance_valid(roots[0]),"clear releases uploaded chunks")
	FileAccess.open("user://grass-lod-upload.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"instances":data.transforms.size(),"cpu_cache_bytes":data.buffer.size()*4},"\t"))
	view.free();TexUpscale.shutdown()
	print("GRASS_LOD_UPLOAD ",checks," checks ",failures," failures")
	get_tree().quit(int(failures>0))
