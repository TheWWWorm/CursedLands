extends "res://tools/tests/scene_raytrace_device.gd"
## Verify renderer placement, not just Node3D values or PT's separate scene.
func placed() -> MeshInstance3D:
	var root := Node3D.new()
	root.position=Vector3(50,3,-50);root.rotation.y=0.6
	var part := Node3D.new();part.position=Vector3(1,0,0);root.add_child(part)
	var mesh := MeshInstance3D.new();mesh.mesh=BoxMesh.new();part.add_child(mesh)
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color.GREEN;mesh.material_override=material
	add_child(root)
	return mesh

func verify(mesh: MeshInstance3D,label: String) -> void:
	await frames(5);await RenderingServer.frame_post_draw
	var box := (mesh.global_transform*mesh.get_aabb()).grow(0.01)
	var hits := RenderingServer.instances_cull_aabb(box,mesh.get_world_3d().scenario)
	check(hits.has(mesh.get_instance_id()),label+" is present at its authored renderer bounds")
	camera.global_position=mesh.global_position+Vector3(0,0,5)
	camera.look_at(mesh.global_position)
	await frames(3);await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var c := picture.get_pixelv(picture.get_size()/2)
	check(c.g>0.7 and c.r<0.15 and c.b<0.15,label+" draws the expected green surface")
	picture.save_png(out.path_join(label+".png"))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(get_tree().physics_interpolation,"motion interpolation is initialized before a startup scene can load")
	camera=Camera3D.new();add_child(camera);camera.current=true
	var first := placed()
	# Matches a direct scene load before deferred window configuration.
	GameData._apply_window()
	await verify(first,"startup")
	var root := first.get_parent().get_parent()
	remove_child(root);add_child(root)
	await verify(first,"reattached")
	GameData.options.phys_interp=0;GameData._apply_window()
	await frames(3)
	root.queue_free();await frames(2)
	var next := placed()
	# Enable in the same frame as a placement, before normal transform flush.
	GameData.options.phys_interp=1;GameData._apply_window()
	await verify(next,"enabled-with-pending-placement")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"test cursor stays free")
	next.get_parent().get_parent().queue_free();camera.queue_free();await frames(3)
	finish()
