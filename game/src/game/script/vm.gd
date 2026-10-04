class_name ScriptVM
extends RefCounted
## Interpreter for the original level scripts (the encrypted SS_TEXT in each .mob).
##
## Execution model (matches how the compiled "VCheck/VTriger" scripts behave):
## * WorldScript runs once when the zone starts.
## * Calling `Name( args )` for a user script spawns a persistent instance.
##   An idle instance re-evaluates its `if (conds) then (body)` blocks every
##   poll; the first block whose conditions all hold runs its body (which may
##   Sleep). `KillScript()` ends the instance once that body has finished.
## * `#OnBriefingComplete` is spawned for every finished conversation.
## Campaign variables (GSGetVar/GSSetVar) are shared by the whole co-op party.

## the original runs every script thread once per server logic tick
## (55 ms):
## an idle thread tests its conditions each tick, and Sleep(n) (dispatcher
## case 7) waits until the thread's own run counter (+8, one per run) is n
## past the count at which the Sleep began — n logic ticks.
const POLL := 0.055        # seconds between condition checks (one logic tick)
const SLEEP_UNIT := 0.055  # Sleep() argument unit (one logic tick)
const MAX_STEPS := 2000    # statements per thread per tick (runaway guard)
const P = preload("res://src/game/script/script_parser.gd")

var world: GameWorld
var session: Session
var ast: ScriptParser
var briefings: Briefings
var globals := {}
var instances: Array = []
var areas := {}            # area id -> Array of Rect2 / Vector3(x, y, r)
var time := 0.0
var time_fixed := false
var _uid_counter := 0
var _pending_zone := []
## Side-quest objectives (QStart/QObj*/QFinish): quest -> {objs: [[kind, arg, arg2, done]], items: n}
var qobjs := {}
var _q_recording := ""
var _q_check := 0.0
## Lever locks changed by SetScience: nid -> [flags, id, value] (saved with the zone).
var sciences := {}
## Builtins called by the script that the VM does not know (tools/quest_test.gd).
var unknown_calls := {}
var _fx_auto := -1   # the next CreateFXSource(-1) id
## WorldScript bodies by source ("" the zone's .mob, "q:<quest mob>" a side
## quest's, "m:<file>" an AddMob file's): a saved WorldScript thread names its
## source (save_state), so a load resumes it where it was.
var world_bodies := {}


class Instance:
	var sname := ""
	var locals := {}
	var blocks: Array = []
	var killed := false
	var poll := 0.0
	var frames: Array = []   # running body: [{body, i, for_var, items, k}]
	var wait_until := 0.0
	var wait_cond: Array = []
	var wait_unit: Object = null
	var block_index := -1
	var src := ""   # WorldScript: its body's source (ScriptVM.world_bodies)


static func create(w: GameWorld, s: Session) -> ScriptVM:
	var vm := ScriptVM.new()
	vm.world = w
	vm.session = s
	vm.briefings = Briefings.new(vm)
	var text := w.mob.script_text if w.mob else ""
	vm.ast = ScriptParser.parse(text)
	for e in vm.ast.errors:
		push_warning("script %s: %s" % [w.zone.get("id", "?"), e])
	for g in vm.ast.globals:
		vm.globals[g] = [] if vm.ast.globals[g] == "group" else null
	var restored: Dictionary = w.get_meta("restored_vm", {}) if w.has_meta("restored_vm") else {}
	var quest_world: Array = vm._merge_quest_script(w)
	# Scripts of .mob files AddMob loaded earlier: their running instances
	# are part of the restored state.
	vm.world_bodies[""] = vm.ast.world
	var quest_src := "q:" + String(w.get_meta("quest_mob", "")) if w.has_meta("quest_mob") else "q:"
	if not quest_world.is_empty():
		vm.world_bodies[quest_src] = quest_world
	if not restored.is_empty():
		for file: String in w.get_meta("added_mobs", []):
			var extra := EIMob.load_bytes(GameData.read_file("maps/" + file))
			if extra and not extra.script_text.is_empty():
				vm.world_bodies["m:" + file.to_lower()] = vm._merge_script(extra.script_text, file.get_basename().to_lower())
	if restored.is_empty():
		vm._start_world(vm.ast.world)
	else:
		vm._restore(restored)
	if not quest_world.is_empty() and String(restored.get("quest", "")) != String(w.get_meta("quest_mob", "")):
		vm._start_world(quest_world, quest_src)
	vm.recalc_merc_briefings()   #  (party deployed)
	return vm


func _start_world(body: Array, src := "") -> void:
	var inst := Instance.new()
	inst.sname = "WorldScript"
	inst.src = src
	inst.killed = true
	inst.frames = [{"body": body, "i": 0}]
	instances.append(inst)


## Adds an active side quest's script to this zone's. Its script names can
## clash with the zone's own (both come from the same editor), so clashing
## names get the quest id appended. Returns the quest's WorldScript body.
func _merge_quest_script(w: GameWorld) -> Array:
	var text := String(w.get_meta("quest_script", "")) if w.has_meta("quest_script") else ""
	if text.is_empty():
		return []
	return _merge_script(text, String(w.get_meta("quest_mob", "")))


## Adds another .mob's script (side quest map, AddMob) to this zone's;
## returns its WorldScript body.
func _merge_script(text: String, q: String) -> Array:
	var extra := ScriptParser.parse(text)
	for name: String in extra.scripts:
		if ast.scripts.has(name):
			var re := RegEx.create_from_string(_regex_escape(name) + "(?![0-9A-Za-z_#])")
			text = re.sub(text, name + "_" + q, true)
	for name: String in extra.globals:
		if ast.globals.has(name):
			var re := RegEx.create_from_string("(?<![0-9A-Za-z_#])" + _regex_escape(name) + "(?![0-9A-Za-z_#])")
			text = re.sub(text, name + "_" + q, true)
	extra = ScriptParser.parse(text)
	for e in extra.errors:
		push_warning("quest script %s: %s" % [q, e])
	ast.scripts.merge(extra.scripts)
	for g in extra.globals:
		ast.globals[g] = extra.globals[g]
		globals[g] = [] if extra.globals[g] == "group" else null
	return extra.world


static func _regex_escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\#" else ch
	return out


# ================================================================ scheduling

func tick(dt: float) -> void:
	_seen_memo.clear()
	_in_tick = true
	_tick(dt)
	_in_tick = false
	_seen_memo.clear()


func _tick(dt: float) -> void:
	time += dt
	if not time_fixed:
		session.state.advance_hours(dt / CampaignState.HOUR_SECONDS)
	_refresh_heroes()
	_check_interactions()
	if not qobjs.is_empty() and time >= _q_check:
		_q_check = time + 0.5
		_check_quest_objectives()
	briefings.tick()
	# Script threads keep running during a conversation: the world tick
	#  calls the thread runner every tick, gated only
	# by the pause byte (world), and the conversation path
	# ("briefing" -> village screen slot 0x88
	# ) never touches the VM.
	# the original walks the thread list (VM) from its head
	# taking each node's next before running it, and a script call adds the new
	# thread at the head: newest first, and a
	# thread started during the tick first runs in the next one. (Running new
	# threads at once never ends in scripts that restart each other through an
	# always-true block, bz8k VCheck#0#108 -> VTriger#0#138 -> VCheck#0#108 at
	# night.) `instances` is kept oldest first.
	_seen_memo.clear()   # the steps above may have changed what units notice
	var cur := instances.duplicate()
	cur.reverse()
	for inst: Instance in cur:
		_run(inst)
	instances = instances.filter(func(x: Instance): return not (x.killed and x.frames.is_empty()))
	if not _pending_zone.is_empty():
		var z = _pending_zone
		_pending_zone = []
		session.call_deferred("leave_zone", z[0], z[1])


func _run(inst: Instance) -> void:
	if inst.frames.is_empty():
		if inst.killed or time < inst.poll:
			return
		inst.poll = time + POLL
		for bi in inst.blocks.size():
			var b: Dictionary = inst.blocks[bi]
			if _all(b.conds, inst):
				inst.block_index = bi
				inst.frames = [{"body": b.body, "i": 0}]
				_once_per_world(inst)
				break
		if inst.frames.is_empty():
			return
	# Waiting?
	if time < inst.wait_until:
		return
	if not inst.wait_cond.is_empty():
		if not _truthy(_eval(inst.wait_cond, inst)):
			return
		inst.wait_cond = []
	if inst.wait_unit != null:
		if is_instance_valid(inst.wait_unit) and inst.wait_unit is GameUnit and ai_busy(inst.wait_unit):
			return
		inst.wait_unit = null
	var steps := 0
	while not inst.frames.is_empty() and steps < MAX_STEPS:
		steps += 1
		var f: Dictionary = inst.frames[-1]
		if f.i >= f.body.size():
			if f.has("items") and f.k + 1 < f.items.size():
				f.k += 1
				_set_var(f.for_var, f.items[f.k], inst)
				f.i = 0
				continue
			inst.frames.pop_back()
			continue
		var st: Array = f.body[f.i]
		f.i += 1
		match st[0]:
			P.S_SET:
				_set_var(st[1], _eval(st[2], inst), inst)
			P.S_FOR:
				var g = _eval(st[2], inst)
				var items: Array = g.duplicate() if g is Array else ([] if g == null else [g])
				items = items.filter(func(x): return x != null and (not x is Object or is_instance_valid(x)))
				if not items.is_empty():
					_set_var(st[1], items[0], inst)
					inst.frames.append({"body": st[3], "i": 0, "for_var": st[1], "items": items, "k": 0})
			P.S_CALL:
				if _stmt_call(st[1], st[2], inst):
					return   # thread is sleeping


func _all(conds: Array, inst: Instance) -> bool:
	for c in conds:
		if not _truthy(_eval(c, inst)):
			return false
	return true


func spawn(name: String, args: Array) -> void:
	var s: Dictionary = ast.scripts.get(name, {})
	if s.is_empty():
		return
	var inst := Instance.new()
	inst.sname = name
	inst.blocks = s.blocks
	var params: Array = s.params
	for k in mini(params.size(), args.size()):
		inst.locals[params[k]] = args[k]
	instances.append(inst)


