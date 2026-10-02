class_name CampaignState
extends RefCounted
## Everything that persists across zones and in save games.

## Global script variables (GSGetVar/GSSetVar). Index 0 is the shared campaign
## state used by all original scripts; in co-op it is the party's shared progress.
var vars := {}
## player index -> Array of hero records (prototype, name, stats, items...)
var heroes := {}
## zone id -> {dead: [nid], removed: [nid], looted: [nid], hidden: [nid], levers: {nid: state}, units: {nid: [x, y, hp]}}
var zones := {}
var visited := {}
var quests := {}          # quest id -> {state, objectives}
var money := 0
var items: Array = []     # shared party inventory (item ids "name.material")
var quest_items := {}     # lowercase quest item name -> true
var parties := {}         # scripted alternative parties (CreateParty)
var current_party := ""
## The quest of the last "q.<zone>.<quest>..." var set to 1 (the original interface
## not saved): the zone objectives screen selects it first.
var last_quest := ""
## Each party has its own bag and money (the original: a party object's item
## container, items, money). `items` / `money` are the
## current party's; the others wait here: party name -> {items, money}.
var party_bags := {}
var side_quests := {}     # quest map id -> "active" | "done" | "rewarded" | "rejected"
var experience := 0.0     # experience not yet distributed
## Hired mercenaries: number N (script var apartyn<N>) -> hero record + controller.
var mercs := {}
## Fully tamed units (Spells.tame stage 3) travelling with the party:
## [{rec, hp, controller, pos}]. the original puts them in the
## tamer's party, whose members go to the next zone.
var pets: Array = []
## Trader records by id (Shops): goods, restock flag, prototypes sold there.
var shops := {}
var current_zone := "gz1g"
## Hours. the original (new game, creates the "Human Hero") sets
## GS var "gtime" = 6.0: a new campaign starts at 06:00.
var world_time := 6.0
## Day counter shown on the global map ("День N, hh:mm").
var day := 1
## Remake co-op (CoopProgress, not in the original): "host" = the joining players'
## credit tracking at this save; "applied" = progress packages already merged
## into this save (package id -> {seq, money, items}).
var coop := {}
## The host's camera at the save (the original scenario.sav: the camera's own
## record, — look-at point, turn, pitch
## distance and velocities; restored as saved, no refocus): CameraRig.pose().
var camera := {}


## Remake co-op (CoopProgress): called as watch(state, player, key, old, new)
## after a var changed, to credit joining players' own campaigns.
static var watch := Callable()


## Real seconds per game hour. the original: clock rate =
## 1 / registry "DefaultTimeScale" (60, settings =
## ) × 1 / 15 hours per logic tick, so 900 ticks of 55 ms =
## 49.5 s an hour (adds ticks × rate to "gtime"; the client
## clock is ticks × rate + offset too).
const HOUR_SECONDS := 900.0 * 0.055


func advance_hours(h: float) -> void:
	world_time += h
	while world_time >= 24.0:
		world_time -= 24.0
		day += 1


## GS var "gtime" is the campaign clock in hours since the start of day 1
## (the original advances it every tick; the global map shows day
## gtime·60/1440 + 1). Scripts read it for timeouts
## (bz1g GTwolf/GTgold, bz2g FrTime, zone9 z.gz9g.a1); the remake keeps it as
## day/world_time and derives the var.
func get_var(player: int, key: String) -> float:
	if key == "gtime":
		return float(day - 1) * 24.0 + world_time
	return float(vars.get("%d:%s" % [player, key], 0.0))


func set_var(player: int, key: String, v: float) -> void:
	if key == "gtime":
		day = int(v / 24.0) + 1
		world_time = fposmod(v, 24.0)
		return
	var k := "%d:%s" % [player, key]
	var old := float(vars.get(k, 0.0))
	vars[k] = v
	if watch.is_valid() and old != v:
		watch.call(self, player, key, old, v)
	# a "q." var set to 1 with
	# three or more parts names the interface's last quest.
	if v == 1.0 and key.begins_with("q.") and key.get_slice_count(".") >= 3:
		last_quest = key.get_slice(".", 2)


func del_var(player: int, key: String) -> void:
	var k := "%d:%s" % [player, key]
	var old := float(vars.get(k, 0.0))
	vars.erase(k)
	if watch.is_valid() and old != 0.0:
		watch.call(self, player, key, old, 0.0)


