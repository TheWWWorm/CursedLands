extends "third_person_kbm.gd"
## Camera/body alignment without changing authoritative bones or geometry.
var measurements := []

func parts(model: EIUnitModel) -> Dictionary:
	var result := {}
	var pending := model._animation_roots.duplicate()
	while not pending.is_empty():
		var node: EIAnimPart = pending.pop_back()
		result[node] = node.global_transform
		pending.append_array(node.animation_children)
	return result

func materials(model: EIUnitModel) -> Dictionary:
	var result := {}
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		# Shadow and reflection copies share the source meshes' materials.
		if model._view_shadows.any(func(row):return row.shadow == mesh or row.get("reflection") == mesh): continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material: result[[mesh,surface]] = material
	return result

func _ready() -> void:
	mode = "first-person alignment"
	GameData.options.gfx_detailed_heads = 1
	var female := "Human Mercenary Thief"
	if GameData.db.find("monster_prototypes",female).is_empty(): female = "merc2" # LiA companion
	for prototype: String in ["Human Hero", female]:
		for smooth: bool in [false, true]:
			for build: Vector3 in [Vector3(.5,.5,.5), Vector3(.1,.2,.8), Vector3(.9,.8,.2)]:
				var record := {"prototype":prototype, "complexion":build, "smooth_joints":smooth}
				var m := EIUnitModel.create(record)
				var peer := EIUnitModel.create(record)
				if m == null or peer == null:
					check(false,"native model exists: "+prototype)
					if m: m.free()
					if peer: peer.free()
					continue
				add_child(m); add_child(peer)
				var peer_materials := materials(peer)
				var own_materials := materials(m)
				m.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				m.position = Vector3(12,3,-9)
				m.set_first_person_view(true)
				var original_mesh := m._view_body_original
				var label := "%s smooth=%s build=%s" % [prototype,smooth,build]
				var max_before := 0.0
				var max_after := 0.0
				var max_depth_change := 0.0
				var bones_intact := true
				var geometry_intact := true
				var visuals_intact := true
				for state: int in [EIUnitModel.ST_NEUTRAL, EIUnitModel.ST_WARRY, EIUnitModel.ST_LIE]:
					m.pose_state = state
					for act: String in (["idle","walk","run","attack","cast"] if state == EIUnitModel.ST_NEUTRAL else ["idle","walk"]):
						m.act(act,1,0)
						var clip := m.player.get_animation(m.player.current_animation)
						for phase: float in [0.0,.25,.5,.75]:
							m.player.seek(clip.length*phase,true); m.flush_pending_pose()
							for heading: float in [0.0,PI/2,PI,-PI/2]:
								m.rotation.y = heading + GameUnit.MODEL_YAW_OFFSET
								var right := Vector3(sin(heading),0,cos(heading))
								var forward := Vector3(cos(heading),0,-sin(heading))
								var eye := m.to_global(m.view_eye_offset(state)) + forward*.28
								var collar := m._view_chest.to_global(m._view_collar)
								var before := parts(m)
								var visual_before := {}
								for mesh in m._view_meshes: visual_before[mesh] = mesh.global_transform
								var bounds := EIFigureGeometry.of(m)
								m.align_first_person_body(eye,right)
								max_before = maxf(max_before,absf((collar-eye).dot(right)))
								max_after = maxf(max_after,absf((collar+m._view_shift-eye).dot(right)))
								max_depth_change = maxf(max_depth_change,absf(m._view_shift.y)+absf(m._view_shift.dot(forward)))
								bones_intact = bones_intact and before == parts(m)
								geometry_intact = geometry_intact and bounds == EIFigureGeometry.of(m)
								for mesh in m._view_meshes:
									visuals_intact = visuals_intact and mesh.global_transform == visual_before[mesh]
				check(max_before > .02 and max_after < .00001, label+" corrects lateral displacement across headings, animations and postures")
				check(max_depth_change < .00001, label+" preserves vertical and forward body motion")
				check(bones_intact and geometry_intact, label+" leaves bones and gameplay bounds untouched")
				check(not m._view_meshes.is_empty() and visuals_intact and own_materials == materials(m),label+" retains mesh-node transforms and materials")
				var peer_unchanged := peer._view_shift == Vector3.ZERO and not peer._head_hidden \
					and peer_materials == materials(peer)
				check(peer_unchanged,label+" does not shift a separate peer or preview model")
				# A pose applied after the camera must be centred at draw time.
				m._view_chest.position.x += .12
				RenderingServer.frame_pre_draw.emit()
				var after := m._view_chest.to_global(m._view_collar)+m._view_shift-m._view_eye
				check(absf(after.dot(m._view_right)) < .00001,label+" late pose changes are aligned before drawing")
				m.set_first_person_view(false)
				var restored := m._view_torso.mesh == original_mesh and m._view_shift == Vector3.ZERO
				check(restored and not RenderingServer.frame_pre_draw.is_connected(m._align_first_person_body),label+" restores original presentation on leaving first person")
				measurements.append({"case":label,"max_uncorrected_lateral":max_before,"max_corrected_lateral":max_after})
				m.free(); peer.free()
	print("FIRST_PERSON_ALIGNMENT ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
