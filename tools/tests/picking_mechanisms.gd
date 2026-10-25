extends Node
const Bounds = preload("res://src/ui/mesh_screen_rect.gd")
var checks := 0
var failures := 0
var game: Game
var world: GameWorld
var camera: Camera3D
var roots: Array[Node3D] = []
var parts: Array[MeshInstance3D] = []
var fallback_calls := 0
var bounds_script: Variant = Bounds

class CustomPermission extends LeverSystem:
	func usable(_nid: int) -> bool: return false

class DispatchProbe extends RefCounted:
	var calls := 0
	func pick_mechanisms(_levers, _objects, _morphs, _usable, _fallback, _camera, _view, _point) -> int:
		calls += 1
		return 987654321

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL ", label)

func pick(point: Vector2, native: bool) -> int:
	bounds_script._native_mechanisms = native
	game._lever_pick_key = []
	return game.pick_lever(point)

func compare(point: Vector2, label: String) -> void:
	var expected := pick(point, false)
	check(pick(point, true) == expected, label)

func fallback(part: MeshInstance3D, cam: Camera3D, view: Dictionary) -> Rect2i:
	fallback_calls += 1
	return Bounds.of_context(part, cam, view)

func mechanism(id: int, at: Vector3, geometry := true, retained := true) -> Node3D:
	var root := Node3D.new(); add_child(root); root.position = at; roots.append(root)
	world.objects[id] = root
	world.levers[id] = {"enabled":true, "science":[1,0,0], "state":0, "states":2}
	var meshes := []
	if geometry:
		var mesh := ArrayMesh.new()
		var arrays := BoxMesh.new().get_mesh_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if retained: mesh.set_meta(EIFigure.GEOMETRY_META, [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX]])
		var part := MeshInstance3D.new(); part.mesh = mesh; root.add_child(part)
		meshes.append(part); parts.append(part)
	world.lever_sys._morph[id] = {"meshes":meshes}
	return root

func clear_scene() -> void:
	world.levers.clear(); world.objects.clear(); world.lever_sys._morph.clear()
	for root in roots: root.free()
	roots.clear(); parts.clear()

