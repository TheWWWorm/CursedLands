class_name Combat
extends RefCounted
## Combat resolution, following the original (function addresses cited per rule

var world: GameWorld
var rng := RandomNumberGenerator.new()


## ai.reg [DifficultyLevels] multiplier ("Attack", "Defence", "Absorption"),
## indexed by the Difficulty Level (: 0 Normal, 1 Novice; arrays
## [1.0, 0.66] / [1.0, 0.66] / [1.0, 0.33]). Attack / Defence
## scale every unit that is not "named" (: id
## [10^9, 2·10^9), the script name ids — heroes, mercenaries, named NPCs) on
## either side, truncated to ints; Absorption
## scales the natural armour of units outside a player party (
## ). A network game always plays at 0.
func difficulty(u: GameUnit, key: String) -> float:
	if GameData.difficulty == 0 or (world.session and world.session.online):
		return 1.0
	if key == "Absorption":
		if u.controller >= 0 or u.has_meta("hero"):
			return 1.0
	elif named(u):
		return 1.0
	return GameData.ai_value("DifficultyLevels", key, 1.0, GameData.difficulty)


## a name-hash id (ScriptVM.name_id); remake heroes too (the original
## names them; the remake gives co-op heroes plain ids).
static func named(u: GameUnit) -> bool:
	return (u.uid >= 1000000000 and u.uid < 2000000000) or u.has_meta("hero")


## Attack / Defence as the original's attack info gives them (ints, scaled).
func attack_value(u: GameUnit) -> int:
	var nw := named_weapon_ratings(u)
	if not nw.is_empty():
		return nw[0]
	return int(int(u.stats.to_hit) * difficulty(u, "Attack"))


## named branch: a unit with a script-name id (not a remake
## hero, whose hero_stats does the same) holding a weapon item gets
## Attack = ftol(weapon attack + T), Defence = ftol(weapon defence
##  + T), T = (weapon type): the type's skill (Melee for
## types 0-4, Archery for 5 / 6; stats) + (Dex - 25) + the
## weapon perk rank's modifier (+ type) + the weapon record's skill
## byte (0 in every weapons.idb row). The stats block comes
## the npcs record of the prototype's name (dex, skills2
## perks), else the prototype: Dex = mana / 3, every skill = round(general
## skills). when the prototype path applies (unnamed / unarmed).
## Cached per weapon in u.stats.
static func named_weapon_ratings(u: GameUnit) -> Array:
	if u.has_meta("hero") or u.uid < 1000000000 or u.uid >= 2000000000:
		return []
	var wid := ""
	for id in Array(u.info.get("weapons", [])):
		if String(id) != "":
			wid = String(id)
			break
	var cache: Array = u.stats.get("named_weapon", [])
	if cache.size() == 2 and cache[0] == wid:
		return cache[1]
	var out := []
	var w := Items.info(wid) if wid else {}
	if not w.is_empty() and w.table == "weapons":
		var wtype := String(w.row.get("type", "")).to_lower()
		var tid := int(w.row.get("type_id", -1))
		var proto_name := String(u.proto.get("name", ""))
		var npc := GameData.db.find("npcs", proto_name)
		var h := {}
		if npc.is_empty():
			var gs := roundf(float(u.proto.get("general_skills", 0.0)))
			h = {"skills": {"melee": gs, "archery": gs}, "dex": float(u.proto.get("mana", 0.0)) / 3.0, "perks": []}
		else:
			h = {"skills": Skills.from_npc(npc), "dex": float(npc.get("dex", 25.0)),
				"perks": Array(npc.get("perks", [])).map(func(x): return String(x).to_lower())}
		var skill := 0.0
		if tid >= 0 and tid <= 4:
			skill = Skills.level(h, "melee")
		elif tid == 5 or tid == 6:
			skill = Skills.level(h, "archery")
		var perk := Perks.best(h, Perks.WEAPON_PERK[wtype]) if Perks.WEAPON_PERK.has(wtype) else 0.0
		var t := skill + float(h.dex) + Perks.attr_bonus(h, "dex") - 25.0 + perk
		out = [int(float(w.row.get("attack", 0.0)) + t), int(float(w.row.get("defence", 0.0)) + t)]
	u.stats.named_weapon = [wid, out]
	return out


