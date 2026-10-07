extends Node
## Compare compiled live eligibility with the retained script predicate.
## Every mutation is checked immediately, without rebuilding spatial state.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var k: RefCounted = ClassDB.instantiate("AIActivityKernel")
	var w := GameWorld.new()
	var u := GameUnit.new()
	u.world = w
	u.uid = 17
	u.proto = {"name":"eligibility-fixture", "spells":[]}
	w.units = {u.uid:u}
	w.time = 1.0
	u.set_meta("calm", {"busy":true, "until":5.0})
	_compare(k, w, u, "quiet", true)
	for key in ["hero", "suspect", "fear_on", "attacker", "um", "alerted", "hate", "peace"]:
		for value in [false, 0, {}, {"unit":u}]:
			u.set_meta(key, value)
			_compare(k, w, u, "metadata presence " + key, false)
			u.remove_meta(key)
			_compare(k, w, u, "metadata removed " + key, true)
	for key in ["noticed", "seen_corpses"]:
		u.set_meta(key, {u.get_instance_id():u})
		_compare(k, w, u, key, false)
		u.set_meta(key, {})
		_compare(k, w, u, key + " empty", true)
	for entry in [["controller",0], ["dead",true], ["hidden",true], ["alert",true],
			["order_failed",true], ["_anim_lock",0.0001], ["_pending_hit",{"t":1}],
			["buffs",{"x":{}}], ["_hp",9.0]]:
		var old: Variant = u.get(entry[0])
		u.set(entry[0], entry[1])
		_compare(k, w, u, str(entry[0]), false)
		u.set(entry[0], old)
		_compare(k, w, u, "restored " + str(entry[0]), true)
	u.orders.append({"type":"move"})
	_compare(k,w,u,"queued order",false)
	u.orders.clear()
	u.info.use_in_script = 1
	_compare(k,w,u,"script participant",false)
	u.info.clear()
	for mode in ["standard","sentry","guard","player","follow","aggression","fear","none"]:
		u.mode = mode
		_compare(k,w,u,"mode " + mode,mode in UnitAI.CALM_MODES)
	u.mode = "standard"
	for index in 3:
		for model in range(-1,8):
			u.info.logic = [{"logic_model":model}, {"logic_model":model + 1}]
			u.info.logic_model = model + 2
			u.set_meta("logic_idx",index)
			_compare(k,w,u,"current descriptor %d/%d" % [index,model],(model+index) in [1,2,3,5])
	u.info.clear()
	u.remove_meta("logic_idx")
	for fear in [{"r":9.0},{"j":4.0},{"danger":false},{"r":NAN},{"j":INF}]:
		u.set_meta("fear",fear)
		_compare(k,w,u,"fear change",false)
	u.set_meta("fear",{"r":10.0,"j":3.0})
	_compare(k,w,u,"default fear",true)
	w.ai.dangers.append({"until":10})
	_compare(k,w,u,"world danger",false)
	w.ai.dangers.clear()
	UnitAI._spell_opts[u.proto.name] = [[],[{}]]
	_compare(k,w,u,"support spell",false)
	u.uid = 1500000001
	_compare(k,w,u,"script character has no AI spell list",true)
	u.uid = 17
	UnitAI._spell_opts.erase(u.proto.name)
	for busy in [false,true]:
		for until in [-1.0,0.0,1.0,1.000001,100.0]:
			u.set_meta("calm",{"busy":busy,"until":until})
			_compare(k,w,u,"deadline",busy and until > w.time)
	u.set_meta("calm",{"busy":true,"until":5.0})
	for kind in ["move","attack","cast","wait","anim","use","follow","rotate",""]:
		for calm in [false,true]:
			u.order = {"type":kind,"calm":calm}
			_compare(k,w,u,"order " + kind,calm and kind == "move")
	u.order = {}
	# Body-derived HP must be used even when the old fallback is stale.
	u.max_hp = 30.0
	u.parts = [{"cur":30.0,"max":30.0,"size":1.0,"type":1,"state":3,"lethal":1.0}]
	u._hp = 1.0
	_compare(k,w,u,"scaled healthy body",true)
	u.parts[0].cur = 29.0
	_compare(k,w,u,"new body wound",false)
	u.parts = []
	u.max_hp = 10.0
	u._hp = 10.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 715481
	for trial in 2048:
		u.controller = rng.randi_range(-4,0)
		u.mode = UnitAI.CALM_MODES[rng.randi_range(0,2)]
		u.info.logic_model = rng.randi_range(0,7)
		u.order = {} if trial % 2 else {"type":"move","calm":trial % 3 == 0}
		u.set_meta("calm",{"busy":trial % 5 != 0,"until":rng.randf_range(0,2)})
		u.set_meta("fear",{"r":10.0 if trial % 7 else 9.0})
		check(k.can_defer(u,w.ai,w.time) == w.ai.activity._eligible_script(u),"mixed live fields %d" % trial)
		check(k.can_defer_owned(u,w.ai,w.time,GameUnit,UnitAI) == w.ai.activity._eligible_script(u),"owned live fields %d" % trial)
	# Exercise actual scheduling and mid-tick invalidation through the adapter.
	u.controller = -1; u.mode = "sentry"; u.info.clear(); u.order = {}; u.remove_meta("fear")
	u.set_meta("calm",{"busy":true,"until":5.0})
	w.ai.activity.begin_tick(GameUnit.TICK)
	u.set_meta("ai_near_t",0.0); u.set_meta("perceived",{})
	check(w.ai.activity.defer_decision(u),"compiled adapter defers quiet actor")
	check(not u.has_meta("ai_near_t") and not u.has_meta("perceived"),"old neighbour cache removed")
	u.set_meta("attacker",true)
	check(not w.ai.activity.defer_decision(u),"same-tick attack wakes immediately")
	u.remove_meta("attacker")
	u._hp = 9.0
	check(not w.ai.activity.defer_decision(u),"same-tick damage wakes immediately")
	u._hp = 10.0
	var before := Time.get_ticks_usec()
	for i in 12000: k.can_defer(u,w.ai,w.time)
	var object_us := Time.get_ticks_usec()-before
	before=Time.get_ticks_usec()
	for i in 12000: k.can_defer_owned(u,w.ai,w.time,GameUnit,UnitAI)
	var owned_us := Time.get_ticks_usec()-before
	print("AI_OWNED_TIMING object_us=",object_us," owned_us=",owned_us)
	w.units = {}; u.free(); w.free()
	print("AI_LIVE_ELIGIBILITY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func _compare(k: RefCounted,w: GameWorld,u: GameUnit,label: String,expected: bool) -> void:
	check(w.ai.activity._eligible_script(u) == expected,"script " + label)
	check(k.can_defer(u,w.ai,w.time) == expected,"native " + label)
	check(k.can_defer_owned(u,w.ai,w.time,GameUnit,UnitAI) == expected,"owned " + label)
