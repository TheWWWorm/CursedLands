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

const POLL := 0.1          # seconds between condition checks
const SLEEP_UNIT := 0.1    # Sleep() argument unit (1/10 s, the engine tick)
const MAX_STEPS := 2000    # statements per thread per tick (runaway guard)
const P = preload("res://src/game/script/script_parser.gd")

var world: GameWorld
var session: Session
var ast: ScriptParser
var briefings: Briefings
var globals := {}
var instances: Array = []
var areas := {}            # area id -> Array of Rect2 / Vector3(x, y, r)
var blocked := {}          # uid -> true (BlockUnit)
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
	if not restored.is_empty():
		for file: String in w.get_meta("added_mobs", []):
			var extra := EIMob.load_bytes(GameData.read_file("maps/" + file))
			if extra and not extra.script_text.is_empty():
				vm._merge_script(extra.script_text, file.get_basename().to_lower())
	if restored.is_empty():
		vm._start_world(vm.ast.world)
	else:
		vm._restore(restored)
	if not quest_world.is_empty() and String(restored.get("quest", "")) != String(w.get_meta("quest_mob", "")):
		vm._start_world(quest_world)
	vm.recalc_merc_briefings()   #  (party deployed)
	return vm


func _start_world(body: Array) -> void:
	var inst := Instance.new()
	inst.sname = "WorldScript"
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
	time += dt
	if not time_fixed:
		session.state.advance_hours(dt / 60.0)
	_refresh_heroes()
	_check_interactions()
	if not qobjs.is_empty() and time >= _q_check:
		_q_check = time + 0.5
		_check_quest_objectives()
	briefings.tick()
	if briefings.active:
		return   # the world is paused during conversations
	# Only the threads that existed when the tick began run in it: a thread
	# started during the tick (a script call, `spawn`) first runs in the next
	# one. Approx.: the original's thread list order is not traced, but running new
	# threads at once never ends in scripts that restart each other through an
	# always-true block (bz8k VCheck#0#108 -> VTriger#0#138 -> VCheck#0#108 at
	# night), which the original plays through.
	for inst: Instance in instances.duplicate():
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
		if is_instance_valid(inst.wait_unit) and inst.wait_unit is GameUnit and not inst.wait_unit.is_idle() \
				and not inst.wait_unit.dead:
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
			if u and not u.is_idle():
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
		"PlayerSee": return _sees(heroes())
		"GetUnitOfPlayer":
			var hs := heroes()
			var k := int(_num(v[1]))
			return hs[k] if k < hs.size() else null
		"GetLeader":
			var hs := heroes()
			return hs[0] if not hs.is_empty() else null
		"GetMercsNumber": return float(maxi(0, heroes().size() - _player_count()))
		# ---- unit queries
		"GetX": return _xy(v[0]).x
		"GetY": return _xy(v[0]).y
		"GetZ":
			var p := _xy(v[0])
			return world.ground_at(p.x, p.y)
		"GetFutureX", "GetFutureY":
			var u := _unit(v[0])
			var p := _xy(v[0])
			if u and not u.path.is_empty():
				p += (u.path[0] - u.pos).normalized() * u.speed() * _num(v[1])
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
		"IsPlayerInDanger": return 1.0 if _in_danger() else 0.0
		"WasLooted":   # builtin 0xe3: the object's flag +8 &
			var u = v[0]
			if typeof(u) == TYPE_OBJECT and not is_instance_valid(u):
				return 0.0
			return 1.0 if u is GameUnit and u.get_meta("looted", false) else 0.0
		"IsUnitBlocked": return 1.0 if blocked.has(_obj_id(v[0])) else 0.0
		# ---- unit control
		"Walk", "Run":
			var u := _unit(v[0])
			if u:
				u.set_meta("script_run", name == "Run")
		"SetCP", "MoveToPoint":
			var u := _unit(v[0])
			if u and not u.dead:
				var to := world.nav.nearest_walkable(Vector2(_num(v[1]), _num(v[2])))
				u.move_to(to, u.get_meta("script_run", false) or name == "MoveToPoint" and u.running, name == "SetCP")
				u.mode_data["point"] = to
		"SetCPFast":
			var u := _unit(v[0])
			if u:
				u.command({"type": "wait", "t": 0.0})
				u.pos = Vector2(_num(v[1]), _num(v[2]))
				u.mode_data["point"] = u.pos
		"Idle":
			var u := _unit(v[0])
			if u:
				u.command({"type": "wait", "t": randf_range(2.0, 5.0)}, true)
		"RotateTo":
			var u := _unit(v[0])
			if u:
				var d := Vector2(_num(v[1]), _num(v[2])) - u.pos
				u.command({"type": "rotate", "angle": atan2(d.y, d.x)}, true)
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
		"UMClear":
			var u := _unit(v[0])
			if u:
				u.command({"type": "wait", "t": 0.0})
				u.orders.clear()
		"UMStandard": _mode(v[0], "standard", {})
		"UMAggression", "UMRevenge": _mode(v[0], "aggression", {})
		"UMFear": _mode(v[0], "fear" if n < 2 or _truthy(v[1]) else "standard", {})
		"UMSentry", "Sentry": _mode(v[0], "sentry", {"point": Vector2(_num(v[1]), _num(v[2]))})
		# Builtins 0x26 UMGuard / 0x33 Guard (unit, x, y, radius)
		#  with stay −1; 0x27 UMGuardEx (unit, x, y, radius, stay).
		# A negative radius / stay takes ai.reg GuardRadius / GuardStayTime.
		"UMGuard", "Guard", "UMGuardEx": _mode(v[0], "guard", {"point": Vector2(_num(v[1]), _num(v[2])),
			"radius": _num(v[3]) if n > 3 else -1.0, "stay": _num(v[4]) if name == "UMGuardEx" and n > 4 else -1.0})
		"UMFollow", "Follow": _mode(v[0], "follow", {"target": _unit(v[1])})
		"UMPlayer":
			var u := _unit(v[0])
			if u and not u.has_meta("hero"):
				u.mode = "standard"
		"SetPlayer":
			var u := _unit(v[0])
			if u:
				u.faction = int(_num(v[1]))
		"BlockUnit":
			var id := _obj_id(v[0])
			if _truthy(v[1]):
				blocked[id] = true
				var u := _unit(v[0])
				if u:
					u.command({"type": "wait", "t": 0.0})
			else:
				blocked.erase(id)
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
			if SideQuests.get_quest(str(v[1])).is_empty():
				_quest_complete(str(v[1]))
			else:
				SideQuests.finish(session, str(v[1]))
			# Single player: flags every trader for a restock.
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
		"GiveQuestItem", "GiveItem":
			session.state.add_item(str(v[1]))
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
			session.state.money += int(_num(v[1]))
			session.notify_got(-1, [], int(_num(v[1])))
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
		"LeaveToZone":
			_pending_zone = [str(v[1]).to_lower(), int(_num(v[2]))]
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
		elif u.pos.distance_to(_xy(t)) < 3.0:
			u.remove_meta("interact")
			if it.size() > 2 and it[2] == "steal":
				if t is GameUnit and not t.dead:
					session.coop.with_purse(u.controller, session.steal.bind(u, t))   # a joiner's own bag
			elif t is GameUnit and Session.lootable(t) and world.units.has(t.uid):
				session.coop.with_purse(u.controller, session.take_loot.bind(u, t))
			elif not (t is GameUnit):
				var nid := _obj_id(t)
				if world.lever_sys.usable(nid):
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
			else:
				briefings.interact(u, t, it[1])


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
	for w in watchers:
		if w == null or not is_instance_valid(w) or w.dead:
			continue
		var r := float(w.stats.get("sight", 15.0))
		for u in world.units_near(w.pos, r):
			if u != w and not out.has(u) and world.ai.can_notice(w, u, r):
				out.append(u)
	return out


