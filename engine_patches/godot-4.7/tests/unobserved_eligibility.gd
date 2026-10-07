extends Node
## Compare clocks, materialized poses and side effects as eligible animations
## change in place, including edits while the player's signals are blocked.
class Part extends Node3D:
	var animation_key := Quaternion.IDENTITY
	var value := 0.0
class Actor extends Node3D:
	var player: AnimationPlayer
	var part: Part
	var events: Array = []
	func event(tag: String) -> void: events.append(tag)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func clip() -> Animation:
	var a := Animation.new()
	a.length = 1.0; a.loop_mode = Animation.LOOP_LINEAR
	var i := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(i,"Part:animation_key")
	a.track_insert_key(i,0.0,Quaternion.IDENTITY)
	a.track_insert_key(i,1.0,Quaternion(Vector3.UP,1.0))
	return a
func actor() -> Actor:
	var u := Actor.new()
	u.part = Part.new(); u.part.name = "Part"; u.add_child(u.part)
	u.player = AnimationPlayer.new(); u.add_child(u.player)
	u.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	u.player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	u.player.call("set_preserve_track_caches_on_finish",true)
	var library := AnimationLibrary.new()
	library.add_animation("a",clip()); u.player.add_animation_library("",library)
	add_child(u)
	u.player.play("a",0.0); u.player.advance(0.0)
	return u
func step(a: Actor, b: Actor, dt: float, label: String, wanted := -1) -> void:
	a.player.advance(dt)
	var deferred: bool = b.player.call("advance_unobserved_pose",dt)
	if wanted >= 0: check(deferred == bool(wanted),label+" eligible")
	if deferred: b.player.advance(0.0)
	check(a.part.animation_key.is_equal_approx(b.part.animation_key),label+" key")
	check(a.part.transform.is_equal_approx(b.part.transform) and is_equal_approx(a.part.value,b.part.value),label+" pose")
	check(a.player.is_playing() == b.player.is_playing() and a.player.assigned_animation == b.player.assigned_animation,label+" playback")
	check(is_equal_approx(a.player.current_animation_position,b.player.current_animation_position),label+" clock")
	check(a.events == b.events,label+" events")
func _ready() -> void:
	var a := actor(); var b := actor()
	for i in 60: step(a,b,0.07,"loop %d"%i,1)
	# The cached eligible clip gains an event track, without changing its name.
	for u: Actor in [a,b]:
		u.player.set_block_signals(true)
		var animation := u.player.get_animation("a")
		var track := animation.add_track(Animation.TYPE_METHOD)
		animation.track_set_path(track,".")
		animation.track_insert_key(track,0.35,{"method":"event","args":["changed"]})
		u.player.call("prepare_track_caches")
	for i in 30: step(a,b,0.09,"added method %d"%i,0)
	check(not a.events.is_empty(),"method actually executed")
	for u: Actor in [a,b]:
		u.player.set_block_signals(false)
		u.player.get_animation("a").remove_track(1)
		u.player.call("prepare_track_caches")
	step(a,b,0.12,"removed method",1)
	# A continuous value track outside the narrow pose contract is eventful.
	for u: Actor in [a,b]:
		var animation := u.player.get_animation("a")
		animation.track_set_path(0,"Part:value")
		animation.track_set_key_value(0,0,0.0)
		animation.track_set_key_value(0,1,20.0)
		u.player.call("prepare_track_caches")
	for i in 5: step(a,b,0.12,"changed property",0)
	for u: Actor in [a,b]:
		var library := u.player.get_animation_library("")
		library.remove_animation("a"); library.add_animation("a",clip())
		u.player.play("a",0.0); u.player.advance(0.0)
	step(a,b,0.12,"replacement resource",1)
	for u: Actor in [a,b]:
		u.player.get_animation("a").loop_mode = Animation.LOOP_NONE
		u.player.call("prepare_track_caches")
	for i in 10: step(a,b,0.12,"nonlooping",0)
	for u: Actor in [a,b]:
		u.player.get_animation("a").loop_mode = Animation.LOOP_LINEAR
		u.player.play("a",0.0); u.player.advance(0.0)
		u.player.speed_scale = -1.5
	step(a,b,0.12,"reverse rate",1)
	for u: Actor in [a,b]:
		u.player.clear_caches()
		remove_child(u); add_child(u)
		u.player.call("prepare_track_caches")
	step(a,b,0.12,"tree reentry",1)
	a.free(); b.free()
	print("UNOBSERVED_ELIGIBILITY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