## Defence is 0 for every unit whose
## weapon type is a bow (5) or crossbow (6) — the weapon in hand
## else the prototype's (creature, units.udb "weapon
## typeID": goblin archers) — monsters and NPCs as well as heroes.
func defence_value(u: GameUnit) -> int:
	var wt := GameSound.held_weapon_type(u)
	if wt < 0:
		wt = int(u.proto.get("weapon_type_id", -1))
	if wt == 5 or wt == 6:
		return 0
	var nw := named_weapon_ratings(u)
	if not nw.is_empty():
		return nw[1]
	return int(int(u.stats.parry) * difficulty(u, "Defence"))


func _init(w: GameWorld) -> void:
	world = w
	rng.seed = 1


## Attack roll of the original: Attack plus a random
## step 2k - (B + 1), k = 0..B (B = "Tuning To hit Random", 40), minus the aimed
## strike penalty (head 25, limbs 10), must reach the target's Defence.
## (The original also subtracts distance / (10 * size) and adds a tiny weapon-speed
## ratio term; both are under one point in melee and left out.)
func attack_hits(att: GameUnit, def: GameUnit, penalty := 0.0) -> bool:
	var b := roundi(float(att.stats.get("hit_random", 40.0)))
	var roll := maxf(float(attack_value(att)) + rng.randi_range(0, b) * 2 - (b + 1), 0.0)
	return maxf(roll - penalty, 0.0) >= float(defence_value(def))


func hit_chance(att: GameUnit, def: GameUnit) -> float:
	var b := roundi(float(att.stats.get("hit_random", 40.0)))
	if defence_value(def) <= 0:
		return 1.0   # the roll is kept >= 0, so Defence 0 is always reached
	var need := ceili((float(defence_value(def)) - float(attack_value(att)) + b + 1) / 2.0)
	return clampf(float(b - clampi(need, 0, b + 1) + 1) / (b + 1), 0.0, 1.0)


## Damage of one hit, the original:
## D = min + random(range); per damage type i the target's natural armour is
## subtracted (max(0, D * factor_i - armour_i)), then every armour layer worn on
## the struck body part (GameUnit.hit_part: random location)
## outer layer first. The remainder comes off that part's health. May be 0 when
## armour stops the blow.
## Wear: each worn piece loses the damage that
## got through it (stops at the layer that stops the blow); the attacker's
## weapon in hand at the blow ((attacker); for a bow or
## crossbow the shooter's at the arrow's arrival) loses what
## the natural armour and the layers absorbed. Collected in `last_wear` for
## apply_wear().
var last_wear := {}
## Damage per type of the last roll_damage (after armour), for severing.
var last_types := PackedFloat32Array()

func roll_damage(att: GameUnit, def: GameUnit, part := "torso") -> float:
	var rec := strike_record(att)
	return absorb(def, float(rec.dmg), rec.types, part)


## The strike's own part of the hit record (at the strike's
## start): value = min + random(range), × (1 + 0.003 strength)
## (1 + 0.003 weakness), at least 1; the type factors +0..
## the aimed part (order); the backstab factor (ai.reg
## "BackstabAdd" + the backstab perk / 100). A missile carries
## its copy to the target.
func strike_record(att: GameUnit) -> Dictionary:
	return {"dmg": maxf(1.0, rng.randf_range(float(att.stats.dmg_min), float(att.stats.dmg_max)) * att.damage_mul()),
		"types": att.stats.get("dmg_types", PackedFloat32Array([0, 0, 1, 0, 0, 0, 0])),
		"aim": att.strike_aim,
		"bs_mul": GameData.ai_value("RPG", "BackstabAdd", 3.0) + float(att.stats.get("backstab", 0.0)) / 100.0}