func fire_event(name: String, args: Array) -> void:
	# A merged script's (side quest, AddMob) handler of the same event was
	# renamed "<name>_<mob>"; it runs as well.
	for sn: String in ast.scripts.keys():
		if sn != name and not sn.begins_with(name + "_"):
			continue
		spawn(sn, args)
		# Event handlers run immediately so their effects are visible this frame.
		var inst: Instance = instances[-1] if not instances.is_empty() and instances[-1].sname == sn else null
		if inst:
			_run(inst)


func on_briefing_complete(player: int, id: String) -> void:
	briefings.complete(player, id)


func on_interact(unit: GameUnit, target: Object, player: int) -> void:
	briefings.interact(unit, target, player)


# ================================================================ values

func _truthy(v) -> bool:
	if typeof(v) == TYPE_OBJECT:
		return is_instance_valid(v)
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	if v is String:
		return not v.is_empty()
	if v is Array:
		return not v.is_empty()
	return v != null and (not v is Object or is_instance_valid(v))


func _num(v) -> float:
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String:
		return v.to_float()
	return 0.0


func _get_var(name: String, inst: Instance):
	if inst.locals.has(name):
		return inst.locals[name]
	if name == "NULL":
		return null
	return globals.get(name)


func _set_var(name: String, v, inst: Instance) -> void:
	if inst.locals.has(name):
		inst.locals[name] = v
	else:
		globals[name] = v


func _eval(e: Array, inst: Instance):
	match e[0]:
		P.N_NUM: return e[1]
		P.N_STR: return e[1]
		P.N_VAR: return _get_var(e[1], inst)
		P.N_CALL: return _call(e[1], e[2], inst)
	return null


func _args(a: Array, inst: Instance) -> Array:
	var out := []
	for x in a:
		out.append(_eval(x, inst))
	return out


func _unit(v) -> GameUnit:
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return null
	if v is GameUnit and world.looted.get(v.uid) == v:
		return null   # a looted corpse is off the server (only WasLooted sees it)
	return v if v is GameUnit and is_instance_valid(v) else null


func _obj_id(v) -> int:
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return 0
	if v is GameUnit and is_instance_valid(v):
		return v.uid
	if v is Node3D and is_instance_valid(v) and v.has_meta("ei"):
		return int(v.get_meta("ei").get("nid", 0))
	return 0


func _xy(v) -> Vector2:
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return Vector2.ZERO
	if v is GameUnit and is_instance_valid(v):
		return v.pos
	if v is Node3D and is_instance_valid(v) and v.has_meta("ei"):
		var p: Vector3 = v.get_meta("ei").position
		return Vector2(p.x, p.y)
	return Vector2.ZERO


func _group(v) -> Array:
	if v is Array:
		return v.filter(func(x): return x != null and is_instance_valid(x))
	return [] if v == null or (v is Object and not is_instance_valid(v)) else [v]


# ================================================================ statements

## Returns true when the instance must pause.
func _stmt_call(name: String, a: Array, inst: Instance) -> bool:
	match name:
		"Sleep":
			inst.wait_until = time + _num(_eval(a[0], inst)) * SLEEP_UNIT
			return true
		"SleepUntil":
			inst.wait_cond = a[0]
			return true
		"SleepUntilIdle":
			var u := _unit(_eval(a[0], inst))
			if u and ai_busy(u):
				inst.wait_unit = u
				inst.wait_until = time + 0.05
				return true
			return false
		"KillScript":
			inst.killed = true
			return false
	if ast.scripts.has(name):
		spawn(name, _args(a, inst))
		return false
	_call(name, a, inst)
	return false


# ================================================================ builtins

