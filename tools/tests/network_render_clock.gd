extends Node
## Packet spacing is wall time; game speed must not shorten the drawn glide.
var checks := 0
var failures := 0

class GroundWorld extends GameWorld:
	func ground_at(_x: float, _y: float) -> float: return 0.0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 20: printerr("FAIL ", label)

func trial(rate: float, native: bool) -> void:
	Engine.time_scale = rate
	var w := GroundWorld.new()
	w.authority = false
	add_child(w)
	w.set_process(false)
	var u := GameUnit.new()
	u.world = w
	w.add_child(u)
	w.set_unit(123, u)
	u._screen = VisibleOnScreenNotifier3D.new()
	u.add_child(u._screen)
	u.net_view = NetSmooth.create() if native else NetSmooth.new()
	if not native: w._client_placement = null
	u.pos = Vector2(10, 20)
	u.facing = 0.0
	u.net_view.got_at(u.pos, 1000, true, u.facing)
	u._sync_transform(0.0)
	# A walking actor travels 4 m/s of simulation time. These updates arrive
	# 100 ms apart in wall time, including an accelerating/slowing host.
	var start := u.pos
	u.pos += Vector2(4.0 * rate * 0.1, 0)
	u.facing = 0.6
	u.net_view.got_at(u.pos, 1100, false, u.facing)
	var clock := u._game_clock
	for frame in 6:
		var dt := rate * 0.1 / 6.0
		if native:
			u._placement_frame = -1
			w._process(dt)
			check(u._placement_frame == Engine.get_process_frames(), "native roster places this frame")
			u._present_frame(dt)
		else:
			u._present_frame(dt)
		var fraction := float(frame + 1) / 6.0
		check(is_equal_approx(u.position.x, lerpf(start.x, u.pos.x, fraction)),
			"position advances over packet interval: rate=%s native=%s frame=%d" % [rate, native, frame])
		check(is_equal_approx(u.net_view.yaw, u.facing * fraction),
			"turn advances over packet interval: rate=%s native=%s frame=%d" % [rate, native, frame])
	check(is_equal_approx(u._game_clock, clock + rate * 0.1), "animation clock keeps simulation speed")
	# Direct placement and stopped frames retain their existing semantics.
	u.pos += Vector2(20, 0)
	u.net_view.got_at(u.pos, 1200, true, -0.4)
	u.facing = -0.4
	u._sync_transform(0.0)
	check(is_equal_approx(u.position.x, u.pos.x) and is_equal_approx(u.net_view.yaw, -0.4), "teleport is immediate")
	var held := u.position
	u.pos += Vector2(1, 0)
	u.net_view.got_at(u.pos, 1300, false, u.facing)
	u._sync_transform(0.0)
	check(u.position == held, "zero elapsed time does not advance interpolation")
	w.free()

func _ready() -> void:
	var previous := Engine.time_scale
	check(ClassDB.class_exists("UnitPresentationKernel"), "native placement path is available")
	for native in [false, true]:
		for rate in [0.5, 1.0, 2.0, 3.0]: trial(rate, native)
	Engine.time_scale = previous
	print("NETWORK_RENDER_CLOCK ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