## the original keeps a var store per player (player record). The campaign
## scripts only name party 0 (GSSetVar(0,...), builtin 0x7f)
## while the mercenary conversations are worked out per player:
## counts each player's own party and writes that player's store
## the store of the player who finished the conversation (both via
## net message 0x81), and the conversation's own var is set to 2
## in that player's store. The remake keeps the shared store
## (index 0, the host's) and, for these mercenary vars, a layer per co-op
## player: player p reads "p:key" once the engine has written one for p, else
## the shared value (so a client sees what the scripts set, e.g. amerc_<i> = 1).
## Approx.: the original's other conversation vars are per player too; the remake
## shares them.
static func is_player_var(key: String) -> bool:
	return key.begins_with("amerc_") or (key.begins_with("b.merc") and key.contains(".n"))


func get_pvar(player: int, key: String) -> float:
	if player != 0 and is_player_var(key):
		var k := "%d:%s" % [player, key]
		if vars.has(k):
			return float(vars[k])
	return get_var(0, key)


func set_pvar(player: int, key: String, v: float) -> void:
	if player != 0 and is_player_var(key):
		vars["%d:%s" % [player, key]] = v
	else:
		set_var(0, key, v)


## Adds looted / stolen items: quest items (items.idb "quest_items", e.g. a
## unit's .mob UNIT_QUEST_ITEMS) go to the quest item list that the script
## builtin HaveItem reads, everything else into the party bag.
func add_item(id: String, n := 1) -> void:
	if Items.kind(id) == "quest":
		quest_items[String(Items.info(id).row.get("name", id)).to_lower()] = true
		return
	for k in n:
		items.append(id)


# ---------------------------------------------------------------- party

func ensure_hero(player: int, prototype: String, player_name := "") -> void:
	if heroes.has(player):
		return
	var proto := GameData.db.find("monster_prototypes", prototype)
	var npc := GameData.db.find("npcs", prototype)
	# the original new game (("Hero", "Human Hero")
	# ): the hero record takes its kit from the
	# PROTOTYPE only — worn items ("wears"), weapon / second weapon
	#  and spells ("spells": healing, eagle sight, made
	# into spell containers). The NPC record of the same name is
	# read only for attributes, skills, experience and perks; its
	# weapons / quest items / spells describe a later-game Zak and are not used,
	# and nothing goes on the belt. Co-op mercenaries use their own kit.
	var weapons := PackedStringArray()
	if String(proto.get("weapon", "")) != "":
		weapons.append(String(proto.weapon))
	elif player > 0:
		weapons = Items.split_list(npc.get("weapons", []))
	var hero := {
		"prototype": prototype,
		"name": hero_name() if player == 0 else GameUnit.unit_title(prototype),
		"level": 1,
		"exp": 0.0,
		"exp_total": float(npc.get("experience", 0.0)),
		"skills": Skills.from_npc(npc),
		"str": float(npc.get("str", 25.0)),
		"dex": float(npc.get("dex", 25.0)),
		"int": float(npc.get("int", 20.0)),
		"hp": -1.0,
		"complexion": GameUnit.proto_complexion(proto),
		"armors": Array(Items.split_list(proto.get("wears", []))).map(func(x): return String(x).to_lower()),
		"weapons": Array(weapons).slice(0, 4).map(func(x): return String(x).to_lower()),
		"quick": [],
		"spells": Array(Items.split_list(proto.get("spells", []) if player == 0 else npc.get("spells", []))).map(func(x): return String(x).to_lower()),
		# Zak starts with his NPC perks too (Backstab from the beginning [reignofmagic guide]).
		"perks": Array(npc.get("perks", [])).map(func(x): return String(x).to_lower()),
	}
	if player > 0 and player_name.strip_edges() and player_name != "Player":
		hero.name = player_name.strip_edges()   # co-op heroes carry their player's name
	if String(hero.name).is_empty():
		hero.name = "Mercenary"
	# The rest of the starting kit goes to the shared bag.
	for w in weapons.slice(1):
		items.append(w.to_lower())
	if player > 0:   # remake co-op kit; the campaign hero's belt starts empty
		for q in Items.split_list(npc.get("quest_items", [])):
			hero.quick.append(q.to_lower())
	heroes[player] = [hero]


# ---------------------------------------------------------------- scripted parties
# The story sometimes swaps player 0's party for another one (Zak alone in
# disguise, Zak polymorphed into a Jun, ...). The inactive main roster waits in
# parties[""]; mercenaries stay with it.

