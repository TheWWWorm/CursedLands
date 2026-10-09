extends RefCounted
## Bounded visual history, shared by all admitted water contacts. The numerical
## field is independent of navigation/physics and never enters saves or packets.
## A 32 m window at 25 cm retains the reference's ~1 m/s propagation speed;
## older native libraries use the same scalar solver on one bounded worker.
const SIZE := 128
const CELL := 0.25
const STEP := 1.0/30.0
const COURANT := 0.0175
const DAMPING := 0.955
const TRAIL_DECAY := 0.9908
const MAX_STEPS := 8
const Current = preload("res://src/game/fx/water_current.gd")
const Surface = preload("res://src/game/fx/water_surface.gd")
var state := PackedFloat32Array() # height, previous height, trail, mean surface
var domain := PackedFloat32Array() # mean surface, flow x/z, material + 1 (0=dry)
var origin := Vector2i.ZERO # in wave cells, Godot X/Z
var texture: ImageTexture
var valid := false
var clock := -1.0
var accumulator := 0.0
var steps_done := 0
var uploads := 0
var last_step_us := 0
var last_domain_us := 0
var _levels := PackedFloat32Array()
var _flow_build := -1
var _quiet_since := -1.0
var _kernel: RefCounted
var _task := -1
var _job: Job
var _surface: Surface
var _cells := {}

class Job extends RefCounted:
	var solve: Callable
	var state: PackedFloat32Array
	var domain: PackedFloat32Array
	var sources: PackedVector4Array
	var weights: PackedVector2Array
	var origin: Vector2
	var steps: int
	var seconds: float
	var elapsed_us := 0
	func run() -> void:
		var start := Time.get_ticks_usec()
		state = solve.call(state,domain,sources,weights,origin,steps,seconds)
		elapsed_us = Time.get_ticks_usec()-start

func _init() -> void:
	if ClassDB.class_exists(&"WaterWaveKernel") and not "--ei-script-water-waves" in OS.get_cmdline_user_args():
		_kernel = ClassDB.instantiate(&"WaterWaveKernel")

func clear() -> void:
	if _task >= 0: WorkerThreadPool.wait_for_task_completion(_task)
	if _job: _job.solve = Callable()
	_task = -1; _job = null
	state = PackedFloat32Array(); domain = PackedFloat32Array(); texture = null
	valid = false; clock = -1; accumulator = 0; _quiet_since = -1
	_levels = PackedFloat32Array(); _flow_build = -1
	_surface = null; _cells.clear()

func _upload() -> void:
	if state.size() != SIZE*SIZE*4: return
	var image := Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGBAF,state.to_byte_array())
	if texture == null: texture = ImageTexture.create_from_image(image)
	else: texture.update(image)
	uploads += 1

func poll() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task): return
	WorkerThreadPool.wait_for_task_completion(_task); _task = -1
	state = _job.state; last_step_us = _job.elapsed_us; steps_done += _job.steps
	_job.solve = Callable(); _job = null
	_upload()

## Copy both heights and the trail in whole cells. Shifting a paused field
## cannot integrate it, and a teleport cannot connect the two water locations.
static func shifted(previous: PackedFloat32Array, delta: Vector2i) -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(SIZE*SIZE*4)
	if previous.size() != result.size() or absi(delta.x) >= SIZE or absi(delta.y) >= SIZE: return result
	for y in range(maxi(0,-delta.y),mini(SIZE,SIZE-delta.y)):
		for x in range(maxi(0,-delta.x),mini(SIZE,SIZE-delta.x)):
			var a := (y*SIZE+x)*4; var b := ((y+delta.y)*SIZE+x+delta.x)*4
			for k in 4: result[a+k] = previous[b+k]
	return result

