class_name MpCharacter
extends RefCounted
## Network characters of the original's multiplayer game (LmpMode): made on the
## character screens (ui/mp_char_panel.gd), kept on the client and brought to
## any server. See.
##
## the original keeps one file per character, "<game>\mp\<n>.mp" (:
## the list object gets + "mp\"; loads
## every "*.mp"; names a new one "%d.mp", n = the largest number
## there + 1). A file holds the player's party object (: name
## containers, exactly one 0x784-byte hero record, the player's GS vars and
## the money XORed with a random key) in the savegame container
## (magic 0x114, version 116, checksum, Nival LZ). The remake keeps the same
## layout of files — user://mp/<n>.mp — but stores its own records in them
## (Godot Variant: {"heroes": [hero record], "money", "items": [] — the bag is
## not in the original's file}), as its save
## games do: the original's binary hero record maps onto the original's unit classes.

const DIR := "user://mp/"
const MAGIC := "EIMP"
const VERSION := 1
const TrainingRefund := preload("res://src/game/training_refund.gd")
## Str + Dex + Int must be 75 to go ; each 15..35
const ATTR_SUM := 75
const ATTR_MIN := 15
const ATTR_MAX := 35
##  (New / Cancel): six attribute fields 25.0, height 0.7.
const ATTR_START := 25
const HEIGHT_START := 0.7
## The edit boxes' limit ((.., 10,..)): name and clan.
const NAME_MAX := 10
## " | ": the hero's name holds "Name | Clan".
const CLAN_SEP := " | "

## The character the player plays (file name, "" none) — / the
## selection screen's in the original. Kept in user:, mp/selected.cfg.
static var selected := ""
static var _loaded_sel := false
static var _selection_dir := ""


# ---------------------------------------------------------------- files

static func dir_path() -> String:
	return ModStore.save_directory(DIR.trim_suffix("/")) + "/"


## The characters on disk, as lists them: every "*.mp" that reads
## back with exactly one hero record (others are skipped, not deleted), in
## name order (FindFirstFile on NTFS: "1.mp", "10.mp", "2.mp" ...).
## [{file, data}]
static func list() -> Array:
	var out := []
	var d := DirAccess.open(dir_path())
	if d == null:
		return out
	var names := Array(d.get_files()).filter(func(f): return String(f).to_lower().ends_with(".mp") and _numbered(f))
	names.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	for f: String in names:
		var data := load_file(f)
		if not data.is_empty():
			out.append({"file": f, "data": data})
	return out


## "<digits>.mp" (refuses to write any other name).
static func _numbered(f: String) -> bool:
	var stem := f.get_basename()
	return not stem.is_empty() and stem.is_valid_int() and not "-" in stem and not "+" in stem


static func load_file(f: String) -> Dictionary:
	var fa := FileAccess.open(dir_path() + f, FileAccess.READ)
	if fa == null or fa.get_length() < 8:
		return {}
	if fa.get_buffer(4).get_string_from_ascii() != MAGIC or fa.get_32() > VERSION:
		return {}
	var v = fa.get_var(false)
	if not v is Dictionary or not one_hero(v):
		return {}
	if ModStore.saved_error(v.get("mod_config", {})) != "": return {}
	return v


## the old file goes to "temp.mp" while the new one is written
## then "temp.mp" is deleted.
static func save_file(f: String, data: Dictionary) -> bool:
	if not _numbered(f) or not one_hero(data):
		return false
	if ModStore.saved_error(data.get("mod_config", {})) != "": return false
	DirAccess.make_dir_recursive_absolute(dir_path())
	var tmp := dir_path() + "temp.mp"
	if FileAccess.file_exists(dir_path() + f):
		DirAccess.rename_absolute(dir_path() + f, tmp)
	var fa := FileAccess.open(dir_path() + f, FileAccess.WRITE)
	if fa == null:
		if FileAccess.file_exists(tmp):
			DirAccess.rename_absolute(tmp, dir_path() + f)
		return false
	fa.store_buffer(MAGIC.to_ascii_buffer())
	fa.store_32(VERSION)
	fa.store_var(data, false)
	fa.close()
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	return true


