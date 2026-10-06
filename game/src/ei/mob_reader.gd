class_name EIMob
extends RefCounted
## Reader for ".mob" map object files: a tree of (id, length, payload) nodes.
## Extracts placed objects/units and the level script (stored encrypted).

const R := {  # record node ids (containers)
	0xA000: "OBJECTDBFILE", 0xB000: "OBJECTSECTION", 0xB001: "OBJECT",
	0xABD0: "WORLD_SET", 0xFF00: "SEC_RANGE", 0xFF01: "MAIN_RANGE", 0xFF02: "RANGE",
	0x1E00: "VSS_SECTION", 0xAA01: "LIGHT", 0xCC01: "SOUND", 0xDD01: "PARTICL",
	0xBBBB0000: "UNIT", 0xBBAB0000: "MAGIC_TRAP", 0xBBAC0000: "LEVER",
	0xBBBC0000: "UNIT_LOGIC", 0xBBBD0000: "GUARD_PT", 0xBBBE0000: "ACTION_PT",
	0xBBBF0000: "TORCH", 0xDDDDDDD1: "DIPLOMATION",
}
## Records that describe one placed thing (UNIT/LEVER/TORCH/MAGIC_TRAP hold the
## same fields as OBJECT plus their own).
const OBJECT_KINDS := ["OBJECT", "UNIT", "LEVER", "TORCH", "MAGIC_TRAP"]
const OBJTYPE := 0xB003
const NID := 0xB002
const OBJNAME := 0xB004
const OBJTEMPLATE := 0xB006
const OBJPRIMTXTR := 0xB007
const OBJPOSITION := 0xB009
const OBJROTATION := 0xB00A
const OBJCOMPLECTION := 0xB00C
const OBJBODYPARTS := 0xB00D
const PARENTTEMPLATE := 0xB00E
const UNIT_PROTOTYPE := 0xBBBB0002
const UNIT_STATS := 0xBBBB0004
const UNIT_QUEST_ITEMS := 0xBBBB0005
const UNIT_QUICK_ITEMS := 0xBBBB0006
const UNIT_SPELLS := 0xBBBB0007
const UNIT_WEAPONS := 0xBBBB0008
const UNIT_ARMORS := 0xBBBB0009
const UNIT_NEED_IMPORT := 0xBBBB000A
const OBJ_PLAYER := 0xB011
const OBJ_PARENT_ID := 0xB012
const OBJ_USE_IN_SCRIPT := 0xB013
const OBJ_QUEST_INFO := 0xB016
const UNIT_LOGIC_MODEL := 0xBBBC0003
const UNIT_LOGIC_GUARD_R := 0xBBBC0004
const UNIT_LOGIC_GUARD_PT := 0xBBBC0005
const UNIT_LOGIC_AGRESSION_MODE := 0xBBBC000E
const UNIT_LOGIC_HELP := 0xBBBC000C
const UNIT_LOGIC_WAIT := 0xBBBC000A
const UNIT_LOGIC_CYCLIC := 0xBBBC0002
const UNIT_LOGIC_ALWAYS_ACTIVE := 0xBBBC000D
const GUARD_PT_POSITION := 0xBBBD0001
const ACTION_PT_LOOK_PT := 0xBBBE0001
const ACTION_PT_WAIT_SEG := 0xBBBE0002
const LEVER_CUR_STATE := 0xBBAC0002
const LEVER_TOTAL_STATE := 0xBBAC0003
const LEVER_IS_CYCLED := 0xBBAC0004
const LEVER_IS_DOOR := 0xBBAC0007
const LEVER_SCIENCE_STATS := 0xBBAC0006   # 3 ints (the Use-skill lock)
## MAGIC_TRAP fields (the original record, written):
## the players it fires at (a bit mask, default -1 = all), its spell, the
## areas that trigger it (x, y, radius), fixed target points (x, y), the cast
## interval in 55 ms ticks (default 15) and LEVER_CAST_ONCE (a byte).
const MT_DIPLOMACY := 0xBBAB0001
const MT_SPELL := 0xBBAB0002
const MT_AREAS := 0xBBAB0003
const MT_TARGETS := 0xBBAB0004
const MT_CAST_INTERVAL := 0xBBAB0005
const LEVER_CAST_ONCE := 0xBBAC0005
const DIPLOMATION_FOF := 0xDDDDDDD2
const DIPLOMATION_PL_NAMES := 0xDDDDDDD3
const SS_TEXT := 0xACCEECCB
## The script as plain text (the original reads it as a string); only
## zone20.mob, the Curse's cave, stores it this way.
const SS_TEXT_PLAIN := 0xACCEECCA

