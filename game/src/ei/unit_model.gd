class_name EIUnitModel
extends Node3D
## Animated creature/character model.
## Appearance comes from the unit databases: race model (mesh template, skin set),
## monster prototype (skin, hair, complexion, worn armor, weapon) and the map's
## per-unit overrides. Human/orc textures are composed at runtime from a skin plus
## one overlay per worn item (res/redress.res), like the original "redress" system.

const ARMOR_PREFIX := {"helm": "hl", "plate": "pl", "leggings": "lg", "shirt": "sh",
	"pants": "pt", "boots": "bt", "gloves": "gl"}
## Inner-to-outer layering for texture composition (the original:
## skin, then the slots shirt, pants, boots, gloves, then plate / leggings
## sorted by the armour record's field, a tie keeping plate first — so
## the pants' leather waist wrap lies over the shirt).
## Approx.: plate and leggings keep a fixed order instead of the sort.
const ARMOR_ORDER := ["shirt", "pants", "boots", "gloves", "plate", "leggings", "helm"]
const ARMOR_PARTS := {
	"plate": ["bd", "lh1", "lh2", "lh3", "rh1", "rh2", "rh3", "l_shell", "r_shell"],
	"leggings": ["hp", "ll1", "ll2", "ll3", "rl1", "rl2", "rl3"],
	"helm": ["hd"],
}
const WEAPON_PREFIX := {"sword": "sw", "axe": "ax", "dagger": "dg", "spear": "sp",
	"hammer": "hm", "bow": "bw", "crossbow": "cb"}
const WEAPON_MESH := {"sword": "rh3.sword%02d", "axe": "rh3.axe%02d", "dagger": "rh3.dagger%02d",
	"spear": "rh3.pike%02d", "hammer": "rh3.club%02d", "crossbow": "rh3.crbow%02dmain"}

static var _textures := {}
const AnimatedPart = preload("res://src/ei/anim_part.gd")

## Optional experiment, disabled by default to preserve the original shapes.
## the original draws every part rigidly with one matrix. Enabling
## this merges body meshes and blends the matrices near joints; it reduces
## some steps but distorts the authored silhouette and texture details.
static var smooth_joints := false

var template := ""
var player: AnimationPlayer
var weapon_type := ""
var _current := ""


## `unit` is a map object dictionary from EIMob (or a synthetic one with
## prototype/complexion/armors/weapons).
static func create(unit: Dictionary) -> EIUnitModel:
	var db := GameData.db
	var proto := db.find("monster_prototypes", unit.get("prototype", unit.get("parent_template", "")))
	var race := db.find("race_models", proto.get("base_race", ""))
	var tmpl: String = unit.get("template", "")
	if tmpl.is_empty():
		tmpl = String(race.get("mask", "")).to_lower()
	var model := EIFigure.get_model(tmpl)
	if model.is_empty():
		return null
	var m := EIUnitModel.new()
	m.template = tmpl
	m.name = tmpl
	m._build(model, unit, proto, race)
	return m


func play(anim: String, blend := 0.15, restart := false) -> void:
	if not has_anim(anim):
		return
	# An explicitly requested clip replaces the logical action sequence.
	# Otherwise a script clip could retain a walk's queued follow-up, or be
	# mistaken for the idle cycle when the script finishes.
	_cycle = -1
	_resume = ""
	_resume_clip = ""
	_play(anim, blend, restart)


func _play(anim: String, blend: float, restart := false) -> void:
	if player == null or (anim == _current and not restart):
		return
	var key := "ei/" + anim
	if player.has_animation(key):
		player.play(key, blend)
		_current = anim
		if restart:
			player.seek(0.0, true)


## Plays a logical action: idle, walk, run, crawl, attack, hit, death, cast...
## Resolves to the original clip names ("cidle", "cidle01", "uattack03", ...).
func act(action: String, variant := 1, blend := 0.15) -> float:
	return _act(action, variant, blend, false)


##  builds a humanoid's movement start + cycle pair whenever
## weapon, state, gait or limp changes. Repeated requests keep that pair.
## Non-humanoids, absent start clips and other actions go straight to act().
func act_with_start(action: String, variant := 1, blend := 0.15) -> float:
	return _act(action, variant, blend, movement_starts and action in ["walk", "run", "crawl"])


