class_name ParticleFx
extends Node3D
## The world's particle effects (the original CParticle list + CEffectParticle
## CEffectArrow, CEffectLightning and CEffectPointLight objects). One per
## GameWorld, on every peer: effects are visual only and are started from the
## same broadcast events everywhere (spellfx / castfx / magicfx / blood /
## fxcmd), so nothing here is replicated or feeds back into gameplay.
##
## Emitters run on the original 55 ms tick; each frame they are drawn with the
## previous -> current state interpolated, one MultiMesh (camera-facing quads,
## 4x4 atlas frames) per emitter.

const TICK := 0.055
const DRAW_DIST := 90.0
const EFFECT_SHADER := preload("res://src/game/fx/particle.gdshader")
## The world draw draws the land, the figures and
## the water first, then, with z writes off (D3D state 0xe = 0), the effects:
## world, the particle emitters (far to near) and the
## lightning bolts. Godot draws units (alpha-to-coverage) and
## foliage in its transparent pass too, sorted by their centres against the
## emitters' pivots, so a unit behind a camp fire could be drawn over its smoke.
## A higher material priority keeps every emitter after them; the emitters keep
## their far-to-near order among themselves (sorting_offset).
const RENDER_PRIORITY := 10
## CEffectParticle one-shot types: deleted 60 ticks after creation.
const ONE_SHOT := [0x2002, 0x2006, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x2018, 0x2019,
	0x201b, 0x201c, 0x201d, 0x201e, 0x201f, 0x2020, 0x2021, 0x2022, 0x2023, 0x2024, 0x2025, 0x2026,
	0x2030, 0x2031, 0x2032, 0x2033, 0x203f, 0x2040, 0x2041, 0x2042, 0x2043]
## Bone selector -> figure part.
const BONES := {1: "hd", 2: "hd", 3: "lh2", 4: "rh2", 5: "ll2", 6: "rl2", 7: "bd"}

## One CEffectParticle (or the particle part of a CEffectWall / CEffectArrow).
class Effect:
	var e: FxEmitter
	var created := 0
	var until := -1          # tick at which it is deleted (-1: until told)
	var move_step := Vector3.ZERO
	var move_ticks := 0
	var id := -1             # script id
	var deleted := false
	var mmi: MultiMeshInstance3D
	var buf := PackedFloat32Array()
	## Radius round wp (Godot space) of the particles last drawn; -1 = not drawn yet.
	var reach := -1.0
	var filled := -1         # tick of the buffer's state (-1: not filled)
	var filled_n := 0
	var stop_at := -1        # tick at which emission stops (tornado)
	var ok := true           # update()'s result this tick
	# A buffer filled on a worker during the tick (_fill_calc), applied by _draw.
	var cap := 0             # the MultiMesh's instance_count
	var pre := -1            # tick of the pending buffer (-1: none)
	var pre_k := 0
	var pre_aabb := AABB()
	var pre_reach := -1.0


var world: GameWorld
var types := FxTypes.new()
var wind := Vector3.ZERO     # the remake has no weather wind (stays 0)
var wind_s := 0.0
var tick := 0
var acc := 0.0
var effects: Array[Effect] = []
var bolts: Array = []        # FxLightning
var lights: Array = []       # {light: OmniLight3D, until, id, step, ticks, pos}
var missiles: Array = []     # CEffectArrow
var script_fx := {}          # script id -> Effect
var script_bolts := {}       # script id -> FxLightning
var script_lights := {}      # script id -> light dict
var _rng := RandomNumberGenerator.new()
var _mats := {}
var _quad: QuadMesh
var _bones := {}             # unit instance id -> {name: Node3D}
var _boxes := {}             # unit instance id -> [tick, AABB] (unit local, Godot space)
var _zone_set := false
## Zone exit stars: [Effect, GS var "z.<target>"] per exit (the original's list).
var _exit_fx: Array = []
## GS var reader (player 0) set by Game: key -> value.
var gs_var: Callable
## Particles drawn last frame (tools/fx_test.gd reports it).
var drawn := 0


static func of(w: GameWorld) -> ParticleFx:
	if w == null:
		return null
	var n := w.get_node_or_null("ParticleFx") as ParticleFx
	if n == null:
		n = ParticleFx.new()
		n.name = "ParticleFx"
		n.world = w
		w.add_child(n)
	return n


func _init() -> void:
	_rng.seed = 0x55aa1234
	_quad = QuadMesh.new()
	_quad.size = Vector2(2, 2)   # vertices at +-1: the shader scales by the particle size


func _ready() -> void:
	GameData.options_changed.connect(_apply_material_options)


# ------------------------------------------------------------------ helpers used by the emitters

func rnd() -> int:
	return _rng.randi()


func ground(x: float, y: float) -> float:
	return world.ground_at(x, y) if world else 0.0