func _domain(terrain: EITerrain) -> void:
	var start := Time.get_ticks_usec()
	domain.resize(SIZE*SIZE*4); domain.fill(0)
	# Navigation stores an upper corner, which can be metres above a sloping
	# river's visible surface. Query the actual unposed triangles instead.
	# Cache one height/gradient per metre; window motion samples only new strips.
	# Keep only this window's cells, not a growing map-wide history.
	if _surface == null: _surface = Surface.new(terrain)
	_surface.begin_frame(false)
	var cells := {}; var samples := {}; var width := terrain.sectors_x*32
	var flow: RefCounted = terrain._current
	for y in SIZE:
		for x in SIZE:
			var point := (Vector2(origin)+Vector2(x+0.5,y+0.5))*CELL
			var cell := Vector2i(floori(point.x),floori(-point.y))
			if not cells.has(cell):
				var value := Vector4.ZERO
				var sample := {}
				if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < terrain.sectors_y*32:
					var at := cell.y*width+cell.x
					var midpoint := Vector2(cell.x+0.5,-cell.y-0.5)
					if not terrain.liquid_ground[at] in [13,14,255]:
						sample = _cells[cell] if _cells.has(cell) else _surface.sample(midpoint)
					var m := int(sample.get("material",-1))
					var h := float(sample.get("height",-INF))
					if m >= 0 and m < terrain.materials.size() and is_finite(h) and not sample.get("lava",false):
						var e := terrain.material_e(m)
						if int(terrain.materials[m].get("type",0)) in [2,3] and e.r+e.g+e.b == 0.0 and terrain._lava[m] == 0.0 and h > terrain.height_at(cell.x+0.5,cell.y+0.5)+0.04:
							var velocity := Vector2.ZERO
							if flow:
								var gradient: Vector3 = flow.sample(Vector2(cell.x+0.5,-cell.y-0.5))
								velocity = Current.velocity(Vector2(gradient.x,gradient.y))
							value = Vector4(h,velocity.x,velocity.y,m+1)
				cells[cell] = value; samples[cell] = sample
			var value: Vector4 = cells[cell]; var at := (y*SIZE+x)*4
			if value.w > 0:
				var slope: Vector2 = samples[cell].slope
				value.x+=slope.dot(point-Vector2(cell.x+0.5,-cell.y-0.5))
			domain[at]=value.x; domain[at+1]=value.y; domain[at+2]=value.z; domain[at+3]=value.w
	_cells=samples
	_levels = terrain._level.duplicate(); _flow_build = flow.builds if flow else -1
	last_domain_us = Time.get_ticks_usec()-start

## Sources contain position X/Z, body radius and metres/second; weights are
## current presence and stable phase. Only currently visible contacts stamp.
func advance(terrain: EITerrain, seconds: float, centre: Vector2,
		sources: PackedVector4Array, weights: PackedVector2Array) -> void:
	if not is_finite(seconds) or not centre.is_finite(): return
	if clock >= 0 and (seconds < clock or seconds-clock > 0.5): clear()
	# A queued old-level solve must never be published after flooding, even
	# if the worker finishes on this same frame.
	if valid and terrain._level != _levels: clear()
	poll()
	var elapsed := maxf(0,seconds-clock) if clock >= 0 else 0.0
	clock = seconds; accumulator = minf(accumulator+elapsed,MAX_STEPS*STEP)
	if sources.is_empty():
		if not valid: return
		if _quiet_since < 0: _quiet_since = seconds
		if seconds-_quiet_since > 25.0: clear(); return
	else: _quiet_since = -1
	# A busy scalar worker owns one immutable snapshot; the next request uses
	# the latest sources and bounded elapsed time. No growing work queue.
	if _task >= 0: return
	var next := origin
	if not sources.is_empty():
		var target := Vector2i(floori(centre.x/CELL)-SIZE/2,floori(centre.y/CELL)-SIZE/2)
		if not valid or absi(target.x-origin.x)>16 or absi(target.y-origin.y)>16: next=target
	var moved := not valid or next != origin
	var flooding := valid and terrain._level != _levels
	var flow: RefCounted = terrain._current
	var flow_changed: bool = (flow.builds if flow else -1) != _flow_build
	if moved or flooding or flow_changed:
		state = shifted(state,next-origin) if valid and not flooding else shifted(PackedFloat32Array(),Vector2i.ZERO)
		origin=next; valid=true; _domain(terrain)
		for i in SIZE*SIZE:
			if domain[i*4+3] == 0.0:
				state[i*4]=0; state[i*4+1]=0; state[i*4+2]=0
			state[i*4+3]=domain[i*4]
		_upload()
	var steps := mini(MAX_STEPS,floori((accumulator+0.0000001)/STEP))
	if steps == 0: return
	accumulator = maxf(0,accumulator-steps*STEP)
	if _kernel:
		var start := Time.get_ticks_usec()
		state = _kernel.step(state,domain,sources,weights,Vector2(origin)*CELL,steps,seconds-accumulator)
		last_step_us=Time.get_ticks_usec()-start; steps_done+=steps; _upload()
	else:
		_job=Job.new(); _job.solve=Callable(get_script(),"solve")
		_job.state=state; _job.domain=domain; _job.sources=sources; _job.weights=weights
		_job.origin=Vector2(origin)*CELL; _job.steps=steps; _job.seconds=seconds-accumulator
		_task=WorkerThreadPool.add_task(_job.run,false,"Water waves")