## The main hero's name in the edition's language: texts.res "unit human_hero"
## (Zak / Зак / Kiran), as the unit name the original shows for the Human Hero prototype.
static func hero_name() -> String:
	var t := GameUnit.unit_title("human_hero")
	return t if t else "Zak"


func add_party_unit(party: String, unit_name: String, prototype: String) -> void:
	var proto := GameData.db.find("monster_prototypes", prototype)
	var npc := GameData.db.find("npcs", prototype)
	var title := GameUnit.unit_title(prototype)
	var h := {
		"prototype": prototype, "unit_name": unit_name,
		"name": hero_name() if unit_name.to_lower() == "hero" else (title if title else unit_name),
		"level": 1, "exp": 0.0, "hp": -1.0,
		"exp_total": float(npc.get("experience", 0.0)), "skills": Skills.from_npc(npc),
		"perks": Array(npc.get("perks", [])).map(func(x): return String(x).to_lower()),
		"str": float(npc.get("str", 25.0)), "dex": float(npc.get("dex", 25.0)), "int": float(npc.get("int", 20.0)),
		"complexion": GameUnit.proto_complexion(proto),
		"armors": Array(Items.split_list(proto.get("wears", []))).map(func(x): return String(x).to_lower()),
		"weapons": [String(proto.weapon).to_lower()] if String(proto.get("weapon", "")) != "" else [],
		"quick": [], "spells": [],
	}
	parties.get_or_add(party, []).append(h)


## "Hero" (the main hero, wherever he is) or "Party::Unit".
func party_member(ref: String) -> Dictionary:
	if "::" in ref:
		for h: Dictionary in parties.get(ref.get_slice("::", 0), []):
			if String(h.get("unit_name", h.name)).to_lower() == ref.get_slice("::", 1).to_lower():
				return h
		return {}
	var main: Array = heroes.get(0, []) if current_party.is_empty() else parties.get("", [])
	return main[0] if not main.is_empty() else {}


func copy_stats(from: String, to: String) -> void:
	var a := party_member(from)
	var b := party_member(to)
	if a.is_empty() or b.is_empty() or a == b:
		return
	for k: String in a:
		if k in ["str", "dex", "int", "exp", "exp_total", "level", "perks"]:
			b[k] = a[k]
		elif k == "skills":
			b[k] = Dictionary(a[k]).duplicate()
	b.spells = Array(a.get("spells", [])).duplicate()
	if not "::" in from:
		b.name = a.name   # the main hero in another shape keeps his name


func copy_items(from: String, to: String) -> void:
	var a := party_member(from)
	var b := party_member(to)
	if a.is_empty() or b.is_empty() or a == b:
		return
	for k in ["armors", "weapons", "quick"]:
		b[k] = Array(a.get(k, [])).duplicate()


## Returns false when nothing changed. The bag goes with the party.
func set_current_party(party: String) -> bool:
	if party == current_party or (not party.is_empty() and parties.get(party, []).is_empty()):
		return false
	parties[current_party] = heroes.get(0, [])
	heroes[0] = parties.get(party, [])
	parties.erase(party)
	party_bags[current_party] = {"items": items, "money": money}
	var bag: Dictionary = party_bags.get(party, {"items": [], "money": 0})
	party_bags.erase(party)
	items = bag.items
	money = int(bag.money)
	current_party = party
	return true


## Script CreateParty: a new party with no members and an empty bag.
func create_party(party: String) -> void:
	#  appends a new party without a name check, but
	# returns the first party of a name: a repeated name changes nothing.
	if party == current_party or party == "" or parties.has(party) or party_bags.has(party):
		return
	parties[party] = []
	party_bags[party] = {"items": [], "money": 0}


## A party's bag by name, as finds it: the party of that name
## else the main party "". The current party's bag is `items` / `money`.
func _bag_name(party: String) -> String:
	return party if party == current_party or party_bags.has(party) or parties.has(party) else ""


func _bag(party: String) -> Dictionary:
	party = _bag_name(party)
	if party == current_party:
		return {"items": items, "money": money}
	return party_bags.get_or_add(party, {"items": [], "money": 0})


## Script CopyLoot (copy = true) / AddLoot: the items and money of `from`'s bag
## replace / are added to `to`'s (the source keeps its own).
func move_loot(from: String, to: String, copy: bool) -> void:
	var a := _bag(from)
	var b := _bag(to)
	var got: Array = Array(a.items).duplicate()
	var cash := int(a.money)
	if copy:
		b.items.clear()
		b.money = 0
	b.items.append_array(got)
	b.money = int(b.money) + cash
	if _bag_name(to) == current_party:
		money = int(b.money)