static func ei(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


static func godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## A carrier taken off the world (a looted corpse kept out of the tree for
## WasLooted, GameWorld.looted) ends its effects as a freed one: the original's
##  purges the removed object's effects.
func carrier_valid(obj: Object) -> bool:
	return is_instance_valid(obj) and not (obj as Node).is_queued_for_deletion() and (obj as Node).is_inside_tree()


func _bone(u: GameUnit, name: String) -> Node3D:
	if u.model == null:
		return null
	var key := u.get_instance_id()
	var m: Dictionary = _bones.get(key, {})
	if not m.has(name):
		m[name] = u.model.find_child(name, true, false)
		_bones[key] = m
	var n = m[name]
	return n if is_instance_valid(n) else null


## Unit bounds in its own (Godot) space, from the figure's meshes.
func _box(u: GameUnit) -> AABB:
	var key := u.get_instance_id()
	# Re-measured now and then: a figure only settles after its first frames.
	if _boxes.has(key) and tick - int(_boxes[key][0]) < 20:
		return _boxes[key][1]
	var box := AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
	if u.model:
		var inv := u.global_transform.affine_inverse()
		var first := true
		for mi: MeshInstance3D in u.model.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree():
				continue   # skinned meshes keep their bind-pose bounds
			var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		# The skinned body: its joints, padded by 0.15 m.
		for sk: Skeleton3D in u.model.find_children("*", "Skeleton3D", true, false):
			var xf := inv * sk.global_transform
			for i in sk.get_bone_count():
				var q: Vector3 = xf * sk.get_bone_global_pose(i).origin
				var b := AABB(q - Vector3.ONE * 0.15, Vector3.ONE * 0.3)
				box = b if first else box.merge(b)
				first = false
	_boxes[key] = [tick, box]
	return box


## (height offset of the centre, radius = half the bbox diagonal).
func carrier_size(obj: Object) -> Vector2:
	if obj is GameUnit:
		var b := _box(obj)
		return Vector2(b.get_center().y, b.size.length() * 0.5)
	return Vector2(0.5, 0.5)


func carrier_height(obj: Object) -> float:
	if obj is GameUnit:
		return _box(obj).size.y
	return 1.0


## the carrier point in EI space.
func carrier_point(e: FxEmitter, obj: Object) -> Vector3:
	if obj is GameUnit:
		var u: GameUnit = obj
		if e.flags & FxEmitter.F_BONE:
			return unit_point(u, e.bone)
		return ei(u.global_position)
	if obj is Node3D:
		return ei((obj as Node3D).global_position)
	return e.ofs


## A unit point by bone selector: 0 the centre, 1..7 bones.
func unit_point(u: GameUnit, sel: int) -> Vector3:
	if sel == 0:
		var b := _box(u)
		return ei(u.global_position) + Vector3(0, 0, b.get_center().y)
	if sel >= 8:
		sel = 7
	var n := _bone(u, BONES.get(sel, "bd"))
	if n == null:
		n = _bone(u, "bd")
	var p: Vector3
	if n:
		p = ei(n.global_position)
	else:
		p = ei(u.global_position) + Vector3(0, 0, _box(u).size.y)
	if sel == 2:
		p.z += 1.0
	return p


func bone_point(u: GameUnit, name: String) -> Vector3:
	var n := _bone(u, name)
	return ei(n.global_position) if n else ei(u.global_position)


## Unit bone size: half the part's mesh extent (approx.).
func bone_size(u: GameUnit, sel: int) -> float:
	var n := _bone(u, BONES.get(sel, "bd"))
	if n == null:
		return 0.15
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", false, false):
		if mi.mesh:
			return clampf(mi.mesh.get_aabb().size.length() * 0.25, 0.05, 0.5)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return clampf((n as MeshInstance3D).mesh.get_aabb().size.length() * 0.25, 0.05, 0.5)
	return 0.15


func view_dir() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3(0, 0, 1)
	return ei(-cam.global_transform.basis.z).normalized()


# ------------------------------------------------------------------ creation

## CEffectParticle create: type at `at` (EI
## space; the offset when attached), size s -> (s).
## opt: k118, k11c, v130 (wall vector), prewarm (updates run now), secs.
func spawn(type: int, at: Vector3, size: float, carrier: Object = null, opt := {}) -> Effect:
	var e := FxTypes.create(self, type)
	if e == null or GameData.get_texture(e.texture) == null:
		return null
	e.scale(size / e.k128)
	if opt.has("k118"):
		e.k118 = float(opt.k118)
	if opt.has("k11c"):
		e.k11c = float(opt.k11c)
	if opt.has("k120"):
		e.k120 = float(opt.k120)
		e.k124 = float(opt.k124)
	if opt.has("v130"):
		e.v130 = opt.v130
	if opt.has("bone"):
		e.bone = int(opt.bone)
	e.ofs = at
	if carrier:
		e.attach(carrier)
		e.wp = carrier_point(e, carrier) + at
	else:
		e.wp = at
	var ef := Effect.new()
	ef.e = e
	ef.created = tick
	if type in ONE_SHOT:
		ef.until = tick + (120 if type == 0x2019 else 60)
	if opt.has("secs"):
		ef.until = tick + maxi(1, roundi(float(opt.secs) / TICK))
	effects.append(ef)
	for i in int(opt.get("prewarm", 0)):
		e.update()
	_ground_marks(type, e, size)
	return ef


## On creation (when is made; for the wall):
## scorch marks (x, y, a, b, angle, min(· 0.6, 1)) —
## FireBlast 0x2002 a = b = (k11c), random angle; LightningBlast 0x2030
## a = b = size, random angle, then the camera shake (pos, size
## 2, 0.25); FireWall 0x2010 a = |v| + size / 2 + 0.3, b = size / 2 + 0.3,
## angle atan2(v.y, v.x) with v the half-extent.
func _ground_marks(type: int, e: FxEmitter, size: float) -> void:
	if type != 0x2002 and type != 0x2030 and type != 0x2010:
		return
	var gm := GroundMarks.of(world)
	if gm == null:
		return
	var st := minf(e.k118 * 0.6, 1.0)
	var p := e.wp
	match type:
		0x2002:
			gm.add_scorch(p.x, p.y, e.k11c, e.k11c, gm.rand_angle(), st)
		0x2030:
			gm.add_scorch(p.x, p.y, size, size, gm.rand_angle(), st)
			CameraRig.shake_at(self, Vector2(p.x, p.y), size, 2.0, 0.25)
		0x2010:
			var v := Vector2(e.v130.x, e.v130.y)
			var h := size * 0.5 + 0.3
			gm.add_scorch(p.x, p.y, v.length() + h, h, atan2(v.y, v.x), st)


func delete(ef: Effect) -> void:
	if ef and not ef.deleted:
		ef.deleted = true
		ef.e.stop()


func add_light(at: Vector3, color: Color, radius: float, secs := -1.0, energy := 1.0, spell := false, kind := "") -> Dictionary:
	var l := OmniLight3D.new()
	if spell:   # spell lights carry flag 0x840: additive (Gfx.light_code)
		Gfx.mark_additive(l)
	l.light_color = color
	l.omni_range = maxf(absf(radius), 0.1)
	l.light_energy = energy
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = Gfx.torch_fog_energy()   # option gfx_torch_glow
	l.add_to_group(&"gfx_torch_glow")
	l.add_to_group(Gfx.POINT_LIGHT_GROUP)
	add_child(l)
	var halo := Gfx.torch_halo(absf(radius), color)
	l.add_child(halo)
	l.global_position = godot(at)
	var d := {"light": l, "until": -1 if secs < 0.0 else tick + roundi(secs / TICK), "pos": at,
		"step": Vector3.ZERO, "ticks": 0, "energy": energy, "age": 0,
		"duration_ticks": -1 if secs < 0.0 else maxi(1, roundi(secs / TICK)),
		"kind": kind if kind == "fire" else ("spell" if spell else ""), "halo": halo.material_override}
	# Only identified torches and spell lights enter the optional remake
	# lighting path. Script point lights keep the original max() behaviour.
	LocalLighting.prepare_particle(d)
	lights.append(d)
	return d


## A lightning strike's light (Weather / MenuScene
## WorldScript: CreatePointLight(1, mid, 80, 255, 255, 255), deleted three
## script ticks later). The original lights the land and figures through the
## max() model only, so the remake's extras for torches stay off: no halo and
## no volumetric mist (an 80 m white light lit the whole mist into a white
## veil on Forward+ that the Compatibility renderer, without mist, never
## showed). Remake safety: it also expires on its own `ticks` after creation,
## so a lost delete (zone change, a peer leaving mid-strike) cannot leave it on.
## Time of the last one (FlashLog context: a storm's lightning strike).
static var last_flash_light_msec := -1


func _flash_light(d: Dictionary, ticks: int) -> void:
	last_flash_light_msec = Time.get_ticks_msec()
	var l: OmniLight3D = d.light
	l.light_volumetric_fog_energy = 0.0
	l.remove_from_group(&"gfx_torch_glow")
	for c in l.get_children():
		c.queue_free()   # the torch halo
	d.erase("halo")
	d.until = tick + maxi(1, ticks)


func remove_light(d: Dictionary) -> void:
	if d.is_empty():
		return
	if is_instance_valid(d.get("light")):
		d.light.queue_free()
	lights.erase(d)


func add_bolt(a: Vector3, b: Vector3, param: float, secs := -1.0, from: Object = null, to: Object = null) -> FxLightning:
	var l := FxLightning.new(self, a, b, param)
	l.from = from
	l.to = to
	l.until = -1 if secs < 0.0 else tick + maxi(1, roundi(secs / TICK))
	bolts.append(l)
	add_child(l.node)
	return l


func remove_bolt(l: FxLightning) -> void:
	if l:
		bolts.erase(l)
		if is_instance_valid(l.node):
			l.node.queue_free()


# ------------------------------------------------------------------ tick

func _process(dt: float) -> void:
	acc += dt
	var n := 0
	while acc >= TICK and n < 8:
		acc -= TICK
		n += 1
	for k in n:
		_tick(k == n - 1)
	if acc >= TICK:
		acc = fmod(acc, TICK)
	_draw(acc / TICK)


## Remake (CPU): the emitters are independent, so the tick runs in three
## passes with the same result as the original's one loop: the bookkeeping and
## the carrier point on the main thread (update_pre), the particles of the
## `par` emitters on WorkerThreadPool (update_sim, each with its own random
## stream; on the frame's last tick also the instance buffer of each emitter
## drawn last frame, _fill_calc) while the main thread runs the others, then
## the removals in list order. MultiMeshes are only touched in _draw.
const PAR_MIN_PARTS := 400   # fewer particles in all: no worker round trip
var _par: Array[Effect] = []
var _fill_eye := Vector3.ZERO
var _fill_fwd := Vector3.ZERO
var _fill_cam := false
var _fill_on := false


func _tick(last := true) -> void:
	tick += 1
	exit_colours()
	for m in missiles.duplicate():
		_missile_tick(m)
	_par.clear()
	var serial: Array[Effect] = []
	var parts := 0
	for ef in effects:
		if not ef.deleted:
			if ef.until >= 0 and tick >= ef.until:
				delete(ef)
			elif is_instance_valid(ef.e.carrier) and ef.e.carrier is GameUnit and ef.e.carrier.dead \
					and ef.e.type not in ONE_SHOT:   # (a freed carrier is dropped in update())
				delete(ef)
		if ef.move_ticks > 0:
			ef.move_ticks -= 1
			ef.e.ofs += ef.move_step
		if ef.stop_at >= 0 and tick >= ef.stop_at:
			ef.stop_at = -1
			ef.e.stop()
		ef.ok = true
		ef.pre = -1
		if ef.e.update_pre():
			if ef.e.par:
				_par.append(ef)
				parts += ef.e.parts.size()
			else:
				serial.append(ef)
	_fill_on = last
	if last:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		_fill_cam = cam != null
		_fill_eye = ei(cam.global_position) if cam else Vector3.ZERO
		_fill_fwd = view_dir()
	if Portability.threads() and _par.size() > 1 and parts >= PAR_MIN_PARTS:
		var gid := WorkerThreadPool.add_group_task(_sim_job, _par.size(), -1, true, "ParticleFx")
		for ef in serial:
			ef.ok = ef.e.update_sim()
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		for ef in _par:
			_sim_job_ef(ef)
		for ef in serial:
			ef.ok = ef.e.update_sim()
	_par.clear()
	var i := 0
	while i < effects.size():
		var ef := effects[i]
		if ef.deleted and not ef.ok:
			effects.remove_at(i)
			if ef.mmi:
				ef.mmi.queue_free()
			for k in script_fx.keys():
				if script_fx[k] == ef:
					script_fx.erase(k)
			if ef.e.type == 0x200a:
				for k in _tornadoes.keys():
					if _tornadoes[k] == ef:
						_tornadoes.erase(k)
			continue
		i += 1
	for l: FxLightning in bolts.duplicate():
		if l.until >= 0 and tick >= l.until:
			remove_bolt(l)
		else:
			l.update_tick()
	for d: Dictionary in lights.duplicate():
		d.age += 1
		if d.ticks > 0:
			d.ticks -= 1
			d.pos += d.step
			d.light.global_position = godot(d.pos)
		if d.until >= 0 and tick >= d.until:
			remove_light(d)


# ------------------------------------------------------------------ drawing

## Remake: fire and magic emitters (with every additive one) glow with the
## bloom (gfx_bloom: their colour × GLOW_BOOST in the HDR buffer, the bloom
## threshold is 1). The 2000 renderer lights no particle (fixed vertex
## colours, SRCALPHA/INVSRCALPHA or SRCALPHA/ONE per emitter), and
## its blend flag does not tell smoke from self-lit sprites (the zone exit
## stars 2038 / 2051, the path dots, stun stars blend normally), so
## gfx_lit_particles tints only the matter types in LIT_TYPES (blood,
## poison clouds, stench) by the zone light; everything else keeps the
## original's full brightness. The tornado 0x200a already takes the sun
## colour in the original.
const GLOW_TYPES := [0x2000, 0x2001, 0x2002, 0x2003, 0x200b, 0x200c, 0x2010, 0x2011, 0x2012, 0x2015,
	0x2016, 0x2017, 0x2019, 0x2027, 0x2028, 0x2029, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2030,
	0x203d, 0x203e, 0x2041, 0x2042, 0x2043]
const LIT_TYPES := [0x200f, 0x2031, 0x2032, 0x2033, 0x2007, 0x2008, 0x2013]
const GLOW_BOOST := 1.35
const SOFT_DISTANCE := 0.6
## Remake option path_through (default on): the move path dots 0x2039 and the
## target marks 0x203a / 0x203b are drawn without the depth test, after the
## water, every particle and the lightning (RENDER_PRIORITY + 2), so they stay
## visible under water, overhangs and behind rocks; fragments the opaque scene
## covers (and dots under the water, FxTypes.under_water) keep THROUGH_ALPHA.
## Off: the original's depth tested drawing (see FxTypes.under_water).
const THROUGH_TYPES := [0x2039, 0x203a, 0x203b]
const THROUGH_ALPHA := 0.6


static func through_on() -> bool:
	return GameData.option("path_through") == 1


## The material of an emitter (by type, texture, blend and option path_through).
func _material_of(e: FxEmitter) -> ShaderMaterial:
	return _material(e.texture, e.add == 1, e.type in GLOW_TYPES, e.type in LIT_TYPES, e.type == 0x2001,
		e.type in THROUGH_TYPES and through_on())


func _material(tex: String, additive: bool, glow := false, lit := false, fire := false, through := false) -> ShaderMaterial:
	var key := tex + ("+" if additive else "") + ("*" if glow else "") + ("~" if lit and not additive else "") + ("#fire" if fire else "") + ("@through" if through else "")
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader(additive, through)
		m.render_priority = RENDER_PRIORITY + 2 if through else RENDER_PRIORITY
		m.set_shader_parameter("through_alpha", THROUGH_ALPHA if through else 0.0)
		m.set_meta("through", through)
		m.set_shader_parameter("tex", GameData.get_texture(tex))
		m.set_meta("glow", glow or additive)
		m.set_meta("lit", lit and not additive)
		m.set_meta("fire", fire)
		_mats[key] = m
	return _mats[key]


static var _shaders := {}


static func _shader(additive: bool, through := false) -> Shader:
	var key := int(additive) + 2 * int(through)
	if not _shaders.has(key):
		if not additive and not through:
			_shaders[key] = EFFECT_SHADER
		else:
			var s := Shader.new()
			s.code = EFFECT_SHADER.code
			if additive:
				s.code = s.code.replace("blend_mix", "blend_add")
			if through:
				s.code = s.code.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,")
			_shaders[key] = s
	return _shaders[key]


## One effect's particles, previous and current state (the shader lerps):
## per instance the 3x4 "transform" holds the previous centre, the current
## centre, the previous and current size and the previous colour (see
## particle.gdshader), COLOR the current colour, CUSTOM the atlas rect.
func _sim_job(i: int) -> void:
	_sim_job_ef(_par[i])


func _sim_job_ef(ef: Effect) -> void:
	ef.ok = ef.e.update_sim()
	# Drawn last frame: most likely drawn this one too.
	if _fill_on and ef.filled >= 0 and ef.mmi != null and not ef.e.parts.is_empty():
		_fill_calc(ef, _fill_cam, _fill_eye, _fill_fwd)


func _fill(ef: Effect, mm: MultiMesh) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_fill_calc(ef, cam != null, ei(cam.global_position) if cam else Vector3.ZERO, view_dir() if cam else Vector3.ZERO)
	_fill_apply(ef, mm)


func _fill_apply(ef: Effect, mm: MultiMesh) -> void:
	ef.filled = tick
	ef.filled_n = ef.e.parts.size()
	if mm.instance_count != ef.cap:
		mm.instance_count = ef.cap
	mm.buffer = ef.buf
	mm.visible_instance_count = ef.pre_k
	mm.custom_aabb = ef.pre_aabb
	if ef.pre_k > 0:
		ef.reach = ef.pre_reach
	ef.pre = -1


## The instance buffer of the emitter's particles (no Godot object touched:
## safe on a worker); _fill_apply hands it to the MultiMesh.
func _fill_calc(ef: Effect, has_cam: bool, eye: Vector3, fwd: Vector3) -> void:
	var e := ef.e
	var n := e.parts.size()
	if ef.cap < n:
		ef.cap = maxi(n, mini(e.d8, 64) if n <= 64 else n * 2)
		ef.buf.resize(ef.cap * 20)
		ef.buf.fill(0.0)
	var b := ef.buf
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var big := 0.0
	var k := 0
	for p: Array in _draw_order(e, has_cam, eye, fwd):
		var c0: int = int(p[0x17])
		var c1: int = int(p[0x16])
		var f: int = int(p[0x12]) & 15
		var col := k * 20
		# Godot space (x, z, -y).
		var gp0 := Vector3(p[4], p[6], -p[5])
		var gp1 := Vector3(p[0], p[2], -p[1])
		b[col] = gp0.x; b[col + 1] = gp0.y; b[col + 2] = gp0.z; b[col + 3] = gp1.x
		b[col + 4] = gp1.y; b[col + 5] = gp1.z; b[col + 6] = p[7]; b[col + 7] = p[3]
		b[col + 8] = ((c0 >> 16) & 255) / 255.0
		b[col + 9] = ((c0 >> 8) & 255) / 255.0
		b[col + 10] = (c0 & 255) / 255.0
		b[col + 11] = ((c0 >> 24) & 255) / 255.0
		b[col + 12] = ((c1 >> 16) & 255) / 255.0
		b[col + 13] = ((c1 >> 8) & 255) / 255.0
		b[col + 14] = (c1 & 255) / 255.0
		b[col + 15] = ((c1 >> 24) & 255) / 255.0
		# 4x4 atlas, frame 0 at the bottom left of the decoded image, 1/512 inset.
		var cx := f & 3
		var ry := f >> 2
		b[col + 16] = cx * 0.25 + 0.001953125
		b[col + 17] = 1.0 - ((ry + 1) * 0.25 - 0.001953125)
		b[col + 18] = (cx + 1) * 0.25 - 0.001953125
		b[col + 19] = 1.0 - (ry * 0.25 + 0.001953125)
		lo = lo.min(gp0).min(gp1)
		hi = hi.max(gp0).max(gp1)
		big = maxf(big, maxf(absf(p[3]), absf(p[7])) * SIZE_K)
		k += 1
	ef.buf = b
	ef.pre = tick
	ef.pre_k = k
	# An emitter between spawns has no particle (lo / hi stay ±INF): keep its
	# last box, a non-finite custom_aabb must never reach the renderer.
	var box := AABB(lo - Vector3.ONE * big, hi - lo + Vector3.ONE * big * 2.0)
	if k > 0 and box.position.is_finite() and box.size.is_finite():
		ef.pre_aabb = box
	elif not (ef.pre_aabb.position.is_finite() and ef.pre_aabb.size.is_finite()):
		ef.pre_aabb = AABB()
	if k > 0:
		var gw := godot(e.wp)
		var reach := maxf((lo - gw).abs().max((hi - gw).abs()).length() + big, 0.0)
		if is_finite(reach):
			ef.pre_reach = reach


## Quad half-extent per unit of particle size (particle.gdshader SIZE_K).
const SIZE_K := 1.1099162


##  draws an emitter's particles far to near: it sorts them
## their projected depth (merge passes / radix
## larger first). Only the blended emitters are sorted here; additive ones
## look the same in any order.
func _draw_order(e: FxEmitter, has_cam: bool, eye: Vector3, fwd: Vector3) -> Array:
	if e.add == 1 or e.parts.size() < 2:
		return e.parts
	if not has_cam:
		return e.parts
	var keys: Array[Vector2] = []
	keys.resize(e.parts.size())
	var i := 0
	for p: Array in e.parts:
		keys[i] = Vector2(-(Vector3(p[0], p[1], p[2]) - eye).dot(fwd), i)
		i += 1
	keys.sort()
	var out := []
	out.resize(keys.size())
	for j in keys.size():
		out[j] = e.parts[int(keys[j].y)]
	return out


## previous -> current lerp; the UV rect is the previous frame's.
func _draw(t: float) -> void:
	drawn = 0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := ei(cam.global_position) if cam else Vector3.ZERO
	# Out of view effects are not refilled either (a remake saving; filling
	# the quads of a few thousand particles each frame costs milliseconds).
	var planes: Array[Plane] = cam.get_frustum() if cam else [] as Array[Plane]
	for ef in effects:
		var e := ef.e
		var hidden: bool = is_instance_valid(e.carrier) and e.carrier is GameUnit \
			and (not e.carrier.visible or e.carrier.hidden)
		var unseen := false
		if cam and e.wp.distance_squared_to(eye) > DRAW_DIST * DRAW_DIST:
			unseen = true   # far off screen: not refilled (a remake saving)
		elif ef.reach >= 0.0 and not hidden:
			var gw := godot(e.wp)
			var r := ef.reach * 1.5 + 3.0
			for pl in planes:
				if pl.distance_to(gw) > r:
					unseen = true
					break
		# an emitter with particles counts the frames its box is
		# out of view (reset when in view); FxEmitter.update skips the
		# F_SKIP ones (0x2038) after 0x38 such frames. A hidden carrier's
		# emitter is not drawn at all (the count stays).
		if not e.parts.is_empty() and not hidden:
			e.e8 = e.e8 + 1 if unseen else 0
		hidden = hidden or unseen
		var n := e.parts.size()
		if ef.mmi == null:
			ef.mmi = MultiMeshInstance3D.new()
			ef.mmi.top_level = true
			ef.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ef.mmi.sorting_use_aabb_center = false
			ef.mmi.material_override = _material_of(e)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _quad
			ef.mmi.multimesh = mm
			add_child(ef.mmi)
		elif e.type in THROUGH_TYPES:
			var want := _material_of(e)   # option path_through switched meanwhile
			if ef.mmi.material_override != want:
				ef.mmi.material_override = want
		var mm := ef.mmi.multimesh
		if hidden or n == 0:
			mm.visible_instance_count = 0
			ef.filled = -1
			continue
		if ef.pre == tick:
			_fill_apply(ef, mm)
		elif ef.filled != tick or ef.filled_n != n:
			_fill(ef, mm)
		drawn += mm.visible_instance_count
		#  draws the emitters in order of the dot product of their
		# position with the camera direction, larger first (introsort
		# descending): far to near along the view axis. Godot
		# sorts transparent instances by their pivot's depth along the view
		# axis minus sorting_offset; the pivot is the top-level origin (0), so
		# this offset makes the depth fwd · (wp - eye) as in the original.
		if cam:
			var so := cam.global_basis.z.dot(godot(e.wp))
			if absf(so - ef.mmi.sorting_offset) > 0.01:
				ef.mmi.sorting_offset = so
	# The previous -> current lerp runs in the shader (lerp_t), so the
	# buffers are only refilled once per tick.
	for m: ShaderMaterial in _mats.values():
		m.set_shader_parameter("lerp_t", t)
	_apply_material_options()
	for l: FxLightning in bolts:
		l.draw(t)


func _apply_material_options() -> void:
	var soft := SOFT_DISTANCE if Gfx.on("gfx_soft_particles") else 0.0
	var tint := Gfx.particle_tint()
	var boost := GLOW_BOOST if Gfx.on("gfx_bloom") else 1.0
	for m: ShaderMaterial in _mats.values():
		m.set_shader_parameter("soft_distance", 0.0 if m.get_meta("through", false) else soft)
		if m.get_meta("glow", false):
			# The original campfire atlas already has a bright yellow core.
			# Extra HDR gain clips its painted detail into a flat yellow shape.
			var gain := 1.0 if m.get_meta("fire", false) and Gfx.on("gfx_firelight") else boost
			m.set_shader_parameter("boost", gain)
		else:
			var lt := tint if m.get_meta("lit", false) else Color.WHITE
			m.set_shader_parameter("light_tint", Vector3(lt.r, lt.g, lt.b))


# ------------------------------------------------------------------ game events

## Broadcast events handled here (Session._on_event, every peer).
const EVENTS := ["castfx", "magicfx", "blood", "fxcmd", "tornado"]


func on_event(ev: Dictionary) -> void:
	match String(ev.get("t", "")):
		"castfx": cast_fx(ev)
		"magicfx": magic_fx(ev)
		"blood": blood(ev)
		"fxcmd": script_cmd(String(ev.get("f", "")), Array(ev.get("a", [])))
		"tornado": tornado(ev)


## CEffectTornado's particle (client, update
## ): 0x200a, size 1, at the tornado (z 0: the control callback
## lifts the funnel to the ground), moved by its step every tick, emission
## stopped once life < 111 (0x6f) ticks, deleted when life runs out. A
## tornado already running when the event comes (a joiner's replay, the zone
## just started here) catches up min(gone, 30) − 1 updates; the remake does
## not know "gone" and takes the full 29 then.
var _tornadoes := {}   # id -> Effect


func tornado(ev: Dictionary) -> void:
	var id := int(ev.get("id", 0))
	var old: Effect = _tornadoes.get(id)
	if old:
		delete(old)
	var life := int(ev.get("life", 0))
	var ef := spawn(0x200a, Vector3(float(ev.x), float(ev.y), 0.0), 1.0, null,
		{"prewarm": 29 if tick < 5 else 0})
	if ef == null:
		return
	ef.move_step = Vector3(float(ev.vx), float(ev.vy), 0.0)
	ef.move_ticks = maxi(life, 0)
	ef.until = tick + maxi(life, 0) + 1
	ef.stop_at = tick + maxi(life - 0x6f, 0)
	_tornadoes[id] = ef

## s(e): clamp(effect / proto effect, 1, 8)^0.33 - 0.2.
static func strength(sp: Dictionary) -> float:
	var base := float(sp.proto.get("effect", 0.0))
	var r := float(sp.effect) / base if base > 0.0 else 1.0
	return pow(clampf(r, 1.0, 8.0), 0.33) - 0.2


func _unit(uid) -> GameUnit:
	if world == null or uid == null:
		return null
	var u = world.units.get(int(uid))
	return u if is_instance_valid(u) else null


func _ground_pt(x: float, y: float, dz := 0.0) -> Vector3:
	return Vector3(x, y, ground(x, y) + dz)


## Spell cast visuals, (event "spellfx": code, x, y, a = caster
## uid, tu = target uid, spell = the full spell id).
func spell_cast(ev: Dictionary) -> void:
	var sp := Spells.parse(String(ev.get("spell", ev.get("code", ""))))
	var code := String(sp.code)
	var s := strength(sp)
	var caster := _unit(ev.get("a"))
	var target := _unit(ev.get("tu"))
	var at := Vector2(float(ev.get("x", 0.0)), float(ev.get("y", 0.0)))
	var gp := _ground_pt(at.x, at.y)
	var ticks := float(sp.duration)
	# A lasting spell replayed for a co-op client that loaded the zone later
	# (Session._send_world_state): only the time it has left, and the wall's
	# direction as it was cast (remake-only).
	var left := float(ev.get("left", -1.0))
	var cast_dir := Vector2(float(ev.get("dx", 0.0)), float(ev.get("dy", 0.0)))
	if left > 0.0:
		ticks = left / TICK
	# A cast without a caster (script CastSpellPoint / CastSpellUnit, magic
	# traps: with caster 0) starts at its source point "fx", "fy".
	var src := Vector3.ZERO
	var has_src := caster != null or ev.has("fx")
	if caster:
		src = unit_point(caster, 0)
	elif has_src:
		src = _ground_pt(float(ev.fx), float(ev.fy), 1.0)
	match code:
		"arrow", "rick_magic", "acid_ray":
			if has_src:
				_missile(code, src, target, gp + Vector3(0, 0, 1), s, sp)
		"lightning", "curse_magic":
			if has_src:
				var b := unit_point(target, 0) if target else gp + Vector3(0, 0, 1)
				add_bolt(src, b, s * 5.0, maxf(ticks, 10.0) * TICK, caster, target)
		"fireball":
			if has_src:
				_fireball(ei(caster.global_position) if caster else src, gp, s, sp)
		"inv_lit":
			var top := Vector3(at.x, at.y, gp.z - 3.0 + 30.0)
			var bot := Vector3(at.x, at.y, gp.z - 3.0)
			add_bolt(top, bot, -7.0 * s, 5 * TICK)
			var tw := get_tree().create_timer(5 * TICK, false)
			tw.timeout.connect(func(): if is_instance_valid(self): add_bolt(top, bot, -7.0 * s, 5 * TICK))
			spawn(0x2030, gp, maxf(float(sp.radius), 0.5), null, {"k118": s})
		"acid_column":
			spawn(0x200c, gp, 1.0)
		"firewall":
			var dir := Vector2(1, 0)
			if cast_dir != Vector2.ZERO:
				dir = cast_dir
			elif caster:
				dir = (at - caster.pos).normalized() if at.distance_to(caster.pos) > 0.01 else Vector2.from_angle(caster.facing)
			elif has_src and at.distance_to(Vector2(src.x, src.y)) > 0.01:
				dir = (at - Vector2(src.x, src.y)).normalized()
			var half := Vector3(-dir.y, dir.x, 0.0) * maxf(float(sp.radius), 0.5)
			spawn(0x2010, gp, s, null, {"k118": s, "v130": half, "secs": maxf(ticks, 1.0) * TICK})
		"litnwall":
			var dir2 := Vector2(1, 0)
			if cast_dir != Vector2.ZERO:
				dir2 = cast_dir
			elif caster:
				dir2 = (at - caster.pos).normalized() if at.distance_to(caster.pos) > 0.01 else Vector2.from_angle(caster.facing)
			elif has_src and at.distance_to(Vector2(src.x, src.y)) > 0.01:
				dir2 = (at - Vector2(src.x, src.y)).normalized()
			var h := Vector3(-dir2.y, dir2.x, 0.0) * maxf(float(sp.radius), 0.5)
			var a2 := gp + h
			var b2 := gp - h
			a2.z = ground(a2.x, a2.y) + 1.0
			b2.z = ground(b2.x, b2.y) + 1.0
			add_bolt(a2, b2, 0.0, maxf(ticks, 10.0) * TICK)
		"acid_fog":
			spawn(0x2007, gp, maxf(float(sp.radius), 1.0), null, {"k118": s, "secs": maxf(ticks, 1.0) * TICK})
		"fireworks":
			spawn(0x2009, gp, s, null, {"secs": maxf(ticks, 1.0) * TICK})
		"clairvoyence":
			var r := maxf(float(sp.radius), 1.0)
			spawn(0x2018, gp, r)
			var tm := get_tree().create_timer(maxf(ticks - 10.0, 0.0) * TICK, false)
			tm.timeout.connect(func(): if is_instance_valid(self): spawn(0x2018, gp, -r))
		"healing":
			for u in _victims(sp, target, at):
				spawn(0x2006, Vector3.ZERO, s, u)
		"link":
			if caster and target:
				var a3 := unit_point(caster, 0)
				spawn(0x2014, a3, s, null, {"v130": unit_point(target, 0) - a3, "secs": maxf(ticks, 10.0) * TICK})
		"teleport":
			if caster:
				var cp := ei(caster.global_position)
				spawn(0x2019, cp + Vector3(0, 0, carrier_height(caster)), 1.0)
			spawn(0x2019, gp - Vector3(0, 0, 0.2), -1.0)


## The units a spell lands on (the same choice as Spells.apply, for visuals).
func _victims(sp: Dictionary, target: GameUnit, at: Vector2) -> Array:
	if float(sp.radius) > 0.2 and world:
		return world.units_near(at, float(sp.radius)).filter(func(u): return not u.dead)
	return [target] if target else []


## the fireball flies level (ground + 1) toward the point
## range x 0.0667 m per tick, then FireBlast. No homing: case 3
## fixes the velocity and the tick count (= round(d / range × 15) − 2)
## toward, the target's position at the cast, and the
## blast (case 3) is at that point.
func _fireball(from: Vector3, to: Vector3, s: float, sp: Dictionary) -> void:
	var rng := maxf(float(sp.range), 1.0)
	var d := Vector2(to.x - from.x, to.y - from.y)
	var n := maxi(1, roundi(d.length() / rng * 15.0) - 2)
	var ef := spawn(0x2000, Vector3(from.x, from.y, ground(from.x, from.y) + 1.0), s * 0.3)
	if ef == null:
		return
	ef.move_ticks = n
	var step := d / float(n)
	ef.move_step = Vector3(step.x, step.y, 0.0)
	var r := float(sp.radius)
	var sa := s
	if r > 0.0:
		var pa := float(sp.proto.get("area", 0.0))
		var ratio := (r * r * PI) / pa if pa > 0.0 else 1.0
		sa = pow(clampf(ratio, 1.0, 8.0), 0.33) - 0.2
	var sz := minf(s, sa)
	var lc := _spell_light(sp)
	var light := add_light(Vector3(from.x, from.y, ground(from.x, from.y) + 1.0), lc.color, lc.radius, n * TICK, lc.energy, true) if lc.radius > 0.0 else {}
	if not light.is_empty():
		light.step = ef.move_step
		light.ticks = n
	get_tree().create_timer(n * TICK, false).timeout.connect(func():
		if not is_instance_valid(self):
			return
		delete(ef)
		var hit := _ground_pt(to.x, to.y, 1.0)
		spawn(0x2002, hit, sz)
		_hit_light(hit, sp))


func _spell_light(sp: Dictionary) -> Dictionary:
	var pr: Dictionary = sp.proto
	var c := Color(float(pr.get("red", 0.0)), float(pr.get("green", 0.0)), float(pr.get("blue", 0.0)))
	var m := maxf(c.r, maxf(c.g, c.b))
	if m <= 0.0:
		return {"radius": 0.0, "color": Color.BLACK, "energy": 0.0}
	# As: the row's colour and radius as they are.
	return {"radius": float(pr.get("light_radius", 1.0)), "color": c, "energy": 1.0}


## the hit of Firearrow (case 0), Acidray (2) and Fireball (3):
## the travelling light is replaced by a new light at the hit
## point with the row's colour and light_radius × 1.5. The hit sets
##  = 0x23 and state 2; (cases 0 / 2 / 3) counts it down
## each tick and sets state 3 once it passes 0 (36 ticks), and the next
## update (state 3) releases the particles and the light
##  with the effect: the light lives 37 ticks.
func _hit_light(at: Vector3, sp: Dictionary) -> void:
	var lc := _spell_light(sp)
	if lc.radius > 0.0:
		add_light(at, lc.color, lc.radius * 1.5, 37 * TICK, lc.energy, true)


## CEffectArrow: a spell missile homing on the
## target at 0.6667 m per tick, carrying its particle type and the spell light.
func _missile(code: String, start: Vector3, target: GameUnit, point: Vector3, s: float, sp: Dictionary) -> void:
	var type: int = {"arrow": 0x2011, "rick_magic": 0x204e, "acid_ray": 0x2012}[code]
	var size := s * 0.4 if code == "acid_ray" else s
	var ef := spawn(type, start, size)
	if ef == null:
		return
	var lc := _spell_light(sp)
	var m := {"ef": ef, "pos": start, "target": target, "point": point, "s": s, "code": code, "ticks": 0, "sp": sp,
		"light": add_light(start, lc.color, lc.radius, -1.0, lc.energy, true) if lc.radius > 0.0 else {}}
	missiles.append(m)


func _missile_tick(m: Dictionary) -> void:
	var t: GameUnit = m.target if is_instance_valid(m.target) else null
	var dest: Vector3 = m.point
	if t:
		dest = ei(t.global_position) + Vector3(0, 0, carrier_height(t) * 0.5)
	var pos: Vector3 = m.pos
	var d := dest - pos
	m.ticks += 1
	var arrived: bool = Vector2(d.x, d.y).length() < 0.6667 or m.ticks > 400
	if not arrived:
		pos += d.normalized() * 0.6667
		pos.z = maxf(pos.z, ground(pos.x, pos.y) + 1.0)
	else:
		pos = dest
	m.pos = pos
	var ef: Effect = m.ef
	ef.e.ofs = pos
	if not m.light.is_empty():
		m.light.pos = pos
		m.light.light.global_position = godot(pos)
	if arrived:
		missiles.erase(m)
		delete(ef)
		remove_light(m.light)
		# the hit star on the target unit.
		var star := 0x2042 if m.code == "acid_ray" else 0x2041
		if t:
			spawn(star, Vector3.ZERO, float(m.s) * 0.7, t)
		else:
			spawn(star, dest, float(m.s) * 0.7)
		if m.code != "rick_magic":
			_hit_light(dest, m.sp)


## Casting effect by school, event "castfx": uid, school.
const CAST_TYPES := {"fire": 0x2027, "lightning": 0x2028, "acid": 0x2029, "illusion": 0x202b,
	"divination": 0x202a, "enchantments": 0x202d, "enchantment": 0x202d, "healing": 0x202e, "domination": 0x202c}


func cast_fx(ev: Dictionary) -> void:
	var u := _unit(ev.get("uid"))
	if u == null:
		return
	var sp := Spells.parse(String(ev.get("spell", "")))
	var school := String(sp.proto.get("school", sp.get("subtype", ""))).to_lower()
	var type: int = CAST_TYPES.get(school, 0x200b)
	var ef := spawn(type, Vector3.ZERO, 1.0, u)
	if ef:
		ef.until = tick + maxi(4, roundi(float(ev.get("secs", 1.0)) / TICK))


## Magic effect on a unit, event "magicfx": uid, code, secs, s.
const MAGIC_TYPES := {"prot_fire": 0x2017, "prot_electro": 0x2016, "prot_acid": 0x2015,
	"eagle_sight": 0x2044, "infravision": 0x2045, "detect_life": 0x2046, "silence": 0x204c,
	"stench": 0x2013, "antimagic": 0x201a, "regeneration": 0x2048, "feeblemind": 0x2049,
	"speed": 0x204b, "slow": 0x204a}


func magic_fx(ev: Dictionary) -> void:
	var u := _unit(ev.get("uid"))
	if u == null:
		return
	var code := String(ev.get("code", ""))
	var k := float(ev.get("s", 1.0))
	var secs := float(ev.get("secs", 10.0))
	# Already running (a loaded save, or a co-op joiner's replay):
	# with its load flag gives the lasting emitter 30 prewarm updates and
	# skips the one-shot start bursts (lichdom, strength, weakness).
	var replay := bool(ev.get("replay", false))
	var old: Dictionary = u.get_meta("fx_magic", {})
	if old.has(code) and old[code] is Effect:
		delete(old[code])
	match code:
		"invisibility":
			# Remake-only: the original draws an invisible unit as usual (
			# flag only matters to game mode 3), so a
			# player's own invisible units get a faint translucent shimmer.
			if u.controller >= 0:
				_shimmer(u, secs)
		"lichdom":
			if not replay:
				spawn(0x2018, Vector3.ZERO, k, u)
			var ur: WeakRef = weakref(u)
			_later(secs, func(): _spawn_on(ur, 0x2018, -k))
		"strength", "weak":
			var sg := 1.0 if code == "strength" else -1.0
			if not replay:
				spawn(0x201b, Vector3.ZERO, k * sg, u)
			var ur: WeakRef = weakref(u)
			_later(secs, func(): _spawn_on(ur, 0x201b, -k * sg))
		_:
			if MAGIC_TYPES.has(code):
				old[code] = spawn(MAGIC_TYPES[code], Vector3.ZERO, k, u, {"secs": secs, "prewarm": 30 if replay else 0})
				u.set_meta("fx_magic", old)


## Remake extra: the unit's meshes pulse between 35 and 55 % transparency for
## `secs` (GeometryInstance3D.transparency; the materials are left alone).
func _shimmer(u: GameUnit, secs: float) -> void:
	var old: Tween = u.get_meta("fx_shimmer") if u.has_meta("fx_shimmer") else null
	if old and old.is_valid():
		old.kill()
	var geos: Array = u.find_children("*", "GeometryInstance3D", true, false)
	var set_t := func(v: float) -> void:
		for g in geos:
			if is_instance_valid(g):
				g.transparency = v
	var tw := u.create_tween().set_loops(maxi(1, ceili(secs / 1.6)))
	tw.tween_method(set_t, 0.35, 0.55, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_method(set_t, 0.55, 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	tw.finished.connect(func():
		for g in geos:
			if is_instance_valid(g):
				g.transparency = 0.0)
	u.set_meta("fx_shimmer", tw)
	var ur: WeakRef = weakref(u)
	_later(secs, func():
		var u2 = ur.get_ref()
		if u2 and u2.get_meta("fx_shimmer", null) == tw:
			tw.kill()
			for g in geos:
				if is_instance_valid(g):
					g.transparency = 0.0
			u2.remove_meta("fx_shimmer"))


## A unit's effect end (held weakly: the unit may leave the world first).
func _spawn_on(ur: WeakRef, type: int, k: float) -> void:
	var u = ur.get_ref()
	if u and u.is_inside_tree():
		spawn(type, Vector3.ZERO, k, u)


func _later(secs: float, f: Callable) -> void:
	get_tree().create_timer(secs, false).timeout.connect(func(): if is_instance_valid(self): f.call())


## Body-part hit, event "blood": uid, part, frac.
const PART_BONES := [1, 7, 3, 4, 5, 6]
const BLOOD_TYPES := {1: 0x200f, 5: 0x200f, 2: 0x2031, 6: 0x2031, 3: 0x2032, 7: 0x2032, 4: 0x2033, 8: 0x2033}


func blood(ev: Dictionary) -> void:
	var u := _unit(ev.get("uid"))
	if u == null:
		return
	var type: int = BLOOD_TYPES.get(int(u.race.get("blood_type", 1)), 0)
	if type == 0:
		return
	var sel: int = PART_BONES[clampi(int(ev.get("part", 1)), 0, 5)]
	spawn(type, Vector3(0, 0, 0.1), bone_size(u, sel) * 2.5, u,
		{"bone": sel, "k11c": 1.0 / 30.0, "k118": clampf(float(ev.get("frac", 0.1)), 0.1, 1.0)})


## Zone exits and torches, set
## up when a zone's world is attached (every peer).
func setup_zone() -> void:
	# Once per world: Game.attach_world runs again after the parties are
	# deployed, which used to start every torch and exit effect twice.
	if world == null or _zone_set:
		return
	_zone_set = true
	for n in world.zone.get("exits", {}):
		var ex: Dictionary = world.zone.exits[n]
		if not ex.has("remove") or String(ex.get("to", "none")) == "none":
			continue
		var r: Rect2 = ex.remove
		var c := r.get_center()
		var ef := spawn(0x2038, _ground_pt(c.x, c.y), 1.0, null,
			{"k118": r.size.x * 0.5, "k11c": r.size.y * 0.5, "k120": 1.0, "k124": 0.0, "prewarm": 20})
		if ef:
			_exit_fx.append([ef, "z." + String(ex.to).to_lower()])
	exit_colours()   #  ends, after the prewarm
	for node in world.objects.values():
		if not is_instance_valid(node) or not node.has_meta("ei"):
			continue
		var o: Dictionary = node.get_meta("ei")
		if String(o.get("kind", "")) != "TORCH" or not o.has("torch_strength"):
			continue
		var s := float(o.torch_strength)
		var p: Vector3 = o.get("position", Vector3.ZERO)
		var off: Vector3 = o.get("torch_offset", Vector3.ZERO)
		var at := Vector3(p.x, p.y, ground(p.x, p.y) + p.z) + off
		#  (TORCH record): particle 0x2001 of the fire size and a
		# light at the fire, colour (0.8, 0.8, 0.8), radius = size × 10.
		spawn(0x2001, at, s)
		add_light(at, Color(0.8, 0.8, 0.8), s * 10.0, -1.0, 1.0, false, "fire")
		var haze := Gfx.heat_haze(0.6 + s * 0.8)   # remake-only, option gfx_heat_haze
		haze.position = godot(at) + Vector3(0.0, 0.3, 0.0)
		add_child(haze)


##  (and every drawn frame through
## ): each exit's emitter = 1.0 when GS var "z.<target>"
## (prefix) is 1, else 0; the spawn then colours new stars
##  instead of white (a closed exit: the leave box and the move
## cursor skip it too). Stars already alive keep their colour.
func exit_colours() -> void:
	if not gs_var.is_valid():
		return
	for x in _exit_fx:
		var ef: Effect = x[0]
		ef.e.v130 = Vector3(1.0 if float(gs_var.call(x[1])) == 1.0 else 0.0, 0.0, 0.0)


## Script builtins (event "fxcmd": f, a), vm.gd and neighbours.
func script_cmd(f: String, a: Array) -> void:
	match f:
		"CreateParticleSource":   # (id, x, y, z, size, "Name")
			if a.size() < 6:
				return
			var type: int = FxTypes.NAMES.get(String(a[5]).to_lower(), 0)
			if type == 0:
				return
			var id := int(a[0])
			if script_fx.has(id):
				delete(script_fx[id])
			var ef := spawn(type, Vector3(float(a[1]), float(a[2]), float(a[3])), float(a[4]))
			if ef:
				ef.id = id
				ef.until = -1
				script_fx[id] = ef
		"SetParticleSourceSize":   # (id, size)
			var ef: Effect = script_fx.get(int(a[0]))
			if ef and a.size() > 1:
				ef.e.scale(float(a[1]) / ef.e.k128)   # (size)
		"MoveParticleSource":   # (id, x, y, z, ticks, flag): delta = (target - pos) / ticks
			var ef: Effect = script_fx.get(int(a[0]))
			if ef and a.size() > 4:
				var n := maxi(1, int(a[4]))
				ef.move_ticks = n
				ef.move_step = (Vector3(float(a[1]), float(a[2]), float(a[3])) - ef.e.ofs) / float(n)
		"DeleteParticleSource":
			var ef: Effect = script_fx.get(int(a[0]))
			if ef:
				delete(ef)
				script_fx.erase(int(a[0]))
		"AttachParticles", "AttachParticleSource":   # (id, object)
			var ef: Effect = script_fx.get(int(a[0]))
			if ef and a.size() > 1:
				var obj := _object(a[1])
				if obj:
					ef.e.ofs = Vector3.ZERO
					ef.e.attach(obj)
					ef.e.flags |= FxEmitter.F_CARRIER
		"CreatePointLight":   # (id, x, y, z, radius, r, g, b[, flash ticks])
			if a.size() < 8:
				return
			var id := int(a[0])
			remove_light(script_lights.get(id, {}))
			var d := add_light(Vector3(float(a[1]), float(a[2]), float(a[3])),
				Color(float(a[5]) / 255.0, float(a[6]) / 255.0, float(a[7]) / 255.0), float(a[4]))
			script_lights[id] = d
			if a.size() > 8:
				_flash_light(d, int(a[8]))
		"MovePointLight":
			var d: Dictionary = script_lights.get(int(a[0]), {})
			if not d.is_empty() and a.size() > 3:
				d.pos = Vector3(float(a[1]), float(a[2]), float(a[3]))
				d.light.global_position = godot(d.pos)
		"DeletePointLight":
			remove_light(script_lights.get(int(a[0]), {}))
			script_lights.erase(int(a[0]))
		"CreateLightning":   # (id, x1, y1, z1, x2, y2, z2, param) or with objects
			if a.size() < 8:
				return
			var id := int(a[0])
			remove_bolt(script_bolts.get(id))
			script_bolts[id] = add_bolt(Vector3(float(a[1]), float(a[2]), float(a[3])),
				Vector3(float(a[4]), float(a[5]), float(a[6])), float(a[7]))
		"DeleteLightning":
			remove_bolt(script_bolts.get(int(a[0])))
			script_bolts.erase(int(a[0]))


func _object(id) -> Node3D:
	if world == null:
		return null
	var u = world.units.get(int(id))
	if is_instance_valid(u):
		return u
	var o = world.objects.get(int(id))
	return o if is_instance_valid(o) else null
