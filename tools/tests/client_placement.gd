extends Node
var checks := 0
var failures := 0

class GroundWorld extends GameWorld:
	var reads := 0
	var height := 3.0
	func ground_at(_x: float, _y: float) -> float:
		reads += 1
		return height

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var w := GroundWorld.new()
	w.authority = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w)
	var u := GameUnit.new()
	u.world = w
	w.add_child(u)
	u.pos = Vector2(10,20)
	u.facing = 0.0
	u.net_view.got(u.pos, true, u.facing)
	await get_tree().physics_frame
	u._sync_transform()
	check(u.position == Vector3(10,3,-20), "initial client placement")
	for i in 100: u._sync_transform()
	check(w.reads == 1, "stationary client reuses its ground result")
	u._move_speed = 7.0
	u._sync_transform()
	check(u._draw_move_speed == 7.0, "cache does not retain old motion speed")
	u.pos += Vector2(0.75,0)
	u.facing = 1.0
	u.net_view.got(u.pos, false, u.facing)
	var start := u.position
	u._sync_transform()
	check(u.position.x > start.x and u.position.x < u.pos.x, "client smoothing continues before cache lookup")
	for i in 120: u._sync_transform()
	check(u.position == Vector3(10.75,3,-20) and is_equal_approx(u.net_view.yaw,1.0), "motion and turning reach their targets")
	var reads := w.reads
	for i in 100: u._sync_transform()
	check(w.reads == reads, "settled motion is cached again")
	w.height = 5.0
	w.nav.floor_rev += 1
	u._sync_transform()
	check(u.position.y == 5.0 and w.reads == reads+1, "changed object floor invalidates placement")
	var terrain := EITerrain.new()
	w.terrain = terrain
	u._sync_transform()
	reads = w.reads
	w.height = 8.0
	terrain.surface_rev += 1
	u._sync_transform()
	check(u.position.y == 8.0 and w.reads == reads+1, "changed terrain surface invalidates placement")
	var replacement := EITerrain.new()
	replacement.surface_rev = terrain.surface_rev
	w.terrain = replacement
	reads = w.reads
	u._sync_transform()
	check(w.reads == reads+1, "replacement terrain with same revision invalidates placement")
	u.position += Vector3(1,2,3)
	u._sync_transform()
	check(u.position == Vector3(10.75,8,-20), "external transform edits cannot leave stale placement")
	u.pos = Vector2(100,200)
	u.net_view.got(u.pos, true, -1.0)
	u.facing = -1.0
	u._sync_transform()
	check(u.position == Vector3(100,8,-200), "teleport places the unit immediately")
	w.authority = true
	u.pos += Vector2(1,2)
	u._sync_transform()
	check(u.position == Vector3(101,8,-202), "authority transition retains direct placement")
	# Replicas draw once per rendered frame, independent of physics catch-up.
	w.authority = false
	u._screen = VisibleOnScreenNotifier3D.new()
	u.add_child(u._screen)
	u.net_view.got(u.pos, true, u.facing)
	u.pos += Vector2(1,0)
	u.net_view._interval = 0.1
	u.net_view._speed = 10.0
	var clock := u._game_clock
	var from := u.position.x
	u._physics_process(0.02)
	u._physics_process(0.02)
	check(u._game_clock == clock and u.position.x == from, "physics catch-up never repeats replica drawing")
	u._process(0.04)
	check(is_equal_approx(u._game_clock, clock + 0.04), "render clock consumes supplied scaled time once")
	check(is_equal_approx(u.position.x, from + 0.4), "smoothing uses rendered interval, not physics delta")
	check(u.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "rendered placement has no second physics interpolation")
	u._process(0.06)
	check(is_equal_approx(u.position.x, from + 1.0), "split render intervals reach identical endpoint")
	w._fixed_step = true
	clock = u._game_clock
	u._physics_process(0.02)
	check(is_equal_approx(u._game_clock, clock + 0.02), "fixed-step tools retain their supplied physics clock")
	w.terrain = null
	terrain.free(); replacement.free()
	w.queue_free()
	await get_tree().process_frame
	print("CLIENT_PLACEMENT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
