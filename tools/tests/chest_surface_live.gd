extends "path_trace_performance.gd"
## Native chest mesh, including its open-lid morph, under raster and PT.
func run() -> void:
	var context := await setup(); var s: Session = context[0]; var g: Game = context[1]
	Engine.max_fps = 30
	var at := Vector3(220,0,-190)
	at.y = t.height_at(at.x,-at.z)
	var chests: Array[Node3D] = []
	for opened in [false,true]:
		var chest := EIFigure.instantiate("stst92","hadoganchest00",Vector3(1 if opened else 0,.5,.5),PackedStringArray(),true,true)
		s.world.add_child(chest); chest.position = at + Vector3(2.7 if opened else -2.7,0,0)
		s.world.objects[990001 + int(opened)] = chest; chests.append(chest)
	camera.global_position = at + Vector3(6,8,10)
	camera.look_at(at + Vector3.UP*.5); camera.fov = 42
	GameData.options.merge({"gfx_water_reflections":0,"gfx_materials":1,"gfx_terrain":1,"character_light":0,"pt_mode":0,"rt_shadows":0,"rt_gi":0},true)
	t.apply_gfx(); Gfx.apply_env(g._env)
	await frames(20); await shot("chest-raster-materials")
	var rt: Node = g.get_node("SceneRaytrace")
	GameData.options.pt_mode = 1; Gfx.apply_env(g._env)
	check(await ready_snapshot(rt), "native PT prepares original closed/open chests")
	if not rt.stats.get("active",false): get_tree().quit(1); return
	await frames(30); await shot("chest-path-traced")
	for chest in chests:
		var count := 0
		for entry: Dictionary in rt._scene.instances:
			var node: Node = entry.node.get_ref()
			if is_instance_valid(node) and chest.is_ancestor_of(node):
				count += 1
				check(rt._scene.geometries[entry.geometry].surface_layer >= 0, "visible chest part uses the mixed atlas material map")
		check(count > 0, "live PT contains the chest")
	g.queue_free(); s.queue_free(); await frames(16); TexUpscale.shutdown()
	print("CHEST_SURFACE_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
