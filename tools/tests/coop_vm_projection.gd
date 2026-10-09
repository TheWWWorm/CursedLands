extends Node
## Structural save-format controls around real original script bodies. The
## ENet companion fixtures separately capture naturally pending sleep/AI state.
const Snapshot := preload("res://src/game/script/coop_vm_state.gd")
var checks := 0
var failures := 0
var vm: ScriptVM
var lead := {"u":1500000001,"h":[0,0]}
var own := {"u":1500000002,"h":[1,0]}
var other := {"u":1500000003,"h":[2,0]}
var npc := {"u":1281}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func row(name: String, actor: Dictionary) -> Dictionary:
	return {"s":name,"l":{"this":actor},"k":false,"b":-1,"i":0,"w":0.0,"f":[],"p":0.055}

func project(state: Dictionary) -> Dictionary:
	var zones := Snapshot.mark_zones({"gz2g":{"vm":state}},1)
	return Snapshot.restore(vm,zones.gz2g.vm)

func loop(items: Array, cursor: int, instruction: int) -> Dictionary:
	# This models the saved cursor within the original For(Heroes) body.
	# It is not a claim that this short registration naturally suspends here.
	var body: Array = vm.ast.scripts["VTriger#0#2"].blocks[0].body
	var at := -1
	for i in body.size():
		if body[i][0] == ScriptParser.S_FOR: at = i
	var entry := row("VTriger#0#2",{})
	entry.l.this = null; entry.b = 0; entry.k = true; entry.i = at+1
	entry.f = [{"i":at+1},{"i":instruction,"v":"VSS#i#val","it":items,"k":cursor}]
	entry.w = 0.825; entry.wu = items[cursor]
	return {"globals":{"VSS#i#val":items[cursor]},"instances":[entry]}