func _ready() -> void:
	check(Bounds._kernel != null and Bounds._kernel.has_method("pick_mechanisms"), "native mechanism batch available")
	if failures:
		print("PICKING_MECHANISMS ", checks, " checks ", failures, " failures")
		get_tree().quit(1); return
	# Query-only scene: no session, rendering or simulation side effects.
	game = Game.new(); world = GameWorld.new(); game.world = world
	game.rig = CameraRig.new(); camera = Camera3D.new(); add_child(camera)
	camera.current = true; camera.far = 80; camera.near = .1; game.rig.camera = camera
	check(pick(Vector2.ZERO,true) == -1, "empty world before mechanism setup has no target")
	world.lever_sys = LeverSystem.new(world)
	mechanism(10, Vector3(0,-.6,-8), false)
	var center := camera.unproject_position(Vector3(0,0,-8))
	var helper := Bounds._kernel; var probe := DispatchProbe.new()
	Bounds._kernel = probe
	check(pick(center,true) == 987654321 and probe.calls == 1, "production query dispatches one native batch")
	Bounds._kernel = helper
	check(pick(center, true) == 10, "origin assist works without mesh parts")
	check(pick(center+Vector2(39,0), true) == 10, "origin assist inside forty pixels")
	check(pick(center+Vector2(40,0), true) == -1, "origin assist excludes forty-pixel boundary")
	mechanism(20, Vector3(0,-.6,-8), false)
	check(pick(center, true) == 10, "equal-distance assist keeps insertion order")
	world.levers[10].enabled = false
	check(pick(center, true) == 20, "same-frame consumed permission disappears")
	world.levers[20].science = [0,0,0]
	check(pick(center, true) == -1, "script-only mechanisms are ineligible")
	world.levers[20].science = []
	check(pick(center, true) == 20, "empty science permits a use")
	roots[1].hide(); check(pick(center, true) == -1, "hidden object excludes origin assist")
	roots[1].show(); roots[1].position.z = 2
	check(pick(center, true) == -1, "behind-camera origin cannot assist")
	clear_scene()
	# Displace the object origin far from the actual gate part, so assistance
	# cannot disguise an incorrect rectangle edge or part-depth result.
	var root := mechanism(31, Vector3(30,0,-8))
	parts[0].position.x = -30
	mechanism(32, Vector3(30,0,-8)); parts[1].position.x = -30
	var rect := Bounds.of_context(parts[0], camera, Bounds.camera_context(camera))
	check(rect.has_area(), "gate part has a nonempty projected rectangle")
	check(pick(Vector2(rect.position), true) == 31, "top/left included and equal depth keeps first gate")
	check(pick(Vector2(rect.end), true) == -1, "bottom/right excluded without origin assist")
	check(pick(Vector2(NAN, rect.position.y), true) == -1, "non-finite pointer cannot hit a rectangle")
	roots[1].position.z = -7
	check(pick(Vector2(rect.get_center()), true) == 32, "nearer part wins")
	root.hide(); roots[1].hide()
	check(pick(Vector2(rect.get_center()), true) == -1, "hidden parents exclude mesh parts")
	clear_scene()
	var rng := RandomNumberGenerator.new(); rng.seed = 719331
	for i in 24:
		mechanism(100+i, Vector3(rng.randf_range(-18,18), rng.randf_range(-9,9), rng.randf_range(-35,4)), true, i%4 != 0)
		if i%3 == 0:
			var mesh := ArrayMesh.new(); mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE if i%2 else Mesh.BLEND_SHAPE_MODE_NORMALIZED
			mesh.add_blend_shape("open")
			var arrays := BoxMesh.new().get_mesh_arrays(); var shapes := []; shapes.resize(Mesh.ARRAY_MAX)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var shifted := vertices.duplicate()
			for k in shifted.size(): shifted[k] += Vector3(1.3,.4,-.7)
			shapes[Mesh.ARRAY_VERTEX] = shifted
			# Match the base normal/tangent format accepted by ArrayMesh.
			shapes[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]; shapes[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shapes])
			mesh.set_meta(EIFigure.GEOMETRY_META,[vertices,arrays[Mesh.ARRAY_INDEX]])
			mesh.set_meta(EIFigure.SHAPES_META,[shifted]); parts[i].mesh = mesh
		if i%7 == 0: parts[i].skin = Skin.new()
	for frame in 72:
		camera.projection = frame%3; camera.size = 18; camera.fov = 55+frame%17
		camera.frustum_offset = Vector2(.3,-.2); camera.h_offset = .1; camera.v_offset = -.2
		camera.transform = Transform3D(Basis.from_euler(Vector3(.07*sin(frame),.08*cos(frame),.03)),Vector3(frame*.017,0,1))
		for i in parts.size():
			if parts[i].get_blend_shape_count(): parts[i].set_blend_shape_value(0,[-.5,0.,.3,1.,2.][(frame+i)%5])
			parts[i].position.y = sin(frame*.1+i)*.3
			world.levers[100+i].enabled = (frame+i)%11 != 0
			roots[i].visible = (frame+i)%13 != 0
		for i in 48:
			compare(Vector2(rng.randf_range(-50,get_viewport().size.x+50),rng.randf_range(-50,get_viewport().size.y+50)), "moving camera/morph/permission "+str(frame)+"/"+str(i))
		for part in parts:
			compare(camera.unproject_position(part.global_position), "live part/origin overlap "+str(frame))
	# Unsupported meshes reach the general path in the native batch itself.
	var view := Bounds.camera_context(camera)
	var direct: int = Bounds._kernel.pick_mechanisms(world.levers,world.objects,world.lever_sys._morph,world.lever_sys.usable,fallback,camera,view,center)
	check(direct == pick(center,false) and fallback_calls > 0, "unsupported geometry invokes original general path")
	var previous := world.lever_sys
	world.lever_sys = CustomPermission.new(world)
	world.lever_sys._morph = previous._morph
	check(pick(center,true) == -1, "custom permission script keeps script query")
	world.lever_sys = previous
	# The same production query works when the helper is missing/older.
	var native := Bounds._kernel; Bounds._kernel = null
	var scalar := pick(center,false); Bounds._kernel = native
	check(pick(center,true) == scalar, "no-native geometry fallback agrees")
	var timing := {}
	for accelerated in [false,true,true,false]:
		var start := Time.get_ticks_usec()
		for frame in 160:
			camera.position.x = frame*.007
			pick(center, accelerated)
		var key := "native" if accelerated else "script"
		if not timing.has(key): timing[key] = []
		timing[key].append(Time.get_ticks_usec()-start)
	bounds_script._native_mechanisms = true
	clear_scene(); camera.free(); game.rig.free(); game.free(); world.free()
	print("PICKING_MECHANISMS_TIMING ",JSON.stringify(timing))
	print("PICKING_MECHANISMS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
