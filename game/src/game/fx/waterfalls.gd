extends Node3D
## Optional terrain-owned waterfall presentation. No nodes/field/shaders are
## allocated while disabled; terrain drives its existing pausable wave clock.
const Field = preload("res://src/game/fx/waterfall_field.gd")
const Programs = preload("res://src/game/fx/waterfall_shader.gd")
const Surface = preload("res://src/game/fx/water_surface.gd")
const MAX_SHELL_VERTICES := 24576
const MAX_SITE_VERTICES := 2046
const MAX_SPRITES := 1536
const WATER_PARAMETERS := [&"level",&"mat_e",&"mat_a",&"mat_wave",&"mat_rgb",&"mat_type",&"sine_tex",&"phase_tex",&"waves"]
const CLOCK_PARAMETERS := [&"wave_phase",&"wave_ticks",&"wave_amplitude",&"wave_gradient",&"wind"]
var field: Field
var shell_vertices := 0
var sprites := 0
var sites := []
var rebuilds := 0
var _terrain: EITerrain
var _shell: ShaderMaterial
var _spray: ShaderMaterial
var _dirty := false
var _surface: Surface


func configure(terrain: EITerrain) -> void:
	name = "Waterfalls"; _terrain = terrain
	set_process(false)
	_surface = null
	field = Field.new(terrain)
	_rebuild()


## Called at the end of terrain.apply_gfx, after all water uniforms exist.
func sync_parameters() -> void:
	if _shell and is_instance_valid(_terrain) and _terrain._water_mat:
		for key: StringName in WATER_PARAMETERS:
			var value: Variant = _terrain._water_mat.get_shader_parameter(key)
			if value != null: _shell.set_shader_parameter(key,value)
	advance()


func advance() -> void:
	if not is_instance_valid(_terrain) or _terrain._water_mat == null: return
	var clock := fposmod(_terrain._waves.time_ticks()*EIWaterWaves.TICK,16.0)
	if _shell:
		for key: StringName in CLOCK_PARAMETERS:
			_shell.set_shader_parameter(key,_terrain._water_mat.get_shader_parameter(key))
		_shell.set_shader_parameter("fall_clock",clock)
	if _spray: _spray.set_shader_parameter("fall_clock",clock)


func request_refresh() -> void:
	if _dirty: return
	_dirty = true
	# Hide stale lips immediately while several SetWaterLevel writes coalesce.
	visible = false
	_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	if not is_instance_valid(_terrain) or field == null: return
	if field.refresh(_terrain._level): _rebuild()
	else: sync_parameters()
	visible = true


func _exit_tree() -> void:
	if _surface: _surface.clear()
	_surface = null
	field = null; _terrain = null; _shell = null; _spray = null


func _rebuild() -> void:
	for child in get_children(): child.free()
	shell_vertices = 0; sprites = 0; sites.clear(); rebuilds += 1
	if field.falls.is_empty():
		_shell = null; _spray = null; return
	if _shell == null:
		_shell = ShaderMaterial.new(); _shell.shader = Programs.shell()
		_shell.render_priority = ParticleFx.RENDER_PRIORITY
		_spray = ShaderMaterial.new(); _spray.shader = Programs.spray()
		_spray.render_priority = ParticleFx.RENDER_PRIORITY+1
	# Preserve the existing bounded, weak-mesh triangle index across floods.
	# begin_frame invalidates posed vertices, so every new level is evaluated.
	if _surface == null: _surface = Surface.new(_terrain)
	_surface.begin_frame(false)
	for fall: Dictionary in field.falls:
		var arrays := _shell_arrays(fall)
		if arrays[Mesh.ARRAY_VERTEX].is_empty(): continue
		var node := _draw(arrays,_shell,"Foam_%d"%int(fall.id))
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		shell_vertices += count
		var spray := _spray_arrays(fall,_surface)
		var number: int = spray[Mesh.ARRAY_VERTEX].size()/6
		if number: _draw(spray,_spray,"Spray_%d"%int(fall.id))
		sprites += number
		var roles := [0,0,0]
		for i in range(0,spray[Mesh.ARRAY_COLOR].size(),6): roles[roundi(spray[Mesh.ARRAY_COLOR][i].b*3.0)] += 1
		sites.append({"id":fall.id,"shell_vertices":count,"sprites":number,"lip":roles[0],"impact":roles[1],"mist":roles[2],"bounds":str(node.get_aabb())})
	sync_parameters()


