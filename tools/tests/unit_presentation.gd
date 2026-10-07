extends Node
var checks := 0
var failures := 0

class GroundWorld extends GameWorld:
	var reads := 0
	var height := 3.0
	func ground_at(x: float, y: float) -> float:
		reads += 1
		return height + x * 0.0125 - y * 0.025

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ", label)

func _ready() -> void:
	check(ClassDB.class_exists("UnitPresentationKernel"), "compiled placement is present")
	if failures:
		get_tree().quit(1)
		return
	var kernel: Object = ClassDB.instantiate("UnitPresentationKernel")
	var w := GroundWorld.new()
	w.authority = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8720134
	var pairs: Array = []
	for i in 64:
		var pair: Array[GameUnit] = [GameUnit.new(), GameUnit.new()]
		pair[0].net_view = NetSmooth.new() # Independent scalar interpolation oracle.
		for u: GameUnit in pair:
			u.world = w
			w.add_child(u)
		pairs.append(pair)
	var terrains: Array[EITerrain] = [EITerrain.new(), EITerrain.new()]
	for step in 128:
		if step % 19 == 0:
			w.terrain = terrains[step % 2]
			w.terrain.surface_rev += 1
			w.height += 0.125
		if step % 11 == 0: w.nav.floor_rev += 1
		if step % 37 == 0: w.terrain = null
		var dt: float = [-0.1, 0.0, 0.004, 0.016, 0.033, 0.055, 0.2][step % 7]
		for i in pairs.size():
			var a: GameUnit = pairs[i][0]
			var b: GameUnit = pairs[i][1]
			if step % 5 == 0:
				var target := Vector2(rng.randf_range(-50,50), rng.randf_range(-50,50)) if step % 20 == 0 else a.pos + Vector2(0.6,-0.4)
				var facing := rng.randf_range(-20,20)
				var speed := rng.randf_range(0,15)
				var turn := rng.randf_range(0,20)
				for u: GameUnit in [a,b]:
					u.pos = target
					u.facing = facing
					u.net_view._speed = speed
					u.net_view._yaw_speed = turn
			if step % 23 == 0:
				for u: GameUnit in [a,b]: u.transform = Transform3D(Basis.IDENTITY, Vector3(-2,3,4))
			if step % 31 == 0:
				for u: GameUnit in [a,b]: u.net_view.view = Vector2.INF; u.net_view.yaw = INF
			if step % 17 == 0:
				for u: GameUnit in [a,b]: u.net_view.yaw = INF
			if step % 13 == 0:
				# A direct placement between native passes replaces its cached
				# ground/transform state, even while the actor stands still.
				a._sync_transform(0.0)
				b._sync_transform(0.0)
			a._move_speed = rng.randf_range(0,7)
			b._move_speed = a._move_speed
			var before := w.reads
			# Negative time on the public script helper means physics delta.
			# NetSmooth itself clamps negative intervals; use zero for this path.
			var elapsed := maxf(dt,0.0)
			a._sync_transform(elapsed)
			var script_reads := w.reads - before
			before = w.reads
			check(kernel.sync_client(w,b,elapsed), "replica accepted")
			check(w.reads - before == script_reads, "identical ground-cache invalidation")
			check(a.net_view.view == b.net_view.view and a.net_view.yaw == b.net_view.yaw,
				"identical smoothed position and yaw %s/%s" % [step,i])
			check(a.transform == b.transform and a._drawn == b._drawn and a._draw_move_speed == b._draw_move_speed,
				"identical transform and movement %s/%s" % [step,i])
			check(a._xf_pos == b._xf_pos and a._xf_facing == b._xf_facing and a._xf == b._xf and
				a._xf_tid == b._xf_tid and a._xf_rev == b._xf_rev and a._xf_floor_rev == b._xf_floor_rev,
				"identical placement cache")
	w.terrain = null
	for t in terrains: t.free()
	var u: GameUnit = pairs[0][1]
	w.authority = true
	check(not kernel.sync_client(w,u,0.02), "authority retains native spline path")
	w.authority = false
	check(not kernel.sync_client(null,u,0.02), "missing world is ignored")
	var other := GroundWorld.new()
	other.authority = false
	check(not kernel.sync_client(other,u,0.02), "foreign world is ignored")
	other.free()
	check(kernel.sync_clients(w,[u],0.02,55) == 0, "disabled and unfinished figures are ignored")
	w.process_mode = Node.PROCESS_MODE_INHERIT
	u._screen = VisibleOnScreenNotifier3D.new()
	u.add_child(u._screen)
	u.net_view.view = Vector2.ZERO
	u.net_view.yaw = 0.0
	u.net_view._speed = 10.0
	u.pos = Vector2(1,0)
	u.facing = 0.0
	var frame := Engine.get_process_frames()
	check(kernel.sync_clients(w,[null,u],0.04,frame) == 1, "live roster batches one ready figure")
	var placed := u.position
	u._process(0.04)
	check(u.position == placed and is_equal_approx(u.position.x,0.4), "unit callback does not smooth twice")
	u.process_priority = -3
	check(kernel.sync_clients(w,[u],0.04,frame) == 0, "earlier custom callback retains its placement")
	u.process_priority = 0
	u.set_process(false)
	check(kernel.sync_clients(w,[u],0.04,frame) == 0, "stopped unit does not move in roster pass")
	w.queue_free()
	await get_tree().process_frame
	print("UNIT_PRESENTATION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