func _call(name: String, a: Array, inst: Instance):
	if not PURE_CALLS.has(name):
		_seen_memo.clear()
	# Special forms with lazily evaluated arguments.
	match name:
		"Any", "Every":
			var var_name: String = a[0][1]
			var items := _group(_eval(a[1], inst))
			var want_all := name == "Every"
			for x in items:
				_set_var(var_name, x, inst)
				var ok := _truthy(_eval(a[2], inst))
				if want_all and not ok:
					return 0.0
				if not want_all and ok:
					return 1.0
			return 1.0 if want_all else 0.0
		"KillScript":
			inst.killed = true
			return null
		"GroupHas", "GroupCross":
			# GroupHas(UnitSee / GroupSee(..), x), GroupCross(g, UnitSee /
			# GroupSee(..)): remake speed, the same answer without listing
			# everything the watchers notice (a big group in a crowd: ~10 ms
			# per test) — each unit asked about is tested against them.
			var k := 0 if name == "GroupHas" else 1
			if a.size() == 2 and a[k] is Array and a[k][0] == P.N_CALL and String(a[k][1]) in ["UnitSee", "GroupSee"] \
					and (a[k][2] as Array).size() == 1:
				var other = _eval(a[0], inst) if k == 1 else null
				var src = _eval(a[k][2][0], inst)
				var watchers := [_unit(src)] if String(a[k][1]) == "UnitSee" else _group(src)
				if k == 0:
					return 1.0 if _sees_has(watchers, _eval(a[1], inst)) else 0.0
				return _group(other).filter(func(x): return _sees_has(watchers, x))
	var v := _args(a, inst)
	var n := v.size()
	match name:
		# ---- logic and arithmetic
		"Not": return 0.0 if _truthy(v[0]) else 1.0
		"IsEqual": return 1.0 if is_equal_approx(_num(v[0]), _num(v[1])) or (v[0] is Object and v[0] == v[1]) else 0.0
		"IsLess": return 1.0 if _num(v[0]) < _num(v[1]) else 0.0
		"IsGreater": return 1.0 if _num(v[0]) > _num(v[1]) else 0.0
		"IsEqualString": return 1.0 if str(v[0]).to_lower() == str(v[1]).to_lower() else 0.0
		"Add": return _num(v[0]) + _num(v[1])
		"Sub": return _num(v[0]) - _num(v[1])
		"Mul": return _num(v[0]) * _num(v[1])
		"Random": return float(randi() % maxi(1, int(_num(v[0]))))
		# ---- campaign variables
		"GSGetVar": return session.state.get_var(0, str(v[1]).to_lower())
		"GSSetVar":
			var key := str(v[1]).to_lower()
			var had: bool = session.state.vars.has("0:%s" % key)
			var old := session.state.get_var(0, key)
			session.state.set_var(0, key, _num(v[2]))
			# Scripts re-set the same value every few ticks; only a change
			# updates the journal / mercs (else "Journal updated." repeats).
			if not had or not is_equal_approx(old, _num(v[2])):
				_on_var_changed(key)
		"GSSetVarMax":
			var key := str(v[1]).to_lower()
			if _num(v[2]) > session.state.get_var(0, key):
				session.state.set_var(0, key, _num(v[2]))
				_on_var_changed(key)
		"GSDelVar": session.state.del_var(0, str(v[1]).to_lower())
		# ---- object lookup and groups
		"GetObject": return _get_object(int(_num(v[0])))
		"GetObjectByID": return _get_object(str(v[0]).to_int())
		"GetObjectByName": return _by_name(str(v[0]))
		"GetObjectID": return float(_obj_id(v[0]))
		"AddObject":
			var g = v[0]
			if g is Array and v[1] != null and not g.has(v[1]):
				g.append(v[1])
		"GroupSize": return float(_group(v[0]).size())
		"GroupHas": return 1.0 if _group(v[0]).has(v[1]) else 0.0
		"GroupCross":
			var b := _group(v[1])
			return _group(v[0]).filter(func(x): return b.has(x))
		"UnitSee": return _sees([_unit(v[0])])
		"GroupSee": return _sees(_group(v[0]))
		# Builtin 0xa5 PlayerSee(player): the player's visible
		# set (player, rebuilt from the player's units
		# and what each one notices, AI) plus the player's units
		# and their noticed lists again. UnitSee / GroupSee (0x5d / 0x5e): the
		# unit's noticed list (AI; UnitAI.can_notice).
		"PlayerSee": return _player_visible()
		# Builtin 0xb4 GetUnitOfPlayer(player, k): the unit
		# the player's k-th party record (0x784 bytes each: the hero
		# first, then the mercenaries), dead or hidden alike; none past the end.
		"GetUnitOfPlayer":
			var hs := _party_records()
			var k := int(_num(v[1]))
			return hs[k] if k >= 0 and k < hs.size() else null
		"GetLeader":
			var hs := heroes()
			return hs[0] if not hs.is_empty() else null
		# Builtin 0xd1 GetMercsNumber(player) ->: the party records
		# whose unit exists and lives, minus one (the hero). Co-op: minus one
		# per player.
		"GetMercsNumber":
			var alive := _party_records().filter(func(u: GameUnit): return not u.dead).size()
			return float(maxi(0, alive - _player_count()))
		# ---- unit queries
		"GetX": return _xy(v[0]).x
		"GetY": return _xy(v[0]).y
		"GetZ":
			var p := _xy(v[0])
			return world.ground_at(p.x, p.y)
		# Builtins 0xbf / 0xc0 GetFutureX / Y(unit, ticks): the
		# unit's position at logic tick now + ticks (round), its
		# (the point reached along its path). 0 for no unit. Remake: along the
		# path at the current speed, 55 ms ticks.
		"GetFutureX", "GetFutureY":
			var u := _unit(v[0])
			if u == null and not (v[0] is Node3D and is_instance_valid(v[0])):
				return 0.0
			var p := _xy(v[0])
			if u and not u.path.is_empty():
				var left := u.speed() * roundf(_num(v[1])) * GameUnit.TICK
				for q: Vector2 in u.path:
					var d := p.distance_to(q)
					if d >= left:
						p += (q - p) * (left / maxf(d, 0.0001))
						break
					p = q
					left -= d
			return p.x if name == "GetFutureX" else p.y
		"DistanceUnitUnit":
			if v[0] == null or v[1] == null:
				return 99999.0
			return _xy(v[0]).distance_to(_xy(v[1]))
		"DistanceUnitPoint":
			if v[0] == null:
				return 99999.0
			return _xy(v[0]).distance_to(Vector2(_num(v[1]), _num(v[2])))
		"UnitInSquare":
			var p := _xy(v[0])
			return 1.0 if v[0] != null and Rect2(Vector2(_num(v[1]), _num(v[2])), Vector2.ZERO).expand(Vector2(_num(v[3]), _num(v[4]))).has_point(p) else 0.0
		"IsDead":
			var u := _unit(v[0])
			return 1.0 if u == null or u.dead else 0.0
		"IsAlive":
			var u := _unit(v[0])
			return 1.0 if u and not u.dead else 0.0
		"IsEnemy":
			var u := _unit(v[0])
			return 1.0 if u and world.relation(u.faction, int(_num(v[1]))) == 2 else 0.0
		# Builtin 0xb1 IsPlayerInDanger(player): the player's combat flag
		# (player == 2,; UnitAI._player_in_combat).
		"IsPlayerInDanger": return 1.0 if _in_danger() else 0.0
		# Builtin 0xe5 IsUnitVisible(unit): in player 0's visible list.
		"IsUnitVisible": return 1.0 if v[0] != null and _player_visible().has(v[0]) else 0.0
		"WasLooted":   # builtin 0xe3: the object's flag +8 &
			var u = v[0]
			if typeof(u) == TYPE_OBJECT and not is_instance_valid(u):
				return 0.0
			return 1.0 if u is GameUnit and u.get_meta("looted", false) else 0.0
		# builtin 0xe6: the object's flag — BlockUnit or a
		# "say_block" line playing (GameUnit.blocked).
		"IsUnitBlocked":
			var bu := _unit(v[0])
			return 1.0 if bu and bu.blocked else 0.0
		# ---- unit control
		"Walk", "Run":
			var u := _unit(v[0])
			if u:
				u.set_meta("script_run", name == "Run")
		# Builtin 0x2 MoveToPoint(unit, x, y) ->: AI state 1 and a
		# move order to the point.
		"MoveToPoint":
			var u := _unit(v[0])
			if u and not u.dead:
				var to := world.nav.nearest_walkable_for(u, Vector2(_num(v[1]), _num(v[2])))
				u.move_to(to, u.get_meta("script_run", false) or u.running)
				u.set_meta("ai_state", 1)
		# Builtins 0x8e SetCP / 0xad SetCPFast(object, x, y, z) put the object
		# there at once (: position.., world grid
		# re-link); a unit then drops what it was doing and stands
		# (creature: order 9, actions reset). SetCPFast first
		# clears object byte +2; SetCP marks a height change ((2)).
		# No walk: the villagers' schedules (basecam.mob) put them on their
		# spots this way. The motivations (Sentry point etc.) are left as
		# they are.
		"SetCP", "SetCPFast":
			var u := _unit(v[0])
			if u:
				u.orders.clear()
				u.order = {}
				u.path = PackedVector2Array()
				u.target = null
				u._set_action("idle")
				u.pos = Vector2(_num(v[1]), _num(v[2]))
			elif v[0] is Node3D and is_instance_valid(v[0]) and n >= 3:
				var nid := _obj_id(v[0])
				var p3 := Vector3(_num(v[1]), _num(v[2]), _num(v[3]) if n > 3 else 0.0)
				world.move_object(nid, p3)
				session.broadcast({"t": "move_obj", "nid": nid, "p": [p3.x, p3.y, p3.z]})
		# Builtin 0x34 Idle(unit): the AI's motivations are dropped
		# (as UMClear) and its state / script command reset
		# an order under way runs .
		"Idle":
			_um_clear(v[0], "none")
			if _unit(v[0]):
				_unit(v[0]).remove_meta("ai_state")
		"RotateTo":
			var u := _unit(v[0])
			if u:
				var d := Vector2(_num(v[1]), _num(v[2])) - u.pos
				u.command({"type": "rotate", "angle": atan2(d.y, d.x)}, true)
				u.set_meta("ai_state", 1)
		"PlayAnimation":
			var u := _unit(v[0])
			if u:
				u.command({"type": "anim", "name": str(v[1]).to_lower()}, true)
		"HideObject":
			_hide(v[0], _truthy(v[1]))
		"RemoveUnitFromServer", "RemoveObjectFromServer":
			var u := _unit(v[0])
			if u:
				world.remove_unit(u)
				session.broadcast({"t": "remove", "uid": u.uid})
			elif v[0] is Node3D and is_instance_valid(v[0]):
				var nid := _obj_id(v[0])
				session.broadcast({"t": "remove_obj", "nid": nid})
				world.objects.erase(nid)
				world.levers.erase(nid)
				world.nav.remove_object(nid)
				v[0].queue_free()
		"KillUnit":
			var u := _unit(v[0])
			if u and not u.dead:
				u.die(null)
		"InflictDamage":
			var u := _unit(v[0])
			if u and not u.dead:
				u.take_damage(_num(v[1]), null)
		# Builtin 0x24 UMClear(unit) ->: every motivation of the
		# unit's AI is dropped (no order is stopped); the unit then does
		# nothing of its own until a UM* call gives it one.
		"UMClear": _um_clear(v[0], "none")
		# Builtin 0x2c UMStandard: Aggression, Suspection
		#  and CorpseWatcher are added beside the
		# calm motivation, which stays (UnitAI.um).
		"UMStandard": _um_add(v[0], {"fight": "standard", "susp": true, "corpse": true})
		# 0x2d UMAggression / 0x2e UMRevenge ((1)
		# the same class): added beside the calm motivation.
		"UMAggression": _um_add(v[0], {"fight": "aggression"})
		"UMRevenge": _um_add(v[0], {"fight": "revenge"})
		# 0xc7 UMFear(unit, flag) -> (flag != 0), added beside the
		# others (UnitAI._fear_priority).
		"UMFear": _um_add(v[0], {"fear": 1 if n < 2 or _truthy(v[1]) else 0})
		"UMSentry", "Sentry": _mode(v[0], "sentry", {"point": Vector2(_num(v[1]), _num(v[2]))})
		# Builtins 0x26 UMGuard / 0x33 Guard (unit, x, y, radius)
		#  with stay −1; 0x27 UMGuardEx (unit, x, y, radius, stay).
		# A negative radius / stay takes ai.reg GuardRadius / GuardStayTime.
		"UMGuard", "Guard", "UMGuardEx": _mode(v[0], "guard", {"point": Vector2(_num(v[1]), _num(v[2])),
			"radius": _num(v[3]) if n > 3 else -1.0, "stay": _num(v[4]) if name == "UMGuardEx" and n > 4 else -1.0})
		"UMFollow": _mode(v[0], "follow", {"target": _unit(v[1])})
		# Builtin 0x3b Follow(unit, target) ->: AI state 6 with the
		# target, keeps it near until the target is gone.
		# It is no motivation (the calm one stays). Remake: a follow order.
		"Follow":
			var fu := _unit(v[0])
			var ft := _unit(v[1])
			if fu and ft and fu != ft and not fu.dead:
				fu.set_meta("ai_state", 6)
				fu.set_meta("ai_target", ft)
				fu.command({"type": "follow", "target": ft, "dist": 2.0})
		# Builtin 0x31 UMPlayer(unit): motivations dropped, the
		# Player motivation added (type 6: the player units' one —
		# engage noticed enemies when aggressive, no calm walk; UnitAI._player)
		# and the AI state reset.
		"UMPlayer":
			var u := _unit(v[0])
			if u and not u.has_meta("hero"):
				_um_clear(u, "player")
				u.remove_meta("ai_state")
		"SetPlayer":
			var u := _unit(v[0])
			if u:
				u.faction = int(_num(v[1]))
		# builtin 0x32: sets / clears the creature's flag
		# and nothing else (no order); player orders then skip the unit.
		"BlockUnit":
			var u := _unit(v[0])
			if u:
				u.blocked = _truthy(v[1])
		"ResetTarget":
			var u := _unit(v[0])
			if u:
				u.target = null
				u.orders.clear()
				u.order = {}
		# the original builtins 0xce / 0xcf: add to the
		# hero's strength / dexterity; 0xcd GiveSkill(unit, "melee" | "archery" |
		# "science" |..., n) adds n levels (etc.: skill byte += n).
		# Approx.: the original's side effects on two more unit fields (
		#  += 0.2) are not traced; stats are recomputed as on level-up.
		"GiveSkill", "GiveStrength", "GiveDexterity":
			var u := _unit(v[0])
			if u and u.has_meta("hero"):
				var hd: Dictionary = u.get_meta("hero")
				if name == "GiveSkill" and n >= 3:
					var sk := str(v[1]).to_lower()
					hd.get_or_add("skills", {})[sk] = Skills.level(hd, sk) + int(_num(v[2]))
				elif n >= 2:
					var key := "str" if name == "GiveStrength" else "dex"
					hd[key] = float(hd.get(key, 25.0)) + _num(v[1])
					#  also change the body once per call:
					# GiveStrength muscle + 0.2, GiveDexterity fat
					#  - 0.2, not below 0 (remake complexion: fat, muscle, height).
					var c: Vector3 = u.info.get("complexion", hd.get("complexion", Vector3(0.5, 0.5, 0.5)))
					if name == "GiveStrength":
						c.y += 0.2
					else:
						c.x = maxf(c.x - 0.2, 0.0)
					Combat.set_complexion(u, hd, c)
				session._refresh_hero(u)
				session.sync_state()
		# ---- diplomacy
		"SetDiplomacy":
			world.set_relation(int(_num(v[0])), int(_num(v[1])), _diplo_in(int(_num(v[2]))))
			session.broadcast({"t": "diplo", "a": int(_num(v[0])), "b": int(_num(v[1])), "v": _diplo_in(int(_num(v[2])))})
		"GetDiplomacy": return float(_diplo_out(world.relation(int(_num(v[0])), int(_num(v[1])))))
		# Builtin 0x43 InvokeAlarm(n, x, y): forced (UnitAI.invoke_alarm).
		"InvokeAlarm":
			world.ai.invoke_alarm(int(_num(v[0])), Vector2(_num(v[1]), _num(v[2])) if n >= 3 else Vector2.ZERO, true)
		# 0x67 IsAlarm / 0x8b AlarmTime (the raise tick) / 0x8c, 0x8d AlarmPosX / Y
		# read the world's alarm table.
		"IsAlarm": return 1.0 if world.ai.alarm(int(_num(v[0]))).on else 0.0
		"AlarmTime": return float(world.ai.alarm(int(_num(v[0]))).time)
		"AlarmPosX": return float(world.ai.alarm(int(_num(v[0]))).pos.x)
		"AlarmPosY": return float(world.ai.alarm(int(_num(v[0]))).pos.y)
		# ---- areas
		"AddRectToArea":
			areas.get_or_add(int(_num(v[0])), []).append(Rect2(Vector2(_num(v[1]), _num(v[2])), Vector2.ZERO).expand(Vector2(_num(v[3]), _num(v[4]))))
		"AddRoundToArea":
			areas.get_or_add(int(_num(v[0])), []).append(Vector3(_num(v[1]), _num(v[2]), _num(v[3])))
		"IsInArea":
			var p := Vector2(_num(v[1]), _num(v[2]))
			for s in areas.get(int(_num(v[0])), []):
				if (s is Rect2 and s.has_point(p)) or (s is Vector3 and p.distance_to(Vector2(s.x, s.y)) <= s.z):
					return 1.0
			return 0.0
		# ---- levers and traps
		"GetLeverState": return float(world.levers.get(_obj_id(v[0]), {}).get("state", 0))
		# the original builtins 0x91 / 0x9e -> (state, time): state −1 =
		# the next one; SwitchLeverState uses the lever's switch time.
		"SwitchLeverState", "SwitchLeverStateEx":
			var id := _obj_id(v[0])
			if world.levers.has(id):
				var st := int(_num(v[1])) if v.size() > 1 else -1
				var time := float(_num(v[2])) if name == "SwitchLeverStateEx" and v.size() > 2 else -10.0
				time = world.lever_sys.set_state(id, st, time)
				session.broadcast({"t": "lever", "nid": id, "state": world.levers[id].state, "time": time})
		"EnableLever":
			var id := _obj_id(v[0])
			if world.levers.has(id):
				world.levers[id].enabled = _truthy(v[1])
				# Clients' cursors check usable() too (remake-only event field).
				session.broadcast({"t": "lever", "nid": id, "enabled": world.levers[id].enabled})
		# Builtin 0x95 ActivateTrap(object, ): object flag (+8) set / cleared
		# only magic traps read it (MagicTraps).
		"ActivateTrap":
			if n >= 2:
				world.traps.set_active(_obj_id(v[0]), _num(v[1]) != 0.0)
		# Builtins 0xa8 CastSpellPoint(spell, x0, y0, x1, y1) / 0xa9 CastSpellUnit(spell,
		# x0, y0, unit): the spell (unknown names do nothing) is cast
		# by nobody from (x0, y0) at the point (x1, y1) / at the unit (none: nothing),
		# (spell, 0, , target, point) -> Spells.cast_from.
		"CastSpellPoint":
			if n >= 5:
				Spells.cast_from(world, str(v[0]), Vector2(_num(v[1]), _num(v[2])), null, Vector2(_num(v[3]), _num(v[4])))
		"CastSpellUnit":
			var tu := _unit(v[3]) if n >= 4 else null
			if tu and not tu.dead:
				Spells.cast_from(world, str(v[0]), Vector2(_num(v[1]), _num(v[2])), tu, tu.pos)
		# SetPlayerAggression(player, value) (builtin 0xa4, "ff") has no case in
		# the original's dispatcher (jump table sends it to the
		# default that only pops the arguments): a no-op; no campaign
		# script calls it.
		"RecalcMercBriefings":
			recalc_merc_briefings()
		# the original builtin 0xac: SetScience(lever, id, value, f1, f2, f4, f8) sets
		# the lever's LEVER_SCIENCE_STATS to [flags, id, value], flags = 1|2|4|8
		# for the non-zero f arguments; [0, 0, 0] = scripts only.
		"SetScience":
			var id := _obj_id(v[0])
			if world.levers.has(id) and n >= 7:
				var flags := 0
				for k in 4:
					if _num(v[3 + k]) != 0.0:
						flags |= 1 << k
				sciences[id] = [flags, int(_num(v[1])), int(_num(v[2]))]
				world.levers[id].science = sciences[id]
		# Builtin 0xb8 SetWaterLevel(material, level, ticks)
		#  (see GameWorld.set_water_level).
		"SetWaterLevel":
			if n >= 3:
				world.set_water_level(int(_num(v[0])), _num(v[1]), int(_num(v[2])))
				session.broadcast({"t": "water", "l": world.water_levels.duplicate(true)})
		# Builtin 0xdf FixItems(): every item the server holds (list at server
		# ) gets its durability back to the maximum.
		"FixItems":
			session.state.fix_items()
			for u: GameUnit in world.units.values():
				if u.has_meta("hero"):
					session._refresh_hero(u)
			session.sync_state()
		# Builtins 0xcb CopyLoot / 0xe0 AddLoot(player, from, to): party bags by
		# name (an unknown name means the main party ""). CopyLoot
		# empties `to` and copies the items and the money
		# `from` into it; AddLoot adds them (merges stacks).
		"CopyLoot", "AddLoot":
			if n >= 3:
				session.state.move_loot(str(v[1]), str(v[2]), name == "CopyLoot")
				session.sync_state()
		"Nop", "SetPlayerAggression":
			pass
		# ---- quests, items, money
		"QuestComplete":
			SmileFaces.party(session)   # remake option "smile_faces"
			if SideQuests.get_quest(str(v[1])).is_empty():
				_quest_complete(str(v[1]))
			else:
				SideQuests.finish(session, str(v[1]))
			# Single player: flags every trader for a restock
			# the network game's branch does not.
			if session.lmp.is_empty():
				session.restock_shops()
		# Builtins 0x92 GiveQuestItem / 0xa6 GiveItem (one case):
		# the item made from the name goes into the player's
		# items through, like a conversation reward. Its client
		# message 6 shows "You picked up: <item>" (Session.notify_got).
		# Builtin 0xa7 GiveMoney: player += n, then the same (empty) item
		# send: "You picked up: Money (n)".
		# Both go through CampaignState.add_item: a quest-table item lands in the
		# quest item list (the remake's store of the bag's quest items, read by
		# HaveItem / EraseQuestItem / levers), anything else in the bag. The
		# party's bag is shared, so every player sees the line (to -1).
		# Co-op: a find from the world, copied to the other players' bags with
		# the remake option coop_share_loot (CoopProgress.share_found).
		"GiveQuestItem", "GiveItem":
			session.coop.with_purse(-1, session.state.add_item.bind(str(v[1])), true)
			session.notify_got(-1, [str(v[1])])
		"GiveUnitQuestItem":
			var u := _unit(v[0])
			if u:
				# The unit carries it: it is found when the unit is looted / robbed.
				var qi := _quest_item_name(v[1])
				u.info["quest_items"] = Array(u.info.get("quest_items", [])) + [qi]
				for m in ["loot", "pockets"]:
					if u.has_meta(m):
						u.get_meta(m).append(qi)
		"EraseQuestItem", "RemoveQuestItem":
			var qi := _quest_item_name(v[1])
			session.state.quest_items.erase(qi)
		"HaveItem": return 1.0 if session.state.quest_items.has(_quest_item_name(v[1])) else 0.0
		"GiveMoney":
			var money := int(_num(v[1]))
			session.coop.with_purse(-1, func() -> void: session.state.money += money, true)
			session.notify_got(-1, [], money)
		"QStart":
			_q_recording = str(v[0]).to_lower()
			if not qobjs.has(_q_recording):
				qobjs[_q_recording] = {"objs": [], "items": session.state.quest_items.size()}
		"QFinish":
			_q_recording = ""
		"QObjArea", "QObjSeeUnit", "QObjSeeObject", "QObjKillUnit", "QObjKillGroup", "QObjGetItem", "QObjUse":
			if _q_recording and qobjs.has(_q_recording):
				var q: Dictionary = qobjs[_q_recording]
				if q.objs.size() < 16 and not q.get("defined", false):
					q.objs.append([name, str(v[0]) if v.size() > 0 else "", _num(v[1]) if v.size() > 1 else 0.0, false])
		# ---- parties
		# Builtin 0x9a CreateParty(player, name) ->: a new empty party
		# (no members, an empty bag, no money) appended to the player's list.
		# **Approx.**: the original appends even when the name exists (lookups then
		# find the older one); the remake replaces a party that is not current.
		"CreateParty":
			session.state.create_party(str(v[1]))
		"AddUnitToParty":
			if "::" in str(v[1]):
				session.state.add_party_unit(str(v[1]).get_slice("::", 0), str(v[1]).get_slice("::", 1), str(v[2]))
		"CopyStats":
			session.state.copy_stats(str(v[1]), str(v[2]))
		"CopyItems":
			session.state.copy_items(str(v[1]), str(v[2]))
		"SetCurrentParty":
			if session.state.set_current_party(str(v[1])):
				session.sync_state()
		"AddUnitUnderControl":
			var u := _unit(v[1])
			if u:
				u.controller = 0
				u.faction = 0
				u.mode = "player"
				u.set_meta("hero", {"name": u.display_name, "prototype": u.proto.get("name", ""), "merc": true})
				session.broadcast({"t": "party"})
		"RemoveUnitFromParty":
			var nm := str(v[1]).to_lower()
			if nm.begins_with("merc") and nm.substr(4).is_valid_int():
				session.state.set_var(0, "apartyn" + nm.substr(4), 0.0)
				session.merc_changed(nm.substr(4).to_int(), false)
		"RedeployParty":
			session.redeploy_party(0)
		# ---- presentation
		"SendStringEvent": _string_event(str(v[1]))
		# Builtin 0x39 SendEvent(a, b) ->: net message 0x12 with the
		# number to every player; the client's handler (table entry set up
		# ) only stores it at client
		# world, which nothing reads (set to -1): no effect.
		"SendEvent": pass
		"PlayMusic": session.broadcast({"t": "music", "name": str(v[1])})
		"PlayMovie": session.broadcast({"t": "movie", "name": str(v[0])})
		"CreateParticleSource", "SetParticleSourceSize", "MoveParticleSource", "DeleteParticleSource", \
		"AttachParticles", "AttachParticleSource", "CreateFX", "CreateFXSource", "DeleteFXSource", \
		"CreateRandomizedFXSource", "CreatePointLight", \
		"MovePointLight", "DeletePointLight", \
		"CreateLightning", "DeleteLightning", "CreateRunPoint", "CreateRunPoint1", "CreateRunway":
			# Presentation only: ParticleFx.script_cmd and the script sounds
			# (GameSound._script_fx) on every peer (Session._on_event).
			var args: Array = v.map(func(x): return x if not x is Object else _obj_id(x))
			if name == "CreateFXSource" and not args.is_empty() and _num(args[0]) < 0:
				# id -1 takes the next free negative id (
				# counting down); numbered here so every peer and a joiner's
				# replay use the same id.
				args[0] = _fx_auto
				_fx_auto -= 1
			session.broadcast({"t": "fxcmd", "f": name, "a": args})
		# ---- time and zones
		"GetWorldTime": return session.state.world_time
		"FixWorldTime":   # stop the zone's clock at the given hour
			time_fixed = true
			if not v.is_empty():
				session.state.world_time = fmod(_num(v[0]), 24.0)
		"RunWorldTime":   # set the hour and let the clock run again
			time_fixed = false
			if not v.is_empty():
				session.state.world_time = fmod(_num(v[0]), 24.0)
		"LeaveToZone":   # the entrance is the original's 0-based exit index (map.txt "#exit" = index + 1)
			_pending_zone = [str(v[1]).to_lower(), int(_num(v[2])) + 1]
		"AddMob":
			_add_mob(str(v[0]))
		_:
			if ast.scripts.has(name):
				spawn(name, v)
			else:
				unknown_calls[name] = int(unknown_calls.get(name, 0)) + 1
				push_warning("script: unknown function %s" % name)
	return null