func _act(action: String, variant: int, blend: float, with_start: bool) -> float:
	var clip := ""
	var requested := code_for(action) if _ACTION_CODE.has(action) else -1
	var cyc := requested >= 0 and requested & STAGE_CYCLE != 0
	# The unit calls this every tick, including during a start/cross clip.
	# Preserve its queued cycle before touching _resume.
	if cyc and requested == _cycle and _current != "":
		return player.get_animation("ei/" + _current).length
	_resume = ""
	_resume_clip = ""
	_cycle = requested if cyc else -1
	_cycle_pos = 0.0
	if not adb.is_empty() and _ACTION_CODE.has(action):
		var code := requested
		clip = pick(code, true, not cyc)
		if clip == "" and code & 0x3fc00000:
			code &= ~0x3fc00000     # no limping clip for this posture
			clip = pick(code, true, not cyc)
	if clip.is_empty():
		clip = resolve(action, variant)
	if clip.is_empty():
		_cycle = -1
		return 0.0
	if with_start and not adb.is_empty():
		#  adds the limp modifier only to the cycle query. The
		# start uses the same weapon/state/gait without stage or modifier bits.
		var start := pick((requested & 0x003fffff) | STAGE_START)
		if start != "":
			_resume = action
			_resume_clip = clip
			_play(start, blend, true)
			return player.get_animation("ei/" + start).length
	_play(clip, blend, not cyc and clip == _current)
	return player.get_animation("ei/" + clip).length


var _resolved := {}

## --- the original animation database (res/database.res "<template>.adb", read
## ). Each clip has a code: weapon mask bits 0-14 (1 << weapon type)
## state 15-17, action 18-21, modifier 22-29 (idle: 1 Stay, 2 LookAround; walk:
## 1/2 limp; attack/hit/death: direction), stage 30-31 (0 unique, 1 start,
## 2 cycle, 3 end). Names from the original's own dumper.
const ST_NEUTRAL := 0
const ST_REST := 0x8000
const ST_ATTACK := 0x10000
const ST_WARRY := 0x20000     # kneeling (sneak)
const ST_LIE := 0x30000       # crawling
const AC_SPECIAL := 0x40000
const AC_ATTACK := 0x80000
const AC_CAST := 0xc0000
const AC_RUN := 0x100000
const AC_WALK := 0x140000
const AC_IDLE := 0x180000
const AC_DEATH := 0x1c0000
const AC_SUFFER := 0x200000
const AC_CROSS := 0x240000
const MOD_1 := 0x400000
const STAGE_START := 0x40000000
const STAGE_CYCLE := 0x80000000
const WEAPON_BIT := {"sword": 1, "axe": 2, "dagger": 4, "spear": 8, "hammer": 16, "bow": 32, "crossbow": 64}
const _ACTION_CODE := {"idle": AC_IDLE, "walk": AC_WALK, "run": AC_RUN, "crawl": AC_WALK,
	"attack": AC_ATTACK, "cast": AC_CAST, "hit": AC_SUFFER, "death": AC_DEATH}

static var _adbs := {}
## [{name, code, weight}] for this template; empty = no database (old name rules).
var adb: Array = []
## Set by the unit before act(): state bits, walk modifier (limp).
var pose_state := ST_ATTACK
var pose_mod := 0
var neutral := false
var movement_starts := false  # original character type 0x32
var _cycle := -1      # code of the playing cycle clip (re-picked when it wraps)
var _cycle_pos := 0.0


## the original: the.adb header's height factor, (h * (c28 - c20) +
## c20) / c24 at the unit's height complexion (1 without a database). The root
## part's translation keys are scaled by it.
static func height_scale(tmpl: String, h: float) -> float:
	var arc := EIResArchive.open_path(GameData.root.path_join("res/database.res")) if GameData.root != "" else null
	var b := arc.read(tmpl + ".adb") if arc else PackedByteArray()
	if b.size() < 0x2c or b.decode_float(0x24) == 0.0:
		return 1.0
	return (h * (b.decode_float(0x28) - b.decode_float(0x20)) + b.decode_float(0x20)) / b.decode_float(0x24)


