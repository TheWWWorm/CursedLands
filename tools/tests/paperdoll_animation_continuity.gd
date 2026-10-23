extends Node
## Exercise the character-creation/camp preview, rather than GameUnit's
## separate in-world redress path. Original data is required.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0}, true)
	for camp in [true, false]:
		var doll := Paperdoll.new()
		doll.camp_frame = camp
		add_child(doll)
		var info := {"prototype":"Human Hero", "complexion":Vector3(.1,.5,.6),
			"armors":PackedStringArray(), "weapons":PackedStringArray()}
		doll.show_info(info)
		check(doll._model != null, "original preview rig loads")
		if doll._model == null: continue
		var clip := doll._model._current
		doll._model.player.speed_scale = .7
		doll._seek_pose(.17)
		for step in 8:
			if camp: doll._sample_camp_pose(12345.0)
			var before := doll._model.player.current_animation_position
			info.complexion = Vector3(.1 + step * .03, .51 + step * .02, .61 + step * .01)
			doll.show_info(info)
			if camp: doll._sample_camp_pose(12345.0)
			check(doll._model._current == clip, "reshape retains clip (%s/%s)" % [camp, step])
			check(is_equal_approx(doll._model.player.current_animation_position, before), "reshape retains phase (%s/%s)" % [camp, step])
			check(is_equal_approx(doll._model.player.speed_scale, .7), "reshape retains rate (%s/%s)" % [camp, step])
		info.armors = PackedStringArray(["hadagan high2 plate.adamantium"])
		info.weapons = PackedStringArray(["battle axe.adamantium"])
		var before := doll._model.player.current_animation_position
		doll.show_info(info)
		if camp: doll._sample_camp_pose(12345.0)
		check(doll._model.weapon_type == "axe", "preview applies new weapon")
		check(doll._model._current == clip and is_equal_approx(doll._model.player.current_animation_position, before), "redress retains clip and phase")
		# Force an unchanged-clock sample on a newly built rig: it must still
		# pose that rig, even though its old mesh already showed the same time.
		check(doll._pose_time >= 0.0 if camp else true, "new camp rig is sampled")
		doll.free()
	await get_tree().process_frame
	print("PAPERDOLL_ANIMATION_CONTINUITY ", JSON.stringify({"checks":checks, "failures":failures}))
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
