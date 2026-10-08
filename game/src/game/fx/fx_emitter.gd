class_name FxEmitter
extends RefCounted
## One particle emitter: the original CParticle (0x1f0 bytes).
## Created by FxTypes.create (Create), updated once per 55 ms logic
## tick by update, drawn by ParticleFx with the previous
## current state interpolated. All positions are in EI space
## (x, y, z up). has the field map.
##
## A particle is an Array laid out like the original's 100-byte record, index =
## byte offset / 4, so the per-type callbacks port one to one:
##   [0..2] position, [3] size, [4..6] previous position, [7] previous size,
##   [8..10] velocity, [0xb..0x10] auxiliary, [0x11] frame, [0x12] previous
##   frame, [0x13] frame timer, [0x14] life, [0x15] flag / index,
##   [0x16] ARGB colour, [0x17] previous colour, [0x18] dead.
## A control point is an Array of 14 values (0x38 bytes): [0..2] position,
## [3..5], [6..8] vectors, [9..0xb] floats, [0xc], [0xd].

const F_EMIT := 1        # emitting
const F_CARRIER := 2     # spawns only while it has a carrier
const F_KEEP := 4        # stays alive without particles
const F_BONE := 0x10     # carrier point from a unit bone
const F_SKIP := 0x20     # not updated while unseen for a while
const F_HIDDEN := 0x40
const WHITE := 0xffffffff

var fx: ParticleFx         # owner (rng, terrain, units)
var flags := F_EMIT
var type := 0              #  (0x2000..0x2052)
var ofs := Vector3.ZERO    #  offset from the carrier / position
var carrier: Object = null #  GameUnit or Node3D
var wp := Vector3.ZERO     #  world position this tick
var dl := Vector3.ZERO     #  motion this tick
var sd := Vector3.ZERO     #  unit vector perpendicular to dl (side)
var upv := Vector3.ZERO    #  unit vector perpendicular to dl and sd
var moved := 0.0
var cc := 0                #  spawn chance %
var d0 := 0                #  minimum spawn attempts per tick
var d4 := 1000.0           #  distance moved per extra attempt
var d8 := 500              #  maximum live particles
var dc := 16               #  frame count
var e0 := 4                #  atlas grid
var e4 := 10000            #  ticks per frame (some types: other data)
var e8 := 0                #  ticks unseen
var ec := -1               #  particle life (some types: other data)
var vmin := Vector3.ZERO
var vmax := Vector3.ZERO
var s := 1.0               #  size
var a110 := 0.0
var m114 := 0.0
var k118 := 1.0
var k11c := 1.0
var k120 := 0.0
var k124 := 0.0
var k128 := 1.0            #  scale reference
var c12c := 0              #  counter
var v130 := Vector3.ZERO   #  auxiliary vector
var bone := 0
var wind := Vector3.ZERO
var wind_s := 0.0
var add := 0               #  1 = additive
var cp: Array = []         #  control points
var parts: Array = []      #  live particles
var texture := ""
var spawn_fn: Callable     #  spawn(p, idx) -> bool
var upd_fn: Callable       #  update(p) -> bool
var ctl_fn: Callable       #  per control point
var alive := true
## Remake: the emitter's own random stream, seeded from ParticleFx's at
## creation (the original draws every emitter from the one CRT rand); with it
## the particles of one emitter can be simulated on a worker thread.
var rng := RandomNumberGenerator.new()
## Remake: the callbacks touch nothing outside the emitter but the ground
## snapshot, so update_sim may run on a worker (FxTypes.SERIAL lists those
## that read units, bones, the camera, the nav grid or the options; they
## stay on the main thread).
var par := true
## Remake, the data update_sim may read besides its own, set by update_pre
## on the main thread: the tick's ground (FxGround, plain arrays) and
## whether the carrier is there (the callbacks test it instead of the node).
var ground_src: FxGround
var has_carrier := false
## Remake: camera shakes a callback asked for ([at, p2, amp, decay], EI
## metres); ParticleFx starts them on the main thread after the tick.
var shakes: Array = []
var _fire_kernel: RefCounted
var _fire_spawn: Callable
var _fire_update: Callable
var _spell_kernel: RefCounted
var _spell_spawn: Callable
var _spell_update: Callable
var _spell_control: Callable


func prepare_spell_batch() -> void:
	if ClassDB.class_exists("SpellParticleKernel") and not OS.get_cmdline_user_args().has("--ei-script-spell-particles"):
		_spell_kernel = ClassDB.instantiate("SpellParticleKernel")
		# An older helper still supports modifiers/orbits. Tornadoes keep the
		# script fallback until a helper advertises this additional batch.
		if type == 0x200a and (not _spell_kernel.has_method("supports_type") or not _spell_kernel.supports_type(type)):
			_spell_kernel = null
			return
		_spell_spawn = spawn_fn
		_spell_update = upd_fn
		_spell_control = ctl_fn


func prepare_fire_batch() -> void:
	if ClassDB.class_exists("FireParticleKernel") and not OS.get_cmdline_user_args().has("--ei-script-fire"):
		_fire_kernel = ClassDB.instantiate("FireParticleKernel")
		_fire_spawn = spawn_fn
		_fire_update = upd_fn


func rnd() -> int:
	return rng.randi()


static func new_particle() -> Array:
	var p := []
	p.resize(25)
	p.fill(0)
	p[0] = 0.0
	p[1] = 0.0
	p[2] = 0.0
	p[3] = 0.0
	for i in range(8, 0x11):
		p[i] = 0.0
	p[0x16] = WHITE
	return p


