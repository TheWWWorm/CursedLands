extends Node
const PickBounds = preload("res://src/ui/mesh_screen_rect.gd")
## Compare native early classification with the unclassified scalar clip path.
var checks := 0
var failures := 0

func _ready() -> void:
	var kernel: RefCounted = PickBounds._kernel
	if kernel == null:
		printerr("PICKING_BOUNDS native kernel unavailable")
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 829166
	for trial in 432:
		cam.projection = int(trial / 6) % 3
		cam.near = 0.1
		cam.far = 50.0
		cam.size = 12.0
		cam.fov = 65.0
		cam.frustum_offset = Vector2(0.3, -0.2)
		cam.transform = Transform3D(Basis.from_euler(Vector3(0.17, -0.24, 0.08)), Vector3(10000, -20000, 30000) if trial % 7 == 0 else Vector3(3, 2, 1))
		var mesh := ArrayMesh.new()
		var vertices := PackedVector3Array()
		var count := 3 * (1 + trial % 41)
		var extent: float = [0.02, 0.3, 2.0, 12.0][trial % 4]
		for i in count:
			vertices.append(Vector3(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent), rng.randf_range(-extent, extent)))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if trial % 2 == 0:
			var indices := PackedInt32Array()
			for i in count: indices.append(count - i - 1)
			arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP if trial % 5 == 0 else Mesh.PRIMITIVE_TRIANGLES, arrays)
		var part := MeshInstance3D.new()
		part.mesh = mesh
		add_child(part)
		var center: Vector3 = [Vector3(0, 0, -8), Vector3(30, 0, -8), Vector3(0, 0, -0.1), Vector3(0, 0, -50), Vector3(0, 30, -8), Vector3(0, 0, 5)][trial % 6]
		part.transform = cam.transform * Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf())).scaled(Vector3(0.7, 1.4, 1.1)), center)
		# Load once, then explicitly disable the script's own extrema shortcut.
		var data := PickBounds._mesh_data(mesh)
		for surface: Dictionary in data.surfaces: surface.extrema = []
		PickBounds._kernel = null
		PickBounds._drop_rect(part.get_instance_id())
		var expected := PickBounds.of(part, cam)
		PickBounds._kernel = kernel
		PickBounds._drop_rect(part.get_instance_id())
		var actual := PickBounds.of(part, cam)
		checks += 1
		if actual != expected:
			failures += 1
			if failures < 12: printerr("FAIL bounds ", trial, " expected=", expected, " actual=", actual)
		part.free()
	cam.free()
	print("PICKING_BOUNDS checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
