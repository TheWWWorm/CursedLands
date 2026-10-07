extends Node
## Preparation must only resolve bindings. Compare all observable playback
## state/events and transforms with a player resolving them on first use.
class Actor extends Node3D:
	var player: AnimationPlayer
	var part: Node3D
	var events: Array = []
	var applied := 0
	func event(tag: String) -> void: events.append(tag)
	func mixed() -> void: applied += 1

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("FAIL ",label)

func actor() -> Actor:
	var a := Actor.new()
	a.part = Node3D.new(); a.part.name = "Part"; a.part.position = Vector3(7,8,9); a.add_child(a.part)
	a.player = AnimationPlayer.new(); a.add_child(a.player)
	a.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	a.player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	a.player.call("set_preserve_track_caches_on_finish",true)
	var library := AnimationLibrary.new()
	for name in ["a","b"]:
		var clip := Animation.new(); clip.length = 0.4
		var t := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(t,"Part")
		clip.position_track_insert_key(t,0.0,Vector3.ZERO)
		clip.position_track_insert_key(t,0.4,Vector3(2,3,4) if name == "a" else Vector3(5,6,7))
		t = clip.add_track(Animation.TYPE_METHOD); clip.track_set_path(t,".")
		clip.track_insert_key(t,0.0,{"method":"event","args":[name+"-start"]})
		clip.track_insert_key(t,0.2,{"method":"event","args":[name+"-middle"]})
		library.add_animation(name,clip)
	a.player.add_animation_library("",library)
	a.player.mixer_applied.connect(a.mixed)
	a.player.animation_finished.connect(func(clip): a.event("finish-"+String(clip)))
	add_child(a)
	return a

func same(a: Actor, b: Actor, label: String) -> void:
	check(a.part.transform == b.part.transform,label+" pose")
	check(a.events == b.events and a.applied == b.applied,label+" events")
	check(a.player.assigned_animation == b.player.assigned_animation and a.player.is_playing() == b.player.is_playing(),label+" playback")
	if a.player.is_playing():
		check(a.player.current_animation_position == b.player.current_animation_position,label+" clock")

func _ready() -> void:
	if not ClassDB.class_has_method("AnimationPlayer","prepare_track_caches"):
		printerr("Preparation API required"); get_tree().quit(1); return
	var a := actor(); var b := actor()
	check(b.player.call("prepare_track_caches"),"prepare attached rig")
	same(a,b,"unstarted preparation")
	for trial in 40:
		for u in [a,b]: u.player.play("a" if trial%2 else "b",0.1 if trial%3 else 0.0)
		check(b.player.call("prepare_track_caches"),"prepare newly assigned playback")
		same(a,b,"before first advance")
		for dt in [0.0,0.17,0.1,0.3]:
			a.player.advance(dt); b.player.advance(dt)
			same(a,b,"advanced")
			b.player.call("prepare_track_caches")
			same(a,b,"mid-play preparation")
		if trial%5 == 0:
			for u in [a,b]:
				u.player.get_animation("a").track_set_key_value(0,1,Vector3(trial,4,5))
			b.player.call("prepare_track_caches")
			same(a,b,"modified library preparation")
	for u in [a,b]:
		u.player.stop()
		u.part.free(); u.part = Node3D.new(); u.part.name = "Part"; u.add_child(u.part)
		u.player.clear_caches()
		remove_child(u); add_child(u)
	b.player.call("prepare_track_caches")
	same(a,b,"replacement target and tree reentry")
	for u in [a,b]: u.player.play_backwards("a",0.0)
	a.player.advance(0.1); b.player.advance(0.1)
	same(a,b,"reverse")
	a.free(); b.free()
	print("CACHE_PREPARATION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
