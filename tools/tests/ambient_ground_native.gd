extends Node
const Habitat = preload("res://src/game/fx/ambient_habitats.gd")

class Query extends "res://src/game/fx/ambient_habitats.gd":
	func _init(t: EITerrain) -> void:
		super(t,false) # No scenery scan is needed for the query fixture.

class Probe extends RefCounted:
	var calls := 0
	var reply: Variant={"height":1234.5}
	func sample(_p,_size,_stride,_heights,_xy,_tiles,_types,_per_atlas,_elevation) -> Variant:
		calls+=1
		return reply

var habitat_script: Variant=Habitat
var checks := 0
var failures := 0
var native: RefCounted
var field: Query
var terrain: EITerrain

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<15: printerr("FAIL ",label)

func compare(p: Vector2, drawn: bool, label: String) -> void:
	var expected: Dictionary=field.call("_ground_script",p,drawn)
	var actual := field.ground(p,drawn)
	check(actual==expected,label+": "+str(p)+" drawn="+str(drawn)+" expected="+str(expected)+" actual="+str(actual))

func _ready() -> void:
	check(ClassDB.class_exists("AmbientGroundKernel"),"native highest-triangle query is available")
	if failures: finish(); return
	native=habitat_script._ground_kernel
	terrain=EITerrain.new(); terrain.sectors_x=1; terrain.sectors_y=1; terrain.grid_w=33
	terrain.texture_size=512; terrain.tile_size=64
	terrain.heights.resize(33*33); terrain.land_xy.resize(33*33); terrain.land_tile.resize(16*16)
	terrain.tile_types=PackedInt32Array([9,0,3,12,255])
	terrain.water_base.resize(32*32); terrain.water_base.fill(-INF); terrain.water_mat.resize(32*32)
	field=Query.new(terrain)
	var probe := Probe.new(); habitat_script._ground_kernel=probe
	check(field.ground(Vector2.ONE)=={"height":1234.5} and probe.calls==1,"production query makes one native dispatch")
	habitat_script._ground_kernel=native
	# Ordered ties and exact shared boundaries use the original first owner.
	for y in range(1,31):
		for x in range(1,31):
			compare(Vector2(x,y),false,"flat four-cell corner")
			compare(Vector2(x+0.5,y+0.5),true,"shared diagonal")
	var rng := RandomNumberGenerator.new(); rng.seed=930521
	for i in terrain.heights.size():
		terrain.heights[i]=rng.randf_range(-3,3)
		terrain.land_xy[i]=Vector2(rng.randf_range(-1.4,1.4),rng.randf_range(-1.4,1.4))
	for i in terrain.land_tile.size(): terrain.land_tile[i]=i%5|((i%4)<<14)
	for i in 1500:
		var p := Vector2(rng.randf_range(-0.5,32.5),rng.randf_range(-0.5,32.5))
		compare(p,false,"jitter/fold highest triangle")
		compare(p,true,"drawn barycentric height")
	terrain._land_mat=ShaderMaterial.new(); terrain._land_mat.shader=Shader.new()
	terrain._land_mat.shader.code="shader_type spatial; uniform bool soft_ground = false;"
	terrain._land_mat.set_shader_parameter("soft_ground",true)
	for i in 300:
		compare(Vector2(rng.randf_range(1,31),rng.randf_range(1,31)),true,"visible loose-ground interpolation")
	terrain._land_mat.set_shader_parameter("soft_ground",false)
	# Live surface changes must never reuse a previous terrain snapshot.
	var point := Vector2(10.2,10.4)
	var before := field.ground(point)
	for i in terrain.heights.size(): terrain.heights[i]+=5.0
	compare(point,false,"live height edit")
	check(absf(float(field.ground(point).height)-float(before.height)-5.0)<0.000001,"same-frame height mutation is visible")
	terrain.land_tile.fill(0); terrain.tile_types[0]=255
	check(int(field.ground(point).type)==255,"full integer material type survives native dispatch")
	terrain.land_tile.fill(63|(255<<6))
	check(int(field.ground(point).type)==8,"missing material index retains unknown-ground fallback")
	terrain.land_tile.fill(0); terrain.tile_types[0]=1025
	check(int(field.ground(point).type)==1025,"material types keep their full integer width")
	var original: Dictionary=field.call("_ground_script",point,false)
	habitat_script._ground_kernel=null
	check(not original.is_empty() and field.ground(point)==original,"missing library uses the complete script result")
	probe.reply=null; habitat_script._ground_kernel=probe
	check(field.ground(point)==original,"declined native input uses the complete script result")
	habitat_script._ground_kernel=native
	timings(rng)
	# Collapsed triangles and map bounds do not generate spurious hits.
	for y in 33:
		for x in 33: terrain.land_xy[y*33+x]=Vector2(-x,-y)
	compare(point,false,"all triangles collapsed")
	for p in [Vector2(-0.1,0),Vector2(0,-0.1),Vector2(32,1),Vector2(1,32),Vector2.INF]:
		check(field.ground(p).is_empty(),"outside map "+str(p))
	# Older libraries remain supported by the existing script implementation.
	habitat_script._ground_kernel=null
	check(field.ground(point)==field.call("_ground_script",point,false),"missing library uses script fallback")
	habitat_script._ground_kernel=native
	check(native.call("sample",Vector2.ONE,Vector2i(32,32),33,PackedFloat32Array(),terrain.land_xy,
		terrain.land_tile,terrain.tile_types,8,Callable())==null,"malformed arrays decline native handling")
	field=null; terrain.free()
	finish()

func finish() -> void:
	print("AMBIENT_GROUND_NATIVE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func timings(rng: RandomNumberGenerator) -> void:
	var points := PackedVector2Array()
	for i in 3000: points.append(Vector2(rng.randf_range(1,31),rng.randf_range(1,31)))
	var rows := []
	for drawn in [false,true]:
		for fast in [false,true,true,false]:
			var total := 0.0
			var started := Time.get_ticks_usec()
			for p: Vector2 in points:
				var hit: Dictionary=field.ground(p,drawn) if fast else field.call("_ground_script",p,drawn)
				total+=float(hit.get("height",0.0))
			rows.append({"native":fast,"drawn":drawn,"queries":points.size(),"usec":Time.get_ticks_usec()-started,"height_sum":total})
	print("AMBIENT_GROUND_TIMING ",JSON.stringify(rows))