##  for damage `dmg` with the type factors `f`.
func absorb(def: GameUnit, dmg: float, f: PackedFloat32Array, part := "torso") -> float:
	last_wear = {"armors": {}, "weapon": 0.0}
	last_types = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var armour: PackedFloat32Array = def.stats.get("armor", PackedFloat32Array())
	var k := difficulty(def, "Absorption")
	var worn := worn_layers(def.get_meta("hero").get("armors", []), part) if def.has_meta("hero") else []
	var total := 0.0
	for t in 7:
		# The attacker's weapon (param_4) loses, per type, what
		# the natural armour absorbed (first loop,:
		# (D·f − max(D·f − armour, 0)), ECX = param_4) and then what
		# the layers absorbed: D·f − max(left, 0) in all.
		var raw := dmg * f[t]
		var d := raw - (armour[t] * k if t < armour.size() else 0.0)
		if d <= 0.0:
			last_wear.weapon += maxf(raw, 0.0)
			continue
		for w: Array in worn:
			d -= w[1][t]
			for i: int in w[0]:
				last_wear.armors[i] = last_wear.armors.get(i, 0.0) + maxf(d, 0.0)
			if d <= 0.0:
				break
		last_wear.weapon += raw - maxf(d, 0.0)
		last_types[t] = maxf(d, 0.0)
		total += maxf(d, 0.0)
	return total


## The armour layers worn on `part`, outer first: [[indices in armors], sum].
##  walks a character's three part layers from 2 down to 0 and
## subtracts each (× the hit record's, 1 for a strike) while damage is
## left; names the items of a layer through the table
## (item type ids helm 0, plate 1, leggings 2, shirt 3, pants 4, boots 5,
## gloves 6): head layer 2 helm; torso 2 plate, 1 shirt; arms 2 plate, 1 shirt
## + gloves; legs 2 leggings, 1 pants + boots; layer 0 has no item. Two items
## of one layer are subtracted together and both wear by the damage left
## after it. Only characters (script-name ids)
## have layers; other units take the natural armour alone. Broken pieces are
## off the body (they go to the inventory).
static func worn_layers(armors: Array, part: String) -> Array:
	var out := []
	for layer: Array in PART_LAYERS.get(part, []):
		var idx := []
		var sum := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
		for ps: Array in layer:
			for i in armors.size():
				if Items.slot(armors[i]) == ps[0] and not Items.is_broken(armors[i]):
					idx.append(i)
					var l := Items.armor_layer(armors[i], ps[1])
					for t in 7:
						sum[t] += l[t]
		if not idx.is_empty():
			out.append([idx, sum])
	return out


## Part layers, outer (layer 2) first, as [slot, absorption set] lists.
const PART_LAYERS := {
	"head": [[["helm", 0]]],
	"torso": [[["plate", 0]], [["shirt", 0]]],
	"arms": [[["plate", 1]], [["shirt", 1], ["gloves", 0]]],
	"legs": [[["leggings", 0], ["leggins", 0]], [["pants", 0], ["boots", 0]]],
}


## A hit record without an attacker on `def` (through the
## logic's, e.g. the tornado's): it lands when
## `to_hit` reaches the target's Defence (the stored roll), deals
## `dmg` with the type factors `f` (+0..) on body part `part`
## the armour factor is 1 here.
func record_hit(def: GameUnit, f: PackedFloat32Array, to_hit: float, dmg: float, part: int) -> void:
	if def.dead or float(defence_value(def)) > to_hit:
		return
	var d := absorb(def, dmg, f, def.part_group(part))
	apply_wear(null, def)
	def.take_damage(d, null, part, last_types)


## Applies `last_wear` to the defender's armour and the attacker's weapon.
func apply_wear(att: GameUnit, def: GameUnit) -> void:
	if def.has_meta("hero"):
		var armors: Array = def.get_meta("hero").get("armors", [])
		for i: int in last_wear.get("armors", {}):
			if i < armors.size():
				wear_item(def, armors, i, last_wear.armors[i], false)
	if att and att.has_meta("hero") and last_wear.get("weapon", 0.0) > 0.0:
		var ws: Array = att.get_meta("hero").get("weapons", [])
		if not ws.is_empty():
			wear_item(att, ws, 0, last_wear.weapon, true)


