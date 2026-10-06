class_name GroundMarks
extends Node3D
## Ground marks of the original: blood marks (list world
## option "marks" = EnableBloodprints), footprints (list
## option "footprints" = EnableFootprints) and scorch marks
## (list, registry EnableFireprints). One per GameWorld
## on every peer and visual only: footprints come from each unit's walk / run
## clip step frames as this peer animates it, blood marks from the broadcast
## "blood" hit event and the authoritative "blood_pool" UID event, scorch
## marks from the effects ParticleFx creates here. Only creation events are
## replicated. The original does not keep marks
## in a savegame (loading empties the three lists), nor does the
## remake. The heavy-monster step shake is
## made here too, from the same step frames.
##
## Each mark is a rectangle (centre, half-extents a / b, angle) projected
## straight down onto the ground (clips it to the
## terrain triangles, +0.01 m), with one atlas cell of its texture and alpha
## base × min(1, life / fade); prints.db gives base alpha, life and fade per
## ground type (EIDatabase "blood_prints" / "foot_prints"). Drawn here as
## Decal nodes culled to EITerrain.DECAL_LAYER (terrain and bridges).

const TICK := 0.055
## Remake caps (the original keeps every mark until its life ends).
const MAX_FOOT := 256
const MAX_BLOOD := 96
const MAX_FIRE := 64
## Registry "EnableFireprints" (settings, default 1
## no Options row, never writes it).
const ENABLE_FIREPRINTS := true
const DEPTH := 2.0              # decal box height (projection range), metres
const FADE_FAR := 70.0          # decals fade out beyond this camera distance
## Hit parts (switch): head, body, left / right hand, legs.
const HIT_PARTS := ["hd", "bd", "lh2", "rh2", "ll2", "rl2"]
## Part half-extents when the part has no own mesh.
const FALLBACK_EXT := {"foot": Vector2(0.05, 0.12), "bd": Vector2(0.2, 0.15), "": Vector2(0.06, 0.12)}

class Mark:
	var foot := false
	var x := 0.0
	var y := 0.0
	var a := 0.0                # half-extent across
	var b := 0.0                # half-extent along
	var grow := 0.0             # blood: size step per tick
	var grow_left := 0          # blood: growth ticks left
	var angle := 0.0            # rectangle angle
	var spin := 0.0             # blood: angle step per tick
	var life := 0               # ticks left
	var fade := 1
	var alpha0 := 1.0
	var blood := -1             # blood type - 1, footprints' blood (-1 none)
	var splash := false         # hit splatter: not picked up by feet
	var decal: Decal


## Persistent typed state avoids rebuilding a set and looking up dictionary fields for
## every unit on every rendered frame. Clip time stays live; death pools retain their authoritative event path.
class StepState:
	var clip := ""
	var frame := 0.0
	var bloody := -1
	var left := 0
	var wait := 0
	var raw := -1.0
	var anim := &""
	var clip_name := ""
	var seen := 0
	var contacts: Dictionary = {}
	var foot_model := 0
	var feet: Array[WeakRef] = []


var world: GameWorld
var tick := 0
var acc := 0.0
var blood_marks: Array[Mark] = []
var foot_marks: Array[Mark] = []
var fire_marks: Array[Mark] = []
var _tables := {}               # "blood" / "foot" -> Array of [alpha, life, fade]
var _cells := {}                # texture cell key -> ImageTexture
var _images := {}               # texture name -> Image
var _steps := {}                # template -> {clip: {act, steps, hit}}
var _pending_units := {}        # units whose animation advanced since the last draw
var _units := {}                # unit instance id -> per-unit step state
var _ext := {}                  # "<instance id>:<part>" -> Vector2 half-extents
var _sole_meshes := {}          # weak mesh reference + its immutable local vertices
var _sole_sweep := 0
var _rng := RandomNumberGenerator.new()
static var _dbres: EIResArchive


static func of(w: GameWorld) -> GroundMarks:
	if w == null:
		return null
	var n := w.get_node_or_null("GroundMarks") as GroundMarks
	if n == null:
		n = GroundMarks.new()
		n.name = "GroundMarks"
		n.world = w
		w.add_child(n)
	return n