## Array of Dictionaries: {kind, type, nid, name, template, parent_template,
## texture, position: Vector3 (EI space), rotation: Quaternion (Godot), complexion: Vector3, parts}
var objects: Array[Dictionary] = []
var script_text := ""
## 32x32 matrix of player-vs-player relations (index = OBJ_PLAYER).
var diplomacy := PackedInt32Array()
var player_names := PackedStringArray()
## SOUND records (0xCC01, the original reader, defaults):
## {id, position (EI), inner, outer (ints, m; default 10 / 15), name,
## waves (PackedStringArray), min_ms, max_ms (default 1500 / 3000),
## random (byte), flag (byte)}.
var sounds: Array[Dictionary] = []


static func load_bytes(d: PackedByteArray) -> EIMob:
	var m := EIMob.new()
	m._walk(d, 0, d.size(), "ROOT", {})
	return m


func _walk(d: PackedByteArray, start: int, end: int, parent_kind: String, into: Dictionary) -> void:
	var p := start
	while p + 8 <= end:
		var id := d.decode_u32(p)
		var n := _record_size(d, p, end, id, parent_kind)
		if n < 8 or p + n > end:
			return
		var body := p + 8
		var blen := n - 8
		if R.has(id):
			var kind: String = R[id]
			if kind == "UNIT_LOGIC":
				# A unit has one logic descriptor per alarm (0 = normal, 1..4:
				# the ones switches to when alarm n is raised).
				# The first one's fields also stay on the unit itself.
				var lg := {}
				_walk(d, body, body + blen, kind, lg)
				if not into.has("logic"):
					into.logic = []
					into.merge(lg)
				into.logic.append(lg)
			elif kind == "GUARD_PT":
				var gp := {"actions": []}
				_walk(d, body, body + blen, kind, gp)
				if not into.has("guard_points"):
					into.guard_points = []
				into.guard_points.append(gp)
			elif kind == "ACTION_PT":
				var ap := {}
				_walk(d, body, body + blen, kind, ap)
				if into.has("actions"):
					into.actions.append(ap)
			elif kind == "SOUND":
				var snd := {"inner": 10, "outer": 15, "min_ms": 1500, "max_ms": 3000, "random": 0, "flag": 0,
					"waves": PackedStringArray(), "position": Vector3.ZERO, "name": ""}
				_walk(d, body, body + blen, kind, snd)
				sounds.append(snd)
			elif kind in OBJECT_KINDS:
				var obj := {"kind": kind, "parts": PackedStringArray(), "complexion": Vector3.ZERO,
					"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO, "texture": "", "template": ""}
				_walk(d, body, body + blen, kind, obj)
				objects.append(obj)
			else:
				_walk(d, body, body + blen, kind, into)
		else:
			_field(d, id, body, blen, into)
		p += n


func _record_size(d: PackedByteArray, p: int, end: int, id: int, parent_kind: String) -> int:
	# Native readers consume typed payloads; the next-header reader skips the
	# declared length only for unhandled fields (LiA 41fbd0 / 41fc60).
	# Shipped zone8 declares a 4-byte aggression field but stores one byte.
	# bz21k / zone13 omit the count word from both trap-array lengths.
	if parent_kind == "UNIT_LOGIC" and id == UNIT_LOGIC_AGRESSION_MODE:
		return 9   # LiA 441010 -> 41fdb0
	if parent_kind == "MAGIC_TRAP" and id in [MT_AREAS, MT_TARGETS]:
		if p + 12 > end:
			return 0
		var stride := 12 if id == MT_AREAS else 8
		return 12 + d.decode_u32(p + 8) * stride   # 43fec0 / 43ff10
	return d.decode_u32(p + 4)


func _field(d: PackedByteArray, id: int, p: int, n: int, o: Dictionary) -> void:
	match id:
		OBJTYPE: o.type = d.decode_u32(p)
		NID: o.nid = d.decode_u32(p)
		OBJNAME: o.name = _str(d, p, n)
		OBJTEMPLATE: o.template = _str(d, p, n).to_lower()
		PARENTTEMPLATE: o.parent_template = _str(d, p, n)
		OBJPRIMTXTR: o.texture = _str(d, p, n).to_lower()
		UNIT_PROTOTYPE: o.prototype = _str(d, p, n)
		OBJPOSITION: o.position = Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))
		OBJCOMPLECTION: o.complexion = Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))
		OBJROTATION: o.rotation = EISpace.quat(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8), d.decode_float(p + 12))
		OBJBODYPARTS: o.parts = _str_array(d, p)
		SS_TEXT: script_text = decrypt(d, p, n)
		SS_TEXT_PLAIN: script_text = d.slice(p, p + n).get_string_from_ascii()
		UNIT_STATS: o.stats = d.slice(p, p + n).to_int32_array()
		UNIT_ARMORS: o.armors = _str_array(d, p)
		UNIT_WEAPONS: o.weapons = _str_array(d, p)
		UNIT_QUICK_ITEMS: o.quick_items = _str_array(d, p)
		UNIT_QUEST_ITEMS: o.quest_items = _str_array(d, p)
		UNIT_SPELLS: o.spells = _str_array(d, p)
		UNIT_NEED_IMPORT: o.need_import = d[p]
		OBJ_PLAYER: o.player = d[p]
		OBJ_PARENT_ID: o.parent_id = d.decode_u32(p)
		OBJ_USE_IN_SCRIPT: o.use_in_script = d[p]
		OBJ_QUEST_INFO: o.quest_info = _str(d, p, n)
		UNIT_LOGIC_MODEL: o.logic_model = d.decode_u32(p)
		UNIT_LOGIC_GUARD_R: o.guard_radius = d.decode_float(p)
		UNIT_LOGIC_GUARD_PT: o.guard_point = _vec3(d, p)
		UNIT_LOGIC_AGRESSION_MODE: o.aggression = d[p]
		UNIT_LOGIC_HELP: o.help_radius = d.decode_float(p)
		UNIT_LOGIC_WAIT: o.logic_wait = d.decode_float(p)
		UNIT_LOGIC_CYCLIC: o.cyclic = d[p]
		UNIT_LOGIC_ALWAYS_ACTIVE: o.always_active = d[p]
		0xBBBC000B: o.alarm_cond = d[p]    # descriptor -> AI: when the unit is alerted
		0xBBBC0006: o.alarm_raise = d[p]   # descriptor: alarm raised when alerted
		0xBBBC0007: o.alarm_use = d[p]     # descriptor: used when its alarm is raised
		GUARD_PT_POSITION: o.position = _vec3(d, p)
		ACTION_PT_LOOK_PT: o.look = _vec3(d, p)
		ACTION_PT_WAIT_SEG: o.wait = d.decode_s16(p)   # read as a short
		0xBBBE0003: o.turn_speed = d.decode_float(p)   # ACTION_PT
		0xBBBE0004: o.action_flag = d[p]               # ACTION_PT: rest at the look
		LEVER_CUR_STATE: o.lever_state = d[p]
		LEVER_TOTAL_STATE: o.lever_states = d[p]
		LEVER_IS_CYCLED: o.lever_cycled = d[p]
		LEVER_IS_DOOR: o.lever_door = d[p]
		0xBBBF0001: o.torch_strength = d.decode_float(p)   # TORCH: fire size, light radius / 10
		0xBBBF0002: o.torch_offset = _vec3(d, p)           # TORCH: fire position offset
		0xBBBF0003: o.torch_sound = _str(d, p, n)          # TORCH: looped fire sound
		MT_DIPLOMACY: o.trap_players = d.decode_s32(p)
		MT_SPELL: o.trap_spell = _str(d, p, n)
		MT_AREAS: o.trap_areas = _vec_array(d, p, n, 3)
		MT_TARGETS: o.trap_targets = _vec_array(d, p, n, 2)
		MT_CAST_INTERVAL: o.trap_interval = d.decode_s32(p)
		LEVER_CAST_ONCE: o.cast_once = d[p]
		LEVER_SCIENCE_STATS: o.lever_science = d.slice(p, p + 12).to_int32_array() if n >= 12 else PackedInt32Array()
		0xCC02: o.id = d.decode_u32(p)
		0xCC03: o.position = _vec3(d, p)
		0xCC04: o.inner = d.decode_s32(p)
		0xCC05: o.name = _str(d, p, n)
		0xCC06: o.min_ms = d.decode_s32(p)
		0xCC07: o.max_ms = d.decode_s32(p)
		0xCC0A: o.waves = _str_array(d, p)
		0xCC0B: o.outer = d.decode_s32(p)
		0xCC0D: o.random = d[p]
		0xCC0E: o.flag = d[p]
		DIPLOMATION_FOF: diplomacy = d.slice(p, p + n).to_int32_array()
		DIPLOMATION_PL_NAMES: player_names = _str_array(d, p)