## durability -= amount; below ai.reg "Item Durability Critical"
## of the maximum the owner warns (ack 0x25 armour / 0x26 weapon), below 1 the
## item is broken (0x23 / 0x24) and goes to the bag (tutorial it012).
func wear_item(u: GameUnit, list: Array, i: int, amount: float, weapon: bool) -> void:
	var id := String(list[i])
	var mx := Items.max_durability(id)
	if mx <= 0.0 or amount <= 0.0:
		return
	var before := Items.durability(id)
	list[i] = Items.with_wear(id, Items.wear(id) + amount)
	var after := Items.durability(list[i])
	var crit := mx * GameData.ai_value("RPG", "Item Durability Critical", 0.3)
	if Items.is_broken(list[i]):
		world.item_worn.emit(u, list[i], "broken_weapon" if weapon else "broken_armor")
	elif before >= crit and after < crit:
		world.item_worn.emit(u, list[i], "critical_weapon" if weapon else "critical_armor")


## The strike's hit record, decided when the strike starts (the original
## builds it with the backstab flag
## then rolls the hit into record = ±FLT_MAX
## the miss goes with the strike's animation command as unit
## ). The blow uses the stored
## outcome and rolls only when none is stored.
## Backstab: a character (hero) striking in melee from within 60 degrees of
## the target's back always hits; a bow / crossbow in hand
## clears it. So does the target's combat stance (unit
## GameUnit.alert: set by its attack command, kept by a unit outside a party,
## and by the AI's suspicion): zeroes the flag for such a target
## and resets the record's backstab factor to 1 — an
## ordinary roll against its Defence, no damage factor.
func strike_roll(att: GameUnit, def: GameUnit) -> Dictionary:
	var backstab := false
	if att.has_meta("hero") and not att.stats.get("ranged", false) and not def.alert:
		var fwd := Vector2.from_angle(def.facing)
		backstab = fwd.dot((def.pos - att.pos).normalized()) > 0.5
	return {"backstab": backstab, "hit": backstab or attack_hits(att, def, aim_penalty(att.strike_aim))}


## an aimed strike (hit record set, from the attack
## order's aim, keyboard.ini cs_* held at the click) lowers the attack
## roll by 25 at the head (part 0), not at the body (part 1), by 10 at a limb,
## the roll kept ≥ 0. The part is the aimed one as it stands:
## takes the order's aim 0..5 as the record's part without the
## neighbour search, which only the random location (aim 6) and
## an out-of-range aim (→ the body) go through.
static func aim_penalty(aim: int) -> float:
	match aim:
		0: return 25.0
		2, 3, 4, 5: return 10.0
	return 0.0


## A blow lands with the hit record `roll` from strike_roll
## (rolled now when empty). A backstab deals ai.reg "BackstabAdd" (3) +
## backstab perk modifier / 100 times the damage: x3, x5
## x7.5, x10.
## `att` null: a missile whose shooter is gone (passes
##  0): the hit record it carries (`roll` with strike_record's
## fields) decides it all — does not roll again (already
## ±FLT_MAX), and with no attacker no weapon wears (param_4 = 0), no
## hostility, the hit hook gets none.
func melee(att: GameUnit, def: GameUnit, roll := {}) -> void:
	if att != null and not is_instance_valid(att):
		att = null
	if roll.is_empty():
		if att == null:
			return
		roll = strike_roll(att, def)
	var backstab: bool = roll.backstab
	if not roll.hit:
		world.on_miss(att, def)
		missed(def, att)
		return
	armor_spells(def, true)
	# an aimed strike (0..5) lands on that part even when it is
	# gone; then deals nothing (part state < 2: severed or
	# absent) — no damage, no wear, no hit number.
	var rec: Dictionary = roll if roll.has("dmg") else {}
	var aim: int = int(rec.aim) if rec else att.strike_aim
	var part := aim if aim >= 0 and aim < 6 and not def.parts.is_empty() else def.hit_part(-1)
	if not def.parts.is_empty() and int(def.parts[part].state) < 2:
		return
	var dmg := absorb(def, float(rec.dmg), rec.types, def.part_group(part)) if rec \
		else roll_damage(att, def, def.part_group(part))
	if backstab:
		var mul: float = float(rec.bs_mul) if rec else GameData.ai_value("RPG", "BackstabAdd", 3.0) + float(att.stats.get("backstab", 0.0)) / 100.0
		dmg *= mul
		for t in last_types.size():
			last_types[t] *= mul
		world.combat_event.emit("backstab", att, def, dmg)
	apply_wear(att, def)
	def.take_damage(dmg, att, part, last_types, 1 if backstab else 0)
	# a unit that lives on after the damage.
	if not def.dead:
		armor_spells(def, false)