func _ready() -> void:
	# Animation advances enqueue their owners. Drain after unit/model drawing,
	# so paused and unchanged figures cost nothing per rendered frame.
	process_priority = 1
	world.ground_marks = self
	world.unit_spawned.connect(queue_unit)
	world.unit_died.connect(_unit_died)
	_rng.randomize()
	for k in [["blood", "blood_prints"], ["foot", "foot_prints"], ["fire", "fire_prints"]]:
		var rows := []
		if GameData.db:
			for r: Dictionary in GameData.db.table(k[1]):
				rows.append(Array(r.get("normal", [0.0, 0, 0])))
		_tables[k[0]] = rows
	GameData.options_changed.connect(_apply_options)
	_scan_units()


func _exit_tree() -> void:
	if is_instance_valid(world) and world.ground_marks == self:
		world.ground_marks = null


## The prints.db row [alpha, life, fade] of a ground type. The original takes the
## "alt" set while world is set (0 / 1 / 2, a mob spawn condition
## never set in the export); the remake always uses "normal".
func _row(kind: String, ground: int) -> Array:
	var rows: Array = _tables.get(kind, [])
	if ground < 0 or ground >= rows.size():
		return []
	var r: Array = rows[ground]
	if r.size() < 3 or float(r[0]) <= 0.0 or int(r[1]) <= 0 or int(r[2]) <= 0:
		return []
	return r


func _apply_options() -> void:
	for m in blood_marks:
		m.decal.visible = GameData.option("marks") != 0
	for m in foot_marks:
		m.decal.visible = GameData.option("footprints") != 0


# ------------------------------------------------------------------ tick

func _process(dt: float) -> void:
	acc += dt
	var n := 0
	while acc >= TICK and n < 8:
		acc -= TICK
		_tick()
		n += 1
	if acc >= TICK:
		acc = fmod(acc, TICK)
	_drain_units()


## World tick: each mark's update, removed at life 0.
func _tick() -> void:
	tick += 1
	for list: Array[Mark] in [blood_marks, foot_marks, fire_marks]:
		var i := 0
		while i < list.size():
			var m := list[i]
			if _update(m) <= 0:
				m.decal.queue_free()
				list.remove_at(i)
				continue
			i += 1


##  (blood) / (footprints).
func _update(m: Mark) -> int:
	var moved := false
	if not m.foot:
		m.grow_left -= 1
		if m.grow_left < 0:
			m.grow = 0.0
		m.angle += m.spin
		moved = m.grow != 0.0 or m.spin != 0.0
	m.life -= 1
	m.a += m.grow
	m.b += m.grow
	var f := float(m.fade - m.life) / float(m.fade)
	var alpha := (1.0 - maxf(f, 0.0)) * m.alpha0
	if moved:
		_place(m)
	if m.decal.modulate.a != alpha:
		m.decal.modulate.a = alpha
	return m.life


# ------------------------------------------------------------------ creation

## a blood mark at (x, y) growing from r0 to r1
## (half-extent) over min(life / 2, 45) ticks; `code` = (blood type - 1) << 16
## | atlas cell (0 / 1 splatters, 2 / 3 pools of bloodprints.mmp, 4 × 4 cells
## of 0.25, a 2 × 2 block per blood type).
func add_blood(x: float, y: float, r0: float, r1: float, code: int, splash: bool) -> void:
	if GameData.option("marks") == 0 or world == null or world.terrain == null:
		return
	var row := _row("blood", world.terrain.mark_ground(x, y))
	if row.is_empty():
		return
	var m := Mark.new()
	m.x = x
	m.y = y
	m.a = r0
	m.b = r0
	m.life = int(row[1])
	m.fade = int(row[2])
	m.alpha0 = float(row[0])
	m.grow_left = maxi(mini(m.life / 2, 45), 1)
	m.grow = (r1 - r0) / float(m.grow_left)
	# the cell turned by rand(4) · π/2;: rand(2π · 1000) / 1000
	# turning by π/180 · 30 / life per tick (30° over the life).
	var turn := _rng.randi() % 4
	m.angle = float(_rng.randi() % roundi(TAU * 1000.0)) * 0.001
	m.spin = PI / 180.0 * (30.0 / float(m.life))
	m.blood = code >> 16
	m.splash = splash
	var u0 := float((code >> 16) & 1) * 0.5 + float(code & 1) * 0.25
	var v0 := float(code >> 17) * 0.5 + float((code & 0xffff) >> 1) * 0.25
	_add(m, _cell("bloodprints", Rect2(u0, v0, 0.25, 0.25), turn), blood_marks, MAX_BLOOD,
		GameData.option("marks") != 0)


