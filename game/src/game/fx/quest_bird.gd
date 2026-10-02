class_name QuestBird
extends Node3D
## The messenger bird that visits the player's hero when a whole quest is
## completed (the original CEffectMoshka). (a q.*
## var change) starts it for "q.<zone>.<quest>" = 2: the world's one bird
##  is reset and sent
## the local player's hero: figure "unmobi" with texture
## "bird00", clip "cflight", started point, timer 200 ticks
## phase 0. Moved every frame with the logic tick count
## (+ the frame's fraction) as time, dt = min(Δ, 5) ticks:
## - phase 0: flies at a point 1.5 m to the side of the hero and 3.2 m up;
##   within 5 m (horizontal) → phase 1 for 100 ticks, height 30, angle
##   atan2(-dx, dy) - t·0.2 - 1.5 (the side direction); timer out → phase 2 to a new point.
## - phase 1: circles the hero at radius 1.5, 3.2 m up, angle t·0.2 + base;
##   at the end it picks a point 50 m along the tangent (angle + π/2,
## ), height + 30 m, and leaves (phase 2, 150 ticks) when the
##   terrain ray to it is clear (> 0.5), else height += 0.5 and retries.
## - phase 2: flies to that point; gone at the timer's end or on arrival.
## The target height is kept ≥ ground + 0.5; one frame's step
## is at most (⁴√(distance to the hero)·0.03 + 0.3)·dt; the figure faces its
## step and the clip advances by dt.
##  also creates the 0x203c "Bag" swarm, scales
## it by 0.5 and attaches it to the figure: the
## glowing midges and their trail (FxTypes.sp_bag); a reset
## stops the old swarm.
## Approx.: object surfaces are left out.

const TICK := GameUnit.TICK
const HALF_PI := PI * 0.5   #  (FLD π, FMUL 0.5)

var world: GameWorld
var hero: GameUnit
var _player: AnimationPlayer
var _p := Vector3.ZERO      # EI position
var _last := 0.0            #  last time (ticks)
var _timer := 0.0
var _angle := 0.0
var _height := 0.0
var _phase := 0


## (re)start the world's bird at `u`.
static func visit(w: GameWorld, u: GameUnit) -> void:
	if w == null or u == null or u.dead or not u.is_inside_tree():
		return
	var bird: QuestBird = w.get_meta("quest_bird") if w.has_meta("quest_bird") else null
	if bird == null or not is_instance_valid(bird):
		bird = QuestBird.new()
		if not bird._build():
			bird.free()
			return
		w.add_child(bird)
		w.set_meta("quest_bird", bird)
	bird.world = w
	bird.hero = u
	bird._p = bird._start_point(_hero_pos(w, u))
	bird._timer = 200.0
	bird._phase = 0
	bird._last = w.time / TICK
	bird.visible = true
	bird.set_process(true)
	bird._place(Vector3.ZERO)
	bird._start_swarm()


func _build() -> bool:
	var fig := EIFigure.instantiate("unmobi", "bird00", Vector3.ZERO)
	if fig == null:
		return false
	add_child(fig)
	var paths := {}
	for n: Node in fig.find_children("*", "Node3D", true, false):
		if not n is MeshInstance3D:
			paths[String(n.name)] = fig.get_path_to(n)
	var model := EIFigure.get_model("unmobi")
	var root_part: String = model.links[0][0] if not model.links.is_empty() else ""
	_player = AnimationPlayer.new()
	fig.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library("ei", EIAnim.library("unmobi", paths, root_part))
	if _player.has_animation("ei/cflight"):
		_player.get_animation("ei/cflight").loop_mode = Animation.LOOP_LINEAR
		_player.play("ei/cflight")
		_player.speed_scale = 0.0
	return true


static func _hero_pos(w: GameWorld, u: GameUnit) -> Vector3:
	return Vector3(u.pos.x, u.pos.y, w.ground_at(u.pos.x, u.pos.y))