static func load_adb(tmpl: String) -> Array:
	if _adbs.has(tmpl):
		return _adbs[tmpl]
	var out := []
	var arc := EIResArchive.open_path(GameData.root.path_join("res/database.res")) if GameData.root != "" else null
	var b := arc.read(tmpl + ".adb") if arc else PackedByteArray()
	if b.size() >= 0x2c and b.slice(0, 3).get_string_from_ascii() == "ADB":
		var n := b.decode_u32(4)
		for i in n:
			var p := 0x2c + i * 88
			if p + 88 > b.size():
				break
			out.append({"name": b.slice(p, p + 16).get_string_from_ascii(),
				"code": b.decode_u32(p + 20), "weight": b.decode_s32(p + 28)})
	_adbs[tmpl] = out
	return out


func weapon_bit() -> int:
	return WEAPON_BIT.get(weapon_type, 0)


## True when the database has relaxed (neutral) stand clips: humans and orcs.
## Monsters only have combat-state clips (the original: units of type != 0x32 always
## use the attack state).
func has_neutral() -> bool:
	return neutral


func _has_neutral() -> bool:
	for e: Dictionary in adb:
		if int(e.code) & 0x3f8000 == AC_IDLE | ST_NEUTRAL:
			return true
	return false


## exact code, then unarmed, then (rest state) neutral / attack
## then with `fallback` any clip of the same state/action/modifier/stage.
func pick(code: int, fallback := true, any_mod := false) -> String:
	var r := _match(code, any_mod)
	if r == "":
		r = _match(code & 0xffff8000, any_mod)
	if r == "" and code & 0x38000 == ST_REST:
		r = _match(code & 0xfffc0000, any_mod)
		if r == "":
			r = _match(code & 0xfffd0000 | ST_ATTACK, any_mod)
	if r == "" and fallback:
		var c := []
		for e: Dictionary in adb:
			if _same(int(e.code), code, any_mod) and has_anim(e.name):
				c.append(e.name)
		if not c.is_empty():
			r = c.pick_random()
	return r


func _same(a: int, b: int, any_mod: bool) -> bool:
	return (a ^ b) & (0xc03f8000 if any_mod else 0xffff8000) == 0


## the query's weapon bits must all be in the clip's mask (an
## unarmed query only takes unarmed clips); of several, one roll 0-99 drops
## the clips whose weight is below it, then a uniform pick (the first uniform
## pick stays when none is left).
func _match(q: int, any_mod: bool) -> String:
	var c := []
	for e: Dictionary in adb:
		var code: int = e.code
		var miss := code if q & 0x7fff == 0 else ~code & q
		if miss & 0x7fff == 0 and _same(code, q, any_mod) and has_anim(e.name):
			c.append(e)
	if c.is_empty():
		return ""
	if c.size() == 1:
		return c[0].name
	var roll := randi() % 100
	var first: Dictionary = c.pick_random()
	var kept := c.filter(func(e): return int(e.weight) >= roll)
	return (kept.pick_random() if not kept.is_empty() else first).name


## The original's query for a logical action (idle
## walk/run, attack, cast, hit/death).
func code_for(action: String) -> int:
	var st := pose_state
	if action == "crawl":
		st = ST_LIE
	if action == "run" and st & ST_WARRY:
		action = "walk"     # no running on knees or crawling (posture 3 = standing run)
	var code: int = _ACTION_CODE[action] | st | weapon_bit()
	match action:
		"idle": code |= STAGE_CYCLE | MOD_1
		"walk", "run", "crawl": code |= STAGE_CYCLE | pose_mod
	return code


## Stance change clip: from-state | cross | target modifier
## (1 neutral, 2 attack, 3 kneel, 4 crawl, 5 rest); `resume` plays after it.
const _CROSS_TO := {ST_NEUTRAL: 1, ST_ATTACK: 2, ST_WARRY: 3, ST_LIE: 4, ST_REST: 5}
var _resume := ""
var _resume_clip := ""  # cycle selected together with a movement start


func cross(from_st: int, to_st: int, resume: String) -> float:
	if adb.is_empty() or not _CROSS_TO.has(to_st):
		return 0.0
	var clip := pick(weapon_bit() | from_st | AC_CROSS | _CROSS_TO[to_st] * MOD_1)
	if clip == "":
		return 0.0
	_play(clip, 0.1, true)
	_cycle = code_for(resume) if _ACTION_CODE.has(resume) else -1
	_cycle_pos = 0.0
	_resume = resume
	_resume_clip = ""
	return player.get_animation("ei/" + clip).length