## An enchanted weapon ("it" rune, spell flag) in hand, the original
## called by the strike after the blow is dealt
## or the missile launched, hit or miss, no chance roll. When the weapon's
## charge holds the spell's stamina it loses that
##  and the spell is cast at the target; short
## it nothing happens. A target the blow killed still gets the cast (the
## direct path has no life test): the charge is spent and the
## spell shown; an area spell still reaches the living round it. Approx.: the
## effect itself is not put on the corpse.
func weapon_spell(att: GameUnit, def: GameUnit) -> void:
	if not att.has_meta("hero"):
		return
	var h: Dictionary = att.get_meta("hero")
	var ws: Array = h.get("weapons", [])
	var sp := Items.spell_of(ws[0]) if not ws.is_empty() else ""
	if sp.is_empty() or not int(Spells.parse(sp).flags) & 0x10000:
		return
	if not Session.spend_charge(ws, 0, float(Spells.parse(sp).mana)):
		return
	if world.session:
		world.session.mark_dirty()
	if not def.dead or float(Spells.parse(sp).radius) > 0.2:
		Spells.apply(world, att, sp, def, def.pos)
	if world.session:
		world.session.broadcast({"t": "spellfx", "code": Spells.parse(sp).code, "sub": Spells.parse(sp).subtype,
			"x": def.pos.x, "y": def.pos.y, "a": att.uid, "tu": def.uid, "spell": sp})


## A hit that lands but whose damage the armour stops entirely (the original
##  when returns 0): the struck bit 0x10 (unit
## ) is set before the damage, so the unit's state update
## still shows a "0" hit number; then (an
## attacking unit's side into the victim's hostility) and the AI hit hook
## . is not reached: no hit reaction
## no healing armour spell, no health change. The struck armour spells
## ((1)) fire before the damage, at the caller. `owner_only`: a
## lasting spell's later ticks pass no attacker (see GameUnit.take_damage).
func blank_hit(def: GameUnit, src: GameUnit, owner_only := false) -> void:
	if def.dead:
		return
	if world.session:
		world.session.broadcast({"t": "hitnum", "uid": def.uid, "n": 0, "f": 0})
	if owner_only:
		return
	if src and not is_instance_valid(src):
		src = null
	if src and src != def and src.faction != def.faction \
			and world.relation(def.faction, src.faction) != 2:
		world.ai._hate(def, src.faction)
	if def.controller < 0:
		world.ai.on_attacked(def, src)
	else:
		world.ai.on_player_attacked(def, src)


## A blow that misses (after the roll fails): no
## struck bit, no hit number, no damage, but the end of the routine still
## runs: a creature attacker's side into the victim's hostility
##  and the AI hit hook (the
## attacker kept, noticed, the call for help). So a missed unit notices its
## attacker as a hit one does.
func missed(def: GameUnit, src: GameUnit) -> void:
	if def.dead or src == null or not is_instance_valid(src) or src == def:
		return
	if src.faction != def.faction and world.relation(def.faction, src.faction) != 2:
		world.ai._hate(def, src.faction)
	if def.controller < 0:
		world.ai.on_attacked(def, src)
	else:
		world.ai.on_player_attacked(def, src)


## Worn armour with an "it" spell (flag), the original over
## the 7 armour slots: `struck` (a blow lands, before the
## damage) fires every such spell but Healing (spell 24); after the damage, if
## the unit lives, only Healing fires. Each needs its charge to
## hold the stamina cost, which it loses; the spell is cast at the wearer.
func armor_spells(u: GameUnit, struck: bool) -> void:
	if not u.has_meta("hero"):
		return
	var h: Dictionary = u.get_meta("hero")
	var armors: Array = h.get("armors", [])
	for ai in armors.size():
		if ai >= armors.size():
			break
		var a := String(armors[ai])
		var sp := Items.spell_of(a)
		if sp.is_empty():
			continue
		var p := Spells.parse(sp)
		if not int(p.flags) & 0x10000:
			continue
		if (GameData.db.table("spell_prototypes").find(p.proto) == 24) == struck:
			continue
		if not Session.spend_charge(armors, ai, float(p.mana)):
			continue
		if world.session:
			world.session.mark_dirty()
		Spells.apply(world, u, sp, u, u.pos)