## a footprint of half-extents (w, h) at (x, y)
## angle `ang`; `code` = left leg << 16 | footprint type (footprints.mmp:
## 0.125 × 0.125 per type, 8 per row; the right leg's print in the cell's left
## half, the left leg's in its right half).
## A print within (w + h) / 2 of a blood pool's half-extent takes that pool's
## blood (not splatters): the blood table row and "footprints<type + 1>"; the
## pool's type is returned (else -1), `bloody` is the type still on the feet.
func add_footprint(x: float, y: float, w: float, h: float, ang: float, code: int, bloody: int) -> int:
	if GameData.option("footprints") == 0 or world == null or world.terrain == null:
		return -1
	var found := false
	var r := (w + h) * 0.5
	for p in blood_marks:
		if (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) <= (p.a + r) * (p.a + r) and not p.splash:
			bloody = p.blood
			found = true
			break
	var row := _row("foot" if bloody == -1 else "blood", world.terrain.mark_ground(x, y))
	if not row.is_empty():
		var m := Mark.new()
		m.foot = true
		m.x = x
		m.y = y
		m.a = w
		m.b = h
		m.angle = ang
		m.life = int(row[1])
		m.fade = int(row[2])
		m.alpha0 = float(row[0])
		var u0 := float(code >> 16) * 0.0625 + float(code & 7) * 0.125
		var v0 := float((code & 0xffff) >> 3) * 0.125
		var tex := "footprints" if bloody == -1 else "footprints%d" % (bloody + 1)
		_add(m, _cell(tex, Rect2(u0, v0, 0.0625, 0.125), 0), foot_marks, MAX_FOOT,
			GameData.option("footprints") != 0)
	return bloody if found else -1


## a scorch mark of half-extents (a, b)
## (x, y), angle `ang`, alpha `strength` (the fire table's alpha is not read;
## only its life and fade, and strength > 0). Texture "fireprints", one of
## its 2 × 2 cells of 0.5 picked by r = rand(4) (u = (r & 1) / 2, v = (r >> 1)
## 2), the cell turned by r · π/2; no growth or turning, ageing as
## footprints. Only while EnableFireprints is set.
func add_scorch(x: float, y: float, a: float, b: float, ang: float, strength: float) -> void:
	if not ENABLE_FIREPRINTS or world == null or world.terrain == null or not strength > 0.0:
		return
	var rows: Array = _tables.get("fire", [])
	var g := world.terrain.mark_ground(x, y)
	if g < 0 or g >= rows.size():
		return
	var row: Array = rows[g]
	if row.size() < 3 or int(row[1]) <= 0 or int(row[2]) <= 0:
		return
	var m := Mark.new()
	m.foot = true   # footprint-style update: no growth, no turning
	m.x = x
	m.y = y
	m.a = a
	m.b = b
	m.angle = ang
	m.life = int(row[1])
	m.fade = int(row[2])
	m.alpha0 = strength
	var r := _rng.randi() % 4
	_add(m, _cell("fireprints", Rect2(float(r & 1) * 0.5, float(r >> 1) * 0.5, 0.5, 0.5), r),
		fire_marks, MAX_FIRE, true)


## A random angle as the original's · 2π / 2^32.
func rand_angle() -> float:
	return float(_rng.randi()) * (TAU / 4294967296.0)


func _add(m: Mark, tex: Texture2D, list: Array[Mark], cap: int, shown: bool) -> void:
	if tex == null:
		return
	var d := Decal.new()
	d.texture_albedo = tex
	d.cull_mask = EITerrain.DECAL_LAYER
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.distance_fade_enabled = true
	d.distance_fade_begin = FADE_FAR
	d.distance_fade_length = 15.0
	d.modulate = Color(1, 1, 1, m.alpha0 * minf(1.0, float(m.life) / float(m.fade)))
	d.visible = shown
	m.decal = d
	add_child(d)
	_place(m)
	list.append(m)
	while list.size() > cap:
		list[0].decal.queue_free()
		list.remove_at(0)


