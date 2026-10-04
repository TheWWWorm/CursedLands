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
## A hero's belt (player list) holds at most four entries: the camp's
## put-on returns at a fifth (case 0x3006, count > 3) and
## the zone transfer copies four ((0..3)). The camp's
## top row shows them in its right four cells.
const BELT_SLOTS := 4


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
	var weapons := proto_weapons(proto)
	var extra := []   # remake co-op fallback kit beyond the four weapon slots
	if weapons.is_empty() and player > 0:
		weapons = Items.split_list(npc.get("weapons", []))
		extra = Array(weapons).slice(4)
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
	# Only what does not fit the four weapon slots goes to the shared bag (the
	# carried weapons are not copied there too).
	for w in extra:
		items.append(String(w).to_lower())
	if player > 0:   # remake co-op kit; the campaign hero's belt starts empty
		for q in Items.split_list(npc.get("quest_items", [])):
			hero.quick.append(q.to_lower())
		cap_belt(hero, items)
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
		"weapons": Array(proto_weapons(proto)).map(func(x): return String(x).to_lower()),
		"quick": [], "spells": [],
	}
	parties.get_or_add(party, []).append(h)


## A party record's weapons as the original makes them (
## new game, script party units, hiring): the prototype's
## weapon and second weapon, each added when its name is
## not empty or "none" (hands both over), into the record's
## weapon list. Nothing goes to the bag.
static func proto_weapons(proto: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k in ["weapon", "second_weapon"]:
		var w := String(proto.get(k, "")).strip_edges()
		if w != "" and w.to_lower() != "none":
			out.append(w)
	return out


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


## Script FixItems: every item back to full durability (only; the
## charge it carries stays).
func fix_items() -> void:
	var fix := func(l: Array) -> void:
		for i in l.size():
			if l[i] is String:
				l[i] = Items.with_wear(l[i], 0.0)
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
		if String(h.get("voice", "")) != "":
			rec.voice = String(h.voice)   # a network character's chosen voice (MpCharacter)
		out.append(rec)
	return out


## Hero record for mercenary N created from its NPC unit (or its map record).
func make_merc(n: int, rec: Dictionary) -> Dictionary:
	var proto_name := String(rec.get("prototype", rec.get("parent_template", "")))
	var proto := GameData.db.find("monster_prototypes", proto_name)
	var npc := GameData.db.find("npcs", proto_name)
	var kit := merc_kit(rec, proto)
	var m := {
		"prototype": proto_name, "merc": n,
		"name": GameUnit.unit_title(proto_name) if String(rec.get("name", "")).to_lower().begins_with("merc") else String(rec.get("name", "")),
		"level": 1, "exp": 0.0,
		"exp_total": float(npc.get("experience", 0.0)), "skills": Skills.from_npc(npc),
		"perks": Array(npc.get("perks", [])).map(func(x): return String(x).to_lower()),
		"str": float(npc.get("str", 22.0)), "dex": float(npc.get("dex", 22.0)), "int": float(npc.get("int", 18.0)),
		"hp": -1.0,
		"complexion": rec.get("complexion", GameUnit.proto_complexion(proto)),
		"armors": kit.armors,
		"weapons": kit.weapons,
		"quick": kit.quick,
		"spells": kit.spells,
		"controller": 0,
	}
	if String(m.name).is_empty():
		m.name = "Mercenary %d" % n
	mercs[n] = m
	return m


## What a hired mercenary carries. the original (hire, n1 / n3) does
## not make a new unit: appends a party record for
## the village unit "merc<N>", and that unit keeps the items it was given when
## the map loaded (the record takes them from the unit when the party leaves
## the zone). The map load gives the unit:
## the prototype's wears, weapon
##      and second weapon into the four weapon slots
##      and its spells
## the record's belt items (UNIT_QUICK_ITEMS
##     four slots) always; only for a record whose "need import" stats apply
##     (Combat.mob_imports) also its spells, armours (each replacing the worn
##     item of its slot) and weapons (appended to the weapon
##     slots; returns -1 and the item is lost once all four are
##     taken).
## Nothing goes to the party bag. Every original mercenary record has need
## import 0, so a mercenary carries its prototype's kit; Merc1 (basecam.mob,
## Human Mercenary Warrior) the stone axe and the stone short bow once each.
static func merc_kit(rec: Dictionary, proto: Dictionary) -> Dictionary:
	var low := func(x): return String(x).to_lower()
	var imports := Combat.mob_imports(rec)
	var weapons: Array = Array(proto_weapons(proto)).map(low)
	var armors: Array = Array(Items.split_list(proto.get("wears", []))).map(low)
	var spells: Array = Array(Items.split_list(proto.get("spells", []))).map(low)
	if imports:
		for a in Array(rec.get("armors", [])).map(low):
			var s := Items.slot(a)
			var at := -1
			for i in armors.size():
				if s != "" and Items.slot(armors[i]) == s:
					at = i
			if at >= 0:
				armors[at] = a
			else:
				armors.append(a)
		for w in Array(rec.get("weapons", [])).map(low):
			if weapons.size() < 4:
				weapons.append(w)
		spells.append_array(Array(rec.get("spells", [])).map(low))
	var quick: Array = Array(rec.get("quick_items", [])).map(low).slice(0, BELT_SLOTS)
	return {"weapons": weapons.slice(0, 4), "armors": armors, "spells": spells, "quick": quick}


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
			Combat.clear_natural_armor(u, h)
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
			h.body = body_state(u)
			# A party member lying dead stays so in a save (the original saves every
			# unit whole), put back by restore_party_positions.
			if u.dead:
				h.dead = true
			else:
				h.erase("dead")


## The F / Follow order across zones. the original (the party
## leaves a zone while the world mode is 1, a game zone) writes each
## party record's = its unit's follow target (the Player motivation's
## -1 when the unit has none), and the party deployment
##  gives it back in a game zone only (mode 1, not a village):
##  on the unit found by that id. Party units keep
## their ids there; the remake gives them new ones, so the target is kept as
## its party record (a hero by name and player, a mercenary by number) and
## only party members are found again. A village leaves the records as they
## are, so a follow given before a village comes back in the next game zone.
## `key` "follow_live" (remake): the order as it stands, for a save game (the
## original saves every unit whole); = none.
func store_follow(world: GameWorld, key := "follow") -> void:
	for u: GameUnit in world.units.values():
		if not u.has_meta("hero"):
			continue
		var h: Dictionary = u.get_meta("hero")
		var ref := party_ref(follow_target(u))
		if not ref.is_empty() or key == "follow_live":
			h[key] = ref
		else:
			h.erase(key)


## `key` as store_follow wrote it, given back to the party units in `world`
## ("follow_live" is used up: a later deployment goes by "follow").
func apply_follow(world: GameWorld, key := "follow", units: Array = []) -> void:
	for u: GameUnit in (units if not units.is_empty() else world.units.values()):
		if not u.has_meta("hero") or u.dead:
			continue
		var h: Dictionary = u.get_meta("hero")
		if not h.has(key):
			continue
		var ref: Array = h[key] if h[key] is Array else []
		if key == "follow_live":
			h.erase(key)
		var t := party_unit(world, ref)
		if t and t != u and not t.dead:
			u.command({"type": "follow", "target": t})


## The unit `u` follows (a lasting F order, not a talk / loot approach).
static func follow_target(u: GameUnit) -> GameUnit:
	var o: Dictionary = u.order if String(u.order.get("type", "")) != "" else (u.orders[-1] if not u.orders.is_empty() else {})
	if String(o.get("type", "")) != "follow" or o.get("once", false):
		return null
	var t = o.get("target")
	return t if t is GameUnit and is_instance_valid(t) and not t.dead else null


## A party unit as its record: ["merc", n] / ["hero", name, player]; [] for others.
static func party_ref(u: GameUnit) -> Array:
	if u == null or not u.has_meta("hero"):
		return []
	var h: Dictionary = u.get_meta("hero")
	if h.has("merc"):
		return ["merc", h.merc]
	return ["hero", String(h.get("unit_name", h.get("name", ""))), u.controller]


static func party_unit(world: GameWorld, ref: Array) -> GameUnit:
	if ref.size() < 2:
		return null
	for u: GameUnit in world.units.values():
		if not u.has_meta("hero"):
			continue
		var h: Dictionary = u.get_meta("hero")
		if ref[0] == "merc" and h.has("merc") and str(h.merc) == str(ref[1]):
			return u
		if ref[0] == "hero" and ref.size() >= 3 and not h.has("merc") and u.controller == int(ref[2]) \
				and String(h.get("unit_name", h.get("name", ""))) == String(ref[1]):
			return u
	return null


## Refreshes `pets` from the tamed party members in `world`.
func collect_pets(world: GameWorld) -> void:
	pets = []
	for u: GameUnit in world.units.values():
		if is_pet(u):
			var rec := u.info.duplicate()
			rec.erase("nid")
			var pet := {"rec": rec, "hp": u.hp, "controller": u.controller, "pos": u.pos, "body": body_state(u)}
			u.set_meta("pet", pet)
			pets.append(pet)


static func is_pet(u: GameUnit) -> bool:
	return not u.dead and not u.has_meta("hero") and int(u.get_meta("tame_stage", 0)) >= 3


## After a load (Session.load_game), once the party units are deployed with
## their stats and equipment rebuilt (apply_hero / _spawn_merc / _spawn_pet).
func restore_party_positions(world: GameWorld) -> void:
	for u: GameUnit in world.units.values():
		if u.has_meta("pet") and u.get_meta("pet").has("pos"):
			u.pos = u.get_meta("pet").pos
		if u.has_meta("pet") and u.get_meta("pet").get("body") is Dictionary:
			apply_body(u, u.get_meta("pet").body)
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
			if h.get("body") is Dictionary:
				apply_body(u, h.body)
			if h.get("dead", false) and not u.dead:
				u.lie_dead()
				if world.session and not h.has("merc"):
					world.session.hero_died(u)   # the co-op respawn / the death notice
	replay_restored(world)


# ---------------------------------------------------------------- unit body / magic
# the original saves every unit whole (world save
# unit =; read back =), both
# in a save game (scenario.sav) and in the zone's state when the
# party leaves it (saves\current). Of that record the remake
# keeps what it models:
#   - the unit logic's stats block, written raw (
#     0x704 bytes), which holds the six body parts (0xf4 each: health
#     and state 3 intact / 2 destroyed / 1 severed / 0 none);
#   - the magic effects (map-object base: count, then
#      per 0x14-byte entry: type byte, strength byte, ticks left
#     +4 — the unit panel shows +4 / 15, — value +8 and
#     read back). On load the effect visuals
#     are made again with 30 prewarm updates and without the one-shot start
#     bursts (with its load flag).
# Leaving a zone does not carry them over to the next one: the hero records
# take only stats and items, and
# then makes every part of the record intact and full; the effects stay with
# the unit object.

## The magic effect's visual code of a buff (Spells._buff names it otherwise).
const _FX_CODE := {"invisible": "invisibility"}


## A unit's body parts ([health / max, state] each) and live magic effects
## ([name, seconds left, effect data, visual strength or -1, visual code]).
static func body_state(u: GameUnit) -> Dictionary:
	var parts := []
	for p: Dictionary in u.parts:
		var m := float(p.get("max", 0.0))
		parts.append([float(p.get("cur", 0.0)) / m if m > 0.0 else 1.0, int(p.get("state", 0))])
	var magic := []
	var now := u.world.time if u.world else 0.0
	var rs: Dictionary = u.world.get_meta("replay", {}) if u.world else {}
	var shown: Dictionary = rs.get("magic", {})
	for k: String in u.buffs:
		var b: Dictionary = Dictionary(u.buffs[k]).duplicate(true)
		var left := float(b.get("until", 0.0)) - now
		if left <= 0.0:
			continue
		b.erase("until")
		var code: String = _FX_CODE.get(k, k)
		var ev = shown.get("%d:%s" % [u.uid, code])
		var s := float(ev[0].get("s", 1.0)) if ev is Array and not ev.is_empty() and ev[0] is Dictionary else -1.0
		magic.append([k, left, b, s, code])
	return {"parts": parts, "magic": magic}


## Puts back body_state(u): the effects first (strength / weakness change the
## maximum HP), then the parts, so `hp` follows from them. The effect visuals
## wait in the world meta "restored_magic" for replay_restored.
static func apply_body(u: GameUnit, st: Dictionary) -> void:
	if u.dead or st.is_empty():
		return
	var now := u.world.time if u.world else 0.0
	var fx := []
	for e in st.get("magic", []):
		if not e is Array or e.size() < 3:
			continue
		var b: Dictionary = Dictionary(e[2]).duplicate(true)
		b.until = now + float(e[1])
		u.buffs[String(e[0])] = b
		if e.size() > 4 and float(e[3]) >= 0.0:
			fx.append({"t": "magicfx", "uid": u.uid, "code": String(e[4]), "secs": float(e[1]),
				"s": float(e[3]), "replay": true})
	u.refresh_max_hp()
	var ps: Array = st.get("parts", [])
	if not ps.is_empty() and ps.size() == u.parts.size():
		for i in ps.size():
			var p: Dictionary = u.parts[i]
			if int(p.state) == 0 or not ps[i] is Array:
				continue
			p.state = int(ps[i][1])
			p.cur = float(ps[i][0]) * float(p.max)
		u._wounds_dirty = true
		u._pose_dirty = true
		u._show_severed(u.severed_mask())
	if not fx.is_empty() and u.world:
		var q: Array = u.world.get_meta("restored_magic", [])
		q.append_array(fx)
		u.world.set_meta("restored_magic", q)


## Host, once `world` is the session's world and in the tree: the restored
## units' effect visuals and the zone's lasting ground spells run again
## (sent to the co-op clients too, as already running: no start sound).
func replay_restored(world: GameWorld) -> void:
	if world == null or world.session == null:
		return
	var q: Array = world.get_meta("restored_magic", [])
	world.remove_meta("restored_magic")
	for ev: Dictionary in q:
		if world.units.has(int(ev.uid)):
			world.session.broadcast(ev)
	var lasting: Array = world.get_meta("restored_lasting", [])
	world.remove_meta("restored_lasting")
	var shown: Array = world.get_meta("restored_spellfx", [])
	world.remove_meta("restored_spellfx")
	# A save that kept the fireballs' visuals (with their age: newer saves,
	# Session._track) brings them back itself; the running spells then do not
	# start one of their own (Spells.restore_lasting, older saves).
	var seen := {}
	for e in shown:
		var e0: Dictionary = e[0]
		if e0.has("age") and Spells.parse(String(e0.get("spell", e0.get("code", "")))).code == "fireball":
			seen.fireball = true
	Spells.restore_lasting(world, lasting, seen)
	for e in shown:
		var ev: Dictionary = Dictionary(e[0]).duplicate()
		if Spells.parse(String(ev.get("spell", ev.get("code", "")))).code in Session.LASTING_SPELLFX:
			ev.left = float(e[1])
		ev.replay = true
		ev.erase("a")   # unit ids change with the deployment; dx / dy keep the wall's direction
		world.session.broadcast(ev)


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
		if u.has_meta("lmp_owner"):
			# A multiplayer hero's body (Session._lmp_respawn) is no map unit:
			# it stays in the zone with its record (world list).
			var rec: Dictionary = u.info.duplicate(true)
			rec.nid = u.uid
			rec.position = Vector3(u.pos.x, u.pos.y, 0)
			z.get_or_add("bodies", []).append({"rec": rec, "facing": u.facing, "loot": u.get_meta("loot", []),
				"owner": int(u.get_meta("lmp_owner")), "conn": int(u.get_meta("lmp_conn", 0))})
			continue
		present[u.uid] = true
		if u.dead:
			z.dead.append(u.uid)
			if u.has_meta("loot"):
				z.loot[u.uid] = u.get_meta("loot")
		else:
			z.units[u.uid] = [u.pos.x, u.pos.y, u.hp, u.faction, u.hidden, body_state(u)]
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
		# Their visuals (Session._track "spellfx"), with the time they have left.
		var shown := []
		for e in rs.get("spells", []):
			var left := float(e[1]) - world.time
			if left > 0.5:
				var ev: Dictionary = Dictionary(e[0]).duplicate()
				if e.size() > 2:   # its age in ticks (Session._track: the cast time)
					ev.age = roundi((world.time - float(e[2])) / GameUnit.TICK)
				shown.append([ev, left])
		if not shown.is_empty():
			z.spellfx = shown
	# Lasting ground spells still running (fire / lightning wall, acid fog,
	# camp fire, fireworks): the original saves every live spell object with the
	# world (: point, caster / target ids, target
	# point, the spell, counter, state), in save games and zone
	# states alike.
	var lasting := Spells.save_lasting(world)
	if not lasting.is_empty():
		z.lasting = lasting
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
	for b: Dictionary in z.get("bodies", []):
		var bu := world.spawn_unit(b.rec)
		if bu:
			bu.controller = -1
			bu.facing = float(b.facing)
			bu.dead = true
			bu.hp = 0
			bu.model.act("death", 1, 0.0)
			bu.freeze_pose(true)
			bu.set_meta("lmp_owner", int(b.owner))
			bu.set_meta("lmp_conn", int(b.conn))
			if not (b.loot as Array).is_empty():
				bu.set_meta("loot", b.loot)
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
			if s.size() > 5 and s[5] is Dictionary:   # body parts and magic effects
				apply_body(u, s[5])
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
	# Started by replay_restored once the world runs (Session.enter_zone).
	if not z.get("lasting", []).is_empty():
		world.set_meta("restored_lasting", z.lasting.duplicate(true))
	if not z.get("spellfx", []).is_empty():
		world.set_meta("restored_spellfx", z.spellfx.duplicate(true))
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


## Belt entries past BELT_SLOTS go to `bag` (kept, in order), e.g. from
## saves of builds that allowed eight.
static func cap_belt(h: Dictionary, bag: Array) -> void:
	var q = h.get("quick")
	if not (q is Array or q is PackedStringArray) or q.size() <= BELT_SLOTS:
		return
	for it in Array(q).slice(BELT_SLOTS):
		bag.append(it)
	h.quick = Array(q).slice(0, BELT_SLOTS)


## Every record's belt within BELT_SLOTS, the extras into that roster's bag:
## the current roster's into the bag, the mercenaries' (who stay with the main
## roster) and a waiting roster's into theirs.
func cap_belts() -> void:
	for k in heroes:
		for h in heroes[k]:
			if h is Dictionary:
				cap_belt(h, items)
	for m in mercs.values():
		if m is Dictionary:
			cap_belt(m, _bag("").items)
	for p in parties:
		for h in parties[p]:
			if h is Dictionary:
				cap_belt(h, _bag(p).items)


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
	s.migrate_charges()
	s.cap_belts()   # saves of builds whose belt took eight
	return s


## Saves of builds that kept charges in the hero record ("charges": item
## string → charge, shared by identical items): each of the record's items
## named there gets that charge on its own string (Items.with_charge), and
## the table goes. Items already in a bag keep a full charge.
func migrate_charges() -> void:
	var records: Array = mercs.values()
	for roster in heroes.values() + parties.values():
		if roster is Array:
			records.append_array(roster)
	for h in records:
		if not h is Dictionary or not h.get("charges") is Dictionary:
			continue
		var ch: Dictionary = h.charges
		for k in ["quick", "weapons", "armors"]:
			var l = h.get(k)
			if not l is Array:
				continue
			for i in l.size():
				if l[i] is String and ch.has(l[i]):
					l[i] = Items.with_charge(l[i], float(ch[l[i]]))
		h.erase("charges")