## A.mob unit record's own stats (the original, called for every
## placed unit after the prototype set-up
## ). The record's chunk (43 ints, read
##  into record) replaces the prototype's values only when
## the record's "need import" byte (chunk -> record) is set
## and not (== 0.0 and max HP == 0 and == 0.0); 85 of the 7953
## campaign map units have it. Block layout (s = the ints, f() = as a float):
##   s0 / s1 HP / max HP, s2 / s3 stamina / max (ints; small block
## max HP also creature), s4 f tuning move
##   s5 f actions, s6..s9 f race speeds, s10 f cos(vision
##   arc / 2), s11 f peripheral skill, s12 f cos 90, s13 f race attack
##   distance, s14 bytes race ai_stay / ai_lie
##   s15..s20 f attack range, to-hit, parry, weapon weight, damage min, damage
##   range (to-hit random
##    stays the prototype's), s21..s27 f damage type factors
##   low byte of s28 the absorption (natural armour = byte x race "def", base
##   and current), s29..s34 f senses, s35..s40 f detection, s41 bytes
##   steal, steal, tame skill. The prototype and race are returned as
##   copies with those fields replaced ([proto, race]); `null` when the block
##   does not apply. Not ported: s5 (the remake's monster actions stay 15) and
##   the record's own item / spell lists the original adds in the same branch.
static func mob_import(record: Dictionary, proto: Dictionary, race: Dictionary) -> Variant:
	if not mob_imports(record):
		return null
	var s := PackedInt32Array(record.stats)
	var p := proto.duplicate()
	var r := race.duplicate()
	p.hp = float(s[1])
	p.mana = float(s[3])
	p.absorption = float(s[28] & 0xff)
	p.tuning_move = _bits_f(s[4])
	p.peripheral_skills = _bits_f(s[11])
	p.attack_range = _bits_f(s[15])
	p.to_hit = _bits_f(s[16])
	p.parry = _bits_f(s[17])
	p.weapon_weight = _bits_f(s[18])
	p.damage_min = _bits_f(s[19])
	p.damage_max = _bits_f(s[20])
	var senses := []
	var detection := []
	for i in 6:
		senses.append(_bits_f(s[29 + i]))
		detection.append(_bits_f(s[35 + i]))
	p.senses = senses
	p.detection = detection
	p.steal_skills = float(s[41] & 0xff)
	p.tame_skills = float((s[41] >> 16) & 0xff)
	r.speeds = [_bits_f(s[6]), _bits_f(s[7]), _bits_f(s[8]), _bits_f(s[9])]
	r.vision_arc = rad_to_deg(acos(clampf(_bits_f(s[10]), -1.0, 1.0))) * 2.0
	r.attack_distance = _bits_f(s[13])
	r.ai_stay = s[14] & 0xff
	r.ai_lie = (s[14] >> 8) & 0xff
	var atk := []
	for i in 7:
		atk.append(_bits_f(s[21 + i]))
	r.attack = atk
	return [p, r]


## the current HP / stamina of an imported record (s0 / s2)
## after the stats are set up from its maxima.
static func mob_import_pools(u: GameUnit) -> void:
	if not mob_imports(u.info):
		return
	var s := PackedInt32Array(u.info.stats)
	u.hp = minf(float(s[0]), u.max_hp)
	u.mana = minf(float(s[2]), u.max_mana)


## Whether applies a record's stats block (see mob_import).
static func mob_imports(record: Dictionary) -> bool:
	var s := PackedInt32Array(record.get("stats", PackedInt32Array()))
	if int(record.get("need_import", 0)) == 0 or s.size() < 42:
		return false
	return not (_bits_f(s[4]) == 0.0 and s[1] == 0 and _bits_f(s[5]) == 0.0)


