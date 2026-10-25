extends Node
## Exact requests, RNG, state and observation boundaries against the independent
## previous collector. The test mixer captures requests without emitting audio.
const Previous = preload("/home/llm2x/Documents/EI/local/scratchpad/cpu-traversal-20261025/repo/tools/tests/unit_sound_state_reference.gd")
var checks := 0
var failures := 0

class Mixer extends SoundMixer:
	var events := []
	var active := {}
	var serial := 0
	func _start(record: Dictionary) -> int:
		serial += 1
		events.append(["play",serial,record.duplicate(true)])
		active[serial] = record.duplicate(true)
		return serial
	func stop(handle: int) -> void:
		events.append(["stop",handle])
		active.erase(handle)
	func playing(handle: int) -> bool:
		events.append(["playing",handle])
		return active.has(handle)

class Actor extends GameUnit:
	var wakes := 0
	func wake_presentation() -> void:
		wakes += 1
		_presentation_sleeping = false
		# Sample after waking, including timeline movement during wake.
		if model and model.player: model.player.advance(0.001)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL ",label)

func fixture(count: int, current: bool) -> Dictionary:
	var world := GameWorld.new()
	var mixer := Mixer.new()
	var collector = UnitSounds.new(mixer,world) if current else Previous.new(mixer,world)
	var actors: Array[GameUnit] = []
	var models := []
	var players := []
	var clips := {}
	var library := AnimationLibrary.new()
	for entry in [["idle",6],["walk",4],["run",5],["attack",2],["death",7],["hit",8],["special",1],["missing",0]]:
		var animation := Animation.new()
		animation.length = 3.0
		library.add_animation(entry[0],animation)
		if entry[1] != 0:
			clips[entry[0]] = {"act":entry[1],"code":0x13<<22,"steps":PackedInt32Array([3,7,1,1]),
				"frame":3,"sounds":PackedInt32Array([1,2,3])}
	collector._adb["probe"] = clips
	collector._steps["probe\\steps"] = 3
	for i in count:
		var actor := Actor.new()
		actor.uid = i+1
		actor.pos = Vector2(i*3.0,0)
		actor.race = {"sfx_path":"probe","idle_sound_p":100,"attack_sound_p":100,
			"type_id":0x32,"steps_path":PackedStringArray(["probe\\steps"])}
		var model := EIUnitModel.new()
		model.template = "probe"
		var player := AnimationPlayer.new()
		model.add_child(player)
		model.player = player
		player.add_animation_library("ei",library)
		actor.add_child(model)
		actor.model = model
		add_child(actor)
		player.play("ei/idle")
		player.advance(0)
		actors.append(actor); models.append(model); players.append(player)
	world._unit_rows = actors.duplicate()
	return {"world":world,"mixer":mixer,"collector":collector,"actors":actors,"models":models,"players":players}

func state(f: Dictionary) -> Dictionary:
	var result := {}
	for actor in f.actors:
		if not is_instance_valid(actor): continue
		var st = f.collector._units.get(actor.get_instance_id())
		if st == null: continue
		result[actor.uid] = [st.clip,st.anim,st.name,st.frame,st.idle,st.attack,st.seen,
			st.get("far",false) if st is Dictionary else st.far]
	return result

func sample(pair: Array, label: String, random_seed := 87211) -> Array:
	var rows := []
	for f in pair:
		f.mixer.events.clear()
		seed(random_seed)
		f.collector.tick()
		var wakes := []
		for actor in f.actors:
			if is_instance_valid(actor): wakes.append(actor.wakes)
		rows.append([state(f),f.mixer.events.duplicate(true),f.mixer.active.duplicate(true),
			randi(),wakes,f.collector._stamp])
	for i in rows[0].size(): check(rows[0][i] == rows[1][i],label+" result "+str(i))
	return rows[1][1]

func pose(pair: Array, clip: String, frame: float) -> void:
	for f in pair:
		var player: AnimationPlayer = f.players[0]
		player.play(clip)
		player.seek(frame / EIAnim.FPS,true)

func played(events: Array, suffix := "") -> int:
	var count := 0
	for event in events:
		if event[0] == "play" and String(event[2].path).contains(suffix): count += 1
	return count

func dispose(pair: Array) -> void:
	for f in pair:
		f.world._unit_rows.clear()
		for actor in f.actors:
			if is_instance_valid(actor): actor.free()
		f.mixer.free(); f.world.free()