## The rectangle's local x axis is (cos, sin)(angle) in EI; the cell's top
## (V 0) faces (sin, -cos)(angle) (the walking direction for footprints).
func _place(m: Mark) -> void:
	var fwd := Vector3(sin(m.angle), 0.0, cos(m.angle))      # Godot (EI y -> -z)
	var z_axis := -fwd
	var x_axis := Vector3.UP.cross(z_axis)
	var ground := world.ground_at(m.x, m.y)
	m.decal.transform = Transform3D(Basis(x_axis, Vector3.UP, z_axis), EISpace.pos(m.x, m.y, ground))
	m.decal.size = Vector3(maxf(m.a, 0.01) * 2.0, DEPTH, maxf(m.b, 0.01) * 2.0)


## One atlas cell as its own texture (Decal has no UV rect), turned `turn` × 90°.
func _cell(tex: String, uv: Rect2, turn: int) -> Texture2D:
	var key := "%s:%s:%d" % [tex, uv, turn]
	if _cells.has(key):
		return _cells[key]
	if not _images.has(tex):
		_images[tex] = GameData.load_image(tex)
	var img: Image = _images[tex]
	var t: ImageTexture = null
	if img:
		var sz := Vector2(img.get_width(), img.get_height())
		var cell := img.get_region(Rect2i(Vector2i((uv.position * sz).round()), Vector2i((uv.size * sz).round())))
		for i in turn:
			cell.rotate_90(CLOCKWISE)
		cell.generate_mipmaps()
		t = ImageTexture.create_from_image(cell)
	_cells[key] = t
	return t


# ------------------------------------------------------------------ triggers

## Body-part hit, event "blood": blood types 1-4 leave a
## splatter of (w + h) / 2 · 0.3 growing to 3×, at the struck part moved by up
## to ±R on x and y (R = the unit's size, at most 1 m), cell rand(2).
func hit(ev: Dictionary) -> void:
	var u := _unit(ev.get("uid"))
	if u == null or float(ev.get("frac", 0.0)) <= 0.0001:
		return
	var bt := int(u.race.get("blood_type", 0))
	if bt < 1 or bt > 4:
		return
	var part := String(HIT_PARTS[clampi(int(ev.get("part", 1)), 0, 5)])
	var n := _part(u, part)
	if n == null:
		return
	var ext := _extent(u, part, n)
	var r := (ext.x + ext.y) * 0.5 * 0.3
	var big := minf(_unit_size(u), 1.0)
	var k := maxi(roundi(big * 100.0), 1)
	var p := ParticleFx.ei(n.global_position)
	var x := p.x + float(_rng.randi() % k) * 0.02 - big
	var y := p.y + float(_rng.randi() % k) * 0.02 - big
	add_blood(x, y, r, r * 3.0, (_rng.randi() % 2) | ((bt - 1) << 16), true)


##  (unit controller): a pool of (w + h) / 2 of the
## body ("bd"; else 0.75 × the smaller horizontal unit extent) growing to 3×, cell
## 2 + rand(2). Called by the authoritative death-queue UID event.
func pool(u: GameUnit) -> void:
	var bt := int(u.race.get("blood_type", 0))
	if bt < 1 or bt > 4:
		return
	var r: float
	var p: Vector3
	var n := _part(u, "bd")
	if n:
		var ext := _extent(u, "bd", n)
		r = (ext.x + ext.y) * 0.5
		p = ParticleFx.ei(n.global_position)
	else:
		r = _unit_size(u, true) * 0.75
		p = ParticleFx.ei(u.global_position)
	add_blood(p.x, p.y, r, r * 3.0, (_rng.randi() % 2 + 2) | ((bt - 1) << 16), false)


## Explicit resynchronization after attaching the effect system. Normal
## frames consume only the animation worklist; tools may rescan after seeking.
func _scan_units() -> void:
	if world == null: return
	for u: GameUnit in world.units.values():
		queue_unit(u)
	_drain_units()


func queue_unit(u: GameUnit) -> void:
	if not is_instance_valid(u): return
	var key := u.get_instance_id()
	if not _units.has(key):
		_units[key] = StepState.new()
		var cleanup := _forget_unit.bind(key)
		if not u.tree_exiting.is_connected(cleanup):
			u.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	_pending_units[key] = u