## Script FixItems: every item back to full durability (the wear suffix gone).
func fix_items() -> void:
	var fix := func(l: Array) -> void:
		for i in l.size():
			if l[i] is String:
				l[i] = Items.unworn(l[i])
	fix.call(items)
	for bag: Dictionary in party_bags.values():
		fix.call(bag.items)
	var records: Array = mercs.values()
	for roster in heroes.values() + parties.values():
		records.append_array(roster)
	for h in records:
		if h is Dictionary:
			for k in ["armors", "weapons", "quick"]:
				if h.get(k) is Array:
					fix.call(h[k])


func party_records(player: int) -> Array:
	var out := []
	for h: Dictionary in heroes.get(player, []):
		var rec := {"prototype": h.prototype, "parent_template": h.prototype, "name": h.get("unit_name", h.name),
			"complexion": h.complexion, "player": 0, "kind": "UNIT", "type": 50}
		rec.armors = PackedStringArray(h.get("armors", []))
		rec.weapons = PackedStringArray(h.get("weapons", []))
		out.append(rec)
	return out


## Hero record for mercenary N created from its NPC unit (or its map record).
func make_merc(n: int, rec: Dictionary) -> Dictionary:
	var proto_name := String(rec.get("prototype", rec.get("parent_template", "")))
	var proto := GameData.db.find("monster_prototypes", proto_name)
	var npc := GameData.db.find("npcs", proto_name)
	var weapons: Array = Array(rec.get("weapons", [])).map(func(x): return String(x).to_lower())
	var m := {
		"prototype": proto_name, "merc": n,
		"name": GameUnit.unit_title(proto_name) if String(rec.get("name", "")).to_lower().begins_with("merc") else String(rec.get("name", "")),
		"level": 1, "exp": 0.0,
		"exp_total": float(npc.get("experience", 0.0)), "skills": Skills.from_npc(npc),
		"perks": Array(npc.get("perks", [])).map(func(x): return String(x).to_lower()),
		"str": float(npc.get("str", 22.0)), "dex": float(npc.get("dex", 22.0)), "int": float(npc.get("int", 18.0)),
		"hp": -1.0,
		"complexion": rec.get("complexion", GameUnit.proto_complexion(proto)),
		"armors": Array(rec.get("armors", Items.split_list(proto.get("wears", [])))).map(func(x): return String(x).to_lower()),
		"weapons": weapons.slice(0, 4),
		"quick": [],
		"spells": Array(rec.get("spells", Items.split_list(npc.get("spells", [])))).map(func(x): return String(x).to_lower()),
		"controller": 0,
	}
	for w in weapons.slice(1):
		items.append(w)
	if String(m.name).is_empty():
		m.name = "Mercenary %d" % n
	mercs[n] = m
	return m


## The hired mercenary keeps its map name "merc<N>" (its display name is
## m.name): the scripts address it by that name (GetObjectByName("merc1"),
## conversations b.merc1.*, whose owner the original matches by the
## name's id, see ScriptVM.name_id).
func merc_record(m: Dictionary) -> Dictionary:
	var script_name: String = "merc%d" % int(m.merc) if typeof(m.get("merc")) in [TYPE_INT, TYPE_FLOAT] else String(m.name)
	return {"prototype": m.prototype, "parent_template": m.prototype, "name": script_name, "complexion": m.complexion,
		"player": 0, "kind": "UNIT", "type": 50, "armors": PackedStringArray(m.armors), "weapons": PackedStringArray(m.weapons)}


func apply_hero(u: GameUnit) -> void:
	for h: Dictionary in heroes.get(u.controller, []):
		if String(h.get("unit_name", h.name)) == String(u.info.get("name", "")) or h.prototype == u.proto.get("name", ""):
			u.display_name = h.name
			Combat.hero_stats(u, h)
			# Aggressive / Defensive (unit) is part of the original's unit
			# save record (restored).
			u.aggressive = bool(h.get("aggressive", true))
			# So is the gait, but only outside villages (entry_gait).
			u.restore_gait(entry_gait(u.world, int(h.get("gait", 2))))
			if float(h.hp) > 0.0:
				u.hp = minf(float(h.hp), u.max_hp)
			u.set_meta("hero", h)
			return