func _ready() -> void:
	var pair := [fixture(1,false),fixture(1,true)]
	check(played(sample(pair,"first observation")) == 0,"first observation remains quiet")
	var st = pair[1].collector._units[pair[1].actors[0].get_instance_id()]
	check(st is RefCounted and not st is Dictionary,"hot sound state uses typed fields")
	pose(pair,"ei/walk",1)
	check(played(sample(pair,"before step")) == 0,"walk waits for its authored step")
	pose(pair,"ei/walk",2)
	check(played(sample(pair,"at step"),"steps") == 1,"step uses prev < frame <= current")
	check(played(sample(pair,"unchanged frame")) == 0,"same frame never repeats a step")
	pose(pair,"ei/walk",1)
	check(played(sample(pair,"same clip wraps")) == 0,"same clip wrap creates no phantom step")
	for f in pair: f.actors[0].buffs = {"silence":{}}
	pose(pair,"ei/walk",6)
	check(played(sample(pair,"silenced step")) == 0,"silence suppresses a crossed step")
	for f in pair: f.actors[0].buffs = {}; f.mixer.listener = Vector3(40,0,0)
	pose(pair,"ei/run",3)
	check(played(sample(pair,"exact range edge"),"steps") == 1,"40-metre range edge remains included")
	for f in pair: f.mixer.listener.x = 40.01
	pose(pair,"ei/run",6)
	check(played(sample(pair,"outside range")) == 0,"outside range stays quiet")
	for f in pair: f.mixer.listener.x = 0
	pose(pair,"ei/run",8)
	check(played(sample(pair,"back in range")) == 0,"return resynchronizes without catch-up audio")
	for f in pair: f.actors[0].visible = false
	pose(pair,"ei/idle",5)
	check(played(sample(pair,"invisible")) == 0,"invisible actor stays quiet")
	for f in pair: f.actors[0].visible = true
	check(played(sample(pair,"shown at same time")) == 0,"visibility return does not repeat a passed frame")
	pose(pair,"ei/hit",3)
	check(played(sample(pair,"voice exact lower edge")) == 0,"voice waits until current exceeds frame")
	pose(pair,"ei/hit",3.5)
	check(played(sample(pair,"voice crossing"),"hit") == 1,"voice uses prev <= frame < current")
	for clip in ["idle","attack","death","special"]:
		pose(pair,"ei/"+clip,4)
		var events := sample(pair,"voice "+clip)
		print("DEBUG_VOICE ",clip," ",state(pair[0])," ",events)
		check(played(events) > 0,"authored "+clip+" request survives")
	pose(pair,"ei/missing",5)
	check(played(sample(pair,"no sound record")) == 0,"missing sound record is quiet")
	for f in pair: f.players[0].stop()
	check(played(sample(pair,"empty animation")) == 0,"empty animation resynchronizes quietly")
	pose(pair,"ei/attack",7)
	check(played(sample(pair,"animation returns")) == 0,"return from empty animation is quiet")
	for f in pair:
		f.collector.set_attack(f.actors[0],777)
		f.mixer.active[777] = {"path":"external acknowledgement"}
		check(f.collector.attack_playing(f.actors[0]),"external acknowledgement handle remains live")
	for f in pair: f.mixer.events.clear(); f.collector.silence_dialogue(true)
	check(pair[0].mixer.events == pair[1].mixer.events,"dialogue stops the same idle and attack handles in order")
	for f in pair: check(not f.collector.attack_playing(f.actors[0]),"dialogue stops the acknowledgement")
	pose(pair,"ei/hit",5)
	check(played(sample(pair,"dialogue voice suppression")) == 0,"dialogue suppresses new voice requests")
	for f in pair: f.collector.silence_dialogue(false); f.actors[0].model = null
	sample(pair,"model removed")
	check(pair[1].collector._units.is_empty(),"missing model removes stale cache entry")
	for f in pair: f.actors[0].model = f.models[0]
	check(played(sample(pair,"model restored")) == 0,"newly observed model stays quiet")
	for f in pair: f.world._unit_rows.clear()
	sample(pair,"registry removal")
	check(pair[1].collector._units.is_empty(),"registry removal clears stale sound state")
	dispose(pair)

	# Independent players and mixed state changes exercise ordering, handles,
	# missing models/players, frozen clips, wakeups, dialogue and actor deletion.
	pair = [fixture(32,false),fixture(32,true)]
	var names := ["idle","walk","run","attack","death","hit","special","missing"]
	for frame in 160:
		for f in pair:
			f.world.zone.type = "brief" if frame%7 == 0 else "game"
			f.mixer.listener = Vector3(float((frame*7)%110),float(frame%3),2)
			f.collector.silence_dialogue(frame%11 == 0)
			for handle in f.mixer.active.keys():
				if (handle+frame)%3 == 0: f.mixer.active.erase(handle)
			for i in f.actors.size():
				var actor: Actor = f.actors[i]
				if not is_instance_valid(actor): continue
				actor.model = null if (i+frame)%19 == 0 else f.models[i]
				f.models[i].player = null if (i+frame)%23 == 0 else f.players[i]
				actor.pos = Vector2(float((i*7+frame)%120),0)
				actor.visible = (i+frame)%13 != 0
				actor._presentation_sleeping = (i+frame)%9 == 0
				actor.strike_miss = (i+frame)%5 == 0
				actor.buffs = {"silence":{}} if (i+frame)%8 == 0 else {}
				var player: AnimationPlayer = f.players[i]
				player.play("ei/"+names[(i+frame/5)%names.size()])
				player.seek(float((frame*3+i)%16)/EIAnim.FPS,true)
				if (i+frame)%17 == 0: player.stop()
			if frame == 80: f.actors[31].free() # stale registry entry is valid input
		sample(pair,"mixed frame "+str(frame),92601+frame)
	check(pair[0].mixer.serial > 30,"mixed fixture actually emits sound requests")
	for f in pair:
		var wakes := 0
		for actor in f.actors:
			if is_instance_valid(actor): wakes += actor.wakes
		check(wakes > 10,"mixed fixture exercises sleeping listeners")
	dispose(pair)
	print("UNIT_SOUND_STATE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
