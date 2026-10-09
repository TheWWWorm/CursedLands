extends RefCounted
## Authored mean-surface flow, independent of wave phase and navigation. The
## global grid gives shared sector vertices one value. Liquid tile origins are
## decoded at two-metre spacing before addressing their nine grid vertices:
## type-4 land XY jitter can exceed half a metre at individual vertices.
const BURIED_TOLERANCE := 0.05
var size := Vector2i.ZERO
var base := PackedFloat32Array()
var owners := PackedInt32Array()
var ground := PackedFloat32Array()
var values := PackedFloat32Array() # downhill Godot X/Z, bend, valid
var texture: ImageTexture
var _kernel: RefCounted
var _levels := PackedFloat32Array()
var builds := 0
var last_build_us := 0
var last_upload_us := 0
var conflicts := 0
var _task := -1
var _job: Build
var _requested := PackedFloat32Array()

class Build extends RefCounted:
	var size: Vector2i
	var base: PackedFloat32Array
	var owners: PackedInt32Array
	var ground: PackedFloat32Array
	var levels: PackedFloat32Array
	var values: PackedFloat32Array
	var calculate: Callable
	var elapsed_us := 0
	func run() -> void:
		var started := Time.get_ticks_usec()
		values = calculate.call(size,base,owners,ground,levels)
		elapsed_us = Time.get_ticks_usec()-started


func _init(terrain: EITerrain) -> void:
	size = Vector2i(terrain.sectors_x*32+1,terrain.sectors_y*32+1)
	base.resize(size.x*size.y); base.fill(INF)
	owners.resize(base.size()); owners.fill(-1)
	ground = terrain.heights
	for node in terrain.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Water_") or node.mesh == null: continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var materials: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		if vertices.size()%9 != 0 or materials.size() != vertices.size(): continue
		for first in range(0,vertices.size(),9):
			var tile := Vector2i(roundi(vertices[first].x/2.0),roundi(-vertices[first].z/2.0))
			if tile.x < 0 or tile.y < 0 or tile.x*2+2 >= size.x or tile.y*2+2 >= size.y: continue
			var cell := tile.y*2*(size.x-1)+tile.x*2
			var clear := not terrain.liquid_ground[cell] in [13,14,255]
			for lane in 9:
				var index := (tile.y*2+lane/3)*size.x+tile.x*2+lane%3
				var m := int(materials[first+lane].y+0.5)%64
				var h := vertices[first+lane].y
				var admitted := clear and m < terrain.materials.size() and terrain._lava[m] == 0.0
				if admitted:
					var emission := terrain.material_e(m)
					admitted = int(terrain.materials[m].get("type",0)) in [2,3] and emission.r+emission.g+emission.b == 0.0
					# The verified sea profiles use sloping shore overlays, not
					# authored river beds. Keep their existing surf/wind appearance.
					admitted = admitted and not m in EITerrain.SEA_MATERIALS.get(terrain.resource_prefix,[])
				# Mixed liquid edges or contradictory copies are deliberately
				# omitted, instead of inventing a join between moving layers.
				if not admitted or (owners[index] >= 0 and (owners[index] != m or absf(base[index]-h)>0.001)):
					if owners[index] != -2: conflicts += 1
					owners[index] = -2
				elif owners[index] != -2:
					owners[index] = m; base[index] = h
	if ClassDB.class_exists(&"WaterCurrentKernel") and not "--ei-script-water-current" in OS.get_cmdline_user_args():
		_kernel = ClassDB.instantiate(&"WaterCurrentKernel")
	refresh(terrain._level)


func refresh(levels: PackedFloat32Array, background := false) -> bool:
	if background and _kernel == null:
		_requested = levels.duplicate()
		if _task < 0 and (_levels != _requested or values.is_empty()): _start()
		return false
	clear()
	if levels == _levels and not values.is_empty(): return false
	_levels = levels.duplicate()
	var started := Time.get_ticks_usec()
	values = _kernel.build(size,base,owners,ground,_levels) if _kernel else build_script(size,base,owners,ground,_levels)
	last_build_us = Time.get_ticks_usec()-started
	return _upload()


func _upload() -> bool:
	if values.size() != base.size()*4: return false
	var started := Time.get_ticks_usec()
	var image := Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,values.to_byte_array())
	if texture == null: texture = ImageTexture.create_from_image(image)
	else: texture.update(image)
	last_upload_us = Time.get_ticks_usec()-started
	builds += 1
	return true


## Flooding can change every logic tick. On libraries without the compiled
## helper, keep at most one immutable worker snapshot plus the latest request;
## never enqueue a growing backlog or touch a texture from a worker. Completed
## fields may lag continuous flooding by a build, but final levels converge.
func _start() -> void:
	_job = Build.new()
	# Bind the static script, not this field instance: a completed worker's
	# Callable must not extend the terrain snapshot or GPU texture lifetime.
	_job.calculate = Callable(get_script(),"build_script")
	_job.size=size; _job.base=base; _job.owners=owners; _job.ground=ground
	_job.levels=_requested.duplicate()
	_task=WorkerThreadPool.add_task(_job.run,false,"Water current")


