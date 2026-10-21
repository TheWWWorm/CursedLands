extends RefCounted
## The original bz5h / bz11g paid rumours bridge their conversation to a
## persistent quest flag. Catalogue refreshes reset all conversation flags;
## a co-op catalogue refresh can therefore erase 2 before the bridge polls.
## Commit the original bridge at completion, before another command can reset
## the topic. No dialogue, price, prerequisite, reward or lever state is added.
const P := preload("res://src/game/script/script_parser.gd")
const GIPAT_QUESTS := ["q.gz9g.fq8", "q.gz11g.fq9", "q.gz16g.fq10", "q.gz7g.fq11", "q.gz16g.fq12"]
const SUSLANGER_QUESTS := ["q.gz1h.q4h", "q.gz1h.fq2", "q.gz2h.fq3", "q.gz1h.fq4", "q.gz2h.fq5"]

static func _var_call(key: String) -> Array:
	return [P.N_CALL,"GSGetVar",[[P.N_NUM,0.0],[P.N_STR,key]]]

static func _source(n: int, gipat: bool) -> String:
	return "b.Spletnica.fq%d"%n if gipat else "b.skelet.skelet_fq%d"%n

static func _target(n: int, gipat: bool) -> String:
	return "b.shava.fq%d"%n if gipat else "b.skelet.fq%d"%n

static func _script(n: int, gipat: bool) -> String:
	return "BuySpletnicaMain#2#%d#0"%(n-8) if gipat else "BuySkeletMain#2#%d#0"%(n-1)

static func _bridge(n: int, gipat := false) -> Dictionary:
	return {"params":["this"],"blocks":[{"conds":[
		[P.N_CALL,"IsEqual",[_var_call(_source(n,gipat)),[P.N_NUM,2.0]]],
		[P.N_CALL,"IsEqual",[_var_call(_target(n,gipat)),[P.N_NUM,0.0]]]],
		"body":[[P.S_CALL,"KillScript",[]],
		[P.S_CALL,"GSSetVar",[[P.N_NUM,0.0],[P.N_STR,_target(n,gipat)],[P.N_NUM,2.0]]],
		[P.S_CALL,"BuyMain#1" if gipat else "BuyNSheriffMain#3",[[P.N_VAR,"this"]]]]}]}

static func _original(ast: ScriptParser, gipat := false) -> bool:
	for n in (range(9,14) if gipat else range(2,7)):
		if ast.scripts.get(_script(n,gipat),{}) != _bridge(n,gipat): return false
	return true

static func apply(ast: ScriptParser, zone: String) -> void:
	if zone in ["bz5h", "bz11g"]:
		var gipat := zone == "bz11g"
		if _original(ast,gipat): ast.set_meta(&"astral_fortunes",true)
		_qualify_offers(ast,gipat)
	elif zone == "gz1h":
		# A save/transfer may have left the village before its next poll.
		# Recognize both maps, including mod overrides, before repairing that
		# pending handoff. A hidden (3) or failed purchase is never evidence.
		var expected := {"params":["this"],"blocks":[{"conds":[
			[P.N_CALL,"IsEqual",[_var_call("b.skelet.fq2"),[P.N_NUM,2.0]]],
			[P.N_CALL,"IsEqual",[_var_call("q.gz1h.fq2"),[P.N_NUM,0.0]]]],
			"body":[[P.S_CALL,"KillScript",[]],[P.S_CALL,"EnableLever",
			[[P.N_CALL,"GetObject",[[P.N_NUM,2261640.0]]],[P.N_NUM,1.0]]]]}]}
		if ast.scripts.get("Raja#0",{}) != expected: return
		var market := EIMob.load_bytes(GameData.read_file("maps/bz5h.mob"))
		if _original(ScriptParser.parse(market.script_text)): ast.set_meta(&"astral_fortunes",true)

