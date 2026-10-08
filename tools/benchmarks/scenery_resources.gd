extends Node
## Resource census, not a frame-time benchmark. Keep all placements alive:
## counting a succession of freed nodes hides opportunities for weak sharing.
## Optional --scenery-control=/absolute/baseline_figure.gd selects a snapshot
## of figure.gd with its class_name declaration removed, for a matched control.

func _ready() -> void:
	GameData.options["gfx_hd_textures"] = 0
	var implementation: GDScript = EIFigure
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenery-control="):
			implementation = load(arg.trim_prefix("--scenery-control=")) as GDScript
	if implementation == null:
		get_tree().quit(2)
		return
	var rows := []
	for map_name: String in ["bz2g", "bz4g", "bz13h"]:
		var mob := EIMob.load_bytes(GameData.read_file("maps/" + map_name + ".mob"))
		var root := Node3D.new()
		var meshes := 0
		var flora := 0
		var unique_meshes := {}
		var unique_materials := {}
		var grouped := {}
		for record: Dictionary in mob.objects:
			if record.kind != "OBJECT" or record.template == "" or record.template.begins_with("ef"):
				continue
			var node: Node3D = implementation.instantiate(record.template, record.texture,
					record.complexion, record.parts, false, true, record.get("name", ""))
			if node == null:
				continue
			root.add_child(node)
			var cell := Vector2i(floori(record.position.x / 16.0), floori(record.position.y / 16.0))
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				if mesh.mesh == null:
					continue
				meshes += 1
				flora += int(record.template.begins_with("nafl"))
				unique_meshes[mesh.mesh.get_instance_id()] = true
				var material := mesh.material_override
				unique_materials[material.get_instance_id()] = true
				var key := [cell, mesh.mesh.get_instance_id(), material.get_instance_id()]
				grouped[key] = int(grouped.get(key, 0)) + 1
		var potential_merges := 0
		for count: int in grouped.values():
			potential_merges += maxi(0, count - 1)
		rows.append({"map": map_name, "meshes": meshes, "foliage_meshes": flora,
				"unique_meshes": unique_meshes.size(), "unique_materials": unique_materials.size(),
				"potential_cell16_merges": potential_merges})
		root.free()
		if meshes == 0:
			printerr("SCENERY_RESOURCES missing fixture ", map_name)
			get_tree().quit(1)
			return
	print("SCENERY_RESOURCES ", JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(),
			"implementation": implementation.resource_path, "rows": rows}))
	get_tree().quit()