func _process(_dt: float) -> void:
	if _resume != "" and player and not player.is_playing():
		var r := _resume
		var clip := _resume_clip
		_resume = ""
		_resume_clip = ""
		_cycle_pos = 0.0
		if clip != "":
			_play(clip, 0.0, true)
		else:
			_cycle = -1
			act(r)
		return
	if _resume != "":
		return
	# A cycle clip that wrapped around picks again (the idle variants).
	if _cycle < 0 or player == null or not player.is_playing():
		return
	var t := player.current_animation_position
	if t < _cycle_pos and _cycle & 0x3c0000 == AC_IDLE:
		var clip := pick(_cycle)
		if clip != "" and clip != _current:
			_play(clip, 0.3)
	_cycle_pos = t


func resolve(action: String, variant := 1) -> String:
	var key := "%s%d" % [action, variant]
	if not _resolved.has(key):
		_resolved[key] = _resolve(action, variant)
	return _resolved[key]


func _resolve(action: String, variant := 1) -> String:
	var prefixes := ["c", "u", "s", "b"]
	for pre in prefixes:
		for name in ["%s%s%02d" % [pre, action, variant], "%s%s" % [pre, action], "%s%s01" % [pre, action]]:
			if has_anim(name):
				return name
	for a in anim_names():
		if a.substr(1).begins_with(action):
			return a
	return ""


func has_anim(anim: String) -> bool:
	return player != null and player.has_animation("ei/" + anim)


func anim_names() -> PackedStringArray:
	var out := PackedStringArray()
	if player:
		for a in player.get_animation_list():
			out.append(a.trim_prefix("ei/"))
	return out


