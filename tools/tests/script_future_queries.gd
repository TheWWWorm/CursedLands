extends Node
## Original dispatcher replay plus actual remake movement after each query.
## Routes/node speeds are supplied fixtures; collision and full path search
## are not compared to the original by this suite.
const P := preload("res://src/game/script/script_parser.gd")

class QueryObject extends GameUnit:
	var requested: Array[int] = []
	var predicted := Vector2.ZERO
	func future_pos(ticks: int) -> Vector2:
		requested.append(ticks)
		return predicted

class TrapVM extends ScriptVM:
	var casts: Array = []
	var damage: Array = []
	func _call(name: String, args: Array, inst: Instance):
		# Observe the spell/damage boundary so the actor can then execute its
		# predicted movement. Script bodies and nested queries execute normally.
		if name == "CastSpellPoint": casts.append(_args(args,inst)); return null
		if name == "InflictDamage": damage.append(_args(args,inst)); return null
		return super._call(name,args,inst)

var checks := 0
var failures: Array = []
var observations: Array = []
var w: GameWorld
var vm: ScriptVM
var s: Session

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 15: printerr("FAIL ",label)

func query(target: Object, delay: float, axis: int) -> float:
	vm.globals.target = target
	return vm._eval([P.N_CALL,"GetFutureX" if axis == 0 else "GetFutureY",
		[[P.N_VAR,"target"],[P.N_NUM,delay]]],ScriptVM.Instance.new())

func dispatcher() -> void:
	var path: String = get_script().resource_path.get_base_dir()+"/fixtures/original_future_queries.json"
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var campaign := "lost_in_astral" if GameData.campaign_id == CampaignProfile.ASTRAL else "original"
	var u := QueryObject.new(); u.world = w; u.pos = Vector2(9,11)
	for index in fixture.campaigns[campaign].rows.size():
		var row: Dictionary = fixture.campaigns[campaign].rows[index]
		var input: Dictionary = row.input
		w.time = float(input.now)*GameUnit.TICK
		u.requested.clear(); u.predicted = Vector2(input.point[0],input.point[1])
		var value := query(u if input.present else null,float(input.delay),int(input.axis))
		var expected: Array[int] = []
		for call: Dictionary in row.calls:
			expected.append(int(call.absolute_tick)-int(input.now))
			check(call.correct_object,"native fixture selects the supplied object")
		check(u.requested == expected,"original prediction dispatch / "+str(index))
		check(value == float(row.value),"original result axis / "+str(index))
	# The console accepts the old one-argument shorthand; omitted delay is 0.
	w.time = 10*GameUnit.TICK; vm.globals.target = u
	for axis in 2:
		u.requested.clear()
		var value: float = vm._eval([P.N_CALL,"GetFutureX" if axis == 0 else "GetFutureY",[[P.N_VAR,"target"]]],ScriptVM.Instance.new())
		check(value == u.predicted[axis] and u.requested == [0],"omitted console delay queries the current position")
	var obj := Node3D.new(); obj.set_meta("ei",{"position":Vector3(83.5,-11.25,4)})
	for delay in [0,3,60]:
		check(query(obj,delay,0)==83.5 and query(obj,delay,1)==-11.25,"stationary map object retains its position")
	obj.free(); u.free()

func moving(route: String, slow: bool, heading: float) -> GameUnit:
	var u := GameUnit.new(); u.world = w; u.controller = -1
	u.race = {"speeds":[0.4,0.16,0.1,0.05]}
	u.proto = {"tuning_move":0.1 if slow else 1.0}
	u.running = true; u.facing = heading
	var cells: Array[Vector2i] = []
	var values := PackedInt32Array()
	var cell := Vector2i(10,10)
	for i in 65 if route == "long" else 15:
		cells.append(cell)
		values.append([512,256,128,768][(i/4)%4] if route == "terrain" else 512)
		cell += Vector2i(1,0) if route == "straight" or i%12<4 else Vector2i(1,1) if i%12<8 else Vector2i(0,1)
	u.pos = NavGrid.center(cells[0])
	for c: Vector2i in cells: u.path.append(NavGrid.center(c))
	u.order = {"type":"move","to":u.path[-1]}
	u._planned_motion = {"cells":cells,"values":values,"path":u.path,"from":u.pos}
	return u

