extends Node
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func _ready()->void:
	var warmer:=ArenaAnimationWarmup.new();add_child(warmer);warmer.prepare()
	var deadline:=Time.get_ticks_msec()+60000
	while warmer.task>=0 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(warmer.task<0,"background catalog completes")
	var ready:=EIAnim._libraries.duplicate()
	for family in range(24,ArenaRules.FAMILIES.size()):
		for rank in 3:
			EIAnim._libraries=ready.duplicate()
			var id:=ArenaRules.prototype(family,rank)
			var prepared:=EIUnitModel.create({"prototype":id},true)
			var actual:=prepared.player.get_animation_library("ei")
			EIAnim._libraries={}
			var ordinary:=EIUnitModel.create({"prototype":id},true)
			var expected:=ordinary.player.get_animation_library("ei")
			check(actual.get_animation_list()==expected.get_animation_list(),"all clips preserved: "+id)
			for clip in expected.get_animation_list():
				var a:=actual.get_animation(clip);var b:=expected.get_animation(clip)
				check(a.length==b.length and a.loop_mode==b.loop_mode and a.get_track_count()==b.get_track_count(),"clip structure")
				for track in b.get_track_count():
					check(a.track_get_path(track)==b.track_get_path(track) and a.track_get_type(track)==b.track_get_type(track) and a.track_get_key_count(track)==b.track_get_key_count(track),"track structure")
					for key in b.track_get_key_count(track):
						check(a.track_get_key_time(track,key)==b.track_get_key_time(track,key) and a.track_get_key_value(track,key)==b.track_get_key_value(track,key),"native animation key")
			prepared.free();ordinary.free()
	EIAnim._libraries=ready
	warmer.queue_free();await get_tree().process_frame
	print("ARENA_ANIMATION_WARMUP ",checks," checks; failures=",JSON.stringify(failures.slice(0,10)))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