func _build(model: Dictionary, unit: Dictionary, proto: Dictionary, race: Dictionary) -> void:
	var db := GameData.db
	var complexion: Vector3 = unit.get("complexion", Vector3.ZERO)
	if complexion == Vector3.ZERO:   # spawned without a map record: the prototype's build
		complexion = GameUnit.proto_complexion(proto)
	var mask := String(race.get("mask", template)).to_lower()
	var parts: Dictionary = model.parts

	# --- which mesh goes on which part
	var mesh_for := {}  # part -> fig part name
	var body_parts: PackedStringArray = unit.get("parts", PackedStringArray())
	for link: Array in model.links:
		var p: String = link[0]
		if "." in p:
			continue
		# Without the map's part list only the body gets meshes; weapon and
		# armour variants are added below from what the unit carries.
		if p in body_parts or (body_parts.is_empty() and _is_body_part(p, model)):
			mesh_for[p] = p
	var layers: Array[String] = []
	var skins: PackedStringArray = race.get("textures", PackedStringArray())
	var skin_i: int = proto.get("skin", 0)
	var skin := skins[skin_i] if skin_i >= 0 and skin_i < skins.size() else (skins[0] if skins.size() else "")
	layers.append(skin.to_lower())

	# Hair is a variant under the head ("hr.00".."hr.02" = prototype hair
	# 0..2); there is no base "hr" part. A helmet hides it.
	var hair_part := "hr.%02d" % int(unit.get("hair", proto.get("hair", 0)))
	if not parts.has(hair_part):
		hair_part = ""

	var wears: Array = Array(unit.get("armors", PackedStringArray()))
	if not unit.has("armors"):
		wears = Array(proto.get("wears", PackedStringArray()))
	var armors := []
	for w: String in wears:
		var nm := w.get_slice("@", 0).get_slice("|", 0).split(".")
		var a := db.find("armors", nm[0])
		if a.is_empty():
			continue
		armors.append([a, db.find("materials", nm[1] if nm.size() > 1 else "")])
	armors.sort_custom(func(x, y): return ARMOR_ORDER.find(x[0].type) < ARMOR_ORDER.find(y[0].type))
	for am: Array in armors:
		var a: Dictionary = am[0]
		var t1: int = a.get("texture1", -1)
		if t1 < 0 or not ARMOR_PREFIX.has(a.type):
			continue
		layers.append("%s_%02d.%s.%d" % [ARMOR_PREFIX[a.type], t1, am[1].get("code", ""), a.get("texture2", 0)])
		for p: String in ARMOR_PARTS.get(a.type, []):
			var v := "%s.armor%02d" % [p, t1]
			if parts.has(v):
				mesh_for[p] = v
		if a.type == "helm":
			mesh_for.erase("hr")

	# The weapon's redress layer shares the body's UV space but overlaps the
	# face and torso, so only the weapon meshes get it (on top of the rest).
	var weapon_layer := ""
	var before := mesh_for.duplicate()
	# Weapon meshes ("rh3.dagger01", "lh3.bwpartb01") are the weapon alone:
	# the original draws them in addition to the hand (its fist grips the
	# handle), unlike armour variants, which replace the part's mesh.
	var held := {}   # part -> weapon fig part
	var weapons: Array = Array(unit.get("weapons", PackedStringArray()))
	if not unit.has("weapons") and String(proto.get("weapon", "")) != "":
		weapons = [proto.weapon]
	for w: String in weapons.slice(0, 1):
		var nm := w.get_slice("@", 0).get_slice("|", 0).split(".")
		var wd := db.find("weapons", nm[0])
		if wd.is_empty():
			continue
		weapon_type = wd.type
		var t1: int = wd.get("texture1", 1)
		var mat := db.find("materials", nm[1] if nm.size() > 1 else "")
		if WEAPON_PREFIX.has(wd.type):
			weapon_layer = ("%s_%02d.%s.%d" % [WEAPON_PREFIX[wd.type], t1, mat.get("code", ""), wd.get("texture2", 0)])
		if WEAPON_MESH.has(wd.type):
			for idx in [t1, t1 - 1]:   # "%02d" of the weapon record (texture1)
				var v: String = WEAPON_MESH[wd.type] % idx
				if parts.has(v):
					held["rh3"] = v
					break
		elif wd.type == "bow":
			for idx in [t1, t1 - 1]:   # "%02d" of the weapon record (texture1)
				if parts.has("lh3.bwpartb%02d" % idx):
					held["lh3"] = "lh3.bwpartb%02d" % idx
					for extra in ["bwparta%02d", "bwtetivaa%02d", "bwtetivab%02d"]:
						if parts.has(extra % idx):
							mesh_for[extra % idx] = extra % idx
					break
		if wd.type == "crossbow":
			for extra in ["crbow%02dpart01", "crbow%02dpart02", "crbow%02dtetiva01", "crbow%02dtetiva02"]:
				if parts.has(extra % t1):
					mesh_for[extra % t1] = extra % t1

	var weapon_parts := {}
	for p: String in mesh_for:
		if before.get(p, "") != mesh_for[p]:
			weapon_parts[p] = true
	# Weapon variants live below animated mount nodes in the original LNK.
	# For example rh3 -> rh3.sword00 -> rh3.dagger03: sword00 supplies both
	# a BON offset and an ANM track. Attaching the blade directly to rh3 puts
	# its handle through the wrist and discards the weapon's animation.
	for p: String in held:
		mesh_for[held[p]] = held[p]
		weapon_parts[held[p]] = true

	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_BACK   # the original render state
	mat.roughness = 1.0
	# D3D fixed-function lighting is Lambert (Godot defaults to Burley, which
	# darkens grazing faces and shows the low-poly facets).
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_texture = _compose(mask, layers)
	set_meta("layers", [mask, layers])
	var wmat := mat
	if weapon_layer:
		wmat = mat.duplicate()
		var wl: Array[String] = layers.duplicate()
		wl.append(weapon_layer)
		wmat.albedo_texture = _compose(mask, wl)

	# --- node hierarchy (base parts + extras that have meshes)
	var weld: bool = smooth_joints and bool(unit.get("weld", true))
	var nodes := {}
	var paths := {}
	var root_part := ""
	var rest_pos := {}      # part -> position in the model at rest (no rotations)
	var parent_of_node := {}
	var welded := {}        # part -> ArrayMesh in part space
	var parent_of := {}
	var needed := {}
	for link: Array in model.links:
		parent_of[link[0]] = link[1]
		if not "." in link[0] and _is_body_part(link[0], model):
			needed[link[0]] = true
	for p: String in mesh_for:
		var ancestor := p
		while ancestor != "":
			needed[ancestor] = true
			ancestor = parent_of.get(ancestor, "")
	for link: Array in model.links:
		var p: String = link[0]
		if not needed.has(p):
			continue
		var n := AnimatedPart.new()
		n.name = p.replace(".", "_")
		var bone: PackedFloat32Array = model.bones.get(p, PackedFloat32Array())
		if bone.size() >= 24:
			n.position = EISpace.vec(EIFigure.bone_pos(bone, complexion))
		var par_name := String(link[1])
		var parent: Node3D = nodes.get(par_name, self)
		if parent == self:
			root_part = p
		else:
			parent_of_node[p] = par_name
			n.animation_parent = parent as EIAnimPart
			if n.animation_parent:
				n.animation_parent.animation_children.append(n)
		parent.add_child(n)
		nodes[p] = n
		rest_pos[p] = rest_pos.get(par_name, Vector3.ZERO) + n.position if parent != self else n.position
		if mesh_for.has(p):
			var fig: Dictionary = parts[mesh_for[p]]
			var mesh := EIFigure.build_mesh(fig, complexion)
			if weld and not weapon_parts.has(p):
				welded[p] = [mesh, mat]
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = wmat if weapon_parts.has(p) else mat
			n.add_child(mi)
	if weld:
		_weld(nodes, rest_pos, parent_of_node, welded)

	if hair_part and nodes.has("hd"):
		var hn := Node3D.new()
		hn.name = "hr"
		var hb: PackedFloat32Array = model.bones.get(hair_part, PackedFloat32Array())
		if hb.size() >= 24:
			hn.position = EISpace.vec(EIFigure.bone_pos(hb, complexion))
		nodes["hd"].add_child(hn)
		var hm := MeshInstance3D.new()
		hm.mesh = EIFigure.build_mesh(parts[hair_part], complexion)
		hm.material_override = mat
		hn.add_child(hm)

	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	player.root_node = NodePath("..")
	# Track paths follow the full part hierarchy so one library fits every unit of this template.
	for p: String in parent_of:
		var chain := PackedStringArray([p.replace(".", "_")])
		var q: String = parent_of[p]
		while parent_of.has(q):
			chain.insert(0, q.replace(".", "_"))
			q = parent_of[q]
		paths[p] = NodePath("/".join(chain))
	adb = load_adb(template)
	player.add_animation_library("ei", EIAnim.library(template, paths, root_part, height_scale(template, complexion.z), true))
	neutral = _has_neutral()
	movement_starts = int(race.get("type_id", 0)) == 0x32
	pose_state = ST_NEUTRAL if neutral else ST_ATTACK
	act("idle", 1, 0.0)