# ================================================================ helpers

func heroes() -> Array:
	var out := []
	for u: GameUnit in world.units.values():
		if u.has_meta("hero") and not u.dead and not u.hidden:
			out.append(u)
	out.sort_custom(func(a, b): return a.controller < b.controller if a.controller != b.controller else a.uid < b.uid)
	return out


## A hero ordered to talk to someone starts the conversation on arrival.
func _check_interactions() -> void:
	for u: GameUnit in world.units.values():
		if not u.has_meta("interact"):
			continue
		var it: Array = u.get_meta("interact")
		var t = it[0]
		if u.dead or not is_instance_valid(t) or u.order.get("type", "") not in ["follow", "move", ""]:
			u.remove_meta("interact")
		elif u.pos.distance_to(_xy(t)) < _interact_reach(u, t, it[2] if it.size() > 2 else ""):
			u.remove_meta("interact")
			# Steal, loot and lever use are the use action (order type 6): the
			# unit turns, plays its clip and the action runs at the clip's hit
			# frame (GameUnit._do_use).
			if it.size() > 2 and it[2] == "revive":   # remake option (Revive)
				if t is GameUnit:
					Revive.begin(session, u, t)
			elif it.size() > 2 and it[2] == "steal":
				if t is GameUnit and not t.dead:
					u.command({"type": "use", "sub": "steal", "at": t.pos, "done": func():
						if is_instance_valid(u) and not u.dead and is_instance_valid(t) and not t.dead:
							session.coop.with_purse(Session.loot_player(u), session.steal.bind(u, t), true)})   # a joiner's own bag
			elif t is GameUnit and Session.lootable(t) and world.units.has(t.uid):
				u.command({"type": "use", "sub": "loot", "at": t.pos, "done": func():
					if is_instance_valid(u) and not u.dead and is_instance_valid(t) and world.units.has(t.uid):
						session.coop.with_purse(Session.loot_player(u), session.take_loot.bind(u, t), true)})
			elif not (t is GameUnit):
				var nid := _obj_id(t)
				if world.lever_sys.usable(nid):
					u.command({"type": "use", "sub": "science", "at": _xy(t), "done": func():
						if is_instance_valid(u) and not u.dead and world.lever_sys.usable(nid):
							_use_lever(u, nid)})
			else:
				briefings.interact(u, t, it[1])


