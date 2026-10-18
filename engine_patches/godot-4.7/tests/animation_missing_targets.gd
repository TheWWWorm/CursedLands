extends Node
## Variant-rig paths repeat across clips. Failed lookup caching must expire at
## every rebuild, including library edits and replacement/renamed targets.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func _ready() -> void:
	ProjectSettings.set_setting("animation/warnings/check_invalid_track_paths",false)
	var rig := Node3D.new(); add_child(rig)
	var part := Node3D.new(); part.name="Present"; rig.add_child(part)
	var player := AnimationPlayer.new(); rig.add_child(player)
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	for clip in 128:
		var animation := Animation.new(); animation.length=1.0
		for index in 65:
			var track := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(track,"Present" if index==0 else "Missing%d"%index)
			animation.position_track_insert_key(track,0.0,Vector3.ZERO)
			animation.position_track_insert_key(track,1.0,Vector3(index+1,clip+1,3))
		library.add_animation("clip%d"%clip,animation)
	player.add_animation_library("",library)
	var times := []
	for iteration in 30:
		player.clear_caches()
		var start := Time.get_ticks_usec()
		check(player.call("prepare_track_caches"),"prepare partial rig")
		times.append(Time.get_ticks_usec()-start)
	player.play("clip17"); player.advance(.5)
	check(part.position.is_equal_approx(Vector3(.5,9,1.5)),"present track unaffected")
	var added := Node3D.new(); added.name="Missing23"; rig.add_child(added)
	player.clear_caches(); player.seek(.5,true)
	check(added.position.is_equal_approx(Vector3(12,9,1.5)),"new target resolves after clear")
	added.name="Missing24"; player.clear_caches(); player.seek(.5,true)
	check(added.position.is_equal_approx(Vector3(12.5,9,1.5)),"renamed target resolves")
	library.get_animation("clip17").track_set_path(25,"Missing24")
	library.get_animation("clip17").track_set_enabled(24,false)
	player.seek(.5,true)
	check(added.position.is_equal_approx(Vector3(13,9,1.5)),"library edit invalidates")
	rig.remove_child(added); added.free()
	added=Node3D.new(); added.name="Missing24"; rig.add_child(added)
	player.clear_caches(); remove_child(rig); add_child(rig)
	player.seek(.5,true)
	check(added.position.is_equal_approx(Vector3(13,9,1.5)),"replacement and tree reentry")
	player.clear_caches(); ProjectSettings.set_setting("animation/warnings/check_invalid_track_paths",true)
	player.call("prepare_track_caches"); player.seek(.5,true)
	check(added.position.is_equal_approx(Vector3(13,9,1.5)),"diagnostic path matches")
	times.sort()
	print("MISSING_ANIMATION_TARGETS ",JSON.stringify({"checks":checks,"failures":failures,"median_prepare_us":times[times.size()/2]}))
	rig.free(); get_tree().quit(1 if failures else 0)