static func new_control() -> Array:
	var c := []
	c.resize(14)
	c.fill(0.0)
	c[0xc] = 0
	c[0xd] = 0
	return c


func set_controls(n: int) -> void:
	cp.clear()
	for i in n:
		cp.append(new_control())


## size-like fields times k (every creator passes size).
func scale(k: float) -> void:
	vmin *= k
	vmax *= k
	s *= k
	k128 *= k
	a110 *= k
	d4 *= k


## attach to a carrier (null detaches).
func attach(obj: Object) -> void:
	if obj == null and carrier != null:
		ofs = wp   # released where it is (the effect object keeps its position)
	carrier = obj
	has_carrier = obj != null


## The ground height (EI z) at x, y: the tick's snapshot (worker safe).
func ground(x: float, y: float) -> float:
	return ground_src.at(x, y) if ground_src else 0.0


## stop emitting; the emitter goes when its particles are gone.
func stop() -> void:
	flags &= ~(F_EMIT | F_KEEP)


func live() -> int:
	return parts.size()


## . Returns false when the emitter is finished.
func update() -> bool:
	if not update_pre():
		return true
	return update_sim()


## first part (main thread: reads the carrier): false = the
## emitter is skipped this tick (unseen F_SKIP).
func update_pre() -> bool:
	if e8 > 0x38 and (flags & F_SKIP):
		return false
	wind = fx.wind
	wind_s = fx.wind_s
	ground_src = fx.ground_snapshot()
	if carrier != null and not fx.carrier_valid(carrier):
		carrier = null
	has_carrier = carrier != null
	var np: Vector3
	if carrier == null:
		np = ofs
	else:
		np = fx.carrier_point(self, carrier) + ofs
	dl = np - wp
	wp = np
	moved = dl.length()
	if moved <= 0.001:
		sd = Vector3.ZERO
		upv = Vector3.ZERO
	else:
		sd = Vector3(dl.y, -dl.x, 0.0)
		if sd.length() < 1e-10:
			sd = Vector3(dl.y - dl.z, -dl.x, dl.x)
		sd = sd.normalized()
		upv = dl.cross(sd).normalized()
	return true


## the rest: control points, particles, spawning. Touches only
## this emitter (and its ground snapshot) when `par`, no node or other
## object; returns false when the emitter is finished.
func update_sim() -> bool:
	if _fire_kernel and spawn_fn == _fire_spawn and upd_fn == _fire_update and not ctl_fn.is_valid():
		return _fire_kernel.step(self)
	# The first spawn reads the carrier's bounds/height and sometimes the
	# camera. Keep that setup on its original script path; subsequent ticks
	# contain only emitter-owned data, including the same random stream.
	if _spell_kernel and spawn_fn == _spell_spawn and upd_fn == _spell_update and ctl_fn == _spell_control \
		and not cp.is_empty() and (type < 0x202b or (ec > 0 and cp.size() >= ec)):
		if type == 0x200a:
			# The funnel samples the tick's immutable ground snapshot. Keep
			# that control update once per emitter; batch all particle work.
			for c in cp: ctl_fn.call(self, c)
		return _spell_kernel.step(self)
	return update_sim_script()


## Independent original update and callback path, also used by custom emitters.
func update_sim_script() -> bool:
	if ctl_fn.is_valid():
		for c in cp:
			ctl_fn.call(self, c)
	# Particles that died last tick are removed now; the others keep their
	# previous state for interpolation, then update (0 = dies, restored).
	var i := 0
	while i < parts.size():
		var p: Array = parts[i]
		if p[0x18]:
			parts.remove_at(i)
			continue
		p[4] = p[0]
		p[5] = p[1]
		p[6] = p[2]
		p[0x17] = p[0x16]
		p[7] = p[3]
		p[0x12] = p[0x11]
		if not upd_fn.call(self, p):
			p[0x18] = 1
			p[0] = p[4]
			p[1] = p[5]
			p[2] = p[6]
			p[0x11] = p[0x12]
			p[3] = p[7]
			p[0x16] = p[0x17]
		i += 1
	var n := roundi(moved / d4) if d4 != 0.0 else 0
	if n <= d0:
		n = d0
	if (flags & F_EMIT) and ((flags & F_CARRIER) == 0 or has_carrier):
		var spawned := 0
		var tries := 0
		while tries < n:
			if parts.size() >= d8:
				break
			if int(rnd() % 100) < cc:
				var idx := spawned
				spawned += 1
				_spawn(idx)
			tries += 1
		if spawned == 0 and cc > 50 and n > 0 and parts.size() < d8:
			_spawn(0)
	if not has_carrier:
		if (flags & F_KEEP) == 0:
			return parts.size() != 0
	elif (flags & F_EMIT) == 0 and parts.is_empty():
		return false
	return true


func _spawn(idx: int) -> void:
	var p := new_particle()
	if spawn_fn.call(self, p, idx):
		#  links it with its previous state equal to the current.
		p[4] = p[0]
		p[5] = p[1]
		p[6] = p[2]
		p[7] = p[3]
		p[0x12] = p[0x11]
		p[0x17] = p[0x16]
		parts.append(p)


## Adds a particle directly (spawn callbacks that fill several at once).
func push(p: Array) -> void:
	p[4] = p[0]
	p[5] = p[1]
	p[6] = p[2]
	p[7] = p[3]
	p[0x12] = p[0x11]
	p[0x17] = p[0x16]
	parts.append(p)
