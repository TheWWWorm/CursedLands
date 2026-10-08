extends Node
## Compare touch selection with the exhaustive pre-optimization fallback.
## Real human and winged creature meshes; ordinary campaign assets required.
var checks := 0
var failures := 0
var game: Game
var camera: Camera3D
var rows: Array[GameUnit] = []
var detailed_before := 0
var detailed_after := 0

class GroundWorld extends GameWorld:
	func ground_at(_x: float, _y: float) -> float: return 0.0

class CountedUnit extends GameUnit:
	var rect_calls := 0
	func screen_rects(cam: Camera3D) -> Array:
		rect_calls += 1
		return super.screen_rects(cam)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ", label)

func reference(p: Vector2) -> GameUnit:
	var hit := game._pick_unit(p)
	if hit: return hit
	var best := TouchInput.target_pixels() * 0.35
	for unit: GameUnit in game.world.visible_units():
		if unit.hidden or not unit.visible or not unit.near_screen(): continue
		var rects := unit.screen_rects(camera)
		if rects.is_empty(): continue
		var rect := Rect2(rects[0])
		var dist := p.distance_to(p.clamp(rect.position, rect.end))
		if dist < best:
			best = dist
			hit = unit
	return hit

func calls() -> int:
	var n := 0
	for unit: CountedUnit in rows: n += unit.rect_calls
	return n

func compare(p: Vector2) -> void:
	var before := calls()
	var expected := reference(p)
	detailed_before += calls() - before
	before = calls()
	game._pick_key = []
	var actual := game.pick_unit(p)
	detailed_after += calls() - before
	check(actual == expected, "same touch target at %s" % p)

func _ready() -> void:
	TouchInput.enabled = true
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	var w := GroundWorld.new()
	w.authority = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w)
	game = Game.new()
	game.world = w
	game.rig = CameraRig.new()
	camera = Camera3D.new()
	add_child(camera)
	game.rig.camera = camera
	camera.current = true
	camera.fov = 55.0
	camera.far = 100.0
	for record: Dictionary in [
		{"prototype":"zone1 Human Fighter3 M", "nid":1, "player":3},
		{"prototype":"zone1 JunEvil", "template":"unmocu", "nid":2, "player":6}]:
		var unit := CountedUnit.new()
		check(unit.setup(w, record), "authored mesh loads")
		w.add_child(unit)
		w.set_unit(unit.uid, unit)
		unit.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		unit._headless = true # Exercise bounds even before visibility queries finish.
		rows.append(unit)
	if failures:
		get_tree().quit(1); return
	var size := get_viewport().get_visible_rect().size
	var margin := TouchInput.target_pixels() * 0.35
	for projection in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL]:
		camera.projection = projection
		camera.size = 18.0
		for pose in ["idle", "walk", "attack", "death"]:
			for unit in rows:
				unit.model.act(pose, 1, 0.0)
				unit.model.player.advance(0.23)
				unit.model.flush_pending_pose()
			for angle in [0.0, 0.8, 2.0]:
				camera.position = Vector3(sin(angle)*18.0, 14.0, cos(angle)*18.0)
				camera.look_at(Vector3(0,1,0))
				rows[0].position = Vector3(-0.5,0,0)
				rows[1].position = Vector3(1.5,0,-0.5)
				for unit in rows:
					var rects := unit.screen_rects(camera)
					check(not rects.is_empty(), "posed mesh has projected bounds")
					if rects.is_empty(): continue
					var r := Rect2(rects[0])
					for point in [r.get_center(), r.position, r.end,
						Vector2(r.position.x-margin*0.9, r.get_center().y),
						Vector2(r.end.x+margin*0.9, r.get_center().y),
						Vector2(r.get_center().x, r.position.y-margin*0.9),
						Vector2(r.get_center().x, r.end.y+margin*0.9)]: compare(point)
				for x in 8:
					for y in 5: compare(Vector2((x+0.5)*size.x/8.0, (y+0.5)*size.y/5.0))
	# A camera inside the bound must keep the conservative fallback. Hidden
	# silhouettes still go through the ordinary selection rules.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = Vector3(0,1,0.1)
	camera.look_at(Vector3(0,1,-5))
	for unit in rows: check(unit.may_cover(camera, Vector2(-10000,-10000), margin), "near camera bound remains conservative")
	rows[1].hide()
	for point in [size*0.5, size*0.25, Vector2.ZERO]: compare(point)
	check(detailed_after < detailed_before, "distant taps skip detailed mesh bounds")
	game.rig.free()
	game.free()
	w.free()
	print("TOUCH_UNIT_PICKING ", checks, " checks ", failures, " failures; bounds ", detailed_before, " -> ", detailed_after)
	get_tree().quit(1 if failures else 0)
