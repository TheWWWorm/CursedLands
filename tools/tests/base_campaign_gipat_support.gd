extends "base_campaign_support.gd"
## Owned base Gipat checkpoints: source-root selection suppresses unrelated
## ambient combat. Actor deaths, item collection, conversations and controls
## still pass through their ordinary gameplay handlers.

var combat_xp := 0.0
var reward_window := {}

# A window is armed before one objective's final ordinary stimulus. Combat
# XP from the fixture's synchronous deaths is measured before advancing the
# VM, so it cannot be mistaken for the authored QuestComplete reward.
func arm(id: String) -> void:
	var h: Dictionary = s.state.heroes[0][0]
	reward_window = {"id":id,"experience":float(h.get("exp_total",0)),
		"combat":combat_xp,"journal":s.state.quests.duplicate(),
		"intelligence":float(h.get("int",25))+Perks.attr_bonus(h,"int")}

func kill(ids: Array) -> void:
	for id: int in ids:
		var u: GameUnit = s.world.units.get(id)
		if check(u != null,"authored combat target exists: "+str(id)):
			var before := float(s.state.heroes[0][0].get("exp_total",0))
			u.die(hero())
			combat_xp += float(s.state.heroes[0][0].get("exp_total",0))-before
	ticks()

# AddMob may finish before or after enter() clears ambient instances. Keep
# its real object/group bindings, but select exactly one copy of its authored
# watcher roots; otherwise a late-added WorldScript and explicit rearm can
# both grant the same reward. Base-map selected instances stay intact.
func rearm_mob(file: String, names: Array) -> void:
	var mob := EIMob.load_bytes(GameData.read_file("maps/"+file))
	var parsed := ScriptParser.parse(mob.script_text)
	var owned := {}
	for name: String in parsed.scripts:
		owned[name] = true
		owned[name+"_"+file.get_basename().to_lower()] = true
	vm().instances = vm().instances.filter(func(inst):
		return not owned.has(inst.sname) and not (inst.sname == "WorldScript" and inst.src == "m:"+file.to_lower()))
	start(names)

func watch(name: String, actor: GameUnit = null) -> void:
	if check(vm().ast.scripts.has(name),s.zone_id+": authored condition "+name):
		vm().spawn(name,[actor])
	ticks()

func dead(name: String) -> void:
	var u: GameUnit = vm().globals.get(name)
	if check(u != null,"authored named target exists: "+name): kill([u.uid])

func group_ids(name: String) -> Array:
	var ids := []
	for u: GameUnit in vm().globals.get(name,[]):
		if u != null and not u.dead: ids.append(u.uid)
	check(not ids.is_empty(),"authored group has living members: "+name)
	return ids

func collect(name: String) -> void:
	var u: GameUnit = vm().globals.get(name)
	if check(u != null,"authored item carrier exists: "+name):
		if not u.dead: kill([u.uid])
		loot(u.uid)

func quest(id: String, label: String) -> void:
	ticks(12)
	check(value(id) == 2,label+": authored quest completes")
	var key := id.get_slice(".",2)
	check(int(s.state.quests.get(key,0)) == 2,label+": journal records completion")
	if check(reward_window.get("id","") == id,label+": explicit reward window names this objective"):
		var others := []
		for q: String in s.state.quests:
			if q != key and int(s.state.quests[q]) == 2 and int(reward_window.journal.get(q,0)) != 2: others.append(q)
		check(others.is_empty(),label+": no other quest completes inside the reward window")
		var row := GameData.db.find("quests",key)
		var expected := float(row.get("experience",0))*pow(1.04,float(reward_window.intelligence)-25.0)
		var observed := float(s.state.heroes[0][0].get("exp_total",0))-float(reward_window.experience)-(combat_xp-float(reward_window.combat))
		check(expected > 0 and absf(observed-expected) <= maxf(0.02,expected*0.0001),label+": actual script experience matches original reward ("+str(observed)+" / "+str(expected)+")")
	reward_window = {}
	stable(label)

func offer(zone: String, topic: String, id: String) -> void:
	await accept(zone,topic,id)

func finish_gipat(marker: String, scope: String) -> void:
	check(vm().unknown_calls.is_empty(),"selected original threads have no unknown calls")
	await finish(marker,scope)
