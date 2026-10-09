extends RefCounted
## Bounded, presentation-only grass pressure. A small toroidal texture avoids
## a loop over units for every blade vertex. Sparse CPU history recovers in
## game seconds; world-coordinate cells keep camera/chunk movement continuous.
const SIDE := 128
const CELL := 0.5
const WIDTH := SIDE*CELL
const INTERVAL := 0.05
const RELAX := 0.55
const MAX_UNITS := 32
const MAX_CELLS := 4096
const PUSH := 0.35
var texture: ImageTexture
var _pixels := PackedByteArray()
var _cells := {} # world cell -> premultiplied horizontal push and pressure
var _previous := {} # visible contact identity -> previous root and presence
var _last_time := -1.0
var _pending := 0.0
var focus := Vector2.ZERO # Godot world XZ
var updates := 0
var last_update_us := 0
var last_contacts := 0


func _init() -> void:
	_pixels.resize(SIDE*SIDE*4)
	for i in SIDE*SIDE: _pixels[i*4] = 128; _pixels[i*4+1] = 128
	texture = ImageTexture.create_from_image(_image())


func _image() -> Image:
	return Image.create_from_data(SIDE,SIDE,false,Image.FORMAT_RGBA8,_pixels)


func _write(cell: Vector2i, value: Vector3) -> void:
	var at := (posmod(cell.y,SIDE)*SIDE+posmod(cell.x,SIDE))*4
	_pixels[at] = roundi(clampf(value.x*0.5+0.5,0.0,1.0)*255.0)
	_pixels[at+1] = roundi(clampf(value.y*0.5+0.5,0.0,1.0)*255.0)
	_pixels[at+2] = roundi(clampf(value.z,0.0,1.0)*255.0)


func clear() -> void:
	for cell: Vector2i in _cells: _write(cell,Vector3.ZERO)
	_cells.clear(); _previous.clear(); _pending = 0.0
	texture.update(_image()); updates += 1


static func shown(u: GameUnit) -> bool:
	return is_instance_valid(u) and u.is_inside_tree() and u.is_visible_in_tree() \
		and not u.hidden and not u.fogged and not u.dead and is_instance_valid(u.model) and u.model.is_visible_in_tree()


static func posed_bounds(u: GameUnit) -> AABB:
	var result := AABB(Vector3.INF,Vector3.ZERO)
	for part in u._geoms:
		if not is_instance_valid(part) or not part is MeshInstance3D or not part.is_visible_in_tree() or part.mesh == null: continue
		var box: AABB = part.get_global_transform_interpolated()*part.get_aabb()
		result = result.merge(box) if result.position.is_finite() else box
	return result


func contacts(details: TerrainDetails, world: GameWorld) -> Array[Dictionary]:
	var nearby := []
	for u: GameUnit in world.visible_units():
		if not shown(u) or not u.near_screen(): continue
		var root := u.get_global_transform_interpolated().origin
		var p := Vector2(root.x,root.z)
		if (p-focus).abs().x > WIDTH*0.5-3.0 or (p-focus).abs().y > WIDTH*0.5-3.0: continue
		nearby.append({"unit":u,"root":root,"distance":p.distance_squared_to(focus),"id":u.get_instance_id()})
	nearby.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance < b.distance if a.distance != b.distance else a.id < b.id)
	var out: Array[Dictionary] = []
	# Keep both pose queries and accepted contacts bounded, even in a crowd.
	for i in mini(MAX_UNITS,nearby.size()):
		var record: Dictionary = nearby[i]; var u: GameUnit = record.unit
		var p := Vector2(record.root.x,-record.root.z)
		if not details.vegetation_allowed(p): continue
		var height: float = details.surface_sample(p).height
		var box := posed_bounds(u)
		# A navigation root on the land is insufficient for levitating models.
		# The same guard excludes bridge occupants above the underlying grass.
		if not box.position.is_finite() or box.position.y > height+0.22 or box.end.y < height: continue
		var radius := clampf(u.figure_radius*0.7,0.18,0.8)
		var length := radius
		var centre := Vector2(record.root.x,record.root.z)
		if u.stance == GameUnit.STANCE_CRAWL:
			length = clampf(maxf(box.size.x,box.size.z)*0.45,radius,1.2)
			centre = Vector2(box.get_center().x,box.get_center().z)
		out.append({"id":record.id,"p":centre,
			"extent":Vector2(length,radius),"angle":-u.facing})
	return out