func _ready() -> void:
	vm = ScriptVM.new()
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		families(); finish(); return
	var text := EIMob.load_bytes(GameData.read_file("maps/zone2.mob")).script_text
	vm.ast = ScriptParser.parse(text); vm.world_bodies[""] = vm.ast.world
	check(vm.ast.errors.is_empty() and vm.ast.scripts.has("VTriger#0#4"),"original delayed trap source parses")
	check(not vm._world_event("VCheck#0#1") and vm._world_event("VCheck#0#88"),"source analysis distinguishes individual trap and shared quest event")
	var source := {"globals":{"Heroes":[lead,own,other],"named":npc},"instances":[row("VCheck#0#1",lead),row("VTriger#0#4",own),row("VCheck#0#1",other)]}
	var before := var_to_bytes(source)
	var marked := Snapshot.mark_zones({"gz2g":{"vm":source,"units":{1281:[1,2,30]}}},1)
	check(not is_same(marked.gz2g.vm,source) and is_same(marked.gz2g.vm.instances,source.instances),"marker clones containers without duplicating immutable VM arrays")
	check(var_to_bytes(source) == before and not source.has(Snapshot.KEY),"marking historical credited VM adds no metadata to the authority snapshot")
	var projected := Snapshot.restore(vm,marked.gz2g.vm)
	check(var_to_bytes(source) == before,"projection cannot mutate host snapshot")
	check(projected.instances.size()==1 and projected.instances[0].s=="VTriger#0#4","recipient's individual pending action survives; other players' actions do not transfer")
	check(projected.instances[0].l.this.h==[0,0],"recipient continuation uses solo stable identity")
	check(projected.globals.Heroes.size()==1 and projected.globals.Heroes[0].h==[0,0],"participant group has one solo occurrence")
	check(projected.globals.named==npc,"native named NPC identity remains unchanged")
	check(not projected.has(Snapshot.KEY),"one-time projection marker is consumed")
	check(Snapshot.restore(vm,projected)==projected,"normal solo snapshot is unchanged on further loads")
	projected.globals.named.u = 999
	check(source.globals.named.u==1281,"restored output owns nested dictionaries independently of source")
	vm.session = Session.new(); vm.session.state = CampaignState.new()
	vm.session.state.create_party("Pretty")
	vm.session.state.add_party_unit("Pretty","Nalo","Human Hadagan Pretty")
	vm.session.state.set_current_party("Pretty")
	var named := {"u":1500000042,"h":[0,0]}
	var companion := project({"globals":{},"instances":[row("VTriger#0#4",named)]})
	check(companion.instances.size()==1 and companion.instances[0].l.this.h==[0,0],"actual Pretty::Nalo party operation preserves a named-role pending action")
	companion = project(loop([named],0,1))
	check(companion.instances[0].f.size()==2 and companion.instances[0].f[1].i==1,"authored named-role For iteration is not mistaken for absent host work")
	companion = project({"globals":{},"instances":[row("VCheck#0#1",named),row("VTriger#0#4",own),row("VTriger#0#4",own),row("VTriger#0#9",named)]})
	check(companion.instances.size()==3 and companion.instances.filter(func(i):return i.s=="VTriger#0#4").size()==2 and companion.instances[-1].s=="VTriger#0#9","temporary-role alias keeps recipient chain once, deliberate own duplicates and unique named-role work")
	vm.session.state.create_party("NamedParty")
	vm.session.state.add_party_unit("NamedParty","Hero","Human Hero")
	vm.session.state.add_party_unit("NamedParty","Nalo","Human Hadagan Pretty")
	vm.session.state.set_current_party("NamedParty")
	companion = project({"globals":{},"instances":[row("VTriger#0#4",{"u":1500000043,"h":[0,1]})]})
	check(companion.instances.size()==1 and companion.instances[0].l.this.h==[0,1],"authored non-primary named roster role retains independent continuation")
	vm.session.free(); vm.session = null
	var duplicate := {"globals":{"items":[lead,own,own,npc]},"instances":[row("VCheck#0#88",lead),row("VCheck#0#88",own),row("VCheck#0#88",own)]}
	projected = project(duplicate)
	check(projected.instances.size()==2 and projected.instances.all(func(i):return i.l.this.h==[0,0]),"cross-owner shared event aliases collapse; same-owner deliberate threads remain")
	check(projected.globals.items.size()==3 and projected.globals.items[0]==projected.globals.items[1] and projected.globals.items[2]==npc,"same-owner deliberate array duplicates and NPC entry remain")
	var prior := loop([lead,own,npc],0,1)
	projected = project(prior); var entry: Dictionary = projected.instances[0]
	check(entry.f.size()==2 and entry.f[1].it.size()==2 and entry.f[1].k==0 and entry.f[1].i==0,"For on excluded host advances to recipient at start of its body")
	check(entry.w==0 and not entry.has("wu") and projected.globals["VSS#i#val"].h==[0,0],"excluded host wait is cleared and loop variable selects recipient")
	projected = project(loop([lead,own,npc],1,1)); entry = projected.instances[0]
	check(entry.f[1].k==0 and entry.f[1].i==1 and entry.w==0.825,"recipient For body keeps instruction and remaining wait")
	check(entry.f[1].it[1]==npc,"later native NPC iteration is retained")
	projected = project(loop([own,lead],1,1)); entry = projected.instances[0]
	check(entry.f.size()==1 and entry.f[0].i==3 and entry.w==0,"completed recipient iteration is not replayed when later host iteration is removed")
	var legacy := row("VTriger#0#4",own)
	legacy.erase("f"); legacy.b=0; legacy.i=5; legacy.w=0.4
	projected=project({"globals":{},"instances":[legacy]}); entry=projected.instances[0]
	check(not entry.has("f") and entry.b==0 and entry.i==5 and entry.w==0.4 and entry.l.this.h==[0,0],"older b/i-only shape preserves exact delayed instruction")
	projected=project({"globals":{},"instances":[row("VTriger#0#4",npc)],"script_ai":[{"actor":npc,"data":{"target":own,"home":npc,"absent":other}}],
		"story_orders":[{"actor":lead,"orders":[{"type":"move","to":Vector2(1,2)}]},{"actor":own,"orders":[{"type":"move","to":Vector2(3,4)}]},
		{"actor":other,"orders":[{"type":"move","to":Vector2(5,6)}]},{"actor":npc,"orders":[{"type":"rotate","angle":0.2}]}],"world_done":{"shared":2}})
	check(projected.instances[0].l.this==npc and projected.script_ai[0].actor==npc and projected.script_ai[0].data.home==npc,"native UID refs survive in locals and AI unchanged")
	check(projected.script_ai[0].data.target.h==[0,0] and projected.script_ai[0].data.absent==null,"AI retains recipient target and leaves other absent peer unresolved")
	check(projected.story_orders.size()==2 and projected.story_orders[0].orders[0].to==Vector2(3,4) and projected.story_orders[1].actor==npc,"recipient order wins over host fallback and other peers; native NPC order remains")
	check(projected.world_done.shared==0,"shared event ownership becomes local without clearing completion")
	var unmarked := {"globals":{"ref":own},"instances":[]}
	check(Snapshot.restore(vm,unmarked)==unmarked,"unmarked historical VM is never guessed or rewritten")
	families()
	finish()