static func _vec3(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))


## A count followed by `k` floats per entry: Vector3 (x, y, radius) or Vector2.
static func _vec_array(d: PackedByteArray, p: int, n: int, k: int) -> Array:
	var out := []
	var count := d.decode_u32(p) if n >= 4 else 0
	for i in mini(count, (n - 4) / (4 * k)):
		var q := p + 4 + i * 4 * k
		if k == 3:
			out.append(Vector3(d.decode_float(q), d.decode_float(q + 4), d.decode_float(q + 8)))
		else:
			out.append(Vector2(d.decode_float(q), d.decode_float(q + 4)))
	return out


static func _str(d: PackedByteArray, p: int, n: int) -> String:
	return d.slice(p, p + n).get_string_from_ascii()


static func _str_array(d: PackedByteArray, p: int) -> PackedStringArray:
	var out := PackedStringArray()
	var count := d.decode_u32(p)
	p += 4
	for i in count:
		var n := d.decode_u32(p + 4)
		out.append(_str(d, p + 8, n - 8).to_lower())
		p += n
	return out


## Level scripts are XOR'd with a linear congruential key stream.
static func decrypt(d: PackedByteArray, p: int, n: int) -> String:
	var key := d.decode_u32(p)
	var out := PackedByteArray()
	out.resize(n - 4)
	for i in n - 4:
		var k1 := ((key * 13) & 0xFFFFFFFF) << 4 & 0xFFFFFFFF
		var k2 := ((k1 + key) & 0xFFFFFFFF) << 8 & 0xFFFFFFFF
		key = (key + ((k2 - key) * 4) + 2531011) & 0xFFFFFFFF
		out[i] = d[p + 4 + i] ^ ((key >> 16) & 0xFF)
	# Scripts are cp1251; keep ASCII readable and mark the rest.
	for i in out.size():
		if out[i] > 127:
			out[i] = 0x3F
	return out.get_string_from_ascii()