## Reach of an interaction, the original (order type 6 = the use
## action; own radius = unit = = 0.9 × the
## figure's larger half extent + 0.05):
##  * loot (sub-code): own radius + 0.3 × the body's radius
##  * a living unit (steal; == 0x50): both units'
##    (`GameUnit.body_radius`) + 0.6;
##  * a map object (lever, chest; sub-code 0): own radius + the object's
##    radius (`GameWorld.object_radius`) − 0.1.
## A talk has no reach in the original: the village click opens the topic list
## once and a field click on a non-hostile unit
## is a move to it. **Approx.**: the remake's
## walk-and-talk keeps 3 m. The remake's 0.5 m nav grid is coarser than the
## original's passability, so an object's or body's reach also covers its nearest
## walkable cell (+ 0.375 m) — gz17h DeadS (r 0.95) lies 1.42 m from its
## nearest open cell, past the original reach of 1.35 m.
func _interact_reach(u: GameUnit, t, kind := "") -> float:
	if not (t is Node3D):
		return 3.0
	var r: float
	if kind == "steal" and t is GameUnit:
		return u.body_radius() + t.body_radius() + 0.6
	elif t is GameUnit and t.dead:
		r = u.figure_radius + 0.05 + 0.3 * (t.figure_radius + 0.05)
	elif t is GameUnit:
		return 3.0
	else:
		r = u.figure_radius + 0.05 + world.object_radius(t) - 0.1
	var p := _xy(t)
	return maxf(r, world.nav.nearest_walkable(p, 3).distance_to(p) + NavGrid.CELL * 0.75)


## A lever / switch used by `u` (sub-code 0): its science
## check against the unit's science (Dex - 25 + skill) and the party's quest items.
func _use_lever(u: GameUnit, nid: int) -> void:
	var h: Dictionary = u.get_meta("hero", {})
	var use := float(u.stats.get("dex", 25.0)) - 25.0 + Skills.level(h, "science")
	var quest := session.state.items.filter(func(x): return Items.kind(String(x)) == "quest")
	# Quest items given by conversations / scripts / loot live in
	# state.quest_items (HaveItem); they open levers too.
	quest.append_array(session.state.quest_items.keys())
	if world.lever_sys.science_ok(nid, use, quest):
		var time := world.lever_sys.set_state(nid, -1)
		session.broadcast({"t": "lever", "nid": nid, "state": world.levers[nid].state, "time": time})
	else:
		u.ack(EIAcks.SCIENCE_FAILED)   # ack 0x11


func _player_count() -> int:
	return maxi(1, session.players.size())


func _refresh_heroes() -> void:
	if globals.has("Heroes"):
		globals["Heroes"] = heroes()


func _get_object(id: int):
	if world.units.has(id):
		return world.units[id]
	var o = world.objects.get(id)
	return o if o != null and is_instance_valid(o) else null


## the original: a script name's object id — h = toupper(c) + 5·h
## over the characters (32-bit), id = h mod 10^9 + 10^9. Named map objects
## carry that id (merc1 = 1000059184), and conversations b.<name>.<id> belong
## to the unit with id name_id(<name>): Shei-Var, "OrcC", is the
## unit named "Shaivar" in bz6g with id 1000012327.
static func name_id(n: String) -> int:
	var h := 0
	for c in n.to_upper().to_ascii_buffer():
		h = (c + h * 5) & 0xFFFFFFFF
	return h % 1000000000 + 1000000000


func _by_name(n: String):
	var by_id = world.units.get(name_id(n))
	if by_id != null and is_instance_valid(by_id):
		return by_id
	n = n.to_lower()
	if n == "hero":
		var hs := heroes()
		return hs[0] if not hs.is_empty() else null
	for u: GameUnit in world.units.values():
		if String(u.info.get("name", "")).to_lower() == n:
			return u
	for o in world.objects.values():
		if is_instance_valid(o) and String(o.get_meta("ei").get("name", "")).to_lower() == n:
			return o
	return null


func _sees(watchers: Array) -> Array:
	var out := []
	var have := {}
	for w in watchers:
		if w == null or not is_instance_valid(w) or w.dead:
			continue
		for u in _noticed(w):
			if not have.has(u):
				have[u] = true
				out.append(u)
	return out


## Whether `x` is in `_sees(watchers)` (tested per watcher as _noticed lists).
func _sees_has(watchers: Array, x) -> bool:
	if not is_instance_valid(x) or not x is GameUnit or (x as GameUnit)._seq == 0:
		return false
	var xu: GameUnit = x
	for w in watchers:
		if w == null or not is_instance_valid(w) or w.dead or w == xu:
			continue
		if _in_tick and _seen_memo.has(w):
			if (_seen_memo[w] as Array).has(xu):
				return true
			continue
		var r := float(w.stats.get("sight", 15.0))
		if xu.pos.distance_squared_to(w.pos) <= r * r and world.ai.can_notice(w, xu, r):
			return true
	return false


## Remake speed (UnitSee / GroupSee / PlayerSee are polled by many script
## conditions every tick): one watcher's noticed units, in GameWorld.units
## order, remembered while nothing can have changed them — only during
## ScriptVM.tick and until a builtin that is not a pure query runs
## (_call, PURE_CALLS); cleared at the start and end of every tick.
var _seen_memo := {}
var _in_tick := false


func _noticed(w: GameUnit) -> Array:
	if _in_tick and _seen_memo.has(w):
		return _seen_memo[w]
	var r := float(w.stats.get("sight", 15.0))
	var out := []
	var terms := world.ai.notice_terms(w, r)
	for u in _units_within(w.pos, r):
		if u != w and world.ai.can_notice_with(w, u, terms):
			out.append(u)
	if _in_tick:
		_seen_memo[w] = out
	return out


## GameWorld.units_near(p, r) (every unit within r, dead ones too, in
## GameWorld.units order) from the host's unit buckets.
func _units_within(p: Vector2, r: float) -> Array:
	if not (world.authority and world.nav and world.nav.size.x > 0):
		return world.units_near(p, r)
	return world.nav.units_all_around(p, r)


## Builtins that only read (no world, unit, group or campaign change).
const PURE_CALLS := {"Not": 1, "IsEqual": 1, "IsLess": 1, "IsGreater": 1, "IsEqualString": 1, "Add": 1,
	"Sub": 1, "Mul": 1, "Random": 1, "GSGetVar": 1, "GetObject": 1, "GetObjectByID": 1, "GetObjectByName": 1,
	"GetObjectID": 1, "GroupSize": 1, "GroupHas": 1, "GroupCross": 1, "UnitSee": 1, "GroupSee": 1,
	"PlayerSee": 1, "GetUnitOfPlayer": 1, "GetLeader": 1, "GetMercsNumber": 1, "GetX": 1, "GetY": 1,
	"GetZ": 1, "GetFutureX": 1, "GetFutureY": 1, "DistanceUnitUnit": 1, "DistanceUnitPoint": 1,
	"UnitInSquare": 1, "IsDead": 1, "IsAlive": 1, "IsEnemy": 1, "IsPlayerInDanger": 1, "IsUnitVisible": 1,
	"WasLooted": 1, "IsUnitBlocked": 1, "GetDiplomacy": 1, "IsInArea": 1, "GetLeverState": 1,
	"HaveItem": 1, "GetWorldTime": 1, "Any": 1, "Every": 1}