func _in_danger() -> bool:
	for h in heroes():
		for u in world.units_near(h.pos, 15.0):
			if not u.dead and world.is_enemy(u, h) and u.order.get("type", "") == "attack":
				return true
	return false


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
		u.move_to(world.nav.nearest_walkable(data.point), u.get_meta("script_run", false))


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
			var id := s.get_slice(" ", 1).to_lower()
			var who := s.get_slice(" ", 2)
			var text := GameData.text("say " + id)
			if text:
				session.broadcast({"t": "say", "who": who, "text": text, "voice": "say\\%s" % id})
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
		_start_world(_merge_script(extra.script_text, file.get_basename().to_lower()))


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
		insts.append({"s": inst.sname, "l": loc, "k": inst.killed, "b": inst.block_index if not top.is_empty() else -1,
			"i": top.get("i", 0), "w": maxf(0.0, inst.wait_until - time)})
	return {"globals": g, "instances": insts, "areas": areas, "alarms": _alarm_save(), "qobjs": qobjs, "sciences": sciences,
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
	for nid in sciences:
		if world.levers.has(int(nid)):
			world.levers[int(nid)].science = sciences[nid]
	for s: Dictionary in d.get("instances", []):
		if s.s == "WorldScript":
			continue
		var def: Dictionary = ast.scripts.get(s.s, {})
		if def.is_empty():
			continue
		var inst := Instance.new()
		inst.sname = s.s
		inst.blocks = def.blocks
		inst.killed = s.k
		for k in s.l:
			inst.locals[k] = _deser(s.l[k])
		if int(s.b) >= 0 and int(s.b) < def.blocks.size():
			inst.block_index = s.b
			inst.frames = [{"body": def.blocks[s.b].body, "i": s.i}]
			inst.wait_until = time + float(s.w)
		instances.append(inst)


func _ser(v):
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return null   # a unit the script removed (RemoveUnitFromServer)
	if v is GameUnit:
		return {"u": v.uid} if is_instance_valid(v) else null
	if v is Node3D:
		return {"o": _obj_id(v)} if is_instance_valid(v) else null
	if v is Array:
		return v.map(_ser)
	return v


func _deser(v):
	if v is Dictionary:
		if v.has("u"):   # a looted corpse taken off the world stays known (WasLooted)
			return world.units.get(int(v.u), world.looted.get(int(v.u)))
		if v.has("o"):
			return world.objects.get(int(v.o))
	if v is Array:
		return v.map(_deser)
	return v


# ================================================================ side-quest objectives

func _check_quest_objectives() -> void:
	for q: String in qobjs.keys():
		var d: Dictionary = qobjs[q]
		if d.get("finished", false) or d.objs.is_empty() or q == _q_recording:
			continue
		d.defined = true
		var all_done := true
		for o: Array in d.objs:
			if not o[3]:
				o[3] = _objective_met(o, d)
			all_done = all_done and o[3]
		if all_done:
			d.finished = true
			SideQuests.finish(session, q)


func _objective_met(o: Array, d: Dictionary) -> bool:
	var target = _objective_target(String(o[1]))
	match String(o[0]):
		"QObjArea":
			return true   # meaning unknown; the other objectives carry the quest
		"QObjSeeUnit", "QObjSeeObject":
			if target == null:
				return true
			var p: Vector2 = target.pos if target is GameUnit else _obj_pos(target)
			for h: GameUnit in heroes():
				if h.pos.distance_to(p) < 14.0:
					return true
			return false
		"QObjKillUnit":
			return target == null or (target is GameUnit and target.dead)
		"QObjKillGroup":
			for u in _group(globals.get(String(o[1]), [])):
				if u is GameUnit and is_instance_valid(u) and not u.dead:
					return false
			return true
		"QObjGetItem":
			return session.state.quest_items.size() > int(d.get("items", 0))
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