## DeleteFileA(dir + entry).
static func delete_file(f: String) -> void:
	if _numbered(f):
		DirAccess.remove_absolute(dir_path() + f)
	if f == selected:
		select("")


## "%d.mp" with the largest number among "<dir>*.mp" + 1.
static func next_file() -> String:
	var n := 0
	var d := DirAccess.open(dir_path())
	if d:
		for f: String in d.get_files():
			if f.to_lower().ends_with(".mp") and _numbered(f):
				n = maxi(n, f.get_basename().to_int())
	return "%d.mp" % (n + 1)


static func select(f: String) -> void:
	_selection_dir = dir_path()
	selected = f
	_loaded_sel = true
	DirAccess.make_dir_recursive_absolute(dir_path())
	var cfg := ConfigFile.new()
	cfg.set_value("mp", "selected", f)
	cfg.save(dir_path() + "selected.cfg")


## The selected character's file ("" when none or gone).
static func selected_file() -> String:
	if _selection_dir != dir_path():
		_selection_dir = dir_path()
		_loaded_sel = false
		selected = ""
	if not _loaded_sel:
		_loaded_sel = true
		var cfg := ConfigFile.new()
		if cfg.load(dir_path() + "selected.cfg") == OK:
			selected = String(cfg.get_value("mp", "selected", ""))
	if selected and not FileAccess.file_exists(dir_path() + selected):
		selected = ""
	return selected


## The selected character's record ({} none).
static func current() -> Dictionary:
	var f := selected_file()
	return load_file(f) if f else {}


static func one_hero(data) -> bool:
	return data is Dictionary and data.get("heroes") is Array and (data.heroes as Array).size() == 1 \
		and data.heroes[0] is Dictionary


static func hero_of(data: Dictionary) -> Dictionary:
	return data.heroes[0] if one_hero(data) else {}


# ---------------------------------------------------------------- names

## The name before " | " (splits at '|').
static func name_part(full: String) -> String:
	var i := full.find("|")
	return (full.substr(0, i) if i >= 0 else full).strip_edges()


static func clan_part(full: String) -> String:
	var i := full.find("|")
	return full.substr(i + 1).strip_edges() if i >= 0 else ""


##  (Enter in the clan box): the name, then " | " + clan unless
## the clan is empty.
static func with_clan(full: String, clan: String) -> String:
	clan = clan.strip_edges()
	return name_part(full) + (CLAN_SEP + clan if clan else "")


## The edit box's characters (mask 3): digits, letters and the
## space; at most 10 (the pixel limit is the panel's).
static func name_char_ok(c: String) -> bool:
	if c.length() != 1 or c == " ":
		return c == " "
	var u := c.unicode_at(0)
	return (u >= 48 and u <= 57) or c.to_upper() != c.to_lower()


# ---------------------------------------------------------------- creation

## The faces to choose : every NPC row of databaseLMP.res
## whose prototype's race model is "unhuma" (male) or "unhufe"
## (female). [[male protos], [female protos]]
##  sort the prototype names with the byte-wise
## strcmp reverses the sorted female vector.
static func faces() -> Array:
	var male := []
	var female := []
	for npc: Dictionary in _rows("npcs"):
		var proto := GameData.db.find("monster_prototypes", String(npc.get("name", "")))
		if proto.is_empty():
			continue
		var model := String(GameData.db.find("race_models", String(proto.get("base_race", ""))).get("mask", "")).to_lower()
		if model == "unhuma":
			male.append(String(npc.name))
		elif model == "unhufe":
			female.append(String(npc.name))
	male.sort()
	female.sort()
	female.reverse()
	return [male, female]