static func _bits_f(v: int) -> float:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_s32(0, v)
	return b.decode_float(0)


## A party unit placed into a zone has no natural armour: the party deployment
##  spawns it from its prototype (
## "Human Hero" absorption 7 on every type) and then, which
## zeroes the seven base values (small block..); the party record's
## block that follows (logic)
## refolds, which copies base into current. Only worn armour and
## protection effects stop its damage after that. A unit that joins the party
## inside a zone (a hired village unit,; script
## AddUnitUnderControl) keeps its armour until the next deployment.
## `h`: the unit's hero / mercenary record, marked "no_natural_armor" so that
## co-op clients, which get the records with the state sync, do the same
## (`sync_natural_armor`).
static func clear_natural_armor(u: GameUnit, h := {}) -> void:
	u.stats.armor = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	if h is Dictionary and not h.is_empty():
		h.no_natural_armor = true


## Co-op client: a party unit's natural armour as the host has it — cleared
## for a unit deployed at a zone entry (its record marked by
## `clear_natural_armor`), the prototype's for one that joined inside the zone
##  and was not deployed since.
static func sync_natural_armor(u: GameUnit, h: Dictionary) -> void:
	if h.get("no_natural_armor", false):
		u.stats.armor = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	else:
		u.stats.armor = u.race_factors("defence", float(u.proto.get("absorption", 0.0)))


## Stats for player characters from attributes, experience, skills and
## equipment (the original):
##   HP / stamina: ai.reg HP/MP Val formula with Str / Dex (Skills.base_pool);
##   Attack = weapon skill + (Dex - 25) + weapon attack (+ weapon perk);
##   Defence = Melee skill + (Dex - 25) + weapon defence (+ weapon perk), 0 for
##   bows and crossbows
##   damage = weapon damage (no attribute bonus); unarmed = prototype damage;
##   armour = prototype absorption x race def per type, plus worn items per body part.
## Body build from Strength and Dexterity, the original
## a = (Str - 15) / 20, b = 1 - (Dex - 15) / 20 (20 = 35 - 15
## no clamping); muscle = 0.7a + 0.3b, fat = (0.2a + 0.8b) * 0.8
## + 0.2; height is kept. The original's figure order is (muscle, fat, height); the
## remake's complexion (map file order) is (fat, muscle, height).
static func reshape(u: GameUnit, h: Dictionary, s: float, d: float) -> void:
	var a := (s - 15.0) / 20.0
	var b := 1.0 - (d - 15.0) / 20.0
	var old: Vector3 = u.info.get("complexion", Vector3(0.5, 0.5, 0.5))
	var c := Vector3((a * 0.2 + b * 0.8) * 0.8 + 0.2, a * 0.7 + b * 0.3, old.z)
	set_complexion(u, h, c)


## Gives a hero's unit a new body build (complexion fat, muscle, height) and
## re-dresses it on every peer.
static func set_complexion(u: GameUnit, h: Dictionary, c: Vector3) -> void:
	var old: Vector3 = u.info.get("complexion", Vector3(0.5, 0.5, 0.5))
	h.complexion = c
	if old.is_equal_approx(c):
		return
	u.info.complexion = c
	if u.model:
		u.set_equipment(PackedStringArray(u.info.get("armors", [])), PackedStringArray(u.info.get("weapons", [])))
	if u.world and u.world.session and u.world.authority:
		u.world.session.broadcast({"t": "reshape", "uid": u.uid, "complexion": c})


