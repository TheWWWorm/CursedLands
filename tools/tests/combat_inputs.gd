extends Node
## Compare shared batch inputs with the previous per-player exhaustive flags.
## Only geometry is synthetic; party sight, hostility, actions and sensing use
## production code, including mode/owner/visibility changes between batches.
var checks := 0
var failures := 0

class World extends GameWorld:
	var closed := false
	func sight_ray(a: GameUnit, b: GameUnit) -> float:
		return 0.0001 if closed and (a.pos.x < 100.0) != (b.pos.x < 100.0) else 1.0

class Host extends Session:
	var flags := {}
	func broadcast(e: Dictionary) -> void:
		if e.get("t") == "combat_flag": flags[int(e.p)] = int(e.v)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("FAIL ",label)

func original(sound: GameSound, player: int) -> int:
	var w := sound._world
	var own: Array[GameUnit] = []
	var attackers := {}
	for u: GameUnit in w.units.values():
		if u.controller == player and not u.dead and not u.hidden: own.append(u)
		if not u.dead and u.order.get("type", "") == "attack":
			var target := GameSound._act_target(u)
			if target:
				if not attackers.has(target): attackers[target] = []
				attackers[target].append(u)
	var flag := 0
	for u: GameUnit in own:
		for ratio in sound._near_ratios(u):
			if ratio <= 2.0: flag = 1
	for u in UnitFog.relevant_for(w.session,player):
		if not is_instance_valid(u) or u.dead: continue
		if GameSound._hostile_act(u): return 2
		var near := sound._near_units(u)
		if not own.is_empty():
			for a: GameUnit in attackers.get(u, []):
				if near.has(a) and w.is_enemy(a,own[0]): return 2
	return flag

func _ready() -> void:
	var w := World.new()
	var host := Host.new(); host.world = w; w.session = host
	host.state = CampaignState.new()
	var sound := GameSound.new(); sound._world = w
	var reference := GameSound.new(); reference._world = w; reference._unit_query = null
	var rng := RandomNumberGenerator.new(); rng.seed = 859030
	var actors: Array[GameUnit] = []
	for i in 32:
		var u := GameUnit.new(); u.uid = i+1; u.world = w
		u.pos = Vector2(70.0+i*2.0,80.0+i%5)
		u.proto = {"senses":PackedFloat32Array([20.0,0.0,0.0,0.0,0.0]),"detect":PackedFloat32Array([1,1,1,1,1])}
		u.stats.sight = 20.0
		u.faction = 1 if i>=4 else 0
		u.controller = i if i<4 else -1
		w.set_unit(u.uid,u); actors.append(u)
		if i<4: host.state.heroes[i] = {}
	w.set_relation(0,1,2); w.set_relation(1,0,2)
	for trial in 96:
		host.online = trial%3 != 0
		host.lmp = {"test":true} if trial%3 == 2 else {}
		w.zone.type = "brief" if trial%11 == 0 else "game"
		w.closed = trial%2 == 0
		w.time = 1.0+float(trial)
		for i in actors.size():
			var u := actors[i]
			u.order = {}
			u.dead = rng.randf()<0.15; u.hidden = rng.randf()<0.15
			u.set_meta("perceived",w.time)
			u.set_meta("noticed",{})
			if trial%7 == 0: u.set_meta("noticed",{actors[(i+3)%32].get_instance_id():actors[(i+3)%32]})
			if rng.randf()<0.2: u.order = {"type":"attack","target":actors[rng.randi_range(0,31)]}
			elif rng.randf()<0.15: u.order = {"type":"cast","spell":"fireball","target":actors[0]}
			u.controller = i if i<4 and trial%13 != i else -1
		w.set_relation(0,1,0 if trial%5 == 0 else 2)
		w.set_relation(1,0,0 if trial%7 == 0 else 2)
		var expected := {}
		seed(trial+401)
		reference._combat_near.clear()
		for player in 4: expected[player] = original(reference,player)
		seed(trial+401)
		sound._combat_near.clear(); sound._sent_flags.clear(); host.flags.clear()
		sound._send_combat_flags()
		check(host.flags == expected,"all-player flags trial %d: %s / %s" % [trial,host.flags,expected])
		for player in 4:
			check(sound.player_combat_flag(player) == original(reference,player),"standalone flag stays current")
	w.units = {}
	for u in actors: u.free()
	sound.free(); reference.free(); w.free(); host.world = null; host.free()
	print("COMBAT_INPUTS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