func _draw(arrays: Array, material: ShaderMaterial, label: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name = label; node.mesh = mesh; node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 4.0
	node.visibility_range_end = 110.0
	add_child(node)
	return node


static func _arrays() -> Array:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(); arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(); arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	return arrays


func _shell_arrays(fall: Dictionary) -> Array:
	var arrays := _arrays()
	var direction: Vector2 = fall.direction; var side := Vector2(-direction.y,direction.x)
	var limit := mini(MAX_SITE_VERTICES,MAX_SHELL_VERTICES-shell_vertices)
	var half_width: float = fall.width*0.5
	var lo: Vector2 = fall.lip-direction*1.8-side*(half_width+1.0)
	var hi := lo
	for along in [-1.8,float(fall.run)+1.8]:
		for across in [-half_width-1.0,half_width+1.0]:
			var p: Vector2 = fall.lip+direction*along+side*across
			lo = lo.min(p); hi = hi.max(p)
	for sy in range(maxi(0,floori(lo.y/32.0)),mini(_terrain.sectors_y,floori(hi.y/32.0)+1)):
		for sx in range(maxi(0,floori(lo.x/32.0)),mini(_terrain.sectors_x,floori(hi.x/32.0)+1)):
			var water := _terrain.get_node_or_null("Water_%d_%d"%[sx,sy]) as MeshInstance3D
			if water == null or water.mesh == null: continue
			var source := water.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
			var materials: PackedVector2Array = source[Mesh.ARRAY_TEX_UV2]
			var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
			for first in range(0,indices.size(),3):
				if arrays[Mesh.ARRAY_VERTEX].size()+3 > limit: return arrays
				var alpha := PackedFloat32Array(); var coords := PackedVector2Array(); var any_visible := false
				for k in 3:
					var i := indices[first+k]; var v := vertices[i]
					var p := Vector2(v.x,-v.z); var relative: Vector2 = p-fall.lip
					var along := relative.dot(direction); var across := relative.dot(side)
					var m := int(materials[i].y+0.5)%64
					var h := v.y+field.levels[m]
					var a := clampf((half_width+0.3-absf(across))/0.65,0.0,1.0)
					a *= clampf((along+1.0)/0.8,0.0,1.0)*clampf((fall.run+1.1-along)/0.8,0.0,1.0)
					if h < field.ground_at(p)-0.04 or h > fall.top+0.4 or h < fall.bottom-0.4 or _terrain._lava[m] > 0.0: a = 0.0
					if m >= _terrain.materials.size() or not int(_terrain.materials[m].get("type",0)) in [2,3,4] or float(_terrain.materials[m].get("self_illum",0.0))>0.0: a = 0.0
					var drop := maxf(0.0,fall.top-h)
					var travel := (sqrt(2.56+19.6*drop)-1.6)/9.8
					if along < 0.0: travel = along/1.6
					elif along > fall.run: travel += (along-fall.run)*0.18
					alpha.append(a); coords.append(Vector2(across,travel)); any_visible = any_visible or a > 0.0
				if not any_visible: continue
				for k in 3:
					var i := indices[first+k]
					arrays[Mesh.ARRAY_VERTEX].append(vertices[i]); arrays[Mesh.ARRAY_NORMAL].append(normals[i])
					arrays[Mesh.ARRAY_TEX_UV].append(coords[k]); arrays[Mesh.ARRAY_TEX_UV2].append(materials[i])
					arrays[Mesh.ARRAY_COLOR].append(Color(1,1,1,alpha[k]))
	return arrays


## Exact authored triangles locate emitters; a navigation water cell can be
## metres above the visible sloping water. Only exposed near-level anchors
## admit spray, so a missing pool does not get a floating mist bank.
func _anchor(fall: Dictionary, surface: Surface, across: float, impact: bool) -> Vector3:
	var direction: Vector2 = fall.direction; var side := Vector2(-direction.y,direction.x)
	var start: float = fall.run-0.3 if impact else -0.8
	var desired: float = fall.bottom if impact else fall.top
	for k in 13:
		var p: Vector2 = fall.lip+side*across+direction*(start+float(k)*0.1)
		var hit: Dictionary = surface.sample(Vector2(p.x,-p.y))
		if hit.is_empty() or hit.lava or absf(float(hit.height)-desired)>0.35: continue
		if float(hit.height)<field.ground_at(p)+0.02: continue
		return Vector3(p.x,float(hit.height)+0.09,-p.y)
	return Vector3(INF,INF,INF)


func _spray_arrays(fall: Dictionary, surface: Surface) -> Array:
	var arrays := _arrays()
	var direction: Vector2 = fall.direction
	var counts := [clampi(ceili(fall.width*7.0),12,36),clampi(ceili(fall.width*8.0),14,40),clampi(ceili(fall.width*3.0),6,20)]
	var limit := MAX_SPRITES-sprites
	for role in 3:
		for i in counts[role]:
			if arrays[Mesh.ARRAY_VERTEX].size()/6 >= limit: return arrays
			var seed := fposmod(float(i+int(fall.id)*3+role*71)*0.61803398875,1.0)
			var across := (float(i)+0.5)/float(counts[role])-0.5
			var anchor := _anchor(fall,surface,across*fall.width*0.85,role>0)
			if not anchor.is_finite(): continue
			for uv: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(0,1),Vector2(1,0),Vector2(1,1)]:
				arrays[Mesh.ARRAY_VERTEX].append(anchor)
				arrays[Mesh.ARRAY_NORMAL].append(Vector3(direction.x,0,-direction.y))
				arrays[Mesh.ARRAY_TEX_UV].append(uv); arrays[Mesh.ARRAY_TEX_UV2].append(Vector2.ZERO)
				arrays[Mesh.ARRAY_COLOR].append(Color(seed,1,float(role)/3.0,1))
	return arrays
