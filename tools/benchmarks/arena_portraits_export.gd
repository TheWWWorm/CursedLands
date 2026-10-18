extends Node
## Pixelated native renders, never repainted or generatively reinterpreted.
func _ready() -> void:
	var output := "user://arena-portraits"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	var manifest := {}
	for family in ArenaRules.ACTIVE_FAMILIES:
		for rank in 3:
			var id := ArenaRules.prototype(family,rank)
			var preview := WikiPreview.new(); preview.fit_slot=true; preview.size=Vector2(384,384)
			add_child(preview); preview.show_model({"kind":"creature","value":id}); preview.turn_by(-0.4)
			for frame in 12: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var doll := preview.creature
			doll._vp.get_texture().get_image().save_png(output.path_join(id.validate_filename()+"-native.png"))
			preview.set_process(false); doll.set_process(false); doll._model.set_process(false)
			doll._model.player.pause()
			var head := doll._model.find_child("hd",true,false) as Node3D
			var bounds := AABB(); var first := true
			if head and head.has_meta(EIFigureGeometry.META):
				bounds=head.global_transform*EIFigureGeometry.box(head.get_meta(EIFigureGeometry.META)); first=false
			elif head:
				for mesh: MeshInstance3D in head.find_children("*","MeshInstance3D",true,false):
					if not mesh.is_visible_in_tree(): continue
					var box := mesh.global_transform * EIUnitModel.preview_bounds(mesh)
					bounds=box if first else bounds.merge(box); first=false
			if not first:
				var center := bounds.get_center()-Vector3(0,bounds.size.y*0.25,0)
				var diameter := maxf(bounds.size.x,bounds.size.y)*1.85
				var distance := diameter*0.5/tan(deg_to_rad(15.0))+bounds.size.z*0.5
				doll._cam.position=center+Vector3(0,0,distance); doll._cam.look_at(center)
				doll._cam.force_update_transform()
			# Render the same geometry and textures directly into a 64 px target.
			# Nearest filtering in the HUD preserves these original pixels.
			doll.size=Vector2(64,64)
			doll._vp.msaa_3d=Viewport.MSAA_DISABLED
			doll._vp.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
			for frame in 3: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := doll._vp.get_texture().get_image()
			var file := "%02d-%d.png" % [family,rank]
			image.save_png(output.path_join(file))
			manifest[id]={"file":file,"family":family,"rank":rank,"size":[image.get_width(),image.get_height()]}
			preview.queue_free(); await get_tree().process_frame
			print("NATIVE_PORTRAIT ",id," ",image.get_size())
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	get_tree().quit()