func _in_danger() -> bool:
	var seen := {}
	for h: GameUnit in _own_units():
		if not seen.has(h.controller):
			seen[h.controller] = true
			if world.ai._player_in_combat(h.controller):
				return true
	return false


## The script's player 0 = every human player in co-op: their living units.
func _own_units() -> Array:
	var out := []
	for u: GameUnit in world.units.values():
		if is_instance_valid(u) and u.controller >= 0 and not u.dead and not u.hidden:
			out.append(u)
	return out


func _player_visible() -> Array:
	if _in_tick and _seen_memo.has(&"player"):
		return (_seen_memo[&"player"] as Array).duplicate()
	var own := _own_units()
	var out := own.duplicate()
	var have := {}
	for x in own:
		have[x] = true
	for x in _sees(own):
		if not have.has(x):
			have[x] = true
			out.append(x)
	if _in_tick:
		_seen_memo[&"player"] = out.duplicate()
	return out


## The party records' units (heroes() without the dead / hidden filter).
func _party_records() -> Array:
	var out := []
	for u: GameUnit in world.units.values():
		if is_instance_valid(u) and u.has_meta("hero"):
			out.append(u)
	out.sort_custom(func(a, b): return a.controller < b.controller if a.controller != b.controller else a.uid < b.uid)
	return out


## UMClear / Idle and UMPlayer: the whole motivation list goes
## `calm` "none" or "player" (the Player motivation, UnitAI._player).
func _um_clear(o, calm: String) -> void:
	_mode(o, calm, {})
	var u := _unit(o)
	if u and not (u.has_meta("hero") and u.controller >= 0):
		u.set_meta("um", {"fight": "none", "susp": false, "corpse": false, "fear": -1})


## A non-calm motivation added: the calm one stays. A unit
## still on its spawn list first gets that list written out (UnitAI.think).
func _um_add(o, add: Dictionary) -> void:
	var u := _unit(o)
	if u == null or u.has_meta("hero") and u.controller >= 0:
		return
	var m: Dictionary = world.ai.mots(u)
	if u.mode == "fear":
		m.fear = 1
	if u.mode in ["aggression", "fear"]:
		u.mode = "standard"
	m.merge(add, true)
	u.set_meta("um", m)


func _mode(o, mode: String, data: Dictionary) -> void:
	var u := _unit(o)
	if u == null or u.has_meta("hero") and u.controller >= 0:
		return
	u.mode = mode
	u.mode_data = data
	u.remove_meta("calm")   # the new motivation starts in state 0
	if mode == "sentry" or mode == "guard":
		# The unit keeps its gait: Walk / Run (builtins 0x40 / 0x41 ->
		# (2 / 3), unit) apply to every later move.
		u.move_to(world.nav.nearest_walkable_for(u, data.point), u.get_meta("script_run", false))


## SleepUntilIdle (builtin 0xb9) sleeps while the unit's AI state (AI +4,
## creature) is not 0. The script commands set it (MoveToPoint
## MoveToObject / RotateTo 1, Attack 3, Cast 4, Follow 6; Idle / UMPlayer clear
## it) and the AI tick ends it: 1 once the
## creature's current and next order are neither a move (1)
## nor a turn (2); 3 once the target is gone or no longer the attack / cast
## target; 4 once no cast order (4 / 5) is left; 6 when the
## target is gone. A unit with no motivation (UMClear / Idle:
## remake mode "none") has it reset on every tick. Computed here when asked.
static func ai_busy(u: GameUnit) -> bool:
	if not is_instance_valid(u) or u.dead:
		return false
	var s := int(u.get_meta("ai_state", 0))
	var busy := false
	if s != 0 and u.mode == "none":
		busy = true   # the reset comes with the next AI tick: one more sleep
		s = 0
	elif s != 0:
		var kinds := [String(u.order.get("type", ""))]
		for o: Dictionary in u.orders:   # the remake queues RotateTo behind clips
			kinds.append(String(o.get("type", "")))
		var t = u.get_meta("ai_target") if u.has_meta("ai_target") else null
		var alive: bool = t is GameUnit and is_instance_valid(t) and not t.dead
		match s:
			1: busy = "move" in kinds or "rotate" in kinds
			3: busy = alive and (u.order.get("target") == t or "cast" in kinds)
			4: busy = "cast" in kinds
			6: busy = alive
	if not busy or s == 0:
		u.remove_meta("ai_state")
		u.remove_meta("ai_target")
	return busy


func _hide(o, hide: bool) -> void:
	var u := _unit(o)
	if u:
		u.hidden = hide
		u.visible = not hide
	elif o is Node3D and is_instance_valid(o):
		o.visible = not hide
		session.broadcast({"t": "hide_obj", "nid": _obj_id(o), "hide": hide})


## Script diplomacy uses -1 war, 0 neutral, 1 alliance; the .mob matrix 2/1/0.
func _diplo_in(v: int) -> int:
	return 2 if v < 0 else (0 if v > 0 else 1)


func _diplo_out(v: int) -> int:
	return -1 if v == 2 else (1 if v == 0 else 0)


func _quest_item_name(v) -> String:
	if v is String:
		return v.to_lower()
	var id := int(_num(v))
	for row in GameData.db.table("quest_items"):
		if int(row.get("script_id", -1)) == id:
			return String(row.name).to_lower()
	return str(id)


## Script QuestComplete (builtin 0x9f, single player): the quest's quests.qdb
## record gives its experience to the party
##  — nothing else: no money, no var, no message (the journal
## line comes from the q.* var the scripts set, see _on_var_changed).
func _quest_complete(q: String) -> void:
	var row := GameData.db.find("quests", q.to_lower())
	var exp := float(row.get("experience", 0.0))
	if exp != 0.0:
		session.give_experience(exp)


func _on_var_changed(key: String) -> void:
	session.mark_dirty()
	if key.begins_with("apartyn") and key.substr(7).is_valid_int():
		session.merc_changed(key.substr(7).to_int(), session.state.get_var(0, key) >= 1.0)
		return
	# Quest variables drive the journal: q.<zone>.<quest>[.<objective>]
	# (1 open, 2 done, 3 failed / withdrawn). Every change of one with three
	# or four parts goes to the HUD (
	#  the field screen's: a text window line and a
	# sound, see GameHUD "journal"); setting it gives no reward (QuestComplete
	# does, _quest_complete).
	if key.begins_with("q."):
		var parts := key.split(".")
		if parts.size() >= 3:
			var q := parts[2]
			var val := session.state.get_var(0, key)
			if parts.size() == 3:
				if is_equal_approx(val, 2.0):
					if int(session.state.quests.get(q, 0)) != 2:
						SmileFaces.party(session)   # remake option "smile_faces": a quest done
					session.state.quests[q] = 2
				elif val >= 3:
					if session.state.quests.get(q, 0) != 2:
						session.state.quests[q] = 3
				elif val >= 1 and not session.state.quests.has(q):
					session.state.quests[q] = 1
			if parts.size() <= 4:
				session.broadcast({"t": "journal", "key": key, "value": val})


func _string_event(s: String) -> void:
	var cmd := s.get_slice(" ", 0).to_lower()
	match cmd:
		"#output", "#otput":
			session.broadcast({"t": "journal"})
		"briefing":
			briefings.play_named(s.get_slice(" ", 1).to_lower(), "")
		"say", "say_block":
			# "say <id> [<unit name>]" → the field screen's
			# (name id (<unit name>) or 0, 0x2a for
			# "say" / 0x2b for "say_block") on every client: the unit speaks
			# its acks.db Scenario line <id> (GameSound.say) and, if found,
			# the text window shows "<name>:" and texts.res "say <id>".
			# The remake's heroes have plain ids, so the host resolves the
			# name as the scripts' other name lookups do ("Hero" = the main
			# hero) and sends the unit's uid.
			var parts := s.split(" ", false)
			var o = _by_name(parts[2]) if parts.size() > 2 else null
			if parts.size() >= 2 and o is GameUnit:
				session.broadcast({"t": "say", "id": parts[1], "uid": o.uid, "block": cmd == "say_block"})
		"tutorial":
			session.broadcast({"t": "tutorial", "id": s.get_slice(" ", 1).to_lower()})
		"endofgame":   # the end-of-game message box (game_hud._show_end_of_game)
			session.broadcast({"t": "end_of_game"})
		_:
			pass


func _add_mob(file: String) -> void:
	var bytes := GameData.read_file("maps/" + file)
	if bytes.is_empty():
		return
	# the original AddMob (builtin 0xa0) ->: a.mob already loaded
	# into the zone (case-insensitive name) is not loaded again; otherwise
	# CWorldServer::LoadMap loads it like a zone's, script too.
	var added: Array = world.get_meta("added_mobs", [])
	for f: String in added:
		if f.to_lower() == file.to_lower():
			return
	var extra := EIMob.load_bytes(bytes)
	added.append(file)
	world.set_meta("added_mobs", added)
	for o: Dictionary in extra.objects:
		if o.kind == "UNIT":
			var u := world.spawn_unit(o)
			if u:
				session.announce_unit(u)
	# Its map objects (chests, levers, ...) on the host; clients place them on
	# the "add_mob" event (Session._on_event applies it on clients only).
	world.add_mob_objects(file)
	session.broadcast({"t": "add_mob", "file": file})
	# The added.mob's own script runs too (the original loads the whole mob):
	# e.g. Zone3ObrVoev.mob completes q23g when the voivode dies, Zone7Zasada
	# q13g, Zone6Flower q24g, Zone8Demon q41g.
	if not extra.script_text.is_empty():
		var src := "m:" + file.to_lower()
		world_bodies[src] = _merge_script(extra.script_text, file.get_basename().to_lower())
		_start_world(world_bodies[src], src)


# ================================================================ mercenary briefings

## Home village of mercenary N (the original pointer table): only there
## does a hired mercenary offer the "dismiss" conversation.
const MERC_HOME := ["", "bz1g", "bz1g", "bz2g", "bz6g", "bz8k", "bz8k", "bz14h", "bz14h", "bz9k", "bz14h"]


