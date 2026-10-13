extends Node
## Unmodified Ingos multiplayer village scripts, controlled 55-ms ticks.
## Replica checks use production snapshots; this is not a transport test.
var checks := 0
var failures := 0
var rows := {}
var replicas: Array[GameUnit] = []
const AMBIENT := {
	"AGuard1":"uspecial10", "AGuard2":"uspecial10", "Batrak1":"uspecial26",
	"Eda1":"uspecial08", "Eda2":"uspecial08", "Eater":"uspecial13",
	"SitterPolice":"uspecial13", "SitterMan":"uspecial15", "PoorMan":"uspecial20",
	"Tiger":"crest",
}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)


func step(world: GameWorld) -> void:
	world._tick(GameUnit.TICK)
	for u: GameUnit in world.unit_rows():
		u._draw_step(0.0)
		if u.model and u.model.player:
			u.model.player.advance(GameUnit.TICK)
			u.model._process(GameUnit.TICK)


func one_shot(world: GameWorld, u: GameUnit, clip: String, story := true) -> void:
	u._anim_lock = 0.0
	u.command({"type":"anim", "name":clip, "story":story})
	step(world)
	var frames := ceili(u._anim_lock / GameUnit.TICK) + 8
	for frame in frames: step(world)


func _ready() -> void:
	seed(104031)
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0, "net_websocket":0,
		"net_lan":0, "net_directory":0, "auto_graphics":0, "unit_fog":1}, true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.use_lmp_database(true)
	var character := MpCharacter.create(String(MpCharacter.faces()[0][0]))
	character.heroes[0].name = "Ambient loop probe"
	MpCharacter.finish(character, "", "", "")
	MpCharacter.save_file("1.mp", character)
	MpCharacter.select("1.mp")
	var session := Session.new()
	add_child(session)
	var game := Game.new()
	game.session = session
	session.game = game
	add_child(game)
	check(session.host(31062, 2) == OK, "ambient authority opens")
	check(session.new_lmp_game("bz2mpg"), "original Ingos multiplayer base loads")
	session.set_physics_process(false)
	game.set_process(false)
	game.get_node("UnitFog").set_process(false)
	game.rig.set_process(false)
	var world := session.world
	world.set_process(false)
	world.set_physics_process(false)
	check(world.zone.mpr == "bz8k" and world.zone.mob == "bz8k-lmp" and world.zone.type == "brief",
		"original safe-area script and actor data")
	# WorldScript binds these authored actor globals on the first tick.
	for frame in 3: step(world)
	for actor: String in AMBIENT:
		var u := world.vm._unit(world.vm.globals.get(actor))
		check(u != null and u.controller < 0 and u.model.has_anim(AMBIENT[actor]), "authored actor " + actor)
		if u == null: continue
		# This cycle is replaced by an intentional Rest AI order after a few
		# seconds. Isolate the authored cycle from that replacement control.
		if actor == "Tiger": u.ai_next = INF
		var replica := GameUnit.new()
		check(replica.setup(world, u.info), "replica uses authored figure " + actor)
		add_child(replica)
		replicas.append(replica)
		replica.set_process(false)
		replica.model.set_process(false)
		rows[actor] = {"uid":u.uid, "unit":u, "replica":replica, "position":u.pos,
			"clip":AMBIENT[actor], "started":false, "starts":0, "idle_frames":0,
			"ready_frames":0, "bad_restart":0, "replica_gaps":0, "replica_restart":0,
			"serial":-1, "events":[]}
	for frame in 600:
		step(world)
		for actor: String in rows:
			var row: Dictionary = rows[actor]
			var u: GameUnit = row.unit
			var replica: GameUnit = row.replica
			var fresh: bool = u._action_serial != row.serial
			if fresh: replica.apply_snapshot(u.snapshot(), frame == 0)
			if fresh:
				if u.action == "anim:" + String(row.clip):
					row.starts += 1
					row.started = true
					if not u.model.player.is_playing() or u.model.player.current_animation_position > GameUnit.TICK + 0.00001:
						row.bad_restart += 1
					if not replica.model.player.is_playing() or replica.model.player.current_animation_position > 0.00001:
						row.replica_restart += 1
				row.events.append({"frame":frame, "action":u.action, "clip":u.model._current,
					"serial":u._action_serial, "lock":u._anim_lock})
			if row.started and u.model._current != row.clip: row.idle_frames += 1
			if row.started and replica.model._current != row.clip: row.replica_gaps += 1
			if row.started and u.is_idle(): row.ready_frames += 1
			replica.model.player.advance(GameUnit.TICK)
			replica.model._process(GameUnit.TICK)
			row.serial = u._action_serial
	for actor: String in rows:
		var row: Dictionary = rows[actor]
		var u: GameUnit = row.unit
		check(row.starts >= (1 if actor == "Tiger" else 3), "authored repeat/cycle starts " + actor)
		check(row.idle_frames == 0, "no standing frame inserted " + actor)
		check(row.bad_restart == 0, "each explicit repeat restarts at the first key " + actor)
		check(row.ready_frames > 0, "pose does not keep the command busy " + actor)
		check(row.replica_gaps == 0 and row.replica_restart == 0, "snapshot keeps pose and repeat serial " + actor)
		check(u.pos == row.position, "authored placement stays fixed " + actor)
	var tiger: GameUnit = rows.Tiger.unit
	check(tiger.model.player.is_playing() and tiger.model._current == "crest", "authored cycle survives calm AI idle refresh")
	var worker: GameUnit = rows.Batrak1.unit
	check(worker.model.player.get_animation("ei/uspecial26").loop_mode == Animation.LOOP_NONE,
		"repeated one-shot is not converted to a shared looping animation")
	# Controlled interruption checks follow the unmodified 33-second run.
	world.vm.instances.clear()
	for actor: String in rows:
		var u: GameUnit = rows[actor].unit
		u.ai_next = INF
		u.command({"type":"wait", "t":0.2})
	for frame in 240: step(world)
	for actor: String in rows:
		var u: GameUnit = rows[actor].unit
		check(u.action == "idle" and u.is_idle() and u._story_clip.is_empty(), "ordinary order releases hold " + actor)
	# A single PlayAnimation must still finish if no script repeats it.
	one_shot(world, worker, "uspecial26")
	check(worker.action == "idle" and worker._story_clip.is_empty(), "unrepeated village one-shot returns to idle")
	one_shot(world, worker, "uspecial26", false)
	check(worker.action == "idle", "non-story one-shot retains normal completion")
	worker.controller = 0
	one_shot(world, worker, "uspecial26")
	check(worker.action == "idle" and worker._story_clip.is_empty(), "party animation is not held")
	worker.controller = -1
	var zone_type: String = world.zone.type
	world.zone.type = "game"
	one_shot(world, worker, "uspecial26")
	check(worker.action == "idle" and worker._story_clip.is_empty(), "gameplay-map one-shot is not held")
	world.zone.type = zone_type
	# Dialogue and death own their explicit presentation immediately.
	worker.command({"type":"anim", "name":"uspecial26", "story":true})
	step(world)
	check(worker.model.begin_dialogue(false), "dialogue can replace the ambient pose")
	var talk_clip := worker.model._current
	worker._set_action("idle")
	check(worker.model._current == talk_clip, "ambient idle suppression does not override dialogue")
	worker.model.end_dialogue()
	worker._set_action("death")
	check(worker.model._current != "uspecial26", "death replaces ambient presentation")
	var report_rows := {}
	for actor: String in rows:
		var row: Dictionary = rows[actor].duplicate()
		row.erase("unit")
		row.erase("replica")
		row.position = str(row.position)
		report_rows[actor] = row
	var report := {"checks":checks, "failures":failures, "actors":report_rows, "frames":600,
		"scope":"Authored script/animation timelines and production snapshot replay, headless; no rendered or transport acceptance."}
	FileAccess.open("user://npc-ambient-loops.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	for replica: GameUnit in replicas: replica.free()
	var peer := session.multiplayer.multiplayer_peer
	session.online = false
	session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	game.free()
	session.free()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	print("NPC_AMBIENT_LOOPS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
