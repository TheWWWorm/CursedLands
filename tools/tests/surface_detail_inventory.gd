extends Node
## Read-only UV/part inventory for the authored material pilot.
func _ready() -> void:
	var out:="user://surface-inventory"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	var entries:=[]
	for source: Array in [["zone1","bridge00","stbr1"],["zone13","stone03","nast6"],["zone1","columnruins01","stst13"]]:
		# These previews intentionally retain the game's row order. They are
		# decoded original data for local inspection, not redistributable art.
		GameData.load_image(source[1]).save_png(out.path_join(source[1]+"-runtime-uv.png"))
		var mob:=EIMob.load_bytes(GameData.read_file("maps/"+source[0]+".mob"))
		for record: Dictionary in mob.objects:
			if record.texture!=source[1] or record.template!=source[2] or record.kind not in ["OBJECT","LEVER"]:continue
			var model:=EIFigure.instantiate(record.template,record.texture,record.complexion,record.parts,false,true)
			add_child(model)
			for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				var arrays:=mesh.mesh.surface_get_arrays(0);var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
				var bounds:=Rect2(uv[0],Vector2.ZERO)
				for p in uv:bounds=bounds.expand(p)
				var entry:={"template":record.template,"texture":record.texture,"name":str(mesh.get_path()),
					"bounds":str(mesh.global_transform*mesh.get_aabb()),"uv_bounds":str(bounds),"vertices":uv.size()}
				entries.append(entry);print("SURFACE_PART ",JSON.stringify(entry))
			model.queue_free();break
	FileAccess.open(out.path_join("surface-inventory.json"),FileAccess.WRITE).store_string(JSON.stringify(entries,"\t"))
	get_tree().quit()
