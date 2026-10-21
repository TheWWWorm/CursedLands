extends "res://tools/tests/water_raytrace_live.gd"
## Same resource ID, edited material values: rebuild and inspect actual pixels.
func rebuild(previous: Object, label: String) -> void:
	check(t._reflection._rt_live.topology_changed(),label+": material value edit invalidates the snapshot")
	t._reflection._rt_topology_poll=0.0; await frames(2)
	check(t._water_mat.get_shader_parameter("planar_texture")==t._reflection.viewport.get_texture(),label+": Mirror remains visible during refresh")
	check(await ready_rt() and t._reflection._rt_live!=previous,label+": replacement RT scene becomes active")

func run() -> void:
	var context := await setup()
	var root := Node3D.new(); context[0].world.add_child(root)
	var node := MeshInstance3D.new(); root.add_child(node)
	var quad := QuadMesh.new(); quad.size=Vector2(5,5); node.mesh=quad
	var view: Camera3D=t._reflection.camera
	var pixel := view.get_viewport().get_visible_rect().size*0.5
	var origin := view.project_ray_origin(pixel); var direction := view.project_ray_normal(pixel)
	var entry := (t._reflection.plane-origin.y)/direction.y
	root.global_position=origin+direction*(entry+2.0); node.global_basis=view.global_basis
	context[0].world.objects["water_rt_material_probe"]=root
	var mat := StandardMaterial3D.new(); mat.albedo_color=Color(0,0,0,0)
	mat.emission_enabled=true; mat.emission=Color.RED; mat.emission_energy_multiplier=2
	node.material_override=mat
	GameData.options.gfx_water_reflections=3; t.apply_gfx()
	check(await ready_rt(),"real river prepares material probe")
	if not t._reflection._rt_ready: get_tree().quit(1); return
	var scene: Object=t._reflection._rt_live
	check(scene._groups.get(root.get_instance_id(),{}).get("indices",[]).size()==1,"primitive mesh is included in the live reflection scene")
	var initial := await reflected("material-red"); var p := initial.get_pixel(320,180)
	print("LIVE_MATERIAL red=",p," format=",initial.get_format())
	check(p.r>1.8 and p.g<0.01,"opaque material with zero alpha still reflects red emission")
	var version := mat.get_instance_id(); var previous: Object=t._reflection._rt_live
	mat.emission=Color.GREEN; await rebuild(previous,"emission edit")
	p=(await reflected("material-green")).get_pixel(320,180)
	print("LIVE_MATERIAL green=",p)
	check(mat.get_instance_id()==version and p.g>1.8 and p.r<0.01,"same material resource updates its reflected colour")
	previous=t._reflection._rt_live
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; mat.alpha_scissor_threshold=0.5
	await rebuild(previous,"transparency edit")
	p=(await reflected("material-cutout")).get_pixel(320,180)
	check(p.g<1.0,"zero-alpha cutout reveals the scenery behind it")
	previous=t._reflection._rt_live; mat.alpha_scissor_threshold=0.0
	await rebuild(previous,"threshold edit")
	p=(await reflected("material-restored")).get_pixel(320,180)
	check(p.g>1.8 and p.r<0.01,"zero cutoff restores the same live surface")
	check(not t._reflection._rt_live.topology_changed(),"unchanged material values do not cause repeated rebuilds")
	FileAccess.open(out.path_join("materials-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":t._reflection.rt_stats},"\t"))
	context[0].world.objects.erase("water_rt_material_probe"); root.queue_free()
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
