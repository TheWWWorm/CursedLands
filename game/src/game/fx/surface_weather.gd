class_name SurfaceWeather
extends Node
## Optional rain response, fed by the existing client precipitation fade.
## Wetness is visual only: navigation, terrain data and weather simulation
## stay unchanged. Sheltering solids are rasterized once, a few per frame.

const WET_SECONDS := 18.0
const DRY_SECONDS := 80.0
const COVER_BATCH := 8
const COVER_BUDGET_US := 2000
const UNCOVERED := -10000.0

var game: Game
var wetness := 0.0
var rain := 0.0
var _world: GameWorld
var _enabled := false
var _cover_queue: Array = []
var _cover_heights := PackedFloat32Array()
var _cover_cursor := 0
var _cover_ready := false
var _object_count := -1
var _rescan := 0.0


func _init(g: Game) -> void:
	game = g
	name = "SurfaceWeather"


func _ready() -> void:
	GameData.options_changed.connect(_on_options)
	_on_options()


func _exit_tree() -> void:
	Gfx.set_surface_weather(0.0, 0.0)


func _on_options() -> void:
	var enabled := Gfx.on("gfx_weather_surfaces")
	if enabled != _enabled or not enabled:
		wetness = 0.0
		rain = 0.0
		Gfx.set_surface_weather(0.0, 0.0)
	_enabled = enabled


func _process(dt: float) -> void:
	var world: GameWorld = game.world if is_instance_valid(game) else null
	if world != _world:
		_world = world
		wetness = 0.0
		rain = 0.0
		_cover_queue.clear()
		_cover_heights.clear()
		_cover_ready = false
		_object_count = -1
		_rescan = 0.0
		Gfx.set_surface_weather(0.0, 0.0)
	if not _enabled or not is_instance_valid(world):
		return
	# A cave remains dry even if a scripted client event requests rain.
	if String(world.zone.get("sky", "")).to_lower() == "cave":
		wetness = 0.0
		rain = 0.0
		Gfx.set_surface_weather(0.0, 0.0)
		return
	_rescan -= dt
	if _rescan <= 0.0:
		_rescan = 1.0
		if world.objects.size() != _object_count:
			_begin_cover(world)
	_step_cover(world.terrain)
	var snd: GameSound = game.sound
	var weather: Weather = snd.weather if is_instance_valid(snd) else null
	# GameSound changes zones before this node runs, but guard the handoff
	# too so one old rain frame cannot dampen the incoming map.
	if weather and weather.world == world:
		rain = rain_intensity(weather, snd._ticks + snd._tick_acc / GameSound.TICK)
	else:
		rain = 0.0
	wetness = advance_wetness(wetness, rain, dt)
	# Do not flash raindrops under a roof while its map is still being built
	# on the first rainy frames after arriving in a zone.
	Gfx.set_surface_weather(wetness if _cover_ready else 0.0, rain if _cover_ready else 0.0)


## Same cosine fade that FxRainSnow uses to reveal precipitation particles;
## snow contributes no rain, and the fade endpoint does not depend on the
## order in which Weather.tick and this controller happen to run.
static func rain_intensity(weather: Weather, now: float) -> float:
	if weather == null or weather._shown != 1:
		return 0.0
	if weather._fade <= 0.0:
		return 1.0 if weather._target == 1 else 0.0
	var f := clampf((now - weather._start) / weather._fade, 0.0, 1.0)
	var amount := (1.0 - cos(f * PI)) * 0.5
	return amount if weather._target == 1 else 1.0 - amount


static func advance_wetness(current: float, intensity: float, dt: float) -> float:
	var target := clampf(intensity, 0.0, 1.0)
	var seconds := WET_SECONDS if target > current else DRY_SECONDS
	return move_toward(clampf(current, 0.0, 1.0), target, maxf(dt, 0.0) / seconds)


func _begin_cover(world: GameWorld) -> void:
	_object_count = world.objects.size()
	_cover_queue = world.objects.values()
	_cover_cursor = 0
	_cover_heights.resize(world.terrain.water.size() if world.terrain else 0)
	_cover_heights.fill(UNCOVERED)


func _step_cover(terrain: EITerrain) -> void:
	if terrain == null or _cover_heights.is_empty():
		return
	var end := mini(_cover_cursor + COVER_BATCH, _cover_queue.size())
	var start := Time.get_ticks_usec()
	while _cover_cursor < end:
		var node: Node3D = _cover_queue[_cover_cursor]
		_cover_cursor += 1
		if is_instance_valid(node):
			rasterize_cover(node, terrain, _cover_heights)
		if Time.get_ticks_usec() - start >= COVER_BUDGET_US:
			break
	if _cover_cursor < _cover_queue.size():
		return
	terrain.set_rain_cover(Image.create_from_data(terrain.sectors_x * EITerrain.SECTOR,
		terrain.sectors_y * EITerrain.SECTOR, false, Image.FORMAT_RF, _cover_heights.to_byte_array()))
	_cover_ready = true
	_cover_queue.clear()
	_cover_heights.clear()


## Static solid cover only: tree billboards, creatures, effects and levers
## are excluded. Triangles use actual placed transforms rather than a
## rectangular building footprint, so open courtyards remain exposed.
## A 1 m grid matches the map cells; this is intentionally not rain physics
## or a per-frame rebuild for moved/deformed objects.
static func rasterize_cover(node: Node3D, terrain: EITerrain, heights: PackedFloat32Array) -> void:
	var info: Dictionary = node.get_meta("ei", {})
	if String(info.get("kind", "OBJECT")) != "OBJECT":
		return
	var template := String(info.get("template", "")).to_lower()
	if template.begins_with("nafl") or template.begins_with("ef") or template.begins_with("nask"):
		return
	var width := terrain.sectors_x * EITerrain.SECTOR
	var height := terrain.sectors_y * EITerrain.SECTOR
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible:
			continue
		var xf := NavGrid._local_xf(mi, node)
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vertices: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for ti in range(0, count - 2, 3):
				var a: Vector3 = xf * vertices[indices[ti] if not indices.is_empty() else ti]
				var b: Vector3 = xf * vertices[indices[ti + 1] if not indices.is_empty() else ti + 1]
				var c: Vector3 = xf * vertices[indices[ti + 2] if not indices.is_empty() else ti + 2]
				var normal := (b - a).cross(c - a)
				if normal.length_squared() < 1e-8 or absf(normal.normalized().y) < 0.25:
					continue
				var tri := PackedVector2Array([Vector2(a.x, -a.z), Vector2(b.x, -b.z), Vector2(c.x, -c.z)])
				var bounds := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
				for y in range(maxi(0, floori(bounds.position.y)), mini(height, ceili(bounds.end.y))):
					for x in range(maxi(0, floori(bounds.position.x)), mini(width, ceili(bounds.end.x))):
						var p := Vector2(x + 0.5, y + 0.5)
						if not Geometry2D.point_is_inside_triangle(p, tri[0], tri[1], tri[2]):
							continue
						var bary := EITerrain._bary(p, tri)
						var cover_y := a.y * bary.x + b.y * bary.y + c.y * bary.z
						if cover_y > terrain.height_at(p.x, p.y) + 0.45:
							var i := y * width + x
							heights[i] = maxf(heights[i], cover_y)
