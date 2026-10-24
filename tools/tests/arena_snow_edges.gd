extends Node
## The actual rendered border must share the native terrain's quantized edge.
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	var ground := ArenaTerrain.create(false)
	var ring := ArenaSnowSurround.new()
	for overview in [false, true]:
		ring.set_overview(overview)
		var extent := 192 if overview else 64
		var vertices: PackedVector3Array = ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in 4 * extent:
			var point := vertices[index]
			var x := int(roundf(point.x)) % 64
			var y := int(roundf(-point.z)) % 64
			if x == 0 and point.x > 0: x = 64
			if y == 0 and point.z < 0: y = 64
			var native_height: float = ground.heights[y * ground.grid_w + x]
			checks += 1
			if absf(point.y-native_height) > 0.00001:
				failures.append("snow gap at %s: %s != %s" % [point,point.y,native_height])
	# Adjacent overview boards share every vertex, including their corners.
	for step in 65:
		checks += 1
		if not is_equal_approx(ArenaTerrain.snow_height(0,step),ArenaTerrain.snow_height(64,step)) or not is_equal_approx(ArenaTerrain.snow_height(step,0),ArenaTerrain.snow_height(step,64)):
			failures.append("overview boards disagree at edge step %d" % step)
	checks += 1
	if ArenaTerrain.snow_height(32,32) != 0 or ArenaTerrain.snow_height(20,44) != 0:
		failures.append("playable clearing changed height")
	ground.free();ring.free()
	print("ARENA_SNOW_EDGES ",checks," checks; failures=",JSON.stringify(failures))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