## The gait a party unit enters a zone with (the original, party
## deployment): the unit is made new (: posture = 2 and
## gait = 2, walk) and its record's gait is put back only when
## the world mode is 1 — a game zone (: zone type 0 → 1
## the global map 1 → 4, a village 2 → 3) — and not on the campaign start
## spot of zone1. So a village is always entered walking and standing, with
## no orders (the units are new). (A per-unit spot record of the
## deployment, second argument, sets it with the posture
##  in any mode; the remake's save loading restores it so.)
static func entry_gait(world: GameWorld, g: int) -> int:
	if world and String(world.zone.get("type", "game")) == "brief":
		return 2
	return g


func store_party_positions(world: GameWorld) -> void:
	for u: GameUnit in world.units.values():
		if u.has_meta("hero"):
			var h: Dictionary = u.get_meta("hero")
			h.hp = u.hp
			h.mana = u.mana
			h.pos = u.pos
			h.gait = u.gait()


## Refreshes `pets` from the tamed party members in `world`.
func collect_pets(world: GameWorld) -> void:
	pets = []
	for u: GameUnit in world.units.values():
		if is_pet(u):
			var rec := u.info.duplicate()
			rec.erase("nid")
			var pet := {"rec": rec, "hp": u.hp, "controller": u.controller, "pos": u.pos}
			u.set_meta("pet", pet)
			pets.append(pet)


static func is_pet(u: GameUnit) -> bool:
	return not u.dead and not u.has_meta("hero") and int(u.get_meta("tame_stage", 0)) >= 3


func restore_party_positions(world: GameWorld) -> void:
	for u: GameUnit in world.units.values():
		if u.has_meta("pet") and u.get_meta("pet").has("pos"):
			u.pos = u.get_meta("pet").pos
		if u.has_meta("hero"):
			var h: Dictionary = u.get_meta("hero")
			if h.has("pos"):
				u.pos = h.pos
			if h.has("hp") and float(h.hp) > 0.0:
				u.hp = minf(float(h.hp), u.max_hp)
			if h.has("mana"):
				u.mana = minf(float(h.mana), u.max_mana)
			if h.has("gait"):
				u.restore_gait(int(h.gait))


# ---------------------------------------------------------------- zones

func store_zone(id: String, world: GameWorld) -> void:
	if world == null or id.is_empty():
		return
	var z := {"dead": [], "removed": [], "units": {}, "levers": {}, "vm": {}, "loot": {},
		"added": world.get_meta("added_mobs", [])}
	var present := {}
	for u: GameUnit in world.units.values():
		if u.has_meta("hero") or is_pet(u):
			continue   # pets leave with the party (collect_pets)
		present[u.uid] = true
		if u.dead:
			z.dead.append(u.uid)
			if u.has_meta("loot"):
				z.loot[u.uid] = u.get_meta("loot")
		else:
			z.units[u.uid] = [u.pos.x, u.pos.y, u.hp, u.faction, u.hidden]
	# Looted corpses (Session.take_loot) are off the world but WasLooted still
	# sees them (GameWorld.looted).
	z.looted = world.looted.keys()
	if world.map:
		for r: Dictionary in world.map.unit_records:
			if not present.has(int(r.nid)):
				z.removed.append(int(r.nid))
	for nid in world.levers:
		z.levers[nid] = [world.levers[nid].state, world.lever_sys.figure_t(nid) if world.lever_sys else 0.0,
			bool(world.levers[nid].get("enabled", true))]
	z.diplomacy = world.diplomacy   # script SetDiplomacy
	z.water = world.water_levels.duplicate(true)   # SetWaterLevel (saved by the original)
	z.traps = world.traps.save_state()   # ActivateTrap flag and countdown (saves the object)
	if world.vm:
		z.vm = world.vm.save_state()
	# Running tornadoes: the original saves them with the world's objects (the
	# effect list by id, the object through its stream slot =
	# position, step, life, start tick; read back).
	if world.tornadoes and not world.tornadoes.list.is_empty():
		z.tornado = world.tornadoes.save_state()
	# Remake-only: script-hidden / removed map objects and script particle
	# sources (Session._track) last as long as the zone does.
	if world.has_meta("replay"):
		var rs: Dictionary = world.get_meta("replay")
		z.objs = rs.objs.duplicate()
		z.moved = rs.get("moved", {}).duplicate(true)
		z.fx = rs.fx.duplicate(true)
		z.music = rs.music.duplicate()
	zones[id] = z