func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("water_wave_field",texture)
	material.set_shader_parameter("water_wave_window",Vector4(origin.x*CELL,origin.y*CELL,1.0/(SIZE*CELL),1.0 if texture else 0.0))

static func compatible(domain: PackedFloat32Array, a: int, b: int) -> bool:
	return domain[b*4+3] == domain[a*4+3] and absf(domain[b*4]-domain[a*4]) < 0.75

static func trail_at(state: PackedFloat32Array, domain: PackedFloat32Array, at: int, p: Vector2) -> float:
	if p.x < -1 or p.y < -1 or p.x >= SIZE or p.y >= SIZE: return 0.0
	var x := floori(p.x); var y := floori(p.y); var f := p-Vector2(x,y); var result := 0.0
	for dy in 2:
		for dx in 2:
			if x+dx < 0 or y+dy < 0 or x+dx >= SIZE or y+dy >= SIZE: continue
			var j := (y+dy)*SIZE+x+dx
			if compatible(domain,at,j): result+=state[j*4+2]*(f.x if dx else 1.0-f.x)*(f.y if dy else 1.0-f.y)
	return result

## Scalar oracle and compatibility fallback. Pressure is stamped only over a
## body's small footprint, avoiding a 16-body loop across every water cell.
static func solve(previous: PackedFloat32Array, domain: PackedFloat32Array, sources: PackedVector4Array,
		weights: PackedVector2Array, origin: Vector2, steps: int, seconds: float) -> PackedFloat32Array:
	if previous.size()!=SIZE*SIZE*4 or domain.size()!=previous.size() or sources.size()!=weights.size() or sources.size()>16 or steps<0 or steps>MAX_STEPS or not origin.is_finite() or not is_finite(seconds): return PackedFloat32Array()
	for i in previous.size():
		if not is_finite(previous[i]) or not is_finite(domain[i]): return PackedFloat32Array()
	var state := previous
	for tick in steps:
		var next := PackedFloat32Array(); next.resize(state.size())
		for y in range(1,SIZE-1):
			for x in range(1,SIZE-1):
				var i := y*SIZE+x; var at := i*4
				if domain[at+3] <= 0.0: continue
				var lap := -4.0*state[at]
				for j in [i-1,i+1,i-SIZE,i+SIZE]:
					if compatible(domain,i,j): lap+=state[j*4]
				var fade := minf(mini(mini(x,y),mini(SIZE-1-x,SIZE-1-y))/6.0,1.0)
				next[at]=clampf((2.0*state[at]-state[at+1]+COURANT*lap)*DAMPING*fade,-0.15,0.15)
				next[at+1]=state[at]*fade
				var velocity := Vector2(domain[at+1],domain[at+2])
				next[at+2]=trail_at(state,domain,i,Vector2(x,y)-velocity*(STEP/CELL))*TRAIL_DECAY*fade
				next[at+3]=domain[at]
		var time := seconds-(steps-1-tick)*STEP
		for u in sources.size():
			var source := sources[u]; var weight := weights[u]
			if not source.is_finite() or not weight.is_finite(): continue
			var radius := clampf(source.z,0.25,2.0)
			var pos := (Vector2(source.x,source.y)-origin)/CELL-Vector2(0.5,0.5)
			var push := (0.0007*clampf(source.w,0,5)+0.0006*sin(time*5.0+weight.y))*clampf(source.z/0.35,0.15,5.0)*clampf(weight.x,0,1)
			var reach := radius/CELL
			if pos.x+reach<1 or pos.y+reach<1 or pos.x-reach>SIZE-2 or pos.y-reach>SIZE-2: continue
			for y in range(maxi(1,floori(pos.y-reach)),mini(SIZE-1,ceili(pos.y+reach)+1)):
				for x in range(maxi(1,floori(pos.x-reach)),mini(SIZE-1,ceili(pos.x+reach)+1)):
					var at := (y*SIZE+x)*4
					if domain[at+3] <= 0.0: continue
					var d2 := Vector2(x-pos.x,y-pos.y).length_squared()/(reach*reach)
					if d2 >= 1.0: continue
					var edge := minf(mini(mini(x,y),mini(SIZE-1-x,SIZE-1-y))/6.0,1.0)
					next[at]=clampf(next[at]-push*(1.0-d2)*(1.0-d2)*edge,-0.15,0.15)
					next[at+2]=maxf(next[at+2],maxf(0.0,1.0-d2/0.5625)*clampf(weight.x,0,1)*edge)
		state=next
	return state
