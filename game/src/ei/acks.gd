class_name EIAcks
extends RefCounted
## Unit acknowledgement voices: database.res "acks.db", loaded by the original
## . Three sections of records keyed by unit name
## (prototype or race name, e.g. "Human Hero" for Zak):
##   1 hero acks, fields 10..44, one list of lines per event;
##   2 NPC reactions, fields 10..14 (to aggression, suspicion, kill, rest, ...);
##   3 two "wrld" lines.
## Each line: 1 wav path in sfx.res, 2 chance in percent, 3 Russian subtitle,
## 4 id. The original plays them by an event code
## CODE_FIELD is its code -> field table (the record offsets both functions use).

## Event codes (the original) used by the remake.
enum {SELECTED = 0, MOVE = 1, ATTACK = 2, CAST = 3, LOOT = 4, USE_OBJECT = 5, STEAL = 6, FOLLOW = 7,
	USE_POTION = 8, CHANGE_POSITION = 9, BIG_ATTACK = 0xa, NO_WAY_TO_ATTACK = 0xb, CANT_CHANGE_POSITION = 0xd,
	NO_PATH = 0xe, CANT_CAST = 0xf, CANT_TELEPORT = 0x10, SCIENCE_FAILED = 0x11, NO_TARGET = 0x12,
	SPELL_COMPLETE = 0x13, OVERLOAD = 0x14, INJURED = 0x15, DECIDE_TO_ATTACK = 0x1c, OUT_OF_STAMINA = 0x1d,
	ARM_CRIPPLED = 0x1e, LEG_CRIPPLED = 0x1f, ATTACKED_IN_DEFENCE = 0x20, WAIT_FOLLOW = 0x21, STEAL_EMPTY = 0x22,
	ARMOR_BROKEN = 0x23, WEAPON_BROKEN = 0x24, SHOP_YES = 0x27, SHOP_NO = 0x28, BORED = 0x29, SCENARIO = 0x2a,
	NPC_AGGRESSION = 0x2e, NPC_SUSPICION = 0x2f, NPC_KILL = 0x30, NPC_REST = 0x31, NPC_IN_AGGRESSION = 0x32}

## code -> [section, field]. Codes 0x16..0x1b, 0x25 and 0x26 have no lines
## (0x25 / 0x26 are the "item durability critical" warnings:
## no voice, only "weapons\timecrash.wav"). 0x29 "Bored" is
## field 32 (: record), its line chosen
## with the line's context mask (field 10); see GameSound.bored_context.
## Section 3 (0x2c / 0x2d, "npc\talk|rest\wrld.wav") is sent by no code path.
const CODE_FIELD := {
	0: [1, 10], 1: [1, 11], 2: [1, 12], 3: [1, 13], 4: [1, 14], 5: [1, 15], 6: [1, 16], 7: [1, 17],
	8: [1, 18], 9: [1, 19], 0xa: [1, 36], 0xb: [1, 20], 0xc: [1, 33], 0xd: [1, 21], 0xe: [1, 22],
	0xf: [1, 23], 0x10: [1, 24], 0x11: [1, 25], 0x12: [1, 26], 0x13: [1, 27], 0x14: [1, 34], 0x15: [1, 35],
	0x1c: [1, 28], 0x1d: [1, 29], 0x1e: [1, 30], 0x1f: [1, 31], 0x20: [1, 39], 0x21: [1, 40], 0x22: [1, 42],
	0x23: [1, 37], 0x24: [1, 38], 0x27: [1, 43], 0x28: [1, 44], 0x29: [1, 32], 0x2a: [1, 41],
	0x2c: [3, 10], 0x2d: [3, 11],
	0x2e: [2, 10], 0x2f: [2, 11], 0x30: [2, 12], 0x31: [2, 13], 0x32: [2, 14],
}

## section -> lower-case name -> field -> Array of {wav, chance, text}
static var _sets := {}
static var _loaded := false


## Decode the immutable voice/subtitle database while the loading screen is
## still visible. The first command or NPC reaction must only choose a line.
static func prepare() -> void:
	_load()


static func lines(names: Array, code: int) -> Array:
	_load()
	var cf: Array = CODE_FIELD.get(code, [])
	if cf.is_empty():
		return []
	var sec: Dictionary = _sets.get(cf[0], {})
	for n in names:
		var rec: Dictionary = sec.get(String(n).to_lower(), {})
		if rec.has(cf[1]):
			return rec[cf[1]]
	return []


## the line for a roll r = rand % 100 is a random one of the
## lines whose chance is at least r (none: silence).
static func pick(ls: Array) -> Dictionary:
	var r := randi() % 100
	var ok := ls.filter(func(l): return int(l.chance) >= r)
	return ok[randi() % ok.size()] if not ok.is_empty() else {}


##  (Bored, code 0x29): a random one of the lines whose mask
## holds every bit of the context (mask & ctx == ctx) and whose chance is at
## least r = rand % 100.
static func pick_masked(ls: Array, ctx: int) -> Dictionary:
	var r := randi() % 100
	var ok := ls.filter(func(l): return (int(l.mask) & ctx) == ctx and int(l.chance) >= r)
	return ok[randi() % ok.size()] if not ok.is_empty() else {}


##  (script "say <id> <unit>"): the unit record's Scenario line
## (section 1, field 41) whose id is exactly `id` (case-sensitive compare).
static func scenario_line(names: Array, id: String) -> Dictionary:
	for l: Dictionary in lines(names, SCENARIO):
		if String(l.id) == id:
			return l
	return {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if GameData.root.is_empty():
		return
	var arc := EIResArchive.open_path(GameData.root.path_join("res/database.res"))
	if arc == null or not arc.has("acks.db"):
		return
	var d := arc.read("acks.db")
	var top := _node(d, 0)
	for sec in _kids(d, top.y, top.y + top.z):
		var by_name := {}
		for rec in _kids(d, sec.y, sec.y + sec.z):
			var name := ""
			var fields := {}
			for f in _kids(d, rec.y, rec.y + rec.z):
				if f.x == 1:
					name = _str(d, f)
				elif f.z > 0:
					var ls := []
					for line in _kids(d, f.y, f.y + f.z):
						var l := {"wav": "", "chance": 100, "text": "", "id": "", "mask": 0}
						for v in _kids(d, line.y, line.y + line.z):
							match v.x:
								1: l.wav = _str(d, v)
								2: l.chance = d.decode_s32(v.y)
								3: l.text = _str(d, v)
								4: l.id = _str(d, v)
								10: l.mask = d.decode_u32(v.y) if v.z >= 4 else 0
						if l.wav:
							ls.append(l)
					fields[f.x] = ls
			if name and not by_name.has(name.to_lower()):
				by_name[name.to_lower()] = fields
		_sets[sec.x] = by_name


## (id, body start, body length) of the tagged node at `p` (EIDatabase format).
static func _node(d: PackedByteArray, p: int) -> Vector3i:
	var id := d[p]
	var n := d[p + 1]
	if n & 1:
		return Vector3i(id, p + 5, (d.decode_u32(p + 1) - 1) / 2)
	return Vector3i(id, p + 2, n / 2)


static func _kids(d: PackedByteArray, p: int, end: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	while p < end:
		var k := _node(d, p)
		out.append(k)
		p = k.y + k.z
	return out


static func _str(d: PackedByteArray, n: Vector3i) -> String:
	var e := n.y + n.z
	while e > n.y and d[e - 1] == 0:
		e -= 1
	return EIText.ansi(d.slice(n.y, e))