## Builds the skinned body (see `smooth_joints`): a flat Skeleton3D with one
## bone per part node, driven by the part nodes (BoneAttachment3D with
## override_pose, so the animation tracks and code that looks parts up by
## name keep working), and one mesh of all welded parts, one surface per
## material (the held weapon's hand has its own texture). Across each joint
## the weight ramps from the part's own bone to 0.5/0.5 at the joint plane,
## measured along the child bone's axis within `r`, so both sides of a joint
## converge on the same transform and overlapping ends (the forearm reaches
## ~5 mm into the fist in the data) move together instead of poking out.
func _weld(nodes: Dictionary, rest_pos: Dictionary, parent_of: Dictionary, welded: Dictionary) -> void:
	if welded.is_empty():
		return
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	add_child(skel)
	var bone_of := {}
	var skin := Skin.new()
	for p: String in nodes:
		var i := skel.add_bone(p)
		bone_of[p] = i
		var rest := Transform3D(Basis(), rest_pos[p])
		skel.set_bone_rest(i, rest)
		skel.set_bone_pose(i, rest)
		skin.add_named_bind(p, rest.affine_inverse())
	for p: String in nodes:
		var ba := nodes[p] as BoneAttachment3D
		ba.override_pose = true   # first, so setting the bone never moves the node
		ba.use_external_skeleton = true
		ba.external_skeleton = ba.get_path_to(skel)
		ba.bone_name = p
	var children := {}
	for c: String in parent_of:
		# Attachment mounts move weapons; they must not bend the hand mesh.
		if not welded.has(c) or not welded.has(parent_of[c]):
			continue
		if not children.has(parent_of[c]):
			children[parent_of[c]] = []
		children[parent_of[c]].append(c)
	# Joint of part c with its parent, in model rest space: position, axis
	# (c's own bone direction, pointing away from the parent), radius.
	var joints := {}
	for c: String in parent_of:
		var par: String = parent_of[c]
		if not welded.has(c) or not welded.has(par):
			continue
		var axis: Vector3 = rest_pos[c] - rest_pos[par]
		var kids: Array = children.get(c, [])
		if not kids.is_empty():
			axis = rest_pos[kids[0]] - rest_pos[c]
		var length := axis.length()
		joints[c] = [rest_pos[c], axis.normalized() if length > 1e-5 else Vector3.DOWN,
			clampf(length * 0.25, 0.02, 0.06)]
	var surf := {}   # material -> [pos, nrm, uv, bones, weights, idx]
	for p: String in welded:
		var mesh: ArrayMesh = welded[p][0]
		var m: Material = welded[p][1]
		if not surf.has(m):
			surf[m] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(),
				PackedInt32Array(), PackedFloat32Array(), PackedInt32Array()]
		var s: Array = surf[m]
		var arr := mesh.surface_get_arrays(0)
		# The joints this part takes part in: [joint, other bone, side] where
		# side = +1 if this part is the child (its body lies along +axis).
		var mine := []
		if joints.has(p):
			mine.append([joints[p], bone_of[parent_of[p]], 1.0])
		for c: String in children.get(p, []):
			mine.append([joints[c], bone_of[c], -1.0])
		var base: int = s[0].size()
		for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
			var mv: Vector3 = v + rest_pos[p]
			s[0].append(mv)
			var other: int = bone_of[p]
			var w := 0.0
			for jt: Array in mine:
				var j: Array = jt[0]
				var r: float = j[2]
				var rel: Vector3 = mv - j[0]
				var along: float = rel.dot(j[1]) * jt[2]   # > 0 inside this part
				if rel.length() > r * 4.0:   # far from the joint (other side of the torso)
					continue
				var d := maxf(along, 0.0)
				if d < r:
					var jw := 0.5 * (1.0 - d / r)
					if jw > w:
						w = jw
						other = jt[1]
			s[3].append_array([bone_of[p], other, 0, 0])
			s[4].append_array([1.0 - w, w, 0.0, 0.0])
		s[1].append_array(arr[Mesh.ARRAY_NORMAL])
		s[2].append_array(arr[Mesh.ARRAY_TEX_UV])
		for i: int in arr[Mesh.ARRAY_INDEX]:
			s[5].append(base + i)
	var body := ArrayMesh.new()
	var mats := []
	for m: Material in surf:
		var s: Array = surf[m]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_TEX_UV] = s[2]
		arrays[Mesh.ARRAY_BONES] = s[3]
		arrays[Mesh.ARRAY_WEIGHTS] = s[4]
		arrays[Mesh.ARRAY_INDEX] = s[5]
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mats.append(m)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = body
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	skel.add_child(mi)
	mi.skin = skin
	mi.skeleton = NodePath("..")


