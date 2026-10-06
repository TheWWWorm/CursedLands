extends Node
## Paired mutable-library and playback tests for the opt-in cache lifetime.
class Actor extends Node3D:
	var part: Node3D
	var player: AnimationPlayer
	var events: Array = []
	var clears := 0
	func record(clip: StringName) -> void: events.append(clip)
	func cleared() -> void: clears += 1

var checks := 0
var fails := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails < 15: push_error(label)

func clip(start: Vector3, end: Vector3) -> Animation:
	var animation := Animation.new()
	animation.length = 0.4
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Part"))
	animation.position_track_insert_key(track, 0.0, start)
	animation.position_track_insert_key(track, 0.4, end)
	return animation

func actor(retain: bool) -> Actor:
	var a := Actor.new()
	a.part = Node3D.new(); a.part.name = "Part"; a.add_child(a.part)
	a.player = AnimationPlayer.new(); a.add_child(a.player)
	a.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	a.player.call("set_preserve_track_caches_on_finish",retain)
	var library := AnimationLibrary.new()
	library.add_animation("a",clip(Vector3.ZERO, Vector3(2,3,4)))
	library.add_animation("b",clip(Vector3(5,6,7), Vector3(8,9,10)))
	a.player.add_animation_library("", library)
	add_child(a)
	a.player.animation_finished.connect(a.record)
	a.player.caches_cleared.connect(a.cleared)
	return a

func compare(a: Actor, b: Actor, label: String) -> void:
	check(a.part.transform == b.part.transform, label+" transform")
	check(a.player.current_animation_position == b.player.current_animation_position,label+" clock")
	check(a.player.is_playing() == b.player.is_playing(),label+" playing")
	check(a.player.assigned_animation == b.player.assigned_animation,label+" assigned")
	check(a.events == b.events,label+" finish signals")

func advance_pair(a: Actor,b: Actor,dt: float,label: String) -> void:
	a.player.advance(dt); b.player.advance(dt)
	compare(a,b,label)

func _ready() -> void:
	if not ClassDB.class_has_method("AnimationPlayer","set_preserve_track_caches_on_finish"):
		push_error("Retained cache runtime required");get_tree().quit(1);return
	var a := actor(false)
	var b := actor(true)
	for trial in 120:
		for unit in [a,b]:
			unit.player.play("a" if trial % 2 == 0 else "b",0.12 if trial % 3 == 0 else 0.0)
		advance_pair(a,b,0.17,"start %d"%trial)
		advance_pair(a,b,0.34,"finish %d"%trial)
	check(a.clears >= b.clears+100,"repeated finishes retain resolved tracks")
	# Mutation invalidates the shared animation library even between clips.
	for unit in [a,b]:
		unit.player.get_animation("a").track_set_key_value(0,1,Vector3(13,14,15))
		unit.player.play("a",0.0)
	advance_pair(a,b,0.4,"edited key")
	check(b.part.position == Vector3(13,14,15),"new key applied")
	for unit in [a,b]:
		unit.player.get_animation_library("").remove_animation("a")
		unit.player.get_animation_library("").add_animation("a",clip(Vector3(20,21,22),Vector3(23,24,25)))
		unit.player.play("a",0.0)
	advance_pair(a,b,0.4,"replaced animation")
	check(b.part.position == Vector3(23,24,25),"replacement animation applied")
	for unit in [a,b]:
		unit.player.stop()
		unit.part.free()
		unit.part = Node3D.new();unit.part.name = "Part";unit.add_child(unit.part)
		# Mutable rigs must invalidate paths explicitly, as with stock Godot.
		unit.player.clear_caches()
		unit.player.play("b",0.0)
	advance_pair(a,b,0.2,"replaced target")
	check(b.part.position == Vector3(6.5,7.5,8.5),"replacement target receives pose")
	for unit in [a,b]:
		remove_child(unit);add_child(unit)
		unit.player.play("a",0.0)
	advance_pair(a,b,0.4,"reentered tree")
	for unit in [a,b]:
		unit.player.play("a",0.0)
		unit.player.queue("b")
	advance_pair(a,b,0.5,"queued transition")
	advance_pair(a,b,0.2,"queued successor")
	advance_pair(a,b,0.4,"queued completion")
	for unit in [a,b]:
		unit.player.stop()
		unit.player.play_backwards("a",0.0)
	advance_pair(a,b,0.17,"reverse start")
	advance_pair(a,b,0.4,"reverse finish")
	var clears_before := b.clears
	b.player.call("set_preserve_track_caches_on_finish",false)
	check(b.clears == clears_before+1,"disabling retention invalidates immediately")
	for unit in [a,b]: unit.player.play("b",0.0)
	advance_pair(a,b,0.5,"disabled retention")
	check(b.clears == clears_before+2,"disabled player clears on finish")
	a.free();b.free()
	print("CACHE_LIFECYCLE PASS=",checks-fails," FAIL=",fails)
	get_tree().quit(0 if fails==0 else 1)