## The voices: every NPC row with its voice flag, into
## the male or female list by its race model, shown "%s %d" with
## «lmp_male_voice» / «lmp_female_voice», numbered from 1. These distinct
## vectors retain NPC table order; only faces are sorted.
## [[male], [female]]
static func voices() -> Array:
	var out := [[], []]
	for npc: Dictionary in _rows("npcs"):
		if not npc.get("voice", false):
			continue
		var proto := GameData.db.find("monster_prototypes", String(npc.get("name", "")))
		var model := String(GameData.db.find("race_models", String(proto.get("base_race", ""))).get("mask", "")).to_lower()
		if model == "unhuma":
			out[0].append(String(npc.name))
		elif model == "unhufe":
			out[1].append(String(npc.name))
	return out


static func _rows(table: String) -> Array:
	var t = GameData.db.tables.get(table, []) if GameData.db else []
	return t if t is Array else []


## A new character of face prototype `proto` (
## ): the prototype's armour (wears) and
## build, the NPC row's whole kit — weapons, belt items
## spells, money (500) and experience to spend (500
## ), its skills (all 0). Attributes 25 / 25 / 25, height 0.7.
## The kit is cut to one weapon, one belt item and one spell when the
## character is finished (`finish`).
static func create(proto_name: String) -> Dictionary:
	var proto := GameData.db.find("monster_prototypes", proto_name)
	var npc := GameData.db.find("npcs", proto_name)
	var xp := float(npc.get("exp_to_distribute", 0.0))
	var c := GameUnit.proto_complexion(proto)
	c.z = HEIGHT_START
	var h := {
		"prototype": proto_name, "name": "", "level": 1,
		"exp": xp, "exp_total": float(npc.get("experience", 0.0)) + xp,
		"skills": Skills.from_npc(npc),
		"str": float(ATTR_START), "dex": float(ATTR_START), "int": float(ATTR_START),
		"hp": -1.0, "complexion": c,
		"armors": Array(Items.split_list(proto.get("wears", []))).map(func(x): return String(x).to_lower()),
		"weapons": Array(Items.split_list(npc.get("weapons", []))).map(func(x): return String(x).to_lower()),
		"quick": Array(Items.split_list(npc.get("quest_items", []))).map(func(x): return String(x).to_lower()),
		"spells": Array(Items.split_list(npc.get("spells", []))).map(func(x): return String(x).to_lower()),
		"perks": Array(npc.get("perks", [])).map(func(x): return String(x).to_lower()),
		"voice": "",
	}
	var v := voices()
	h.voice = String(v[1][0] if is_female(proto_name) and not v[1].is_empty() else (v[0][0] if not v[0].is_empty() else ""))
	TrainingRefund.start(h)
	reshape(h)
	return {"heroes": [h], "mod_config": ModStore.effective().duplicate(true), "money": int(npc.get("money", 0)), "items": []}


static func is_female(proto_name: String) -> bool:
	return faces()[1].has(proto_name)


## Another face for the character being made (in state 10): the
## hero is rebuilt from the new prototype; attributes, height and name stay.
static func change_face(data: Dictionary, proto_name: String) -> Dictionary:
	var old := hero_of(data)
	var out := create(proto_name)
	var h := hero_of(out)
	for k in ["str", "dex", "int", "name"]:
		h[k] = old.get(k, h[k])
	var c: Vector3 = h.complexion
	c.z = (old.complexion as Vector3).z if old.get("complexion") is Vector3 else HEIGHT_START
	h.complexion = c
	reshape(h)
	return out


##  (the network hero editor only): the build
## from Strength and Dexterity, height kept. Remake complexion order (fat,
## muscle, height) as Combat.reshape.
static func reshape(h: Dictionary) -> void:
	var a := (float(h.str) - 15.0) / 20.0
	var b := 1.0 - (float(h.dex) - 15.0) / 20.0
	var old: Vector3 = h.get("complexion", Vector3(0.5, 0.5, HEIGHT_START))
	h.complexion = Vector3((a * 0.2 + b * 0.8) * 0.8 + 0.2, a * 0.7 + b * 0.3, old.z)