func actual_motion() -> void:
	for route: String in ["straight","curve","terrain","long"]:
		for slow in [false,true]:
			for heading: float in [0,PI]:
				for elapsed in [0,7,31]:
					for delay in [0,1,3,10,30,60,200]:
						var u := moving(route,slow,heading)
						w.time = 100*GameUnit.TICK
						for tick in elapsed:
							u._step_along_path(GameUnit.TICK); w.time += GameUnit.TICK
						var before := u.pos; var facing := u.facing; var path := u.path.duplicate(); var clock := u._motion_tick
						var predicted := Vector2(query(u,delay,0),query(u,delay,1))
						var label := "%s/slow%s/heading%s/elapsed%d/delay%d"%[route,slow,heading,elapsed,delay]
						check(u.pos==before and u.facing==facing and u.path==path and u._motion_tick==clock,"query does not advance movement / "+label)
						for tick in delay: u._step_along_path(GameUnit.TICK)
						var error := predicted.distance_to(u.pos)
						check(error<0.00002,"prediction matches subsequently executed movement / "+label)
						observations.append({"case":label,"predicted":[predicted.x,predicted.y],"arrived":[u.pos.x,u.pos.y],"error":error})
						u.free()

func authored_traps() -> void:
	if GameData.campaign_id == CampaignProfile.ASTRAL: return
	var mob := EIMob.load_bytes(GameData.read_file("maps/zone19.mob"))
	var parsed := ScriptParser.parse(mob.script_text)
	var names: Array = parsed.scripts.keys().filter(func(key): return str(parsed.scripts[key]).contains("GetFutureX"))
	check(parsed.errors.is_empty() and names.size()==11,"installed zone19 supplies eleven future-position trap bodies")
	for name: String in names:
		for elapsed in [0,7]:
			for slow in [false,true]:
				var u := moving("terrain",slow,PI)
				for tick in elapsed: u._step_along_path(GameUnit.TICK)
				w.time = (101+elapsed)*GameUnit.TICK
				var script := TrapVM.new(); script.world = w; script.session = s; script.ast = parsed
				script.spawn(name,[u]); script._run(script.instances[-1])
				check(script.casts.size()==1,"authored trap casts once / "+name)
				check(script.damage.size()==1 and script.damage[0]==[u,1000.0],"authored trap retains damage target and amount / "+name)
				for tick in 3: u._step_along_path(GameUnit.TICK)
				if script.casts.size()==1:
					var cast: Array = script.casts[0]
					check(cast[0]=="fireball" and Vector2(cast[1],cast[2]).distance_to(u.pos)<0.00002 and Vector2(cast[3],cast[4]).distance_to(u.pos)<0.00002,
						"authored nested queries aim at the actor's actual three-tick position / "+name)
				check(script.instances[-1].killed and script.instances[-1].sleep_ticks==0 and not script.instances[-1].sleep_cond.is_empty(),
					"authored trap preserves its post-hit sleep and rearm continuation / "+name)
				u.free(); script.world = null; script.session = null

func _ready() -> void:
	s = Session.new(); s.process_mode = Node.PROCESS_MODE_DISABLED; add_child(s)
	w = GameWorld.new(); w.process_mode = Node.PROCESS_MODE_DISABLED; w.presentation = false
	w.nav = NavGrid.new(); w.session = s; s.world = w; add_child(w)
	vm = ScriptVM.new(); vm.world = w; vm.session = s; w.vm = vm
	dispatcher(); actual_motion(); authored_traps()
	FileAccess.open("user://script-future-queries.json",FileAccess.WRITE).store_string(JSON.stringify({
		"campaign":GameData.campaign_id,"checks":checks,"failures":failures,"movement":observations,
		"scope":"Original interpreter dispatch/tick rounding/axis result with supplied object predictor; actual remake movement with supplied routes, terrain factors and no other actors. Base also executes eleven installed zone19 trap bodies with observed spell/damage boundaries. Not original spline or full-scene replay."},"\t"))
	w.vm = null; vm.world = null; vm.session = null; s.world = null; w.free(); s.free()
	print("SCRIPT_FUTURE_QUERIES ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