## a random direction, radius 50 and 30 m up; while the terrain
## ray from the hero (+1.5 m) is blocked (≤ 0.5): height + 3, radius − 5
## (at least 4). The original's hero z (object) stands on floors; the
## remake's figure z is the terrain, so the ray starts at the AI map's stand
## height, as `GameWorld.sight_ray` does (else a hero on a floor, gz19h's
## teleporter at (456.6, 61), has the ray start under the floor and every try
## fails). **Remake guard**: the original loop has no limit; after 200 tries (600 m
## up) the last point is taken so a roofed hero cannot hang the game.
func _start_point(h: Vector3) -> Vector3:
	var up := 30.0
	var r := 50.0
	var z0 := maxf(h.z, world._stand_z(Vector2(h.x, h.y)))
	var q := h
	for _try in 200:
		r = maxf(r, 4.0)
		var a := randf() * TAU
		q = Vector3(cos(a) * r + h.x, sin(a) * r + h.y, h.z + up)
		if world.terrain_ray(Vector2(h.x, h.y), z0 + 1.5, Vector2(q.x, q.y), q.z) > 0.5:
			return q
		up += 3.0
		r -= 5.0
	return q


func _process(_dt: float) -> void:
	if world == null or hero == null or not is_instance_valid(hero) or not hero.is_inside_tree():
		_stop()
		return
	var t := world.time / TICK
	var d := clampf(t - _last, 0.0, 5.0)
	_last = t
	_timer -= d
	var h := _hero_pos(world, hero)
	var to := Vector3.ZERO
	match _phase:
		0:
			if _timer < 0.0:
				_phase = 2
				_timer = 150.0
				_exit = _start_point(h)
			var dv := h - _p
			if dv.x * dv.x + dv.y * dv.y < 25.0:
				_phase = 1
				_timer = 100.0
				_height = 30.0
				_angle = atan2(-dv.x, dv.y) - t * 0.2 - 1.5   # FPATAN(-dx, dy)
			var side := Vector2(dv.y, -dv.x)
			side = side.normalized() * 1.5 if side.length_squared() > 0.0 else Vector2.ZERO
			to = Vector3(h.x + side.x, h.y + side.y, h.z + 3.2)
		1:
			var a := t * 0.2 + _angle
			if _timer < 0.0:
				var q := Vector3(cos(HALF_PI + a) * 50.0 + _p.x, sin(HALF_PI + a) * 50.0 + _p.y, _p.z + _height)
				if world.terrain_ray(Vector2(_p.x, _p.y), _p.z, Vector2(q.x, q.y), q.z) > 0.5:
					_phase = 2
					_timer = 150.0
					_exit = q
				else:
					_height += 0.5
			to = Vector3(cos(a) * 1.5 + h.x, sin(a) * 1.5 + h.y, h.z + 3.2)
		2:
			if _timer < 0.0 or _p == _exit:
				_stop()
				return
			to = _exit
	to.z = maxf(to.z, world.ground_at(to.x, to.y) + 0.5)
	var step := to - _p
	var len := step.length()
	if len != 0.0:
		var max_step := (sqrt(sqrt(_p.distance_to(h))) * 0.03 + 0.3) * d
		if max_step < len:
			step *= max_step / len
		_p += step
	_place(step)
	if _player:
		_player.advance(d * TICK)


var _exit := Vector3.ZERO   # phase 2 goal (.. reused by the original)


func _place(dir: Vector3) -> void:
	position = EISpace.pos(_p.x, _p.y, _p.z)
	var g := EISpace.vec(dir)
	if g.length_squared() > 0.000001:
		# Figures face EI -Y (Godot +Z) at rest: turn +Z onto the step.
		basis = Basis.looking_at(-g.normalized(), Vector3.UP if absf(g.normalized().y) < 0.999 else Vector3.FORWARD)


func _stop() -> void:
	visible = false
	set_process(false)
	_end_swarm()


var _swarm = null   # ParticleFx.Effect of the 0x203c swarm


func _start_swarm() -> void:
	_end_swarm()
	if world:
		_swarm = ParticleFx.of(world).spawn(0x203c, Vector3.ZERO, 0.5, self)


##  on the swarm; detached, its midges end (control −13) and the
## trail fades.
func _end_swarm() -> void:
	if _swarm != null and is_instance_valid(world):
		var e: FxEmitter = _swarm.e
		e.stop()
		e.attach(null)
	_swarm = null