static func points_left(h: Dictionary) -> int:
	return ATTR_SUM - (int(h.str) + int(h.dex) + int(h.int))


## "+" / "−" on an attribute: − while above 15; + while below
## 35 and the sum below 75.
static func step_attr(h: Dictionary, attr: String, d: int) -> bool:
	var v := int(h.get(attr, ATTR_START))
	if d < 0 and v <= ATTR_MIN or d > 0 and (v >= ATTR_MAX or points_left(h) < 1):
		return false
	h[attr] = float(v + d)
	reshape(h)
	return true


## The height panel: an int 0..100, the hero's = value / 100
## shown as __ftol(· 100).
static func height_of(h: Dictionary) -> int:
	var c = h.get("complexion")
	return clampi(int(float(c.z) * 100.0 + 1e-4) if c is Vector3 else 70, 0, 100)


static func step_height(h: Dictionary, d: int) -> bool:
	var v := height_of(h)
	if d < 0 and v < 1 or d > 0 and v > 99:
		return false
	var c: Vector3 = h.complexion
	c.z = (v + d) * 0.01
	h.complexion = c
	return true


## Next from the creation step needs the balance 0 and a name.
static func can_continue(h: Dictionary) -> bool:
	return points_left(h) == 0 and not String(h.get("name", "")).is_empty()


## every weapon, belt item and spell but the chosen one of each
## goes (the active weapon is the first); the chosen spell goes too when the
## hero cannot take it (its school knowledge below the spell's complexity, or
## too little stamina:).
static func finish(data: Dictionary, weapon: String, belt: String, spell: String) -> void:
	var h := hero_of(data)
	h.weapons = [weapon] if weapon and (h.weapons as Array).has(weapon) else []
	h.quick = [belt] if belt and (h.quick as Array).has(belt) else []
	var stamina := Skills.base_pool(float(h.get("exp_total", 0.0)), float(h.get("dex", 25.0)), "MP")
	h.spells = [spell] if spell and (h.spells as Array).has(spell) and Spells.usable_by(h, stamina, spell) else []


# ---------------------------------------------------------------- network

## Host: a character a client brought, as the original's server takes it
## (message 8,; and for files): exactly one hero
## record, otherwise refused; nothing else is checked there — stats, items,
## money, level and name are taken as they come. Remake: the record is then
## made safe for this game like a brought campaign hero
## (CoopProgress.sanitize_hero: unknown prototype → Human Hero, unknown items
## dropped, numbers clamped) and the money bounded; {} when refused. The
## bag (player) is not part of the party record, so a
## character always arrives with an empty one.
static func accept(data) -> Dictionary:
	if not data is Dictionary or ModStore.saved_error(data.get("mod_config", {})) != "": return {}
	if not data.get("mod_config", {}).is_empty() and ModStore.progress_signature(data.mod_config) != ModStore.progress_signature(ModStore.effective()): return {}
	if not one_hero(data):
		return {}
	var h := CoopProgress.sanitize_hero(hero_of(data))
	if h.is_empty():
		return {}
	var v = hero_of(data).get("voice")
	h.voice = String(v) if v is String and not GameData.db.find("npcs", v).is_empty() else ""
	return {"heroes": [h], "money": clampi(int(CoopProgress._num(data.get("money", 0), 0.0)), 0, 99999999),
		"items": []}


## The party record of a hero and its purse, as the original's server sends it
## back (message 0x80) for the client to save:
## the hero and the money; not the bag (does not)
## so `items` is ignored.
static func record(hero: Dictionary, money: int, _items: Array) -> Dictionary:
	var h := hero.duplicate(true)
	for k in ["pos", "unit_name", "mana", "controller"]:
		h.erase(k)
	h.hp = -1.0
	return {"heroes": [h], "mod_config": ModStore.effective().duplicate(true), "money": money, "items": []}