func _forget_unit(key: int) -> void:
	if _units.has(key):
		_clear_deform_contacts(_units[key])
		_units.erase(key)
	_pending_units.erase(key)


func _unit_died(u: GameUnit, _killer: GameUnit) -> void:
	var st: StepState = _units.get(u.get_instance_id())
	if st != null: _clear_deform_contacts(st)


func _drain_units() -> void:
	if world == null or world.terrain == null: return
	for key: int in _pending_units:
		var u: GameUnit = _pending_units[key]
		if not is_instance_valid(u): continue
		var st: StepState = _units[key]
		if u.dead:
			_clear_deform_contacts(st)
		elif u.model != null and u.model.player != null:
			_step_frames(u, st)
	_pending_units.clear()
	if tick >= _sole_sweep and _sole_meshes.size() > 256:
		_sole_sweep = tick + 40
		for key in _sole_meshes.keys():
			if _sole_meshes[key].ref.get_ref() == null: _sole_meshes.erase(key)


func _step_frames(u: GameUnit, st: StepState) -> void:
	var pl := u.model.player
	var anim: StringName = pl.current_animation
	if anim == &"":
		_clear_deform_contacts(st)
		st.clip = ""
		st.frame = 0.0
		st.raw = -1.0
		st.anim = &""
		st.clip_name = ""
		return
	# Early out while the pose has not moved (idle units, and the off-screen
	# ones the animation LOD steps only now and then).
	var raw := pl.current_animation_position
	if raw == st.raw and anim == st.anim:
		return
	st.raw = raw
	if anim != st.anim:
		st.anim = anim
		st.clip_name = String(anim).trim_prefix("ei/")
	var clip := st.clip_name
	if clip == "":
		return
	var cur := raw * EIAnim.FPS
	if clip != st.clip:
		st.clip = clip
		st.frame = 0.0
	var prev: float = st.frame
	if cur == prev:
		return
	st.frame = cur
	var rec: Dictionary = _clip_steps(u.model.template).get(clip, {})
	if rec.is_empty():
		_clear_deform_contacts(st)
		return
	if int(rec.act) in [4, 5] and u.visible and u.stance != GameUnit.STANCE_CRAWL:
		_deform_feet(u, st)
	else:
		_clear_deform_contacts(st)
	if int(rec.act) == 2:   # clip flags: the shake at record
		# Skipped while the client's world mode is 3 (
		# set from world): the village screen.
		if _passed(prev, cur, float(rec.hit)) and String(world.zone.get("type", "")) != "brief":
			_step_shake(u)
		return
	if not u.visible or u.stance == GameUnit.STANCE_CRAWL:   # unit = 0: no prints
		return
	var steps: PackedInt32Array = rec.steps
	for i in steps.size():
		var f := steps[i] - 1
		if f == 0:
			break
		if f < 0:
			continue
		if _passed(prev, cur, f):
			_step_shake(u)
			_step(u, i, st)
			break


func _passed(prev: float, cur: float, f: float) -> bool:
	return (prev < f and f <= cur) if cur > prev else (prev < f or f <= cur)


## a monster whose prototype "detonation" (record) is > 0
## shakes the camera at each step (and at a clip's frame):
## (unit position, 5, detonation, 0.25).
func _step_shake(u: GameUnit) -> void:
	var amp := float(u.proto.get("detonation", 0.0))
	if amp > 0.0:
		CameraRig.shake_at(self, Vector2(u.pos.x, u.pos.y), 5.0, amp, 0.25)


##  step: the foot "ll<n>" / "rl<n>" (n = race leg_segment, 1-8
## step index even = left unless first_step_right) makes a print of its
## half-extents, moved back by half of them along the facing, at angle
## π − acos(dir.y) (negated for dir.x < 0); feet stay bloody for rand(4) + 4
## more steps after a pool.
func _step(u: GameUnit, i: int, st: Variant) -> void:
	var fp := int(u.race.get("footprint_type", -1))
	var leg := int(u.race.get("leg_segment", 0))
	if leg <= 0 or leg >= 9:
		return
	var left := i & 1 == 0
	if bool(u.race.get("first_step_right", false)):
		left = not left
	var part := ("ll%d" if left else "rl%d") % leg
	var n := _part(u, part)
	if n != null:
		_plant_step(u, n, left, fp, st)
		return
	# Multi-legged figures (including spiders) name their terminal segments
	# leg1_l4, leg2_r4, etc. Their walking cycle plants alternating tripods.
	for pair in range(1, 9):
		var side := left if pair & 1 else not left
		n = _part(u, "leg%d_%s%d" % [pair, "l" if side else "r", leg])
		if n != null:
			_plant_step(u, n, side, fp, st)