## the original (script builtin RecalcMercBriefings, also run when
## a party is deployed, and after every conversation
## ): the conversations of the ten mercenaries "merc<i>" are
## engine-managed GS vars b.merc<i>.n<k>_<i>:
##   n8  "not yet" (set to 1 by the zone scripts, cleared when told),
##   n1  hire (amerc_<i> = 1), n3 hire again (amerc_<i> = 2, after a dismissal),
##   n2  dismiss (hired, in the home village), n9 party full (2 mercenaries),
##   n10 farewell (set by scripts; clears everything), n11 nothing to say.
## amerc_<i>: 0 not available, 1 may be hired (set by scripts), 2 was hired.
## For each player: its own party's living mercenaries are counted and the
## vars written into its own store (CampaignState.set_pvar); a mercenary is
## "hired" for the player whose party it is in.
func recalc_merc_briefings() -> void:
	var st := session.state
	var zone := String(world.zone.get("id", "")).to_lower()
	var idxs := []
	for pl in session.players.values():
		if not int(pl.index) in idxs:
			idxs.append(int(pl.index))
	if idxs.is_empty():
		idxs.append(0)
	for p: int in idxs:
		# The original counts the party's living members besides the hero.
		var hired := 0
		for n in st.mercs:
			if _merc_of(int(n), p) and st.get_var(0, "adeadn%d" % int(n)) < 1.0:
				hired += 1
		for i in range(1, 11):
			var b := func(k: int) -> String: return "b.merc%d.n%d_%d" % [i, k, i]
			var getv := func(k: String) -> float: return st.get_pvar(p, k)
			var setv := func(k: String, v: float) -> void: st.set_pvar(p, k, v)
			var amerc := "amerc_%d" % i
			setv.call(b.call(11), 0.0)
			if _merc_of(i, p):
				setv.call(b.call(8), 0.0)
				setv.call(b.call(1), 0.0)
				setv.call(b.call(3), 0.0)
				if getv.call(b.call(10)) == 0.0:
					setv.call(b.call(9), 0.0)
					setv.call(b.call(2), 1.0 if zone == MERC_HOME[i] else 0.0)
				else:
					setv.call(b.call(2), 0.0)
					setv.call(b.call(9), 0.0)
			elif getv.call(b.call(10)) != 0.0:
				for k in [8, 1, 2, 3, 9, 10]:
					setv.call(b.call(k), 0.0)
				setv.call(amerc, 0.0)
			elif getv.call(amerc) != 0.0:
				if getv.call(b.call(8)) == 1.0:
					for k in [1, 2, 3, 9, 10]:
						setv.call(b.call(k), 0.0)
				elif hired < 2:
					var first: bool = getv.call(amerc) == 1.0
					setv.call(b.call(1), 1.0 if first else 0.0)
					setv.call(b.call(3), 0.0 if first else 1.0)
					setv.call(b.call(8), 0.0)
					setv.call(b.call(2), 0.0)
					setv.call(b.call(9), 0.0)
				else:
					for k in [1, 3, 8, 2]:
						setv.call(b.call(k), 0.0)
					setv.call(b.call(9), 1.0)
			elif getv.call(b.call(8)) != 1.0:
				setv.call(b.call(11), 1.0)


## Whether mercenary `n` is in player `p`'s party.
func _merc_of(n: int, p: int) -> bool:
	var m = session.state.mercs.get(n)
	return m != null and int((m as Dictionary).get("controller", 0)) == p


## the original, run before a finished conversation's variable is
## set to 2: n8 is cleared, n1 / n3 hire mercenary i (amerc_<i> = 2, unit
## added to the party), n2 / n10 remove it from the party; then
## RecalcMercBriefings. `player` finished it: the vars are its own and a
## hired mercenary joins its party (runs on that player).
func merc_briefing_done(var_name: String, player := 0) -> void:
	var key := var_name.to_lower()
	var re := RegEx.create_from_string("^b\\.merc(\\d+)\\.n(\\d+)_(\\d+)$")
	var m := re.search(key)
	if m and m.get_string(1) == m.get_string(3):
		var i := m.get_string(1).to_int()
		match m.get_string(2).to_int():
			8:
				session.state.set_pvar(player, key, 0.0)
			1, 3:
				session.state.set_pvar(player, "amerc_%d" % i, 2.0)
				session.merc_changed(i, true, player)
			2, 10:
				session.merc_changed(i, false)
	recalc_merc_briefings()


# ================================================================ persistence

## the original's world save writes the whole script machine (
## ): the globals, the areas and every thread of the list
## (VM, count, one record each: its script, locals
## and run state) — the level's WorldScript too while it still runs, e.g.
## zone1's sleeping in its first Sleep(2) when the zone autosave is made. So
## each thread is kept whole: its frames (the running block, or the
## WorldScript body by source, and the For loops inside it with their items
## and position), what it waits for (Sleep time left, SleepUntil condition,
## SleepUntilIdle unit) and the next condition poll. "b" / "i" (the running
## block and its statement) stay for older builds' saves.
func save_state() -> Dictionary:
	var g := {}
	for k in globals:
		g[k] = _ser(globals[k])
	var insts := []
	for inst: Instance in instances:
		var top: Dictionary = inst.frames[0] if not inst.frames.is_empty() else {}
		var loc := {}
		for k in inst.locals:
			loc[k] = _ser(inst.locals[k])
		var fr := []
		for f: Dictionary in inst.frames:
			var e := {"i": int(f.i)}
			if f.has("items"):
				e.v = f.for_var
				e.it = _ser(f.items)
				e.k = int(f.k)
			fr.append(e)
		var d := {"s": inst.sname, "l": loc, "k": inst.killed, "b": inst.block_index if not top.is_empty() else -1,
			"i": top.get("i", 0), "w": maxf(0.0, inst.wait_until - time), "f": fr, "p": maxf(0.0, inst.poll - time)}
		if inst.sname == "WorldScript":
			d.src = inst.src
		if not inst.wait_cond.is_empty():
			d.wc = inst.wait_cond.duplicate(true)
		if inst.wait_unit != null and is_instance_valid(inst.wait_unit):
			d.wu = _ser(inst.wait_unit)
		insts.append(d)
	return {"globals": g, "instances": insts, "areas": areas, "alarms": _alarm_save(), "qobjs": qobjs, "sciences": sciences,
		"fx_auto": _fx_auto,   # the replayed CreateFXSource(-1) sources keep their ids (zone "fx")
		"quest": String(world.get_meta("quest_mob", "")) if world.has_meta("quest_mob") else ""}


func _alarm_save() -> Array:
	var out := []
	for i in 5:
		var a: Dictionary = world.ai.alarm(i)
		out.append([a.on, a.time, a.pos.x, a.pos.y])
	return out


## Raised alarms are raised again in their order, which also puts the units
## back on the alarm descriptors. Older saves (a dict of alarm ids) carry no
## position.
func _alarm_load(al) -> void:
	var raised := []
	if al is Array:
		for i in al.size():
			if al[i] is Array and bool(al[i][0]):
				raised.append([int(al[i][1]), i, Vector2(float(al[i][2]), float(al[i][3]))])
	elif al is Dictionary:
		for k in al:
			raised.append([0, int(k), Vector2.ZERO])
	raised.sort()
	for r: Array in raised:
		world.ai.invoke_alarm(int(r[1]), r[2], false)
		var t: Array = world.get_meta("alarms", [])
		if int(r[1]) < t.size():
			t[int(r[1])].time = int(r[0])


func _restore(d: Dictionary) -> void:
	for k in d.get("globals", {}):
		globals[k] = _deser(d.globals[k])
	areas = d.get("areas", {})
	_alarm_load(d.get("alarms", []))
	qobjs = d.get("qobjs", {})
	sciences = d.get("sciences", {})
	_fx_auto = mini(_fx_auto, int(d.get("fx_auto", -1)))
	for nid in sciences:
		if world.levers.has(int(nid)):
			world.levers[int(nid)].science = sciences[nid]
	var legacy_world := 0
	for s: Dictionary in d.get("instances", []):
		var inst := Instance.new()
		inst.sname = s.s
		var body: Array = []
		if s.s == "WorldScript":
			# Older saves name no source: their first WorldScript is the zone's.
			var src := String(s.get("src", "" if legacy_world == 0 else "?"))
			if not s.has("src"):
				legacy_world += 1
			if not world_bodies.has(src):
				continue
			inst.src = src
			body = world_bodies[src]
		else:
			var def: Dictionary = ast.scripts.get(s.s, {})
			if def.is_empty():
				continue
			inst.blocks = def.blocks
			if int(s.b) >= 0 and int(s.b) < def.blocks.size():
				inst.block_index = s.b
				body = def.blocks[s.b].body
		inst.killed = s.k
		for k in s.l:
			inst.locals[k] = _deser(s.l[k])
		if not body.is_empty():
			inst.frames = _restore_frames(body, s)
		if s.s == "WorldScript" and inst.frames.is_empty():
			continue   # a finished one is gone (tick drops it)
		inst.wait_until = time + float(s.get("w", 0.0))
		inst.poll = time + float(s.get("p", 0.0))
		var wc = s.get("wc", [])
		if wc is Array and not wc.is_empty():
			inst.wait_cond = wc
		if s.has("wu"):
			var wu = _deser(s.wu)
			inst.wait_unit = wu if wu is GameUnit else null
		instances.append(inst)


## A saved thread's frames: the first runs `body`, each further one the For
## loop of the statement before its parent's position. Frames that no longer
## fit (another build's script) are dropped from there on.
func _restore_frames(body: Array, s: Dictionary) -> Array:
	var saved = s.get("f")
	if not saved is Array or saved.is_empty():
		return [{"body": body, "i": int(s.get("i", 0))}]
	var out := []
	var cur := body
	for e in saved:
		if not e is Dictionary:
			break
		if not out.is_empty():
			var parent: Dictionary = out[-1]
			var at := int(parent.i) - 1
			if at < 0 or at >= parent.body.size() or parent.body[at][0] != P.S_FOR:
				break
			cur = parent.body[at][3]
		var f := {"body": cur, "i": clampi(int(e.get("i", 0)), 0, cur.size())}
		if e.has("it"):
			# Kept whole (a unit gone since is null): k counts in this list.
			var items: Array = _deser(e.it) if e.it is Array else []
			var k := int(e.get("k", 0))
			if k >= items.size():
				break
			f.for_var = String(e.get("v", ""))
			f.items = items
			f.k = k
		out.append(f)
	return out