static func recover(vm: ScriptVM) -> void:
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL or not vm.ast.has_meta(&"astral_fortunes"): return
	var st := vm.session.state
	var gipat: bool = vm.world.zone.get("id","") == "bz11g"
	for n in (range(9,14) if gipat else range(2,7)):
		var source := _source(n,gipat)
		var target := _target(n,gipat)
		if st.get_var(0,source) != 2.0 or st.get_var(0,target) != 0.0: continue
		if vm.world.zone.get("id","") in ["bz5h", "bz11g"]:
			var name := _script(n,gipat)
			var pending: ScriptVM.Instance = null
			for inst: ScriptVM.Instance in vm.instances:
				if inst.sname == name and not inst.killed: pending=inst;break
			if pending == null:
				vm.spawn(name,[null]); pending=vm.instances.back()
			pending.poll=0.0
			vm._run(pending)
		else:
			# Preserve the bridge's durable flag; the current map's original
			# Raja/TorchBase scripts still own the hand cursor and entrance.
			st.set_var(0,target,2.0)
			vm.session.mark_dirty()


## The shared GS offer is chosen by GetMoney(0) once, but a guest has its
## own purse. Recognize the complete shipped offer, including prerequisites,
## before choosing the same authored response for the actual buyer. A mod
## with different conditions, side effects or price retains its own logic.
static func _qualify_offers(ast: ScriptParser, gipat: bool) -> void:
	var offers := {}
	var first := 9 if gipat else 2
	var price := 500.0 if gipat else 50.0
	for n in range(first,first+5):
		var source := _source(n,gipat)
		var guards := [[P.N_CALL,"IsEqual",[_var_call((GIPAT_QUESTS if gipat else SUSLANGER_QUESTS)[n-first]),[P.N_NUM,2.0]]]]
		if not gipat and n==2:
			guards.append([P.N_CALL,"IsEqual",[_var_call("b.skelet.skelet_about"),[P.N_NUM,2.0]]])
		guards.append([P.N_CALL,"IsEqual",[_var_call(_target(n,gipat)),[P.N_NUM,0.0]]])
		var poor := [P.N_CALL,"IsLess",[[P.N_CALL,"GetMoney",[[P.N_NUM,0.0]]],[P.N_NUM,price]]]
		var set_offer := [P.S_CALL,"GSSetVar",[[P.N_NUM,0.0],[P.N_STR,source],[P.N_NUM,1.0]]]
		var expected := {"params":["this"],"blocks":[
			{"conds":[[P.N_CALL,"Not",[poor]]]+guards,"body":[[P.S_CALL,"KillScript",[]],set_offer]},
			{"conds":[poor]+guards,"body":[[P.S_CALL,"KillScript",[]],
			[P.S_CALL,"GSSetVar",[[P.N_NUM,0.0],[P.N_STR,source+"f"],[P.N_NUM,1.0]]],
			[P.S_CALL,"GSSetVar",[[P.N_NUM,0.0],[P.N_STR,source],[P.N_NUM,3.0]]]]}]}
		var script := ("Spletnica#%d" if gipat else "Skelet#%d")%(n-first+1)
		var id := source.get_slice(".",2)
		if ast.scripts.get(script,{}) == expected and float(GameData.db.find("briefings",id).get("money",0.0)) == -price:
			offers[source.to_lower()] = {"source":source,"price":int(price),"guards":guards}
	ast.set_meta(&"astral_paid_offers",offers)

static func paid_entries(vm: ScriptVM, entries: Array, player: int) -> Array:
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL: return entries
	var offers: Dictionary = vm.ast.get_meta(&"astral_paid_offers",{})
	if offers.is_empty(): return entries
	var result := []
	var seen := {}
	for entry: Array in entries:
		var key := ("b.%s.%s"%entry).to_lower().trim_suffix("f")
		if not offers.has(key): result.append(entry); continue
		if seen.has(key): continue
		seen[key] = true
		var offer: Dictionary = offers[key]
		if not offer.guards.all(func(c):return bool(vm._eval(c,ScriptVM.Instance.new()))): continue
		var source: String = offer.source
		result.append([source.get_slice(".",1),source.get_slice(".",2)+("f" if vm.session.coop.owner_money(player)<int(offer.price) else "")])
	return result

static func selected_topic(vm: ScriptVM, entries: Array, requested: String) -> String:
	if vm.session.state.campaign_id != CampaignProfile.ASTRAL: return requested
	var key := requested.to_lower().trim_suffix("f")
	if not vm.ast.get_meta(&"astral_paid_offers",{}).has(key): return requested
	for entry: Array in entries:
		var current := "b.%s.%s"%entry
		if current.to_lower().trim_suffix("f") == key: return current
	return requested