func restore_zone(id: String, world: GameWorld) -> void:
	var z: Dictionary = zones.get(id, {})
	if z.is_empty():
		return
	# Units that scripts added from extra .mob files come back first.
	for file: String in z.get("added", []):
		var extra := EIMob.load_bytes(GameData.read_file("maps/" + file))
		for o: Dictionary in extra.objects:
			if o.kind == "UNIT" and not world.units.has(int(o.get("nid", -1))):
				world.spawn_unit(o)
		world.add_mob_objects(file)
	world.set_meta("added_mobs", z.get("added", []).duplicate())
	var looted: Array = z.get("looted", [])
	for nid in z.removed:
		var u: GameUnit = world.units.get(int(nid))
		if u and looted.has(int(nid)):
			u.dead = true
			u.hp = 0
			world.remove_looted(u)
		elif u:
			world.remove_unit(u)
	for nid in z.dead:
		var u: GameUnit = world.units.get(int(nid))
		if u:
			u.dead = true
			u.hp = 0
			u.model.act("death", 1, 0.0)
			u.freeze_pose(true)
			if z.get("loot", {}).has(nid):
				u.set_meta("loot", z.loot[nid])
	for nid in z.units:
		var u: GameUnit = world.units.get(int(nid))
		if u:
			var s: Array = z.units[nid]
			u.pos = Vector2(s[0], s[1])
			u.hp = s[2]
			if s.size() > 4:   # script SetPlayer / HideObject
				u.faction = int(s[3])
				u.hidden = bool(s[4])
				u.visible = not u.hidden
	for nid in z.levers:
		if world.levers.has(int(nid)):
			var v = z.levers[nid]
			if v is Array:
				world.lever_sys.restore(int(nid), int(v[0]), float(v[1]))
				if v.size() > 2:   # EnableLever
					world.levers[int(nid)].enabled = bool(v[2])
			else:   # older saves: the state alone
				world.levers[int(nid)].state = int(v)
				world.lever_sys.apply(int(nid), false)
	if z.has("objs") or z.has("fx"):
		world.set_meta("replay", {"objs": z.get("objs", {}).duplicate(), "fx": z.get("fx", {}).duplicate(true),
			"magic": {}, "spells": [], "music": z.get("music", {}).duplicate(), "weather": {}, "tornado": {},
			"moved": z.get("moved", {}).duplicate(true)})
		for nid in z.get("moved", {}):   # script SetCP on objects
			var mp: Array = z.moved[nid]
			world.move_object(int(nid), Vector3(mp[0], mp[1], mp[2]))
		for nid in z.get("objs", {}):
			var o = world.objects.get(int(nid))
			if o and is_instance_valid(o):
				if int(z.objs[nid]) == 2:
					# As ScriptVM RemoveObjectFromServer / the clients' "remove_obj":
					# out of the object table, the levers and the walk grid too.
					world.objects.erase(int(nid))
					world.levers.erase(int(nid))
					world.nav.remove_object(int(nid))
					o.queue_free()
				else:
					o.visible = int(z.objs[nid]) != 1
	if z.get("diplomacy", PackedInt32Array()).size() >= 1024:
		world.diplomacy = z.diplomacy
	world.set_water_state(z.get("water", {}))
	world.traps.restore_state(z.get("traps", {}))
	world.set_meta("restored_vm", z.get("vm", {}))
	if not z.get("tornado", []).is_empty():
		world.set_meta("restored_tornado", z.tornado)


# ---------------------------------------------------------------- files

func to_dict() -> Dictionary:
	return {"version": 1, "vars": vars, "heroes": heroes, "zones": zones, "visited": visited,
		"quests": quests, "money": money, "items": items, "quest_items": quest_items,
		"parties": parties, "current_party": current_party, "party_bags": party_bags, "experience": experience, "mercs": mercs, "pets": pets, "side_quests": side_quests, "shops": shops, "current_zone": current_zone,
		"world_time": world_time, "day": day, "coop": coop, "camera": camera}


func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(to_dict())
	return OK


static func load_from(path: String) -> CampaignState:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var value: Variant = f.get_var(false)
	if not value is Dictionary or not value.get("heroes", {}) is Dictionary:
		return null
	var d: Dictionary = value
	var s := CampaignState.new()
	for k in d:
		if k != "version" and k in s:
			s.set(k, d[k])
	# Older remake builds marked "b.<npc>.constr*" told (2) when a topic list
	# opened; the original never ends them (opens the shop instead), so
	# they are pending (1) again.
	for k: String in s.vars.keys():
		if k.get_slice(".", 2).begins_with("constr") and k.contains(":b.") and is_equal_approx(float(s.vars[k]), 2.0):
			s.vars[k] = 1.0
	return s