func _ser(v):
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return null   # a unit the script removed (RemoveUnitFromServer)
	if v is GameUnit:
		var key := _hero_key(v)
		return {"u": v.uid, "h": key} if not key.is_empty() else {"u": v.uid}
	if v is Node3D:
		return {"o": _obj_id(v)} if is_instance_valid(v) else null
	if v is Array:
		return v.map(_ser)
	return v


func _deser(v):
	if v is Dictionary:
		if v.has("h"):
			var hu := _hero_by_key(v.h)
			if hu:
				return hu
		if v.has("u"):   # a looted corpse taken off the world stays known (WasLooted)
			return world.units.get(int(v.u), world.looted.get(int(v.u)))
		if v.has("o"):
			return world.objects.get(int(v.o))
	if v is Array:
		return v.map(_deser)
	return v


## A hero's unit is made anew with a fresh id at every deployment
## (Session._deploy_parties, in the order of the players present), while
## the original keeps every unit's id in the save: a script value
## naming a hero (e.g. zone1's VCheck#0#1 `this`, one thread per hero) keeps
## the hero by [player, roster index] so a load finds the same hero again.
## Mercenaries keep their name's id (Session._spawn_merc) and need none.
func _hero_key(u: GameUnit) -> Array:
	if not u.has_meta("hero") or u.get_meta("hero").has("merc") or session == null or session.state == null:
		return []
	var roster: Array = session.state.heroes.get(u.controller, [])
	for i in roster.size():
		if is_same(roster[i], u.get_meta("hero")):
			return [u.controller, i]
	return []


func _hero_by_key(key) -> GameUnit:
	if not key is Array or key.size() < 2 or session == null or session.state == null:
		return null
	var roster: Array = session.state.heroes.get(int(key[0]), [])
	if int(key[1]) < 0 or int(key[1]) >= roster.size():
		return null
	for u: GameUnit in world.units.values():
		if u.controller == int(key[0]) and u.has_meta("hero") and is_same(u.get_meta("hero"), roster[int(key[1])]):
			return u
	return null


# ================================================================ co-op: story events once per world

## The campaign scripts check many story triggers once per party unit: the
## level editor's per-unit checks compile to `For( VSS#i#val, Heroes ) (
## VCheck#..( VSS#i#val ) )`, one thread per unit with `this` = that unit, each
## ending itself with KillScript when it fires (zone1 VCheck#0#1: a unit near
## DgunDragon → VTriger#0#15 → #44 → the villagers' flight). the original fills
## Heroes with every unit of the party it deploys (appends
## "AddObject(Heroes, GetObjectByID(%d))" per unit, resets
## the group) and a script call always adds a new thread (case 8
## no check for a running copy), so nothing stops a second
## unit from firing the same trigger. The campaign was single player: one
## player's party, which usually arrives together. The original multiplayer
## maps (*-lmp.mob, the z*q* quest maps) have no such per-unit checks.
## Remake co-op: when a one-shot check (every block ends the thread with
## KillScript) fires for a hero of one player, the idle copies of that check
## for the other players' units end too — a story event (flight, talk,
## cutscene, quest step) happens once per world. Checks whose trigger acts on
## the unit itself (`this` used in an action: InflictDamage traps, SetCP
## teleports, fireballs, Follow, a global set to it, further checks on it)
## stay per unit, and the same player's units keep the original behaviour, so
## single player is unchanged.
var _world_event_memo := {}


func _once_per_world(inst: Instance) -> void:
	var def: Dictionary = ast.scripts.get(inst.sname, {})
	var params: Array = def.get("params", [])
	if params.is_empty() or not inst.locals.has(params[0]):
		return
	var me = inst.locals[params[0]]
	if typeof(me) != TYPE_OBJECT or not is_instance_valid(me) or not me is GameUnit or not me.has_meta("hero"):
		return
	if not _world_event(inst.sname):
		return
	for o: Instance in instances:
		if o == inst or o.sname != inst.sname or o.killed or not o.frames.is_empty():
			continue
		var other = o.locals.get(params[0])
		if typeof(other) == TYPE_OBJECT and is_instance_valid(other) and other is GameUnit \
				and other.has_meta("hero") and other.controller != me.controller:
			o.killed = true   # idle: dropped at the end of this tick, never runs


## Script `sname` is a one-shot check whose trigger does not act on its unit.
func _world_event(sname: String) -> bool:
	if _world_event_memo.has(sname):
		return _world_event_memo[sname]
	var def: Dictionary = ast.scripts.get(sname, {})
	var blocks: Array = def.get("blocks", [])
	var params: Array = def.get("params", [])
	var ok := not blocks.is_empty() and not params.is_empty()
	for b: Dictionary in blocks:
		if ok and not b.body.any(func(st: Array): return st[0] == P.S_CALL and st[1] == "KillScript"):
			ok = false
	var seen := {}
	for b: Dictionary in blocks:
		if ok and _acts_on(b.body, String(params[0]), seen):
			ok = false
	_world_event_memo[sname] = ok
	return ok


## Statements `body` use variable `v` in an action (scripts called with it are followed).
func _acts_on(body: Array, v: String, seen: Dictionary) -> bool:
	for st: Array in body:
		match st[0]:
			P.S_SET:
				if _refs(st[2], v):
					return true
			P.S_FOR:
				if _refs(st[2], v) or _acts_on(st[3], v, seen):
					return true
			P.S_CALL:
				var called: Dictionary = ast.scripts.get(st[1], {})
				for k in (st[2] as Array).size():
					var a: Array = st[2][k]
					if called.is_empty() or not (a[0] == P.N_VAR and a[1] == v):
						if _refs(a, v):
							return true
						continue
					var cp: Array = called.params
					if k >= cp.size():
						continue
					var key := "%s#%s" % [st[1], cp[k]]
					if seen.has(key):
						continue
					seen[key] = true
					for b: Dictionary in called.blocks:
						if b.conds.any(func(c): return _refs(c, cp[k])) or _acts_on(b.body, cp[k], seen):
							return true
	return false


func _refs(e: Array, v: String) -> bool:
	match e[0]:
		P.N_VAR:
			return e[1] == v
		P.N_CALL:
			for a: Array in e[2]:
				if _refs(a, v):
					return true
	return false


# ================================================================ side-quest objectives

func _check_quest_objectives() -> void:
	for q: String in qobjs.keys():
		var d: Dictionary = qobjs[q]
		if d.get("finished", false) or d.objs.is_empty() or q == _q_recording:
			continue
		d.defined = true
		# QFinish compiles the recorded objectives into a chain
		# of scripts Su0 .. SuN: Su<i> waits for objective i's condition, then
		# runs Su<i+1>, sets GS var q.<id>.<id>.<i+1> = 2 and (but for the last)
		# q.<id>.<id>.<i+2> = 1; SuN: QuestComplete(0, id), q.<id>.<id> = 2.
		# So the objectives are met one after the other, in order.
		var cur := int(d.get("cur", 0))
		while cur < d.objs.size() and d.objs[cur][3]:   # saves from before the chain
			cur += 1
		if cur < d.objs.size() and _objective_met(d.objs[cur], d):
			d.objs[cur][3] = true
			d.cur = cur + 1
			var base := "q.%s.%s" % [q, q]
			_set_quest_var("%s.%d" % [base, cur + 1], 2.0)
			if cur + 1 < d.objs.size():
				_set_quest_var("%s.%d" % [base, cur + 2], 1.0)
		elif cur >= d.objs.size():
			d.finished = true
			SideQuests.finish(session, q)
			_set_quest_var("q.%s.%s" % [q, q], 2.0)


func _set_quest_var(key: String, val: float) -> void:
	if session.state.get_var(0, key) != val:
		session.state.set_var(0, key, val)
		_on_var_changed(key)


## The conditions QFinish writes (the original strings..):
## QObjArea "any( i, Heroes, IsInArea( %f, GetX(i), GetY(i) ) )", QObjSeeObject
## "any( i, Heroes, IsLess( DistanceUnitUnit( i, %s ), 7 ) )", QObjSeeUnit
## "IsUnitVisible( %s )", QObjKillUnit "Not( IsAlive( %s ) )", QObjKillGroup
## "Not( any( i, %s, IsAlive(i) ) )", QObjUse "IsEqual( GetLeverState(%s), %f )",
## QObjGetItem "HaveItem( 0, %f )".
func _objective_met(o: Array, d: Dictionary) -> bool:
	var target = _objective_target(String(o[1]))
	match String(o[0]):
		"QObjArea":
			var id := int(String(o[1]).to_float())
			for h: GameUnit in heroes():
				for s in areas.get(id, []):
					if (s is Rect2 and s.has_point(h.pos)) or (s is Vector3 and h.pos.distance_to(Vector2(s.x, s.y)) <= s.z):
						return true
			return false
		"QObjSeeObject":
			if target == null:
				return false   # DistanceUnitUnit with no unit: 99999
			var p: Vector2 = target.pos if target is GameUnit else _obj_pos(target)
			for h: GameUnit in heroes():
				if h.pos.distance_to(p) < 7.0:
					return true
			return false
		"QObjSeeUnit":
			return target != null and _player_visible().has(target)
		"QObjKillUnit":
			return target == null or (target is GameUnit and target.dead)
		"QObjKillGroup":
			for u in _group(globals.get(String(o[1]), [])):
				if u is GameUnit and is_instance_valid(u) and not u.dead:
					return false
			return true
		"QObjGetItem":
			return session.state.quest_items.has(_quest_item_name(String(o[1]).to_float()))
		"QObjUse":
			var id := _obj_id(target) if target != null else -1
			return world.levers.has(id) and int(world.levers[id].state) == int(o[2])
	return true


## "GetObject(1000086)" -> the unit or map object with that id.
func _objective_target(s: String):
	var n := s.get_slice("(", 1).get_slice(")", 0).strip_edges()
	if not n.is_valid_int():
		return null
	return _get_object(n.to_int())


func _obj_pos(o) -> Vector2:
	if o is Node3D and is_instance_valid(o):
		var p: Vector3 = (o as Node3D).global_position
		return Vector2(p.x, -p.z)
	return Vector2.INF
