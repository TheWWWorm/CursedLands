extends "arena_expansion_ui.gd"
func _ready()->void:
	await frames(24)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"gfx_hd_textures":0},true)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,800);get_window().position=Vector2i.ZERO
	var row:=HBoxContainer.new();row.position=Vector2(30,120);row.size=Vector2(1200,360);add_child(row)
	for id in ["bansheelightf2","bansheelightf4","bansheedarkf12","goblinf1","toadm2"]:
		var card:=ArenaCreatureCard.new();card.prototype=id;card.custom_minimum_size=Vector2(210,330);row.add_child(card)
	await frames(35)
	for card in row.get_children():
		var preview:WikiPreview=card.preview
		var model:EIUnitModel=preview.creature._model
		check(model!=null,"preview loaded: "+card.prototype)
		if model==null:continue
		model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for phase in [0.0,0.25,0.5,0.75]:
			model.player.seek(phase*model.player.current_animation_length,true);model.flush_pending_pose();preview._fit_creature()
			for part:Array in model._morph_parts:
				var mesh:MeshInstance3D=part[0]
				var bounds:=EIUnitModel.preview_bounds(mesh).grow(0.001)
				var shapes:Array=mesh.mesh.surface_get_blend_shape_arrays(0)
				var vertices:PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				if not part[2].is_empty():vertices.fill(Vector3.ZERO)
				for shape:int in part[2]:
					var weight:=mesh.get_blend_shape_value(shape)
					var positions:PackedVector3Array=shapes[shape][Mesh.ARRAY_VERTEX]
					for i in vertices.size():vertices[i]+=positions[i]*weight
				check(vertices.is_empty() or Array(vertices).all(func(vertex):return bounds.has_point(vertex)),"current pose fits its preview bounds: "+card.prototype+" "+str(phase))
		if card.prototype.begins_with("banshee"):
			check(preview._fit_distance<8.0,"idle banshee framing excludes distant attack/death morphs: "+card.prototype)
	await shot("banshee-framing")
	print("ARENA_MORPH_PREVIEW ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
