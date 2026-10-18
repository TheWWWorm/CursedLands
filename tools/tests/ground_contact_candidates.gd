extends Node
## Every enclosed triangle sample must survive the broad phase, including
## folded/inverted cells, exact edges and the shader's barycentric tolerance.
var checks := 0
var failures := 0
const OFFSETS := [Vector2i.ZERO, Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 8: printerr("FAIL ", message)

func _ready() -> void:
	var terrain := EITerrain.new()
	terrain.sectors_x = 1; terrain.sectors_y = 1; terrain.grid_w = 33
	terrain.land_xy.resize(33 * 33)
	var random := RandomNumberGenerator.new(); random.seed = 39101
	for displaced in [false, true]:
		for i in terrain.land_xy.size():
			terrain.land_xy[i] = Vector2(random.randf_range(-0.99,0.99),random.randf_range(-0.99,0.99)) if displaced else Vector2.ZERO
		var image := GroundSurfaceData._candidate_image(terrain)
		check(image.get_format() == Image.FORMAT_RH and image.get_size() == Vector2i(128,128), "bounded half-float lookup")
		var weights: Array[Vector3] = []
		for x in 9:
			for y in range(9-x): weights.append(Vector3(float(x)/8.0,float(y)/8.0,1.0-float(x+y)/8.0))
		for edge in 3:
			var w := Vector3(0.5,0.5,0.5); w[edge] = -0.000009
			w[(edge+1)%3] += 0.000009
			weights.append(w)
		for y in 32:
			for x in 32:
				var points: Array[Vector2] = []
				for dy in 2:
					for dx in 2: points.append(Vector2(x+dx,y+dy)+terrain.land_xy[(y+dy)*33+x+dx])
				for triangle: Array in [[points[2],points[1],points[0]], [points[1],points[2],points[3]]]:
					for w in weights:
						var p: Vector2 = triangle[0]*w.x+triangle[1]*w.y+triangle[2]*w.z
						var target := Vector2i(floor(p))
						var bit := OFFSETS.find(Vector2i(x,y)-target)
						if bit < 0 or p.x < 0 or p.y < 0 or p.x >= 32 or p.y >= 32: continue
						var mask := int(image.get_pixelv(Vector2i(floor(p*4.0))).r)
						check((mask & (1 << bit)) != 0, "candidate retains enclosed point " + str(p))
		var total := 0
		for y in 128:
			for x in 128:
				var value := image.get_pixel(x,y).r
				check(value == int(value) and value >= 0 and value <= 511, "all masks survive float16 exactly")
				for bit in 9: total += int((int(value) & (1 << bit)) != 0)
		if not displaced: check(float(total)/(128*128) < 3.0, "regular terrain averages fewer than three candidates instead of nine")
	terrain.free()
	print("GROUND_CONTACT_CANDIDATES ",checks," checks; failures=",failures)
	get_tree().quit(int(failures > 0))