static func hero_stats(u: GameUnit, h: Dictionary) -> void:
	var s := float(h.get("str", 20.0)) + Perks.attr_bonus(h, "str")
	var d := float(h.get("dex", 20.0)) + Perks.attr_bonus(h, "dex")
	var i := float(h.get("int", 20.0)) + Perks.attr_bonus(h, "int")
	var total := float(h.get("exp_total", h.get("exp", 0.0)))
	# Pools keep their fill fraction (a fresh unit is full: sets the
	# current values from the new maxima).
	var hp_frac := u.hp / u.max_hp if u.max_hp > 0.0 and u.hp > 0.0 else 1.0
	var mp_frac := clampf(u.mana / u.max_mana, 0.0, 1.0) if u.max_mana > 0.0 else 1.0
	u.max_hp = Skills.base_pool(total, s)
	u.hp = u.max_hp * hp_frac
	u.max_mana = Skills.base_pool(total, d, "MP")
	u.mana = u.max_mana * mp_frac
	var weapons: Array = h.get("weapons", [])
	var wtype := ""
	var w_att := 0.0
	var w_def := 0.0
	u.stats.ranged = false
	u.stats.reach = 1.3
	u.stats.range = float(u.proto.get("attack_range", 0.0))   # unarmed: (see GameUnit.melee_reach)
	u.stats.dmg_min = float(u.proto.get("damage_min", 1.0))
	u.stats.dmg_max = u.stats.dmg_min + float(u.proto.get("damage_max", 1.0))
	u.stats.dmg_types = u.race_factors("attack", 1.0)
	u.stats.erase("weapon_actions")
	if not weapons.is_empty():
		var dmg := Items.damage(weapons[0])
		u.stats.dmg_min = dmg.x
		u.stats.dmg_max = dmg.y
		u.stats.dmg_types = Items.damage_types(weapons[0])
		var w := Items.info(weapons[0])
		wtype = String(w.row.get("type", "")).to_lower()
		w_att = float(w.row.get("attack", 0.0))
		w_def = float(w.row.get("defence", 0.0))
		u.stats.weapon_actions = float(w.row.get("actions", 30.0))
		u.stats.reach = maxf(1.3, float(w.row.get("range", 0.0)) + 1.3)
		u.stats.range = float(w.row.get("range", 0.0))
		u.stats.ranged = wtype in ["bow", "crossbow"]
		if u.stats.ranged:
			u.stats.reach = 14.0
	var skill := Skills.level(h, "archery" if u.stats.ranged else "melee")
	u.stats.to_hit = maxf(1.0, skill + (d - 25.0) + w_att)
	u.stats.parry = 0.0 if u.stats.ranged else maxf(1.0, Skills.level(h, "melee") + (d - 25.0) + w_def)
	u.stats.part_armor = part_armor(h.get("armors", []))
	var torso: PackedFloat32Array = u.stats.part_armor.get("torso", PackedFloat32Array())
	var absorb := 0.0
	for t in 7:
		absorb += float(u.stats.armor[t]) + (torso[t] if t < torso.size() else 0.0)
	u.stats.absorption = absorb / 7.0
	u.stats.str = s
	u.stats.dex = d
	u.stats.int = i
	# No reshape here: (stats -> build) is only used by the
	# multiplayer hero editor; campaign heroes keep their
	# prototype / map build.
	# max load = (1 + lift perk/100) * Str * 12; load = weight of the
	# equipped weapons, armour and belt items; actions = Dex * 0.2 + 10.
	u.stats.max_load = s * 12.0
	var load := 0.0
	for k in ["weapons", "armors", "quick"]:
		for it in h.get(k, []):
			var st := Items.parse_stack(String(it))
			load += Items.weight(st[0]) * int(st[1])
	u.stats.load = load
	u.stats.actions = d * 0.2 + 10.0
	Perks.apply(u, h, wtype)
	u.stats.actions *= 1.0 + float(u.stats.get("quick", 0.0)) / 100.0


## Worn armour per body part. the original slot -> part table: helm
## the head; shirt and plate on the torso (their second set on the arms);
## gloves on the arms; pants, boots and leggings on the legs. Layers add up.
const PART_SLOTS := {
	"head": [["helm", 0]],
	"torso": [["shirt", 0], ["plate", 0]],
	"arms": [["shirt", 1], ["plate", 1], ["gloves", 0]],
	"legs": [["pants", 0], ["boots", 0], ["leggings", 0], ["leggins", 0]],
}


static func part_armor(armors: Array) -> Dictionary:
	var out := {}
	for part: String in PART_SLOTS:
		var sum := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
		for a in armors:
			for ps: Array in PART_SLOTS[part]:
				if Items.slot(a) == ps[0]:
					var l := Items.armor_layer(a, ps[1])
					for t in 7:
						sum[t] += l[t]
		out[part] = sum
	return out