func _plant_step(u: GameUnit, n: Node3D, left: bool, fp: int, st: Variant) -> void:
	# A legged creature can displace soft ground without a footprint atlas cell.
	if fp < 0:
		return
	var contact := _sole_contact(n)
	if contact.is_empty():
		return
	var p: Vector2 = contact.p
	var ext: Vector2 = contact.extent
	var found := add_footprint(p.x, p.y, ext.x, ext.y, contact.angle,
		(int(left) << 16) | fp, int(st.bloody))
	if int(st.left) < 1:
		st.bloody = -1
	else:
		st.left = int(st.left) - 1
	if found >= 0:
		st.bloody = found
		st.left = _rng.randi() % 4 + 4


func _clear_deform_contacts(st: StepState) -> void:
	if st.contacts.is_empty():
		return
	var details := world.terrain.details if is_instance_valid(world) and is_instance_valid(world.terrain) else null
	if is_instance_valid(details) and is_instance_valid(details.soft_ground):
		for id: int in st.contacts:
			details.soft_ground.forget_contact(id)
	st.contacts.clear()


func _deform_feet(u: GameUnit, st: StepState) -> void:
	var details := world.terrain.details
	if not is_instance_valid(details) or not is_instance_valid(details.soft_ground):
		return
	if int(u.race.get("leg_segment", 0)) <= 0:
		return
	if u.global_position.y > world.terrain.ground_at(u.pos.x, u.pos.y) + 0.2:
		_clear_deform_contacts(st)
		return
	if st.foot_model != u.model.get_instance_id():
		_clear_deform_contacts(st)
		st.foot_model = u.model.get_instance_id()
		st.feet = []
		st.contacts = {}
		# Terminal hind feet, front paws (shorter chains on quadrupeds), and
		# each of a spider's legs. Upright hands fail the ground-contact check.
		var prefixes := ["ll", "rl", "lh", "rh"]
		for pair in range(1, 9):
			prefixes.append("leg%d_l" % pair)
			prefixes.append("leg%d_r" % pair)
		for prefix: String in prefixes:
			for segment in range(8, 0, -1):
				var n := _part(u, prefix + str(segment))
				if n != null:
					st.feet.append(weakref(n))
					break
	for ref: WeakRef in st.feet:
		var n := ref.get_ref() as Node3D
		if n == null:
			continue
		var contact := _sole_contact(n)
		var id := n.get_instance_id()
		if contact.is_empty():
			if st.contacts.has(id): st.contacts[id].grounded = false
			continue
		var p: Vector2 = contact.p
		var previous: Dictionary = st.contacts.get(id, {})
		# The footfall stays at the rendered sole. Its successive plants also
		# sweep a wider band of loose material, including between footprints.
		if not previous.is_empty() and previous.grounded and p.distance_squared_to(previous.p) < 0.0036:
			continue
		details.add_step(p.x, p.y, contact.extent.x, contact.extent.y, contact.angle, id, p)
		st.contacts[id] = {"p": p, "grounded": true}