func poll() -> void:
	if _task<0 or not WorkerThreadPool.is_task_completed(_task): return
	WorkerThreadPool.wait_for_task_completion(_task); _task=-1
	values=_job.values; _levels=_job.levels; last_build_us=_job.elapsed_us
	_job.calculate=Callable()
	_job=null; _upload()
	if _requested!=_levels: _start()


func clear() -> void:
	if _task>=0: WorkerThreadPool.wait_for_task_completion(_task)
	if _job!=null: _job.calculate=Callable()
	_task=-1; _job=null; _requested=PackedFloat32Array()


## The scalar oracle is also the fallback for old/absent native libraries.
## Visible surface differences supply the gradient; the bed only excludes
## buried overlay edges. The 5x5 tent and bend use the reference's grid rules.
static func build_script(dim: Vector2i, rest: PackedFloat32Array, material: PackedInt32Array,
		bed: PackedFloat32Array, levels: PackedFloat32Array) -> PackedFloat32Array:
	var count := dim.x*dim.y
	if dim.x<1 or dim.y<1 or count>4194304 or rest.size()!=count or material.size()!=count or bed.size()!=count: return PackedFloat32Array()
	var heights := PackedFloat32Array(); heights.resize(count); heights.fill(INF)
	var gradient := PackedVector2Array(); gradient.resize(count)
	var active := PackedInt32Array()
	for i in count:
		var m := material[i]
		if m<0 or m>=levels.size(): continue
		var h := rest[i]+levels[m]
		if not is_finite(h) or not is_finite(bed[i]) or h<bed[i]-BURIED_TOLERANCE: continue
		heights[i]=h
		if not is_finite(heights[i]): continue
		active.append(i)
	for i in active:
		var x := i%dim.x; var y := i/dim.x
		var a := heights[i-1] if x>0 else INF
		var b := heights[i+1] if x+1<dim.x else INF
		var c := heights[i-dim.x] if y>0 else INF
		var d := heights[i+dim.x] if y+1<dim.y else INF
		gradient[i]=Vector2(difference(heights[i],a,b),difference(heights[i],c,d))
	var result := PackedFloat32Array(); result.resize(count*4)
	for i in active:
		var x := i%dim.x; var y := i/dim.x
		var sum := Vector2.ZERO; var weight := 0.0
		for dy in range(-2,3):
			if y+dy<0 or y+dy>=dim.y: continue
			for dx in range(-2,3):
				if x+dx<0 or x+dx>=dim.x: continue
				var j := i+dy*dim.x+dx
				if not is_finite(heights[j]): continue
				var w := (3-absi(dx))*(3-absi(dy))
				sum += gradient[j]*w; weight += w
		var bend := 0.0
		for axis in 2:
			var step := 2 if axis==0 else dim.x*2
			var coordinate := x if axis==0 else y
			var limit := dim.x if axis==0 else dim.y
			var left := coordinate>=2 and is_finite(heights[i-step])
			var right := coordinate+2<limit and is_finite(heights[i+step])
			var a := gradient[i-step] if left else gradient[i]
			var b := gradient[i+step] if right else gradient[i]
			var delta := (b-a)/(4.0 if left and right else 2.0)
			bend += delta.length_squared()
		result[i*4]=-sum.x/weight; result[i*4+1]=sum.y/weight
		result[i*4+2]=sqrt(bend); result[i*4+3]=1.0
	return result


static func difference(centre: float, left: float, right: float) -> float:
	if is_finite(left) and is_finite(right): return (right-left)*0.5
	if is_finite(left): return centre-left
	return right-centre if is_finite(right) else 0.0


## Godot world X/Z. Matches the vertex shader's bilinear, clamped grid fetch;
## the exact contact query still decides whether a creature touches water.
func sample(point: Vector2) -> Vector3:
	if not point.is_finite() or point.x<0 or point.y>0 or point.x>size.x-1 or -point.y>size.y-1 or values.is_empty(): return Vector3.ZERO
	var p := Vector2(point.x,-point.y)
	var x := mini(floori(p.x),size.x-2); var y := mini(floori(p.y),size.y-2)
	var a := value(y*size.x+x).lerp(value(y*size.x+x+1),p.x-x)
	var b := value((y+1)*size.x+x).lerp(value((y+1)*size.x+x+1),p.x-x)
	return a.lerp(b,p.y-y)


func value(index: int) -> Vector3:
	return Vector3(values[index*4],values[index*4+1],values[index*4+2])


static func velocity(current: Vector2) -> Vector2:
	var slope := current.length()
	return current*(minf(0.5+2.5*slope,4.0)*smoothstep(0.015,0.08,slope)/maxf(slope,0.00001))