func families() -> void:
	var compat := preload("res://src/game/script/story_compat.gd")
	var traps := preload("res://src/game/script/story_coop_traps.gd")
	var cases := ["gz6g"] if GameData.campaign_id == CampaignProfile.ORIGINAL else ["gz36j","gz1h","gz9g"]
	var campaign := CampaignMap.load_from(GameData.texts)
	for zone: String in cases:
		var map: Dictionary = campaign.zone(zone)
		var mob := String(map.get("mob",map.get("mpr",""))).get_basename()
		vm.ast = ScriptParser.parse(EIMob.load_bytes(GameData.read_file("maps/"+mob+".mob")).script_text)
		compat.apply(vm.ast,GameData.campaign_id,zone)
		var watchers: Array = vm.ast.scripts.keys().filter(func(n):return vm.ast.scripts[n].has("trap"))
		check(watchers.size()==1,zone+": original source installs one inspected family")
		if watchers.is_empty(): continue
		var definition: Dictionary = vm.ast.scripts[watchers[0]]
		var mapping := Snapshot._family_map(vm,definition,0)
		check(mapping.size()==definition.family.size(),zone+": complete native recipient-role family matches structurally")
		if mapping.is_empty(): continue
		var rows := []
		for name: String in mapping:
			var own_row := row(name+traps.COPY,{})
			own_row.l = {"this":null,traps.KEY:"h:1:0"}; own_row.b=0; own_row.f=[{"i":2}]; own_row.w=0.1
			rows.append(own_row)
			var foreign := own_row.duplicate(true); foreign.l[traps.KEY]="h:2:0"; rows.append(foreign)
			var original := row(mapping[name],{}); original.l.this=null; rows.append(original)
		rows.append({"s":watchers[0],"l":{traps.SEEN:["h:1:0","h:2:0"]}})
		var before := var_to_bytes(rows)
		var returned := Snapshot._participant_rows(vm,rows,1)
		check(returned.size()==mapping.size() and returned.all(func(r):return r.s in mapping.values()),zone+": recipient branch replaces native alias once and other peer work stays absent")
		check(returned.all(func(r):return r.f==[{"i":2}] and r.w==0.1 and not r.l.has(traps.KEY)),zone+": saved authored body instruction and delay survive role conversion")
		check(var_to_bytes(rows)==before,zone+": translating participant family cannot mutate saved source")
		var spent := rows.filter(func(r):return r.s==watchers[0] or r.s in mapping.values())
		check(Snapshot._participant_rows(vm,spent,1).is_empty(),zone+": spent guest activation cannot inherit or rearm the host's idle copy")
		var target: String = mapping[definition.trap.root]
		vm.ast.scripts[target].blocks[0].body.append([ScriptParser.S_CALL,"KillScript",[]])
		check(Snapshot._family_map(vm,definition,0).is_empty(),zone+": changed native counterpart is never guessed")

func finish() -> void:
	print("COOP_VM_PROJECTION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
