class_name WikiScenePreview
extends SubViewportContainer
## Reference-only scenery. No Session, GameWorld, script VM or player units.
var viewport: SubViewport
var camera: Camera3D
var model: Node3D
var _center := Vector3.ZERO
var _distance := 1.0
var _angle := 0.0
var _zoom := 1.0
var _scene := false
var _pose := Transform3D.IDENTITY
var _bounds := AABB()
var _environment: Environment
var _light: DirectionalLight3D
var _zone := {}

func show_descriptor(descriptor: Dictionary) -> bool:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(640,480)
	viewport.transparent_bg = descriptor.kind == "allod"
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR if descriptor.kind == "scene" else Environment.BG_CLEAR_COLOR
	environment.environment.background_color = Color("26332c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	_environment = environment.environment
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = .7
	_light = light
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.near = .1
	camera.far = 2000
	camera.fov = 50
	viewport.add_child(camera)
	var campaign := CampaignMap.load_from(GameData.texts)
	_scene = descriptor.kind == "scene"
	if _scene:
		var zone := campaign.zone(descriptor.value)
		_zone = zone
		model = EIMapScene.load_map(zone.get("mpr", ""), zone.get("mob", ""))
		if model == null: return false
		viewport.add_child(model)
		# Frame the authored village centre. Some old camera tracks start inside
		# scenery, so copying their first key does not make a useful still.
		# This is an illustration, never a north-up map with position pins.
		var terrain: EITerrain = model.terrain
		var extent: Vector2 = terrain.size_ei()
		var restriction: Vector3 = zone.get("restrict", Vector3(extent.x*.5,extent.y*.5,20))
		_center = EISpace.pos(restriction.x,restriction.y,terrain.height_at(restriction.x,restriction.y))
		var radius := clampf(restriction.z,10,26)
		camera.position = _center + Vector3(0,radius*1.6,radius*.85)
		camera.look_at(_center)
		_pose = camera.transform
		camera.transform = _pose
	else:
		model = Node3D.new()
		viewport.add_child(model)
		var id := String(descriptor.value)
		var figures: PackedStringArray = campaign.allods.get(id, PackedStringArray())
		if figures.size() < 4: return false
		_add_figure(figures[3], id+"mapg")
		for zone: Dictionary in campaign.zones.values():
			if zone.get("allod", "") == id and zone.get("type", "") == "game" and zone.get("figure", ""):
				_add_figure(String(zone.figure).to_lower(), id+"map")
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		if first: return false
		_center = bounds.get_center()
		_bounds = bounds
		_distance = maxf(bounds.size.length()*2,.1)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_update()
	return true

func apply_reference_lighting() -> void:
	# Offline illustration exporter only. Live previews never change global
	# lighting, fog, time, player state or the running world's environment.
	if not _scene: return
	var cave: bool = _zone.get("sky", "") == "cave"
	var lights := EILights.load_for(_zone.get("allod", ""), cave)
	Gfx.update_original(_environment, _light, lights, 12.0, cave)
	_environment.background_color = lights.sample("sky", 0.0 if cave else 12.0) if lights else Color("52625a")

func _add_figure(name: String, texture: String) -> void:
	var figure := EIFigure.instantiate(name,texture,Vector3.ZERO)
	if figure == null: return
	model.add_child(figure)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = GameData.get_texture(texture)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	for mesh: MeshInstance3D in figure.find_children("*","MeshInstance3D",true,false): mesh.material_override = material

func turn_by(amount: float) -> void:
	_angle += amount
	_update()

func zoom_to(value: float) -> void:
	_zoom = value
	_update()

func _update() -> void:
	if camera == null: return
	if _scene:
		camera.transform = _pose
		camera.fov = clampf(50*_zoom,25,85)
	else:
		camera.position = _center + Vector3(sin(_angle)*.5, .85, cos(_angle)*.5).normalized()*_distance*_zoom
		camera.look_at(_center)
		var local_view := camera.global_transform.affine_inverse()
		var projected := Rect2()
		var first := true
		for x in 2:
			for y in 2:
				for z in 2:
					var point := local_view * (_bounds.position + _bounds.size*Vector3(x,y,z))
					var screen := Vector2(point.x,point.y)
					projected = Rect2(screen,Vector2.ZERO) if first else projected.expand(screen)
					first = false
		var aspect := maxf(float(viewport.size.x)/maxf(viewport.size.y,1),.1)
		camera.size = maxf(projected.size.y,projected.size.x/aspect)*1.12*_zoom
	camera.force_update_transform()