func update(details: TerrainDetails, world: GameWorld, centre: Vector2, seconds: float) -> void:
	var dt := seconds-_last_time if _last_time >= 0.0 else 0.0
	_last_time = seconds
	if world == null or not world.can_process(): return
	var session := world.session
	if session and (session.loading_game or session._zone_holding or session._remote_loading or session.movie_active()): return
	if session and session.lmp_travel and not session.lmp_travel.can_tick(world): return
	if dt <= 0.0 or not is_finite(dt): return
	if dt > 0.25: clear(); dt = INTERVAL
	_pending += dt
	if _pending+0.0000001 < INTERVAL: return
	var started := Time.get_ticks_usec()
	focus = centre
	var inputs := contacts(details,world)
	advance(inputs,focus,_pending); _pending = 0.0
	last_update_us = Time.get_ticks_usec()-started


## Also used by the deterministic contact/history fixture. Inputs contain
## only already-admitted visible geometry; no unit or scene state is modified.
func advance(inputs: Array[Dictionary], centre: Vector2, dt: float) -> void:
	if dt <= 0.0 or not is_finite(dt): return
	focus = centre
	last_contacts = mini(MAX_UNITS,inputs.size())
	if _cells.is_empty() and inputs.is_empty(): return
	var decay := exp(-dt/RELAX)
	for cell: Vector2i in _cells.keys():
		var value: Vector3 = _cells[cell]*decay
		var offset := (Vector2(cell)*CELL+Vector2.ONE*CELL*0.5-focus).abs()
		if value.z < 1.0/255.0 or maxf(offset.x,offset.y) >= WIDTH*0.5-1.0:
			_cells.erase(cell); _write(cell,Vector3.ZERO)
		else: _cells[cell] = value; _write(cell,value)
	var current := {}
	for i in mini(MAX_UNITS,inputs.size()):
		var input: Dictionary = inputs[i]
		var previous: Dictionary = _previous.get(input.id,{"p":input.p,"presence":0.0})
		var distance := (input.p as Vector2).distance_to(previous.p)
		if distance > 2.0: previous = {"p":input.p,"presence":0.0}; distance = 0.0
		var presence := minf(float(previous.presence)+dt/0.2,1.0)
		var samples := maxi(1,ceili(distance/(CELL*0.5)))
		for sample in samples:
			_stamp((previous.p as Vector2).lerp(input.p,float(sample+1)/samples),input.extent,float(input.angle),presence)
		current[input.id] = {"p":input.p,"presence":presence}
	_previous = current
	texture.update(_image()); updates += 1


func _stamp(p: Vector2, extent: Vector2, angle: float, presence: float) -> void:
	var radius := maxf(extent.x,extent.y)+CELL
	var first := Vector2i(((p-Vector2.ONE*radius)/CELL).floor())
	var last := Vector2i(((p+Vector2.ONE*radius)/CELL).floor())
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell := Vector2i(x,y)
			var location := (Vector2(cell)+Vector2.ONE*0.5)*CELL
			var offset := (location-focus).abs()
			if maxf(offset.x,offset.y) >= WIDTH*0.5-1.0: continue
			var delta := location-p
			# Half a texel of support yields smooth sub-cell motion after the
			# GPU's linear filtering, including narrow standing figures.
			var q := delta.rotated(-angle)/(extent+Vector2.ONE*CELL*0.5)
			var weight := (1.0-smoothstep(0.15,1.0,q.length()))*presence
			if weight <= 1.0/255.0: continue
			var direction := delta.normalized() if delta.length_squared() > 0.00001 else Vector2.from_angle(angle+PI*0.5)
			var old: Vector3 = _cells.get(cell,Vector3.ZERO)
			if weight <= old.z: continue
			if not _cells.has(cell) and _cells.size() >= MAX_CELLS: continue
			var value := Vector3(direction.x*weight,direction.y*weight,weight)
			_cells[cell] = value; _write(cell,value)


const UNIFORMS := """
uniform sampler2D vegetation_pressure : filter_linear, repeat_enable;
uniform vec2 vegetation_focus = vec2(0.0);
"""
const DEFORM := """
	vec2 pressure_distance = abs(origin.xz-vegetation_focus);
	float pressure_fade = 1.0-smoothstep(27.0,30.0,max(pressure_distance.x,pressure_distance.y));
	vec3 pressure = texture(vegetation_pressure,origin.xz/64.0).rgb;
	float pressed = pressure.b*pressure_fade;
	vec2 push = (pressure.rg*2.0-1.0)*pressure_fade*step(0.001,pressure.b);
	VERTEX += transpose(MODEL_NORMAL_MATRIX)*vec3(push.x,0.0,push.y)*0.35*tip*tip*fade*present;
	VERTEX.y *= 1.0-pressed*tip*0.50;
"""


static func source(original: String) -> String:
	return original.replace("void vertex() {",UNIFORMS+"\nvoid vertex() {").replace("\t// A grass bed follows",DEFORM+"\t// A grass bed follows")