func _sole_contact(n: Node3D) -> Dictionary:
	if n.has_meta(EIFigureGeometry.META):
		var box := n.global_transform * EIFigureGeometry.box(n.get_meta(EIFigureGeometry.META))
		var centre := box.get_center()
		if box.position.y > world.terrain.ground_at(centre.x, -centre.z) + 0.09:
			return {}
	var points := PackedVector3Array()
	var bottom := INF
	for child: Node in n.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var key := mi.mesh.get_instance_id()
		if not _sole_meshes.has(key):
			var vertices := PackedVector3Array()
			for surface in mi.mesh.get_surface_count():
				vertices.append_array(mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
			_sole_meshes[key] = {"ref": weakref(mi.mesh), "vertices": vertices}
		var transform := mi.global_transform
		for vertex: Vector3 in _sole_meshes[key].vertices:
			var p := transform * vertex
			points.append(p)
			bottom = minf(bottom, p.y)
	if points.is_empty():
		return {}
	# Use the actual sole/tip, not the ankle pivot or the whole shin's box.
	var forward := Vector2(n.global_basis.z.x, -n.global_basis.z.z).normalized()
	if forward.length_squared() < 0.1: forward = Vector2.UP
	var across := Vector2(forward.y, -forward.x)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p: Vector3 in points:
		if p.y > bottom + 0.035:
			continue
		var xy := Vector2(p.x, -p.z)
		var local := Vector2(xy.dot(across), xy.dot(forward))
		lo = lo.min(local)
		hi = hi.max(local)
	var mid := (lo + hi) * 0.5
	var p := across * mid.x + forward * mid.y
	if bottom > world.terrain.ground_at(p.x, p.y) + 0.075:
		return {}
	var extent := ((hi - lo) * 0.5).clamp(Vector2(0.025, 0.045), Vector2(0.32, 0.46))
	return {"p": p, "extent": extent, "angle": forward.angle() - PI * 0.5, "height": bottom}


# ------------------------------------------------------------------ unit helpers

func _unit(uid) -> GameUnit:
	if world == null or uid == null:
		return null
	var u = world.units.get(int(uid))
	return u if is_instance_valid(u) else null


func _part(u: GameUnit, name: String) -> Node3D:
	if u.model:
		u.model.flush_pending_pose()
	return u.model.find_child(name, true, false) as Node3D if u.model else null


## Part half-extents across / along: the part box's max x / y
## (box min.., max.., unions them into the unit box
## ), from the.fig header's per-variant centred min / max.
## Authored FIG max is independent of the rendered vertex bounds. Read it
## on each call, so complexion/redressing cannot retain an old part's size.
## Mesh bounds below are only the fallback for custom parts without FIG data.
func _extent(u: GameUnit, name: String, n: Node3D, kind := "") -> Vector2:
	if n.has_meta(EIFigureGeometry.META):
		var g: Dictionary = n.get_meta(EIFigureGeometry.META)
		var maximum: Vector3 = g.max
		return Vector2(maximum.x, maximum.y)
	var key := "%d:%s:%d" % [u.get_instance_id(), name, n.get_instance_id()]
	if _ext.has(key):
		return _ext[key]
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", false, false):
		if mi.mesh == null:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var e: Vector2 = FALLBACK_EXT.get(kind if kind != "" else name, FALLBACK_EXT[""])
	if not first and box.size.x > 0.001 and box.size.z > 0.001:
		e = Vector2(box.size.x, box.size.z) * 0.5
	_ext[key] = e
	return e


## The hit-jitter radius takes max; the body-less pool takes
## min of the same extents (executed, despite its misleading
## ). Both use the raw unrotated FIG union.
func _unit_size(u: GameUnit, smaller := false) -> float:
	var b := ParticleFx.of(world)._box(u)
	return (minf(b.size.x, b.size.z) if smaller else maxf(b.size.x, b.size.z)) * 0.5


## Step frames (record.., frame + 1; 1 ends the list) of the walk
## and run clips (action 4 / 5) of a template's animation database, and the
## frame of the action-2 clips (flags, the shake frame).
func _clip_steps(tmpl: String) -> Dictionary:
	if _steps.has(tmpl):
		return _steps[tmpl]
	var out := {}
	if _dbres == null and GameData.root != "":
		_dbres = EIResArchive.open_path(GameData.root.path_join("res/database.res"))
	var b := _dbres.read(tmpl + ".adb") if _dbres else PackedByteArray()
	if b.size() >= 0x2c and b.slice(0, 3).get_string_from_ascii() == "ADB":
		for i in b.decode_u32(4):
			var p := 0x2c + i * 88
			if p + 88 > b.size():
				break
			var act := (b.decode_u32(p + 20) >> 18) & 15
			if act != 4 and act != 5 and act != 2:
				continue
			var steps := PackedInt32Array()
			for k in 4:
				steps.append(b.decode_s32(p + 0x30 + k * 4))
			out[b.slice(p, p + 16).get_string_from_ascii()] = {"act": act, "steps": steps, "hit": b.decode_u32(p + 0x40)}
	_steps[tmpl] = out
	return out