## Shows or hides a part and everything below it (severed limbs). The welded
## body has no per-part mesh, so the part is also shrunk to its joint.
func set_part_visible(part: String, on: bool) -> void:
	var n := find_child(part, true, false) as Node3D
	if n == null:
		return
	n.visible = on
	n.scale = Vector3.ONE if on else Vector3.ONE * 0.001


## Body parts are the non-variant parts that have bones; weapon/armor extras
## (bows, quivers, shells) are only created when worn.
static func _is_body_part(p: String, model: Dictionary) -> bool:
	return model.parts.has(p) and not (p.begins_with("bw") or p.begins_with("crbow")
		or p.begins_with("base") or p in ["arrows", "quiver", "l_shell", "r_shell"])


static func _compose(mask: String, layers: Array[String]) -> Texture2D:
	var key := mask + "|" + "|".join(layers)
	if _textures.has(key):
		return _textures[key]
	var base: Image = null
	for i in layers.size():
		var img := _load_layer(mask, layers[i])
		if img == null:
			continue
		if base == null:
			base = img
			continue
		if img.get_size() != base.get_size():
			img.resize(base.get_width(), base.get_height(), Image.INTERPOLATE_BILINEAR)
		base.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	var tex: Texture2D = null
	if base:
		base.generate_mipmaps()
		tex = ImageTexture.create_from_image(base)
	_textures[key] = tex
	return tex


static func _load_layer(mask: String, layer: String) -> Image:
	var d := GameData.redress.read(mask + layer + ".mmp")
	if d.is_empty():
		d = GameData.textures.read(layer + ".mmp")
	return EIMmp.decode(d) if not d.is_empty() else null
