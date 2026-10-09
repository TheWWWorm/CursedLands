extends Node
## Opt-in local water mist. Uses the existing Forward+ volumetric lighting
## and leaves its environment/global fog settings unchanged.
const Sources = preload("res://src/game/fx/weather_mist_sources.gd")
const Wind = preload("res://src/game/fx/weather_wind.gd")
const MAX_VOLUMES := 6
const CACHE_CELLS := 16
const RANGE := 24.0
const OPTICAL_DEPTH_LIMIT := 1.0
# Active boxes occupy one 3x3 cell square. Sum of horizontal ray projection
# is at most its diagonal; sum of vertical projection at most six heights.
# The corresponding path bound caps added continuous-field opacity at63.3%
# on the worst long ray. R1 open water starts at0.05/m (swamp0.15/m);
# this local cap is below0.015/m. Actual play/low-angle views additionally
# validate silhouette contrast; weak native densities would be discarded.
const MAX_PATH := sqrt(18.0*Sources.CELL*Sources.CELL+pow(MAX_VOLUMES*Sources.MAX_HEIGHT,2))
const MAX_DENSITY := OPTICAL_DEPTH_LIMIT/MAX_PATH
const DRIFT_PERIOD := 100.0*TAU # common period of both rational wisp vectors
const SHADER := """
shader_type fog;
uniform sampler2D source_mask : filter_nearest, repeat_disable;
uniform int source_grid;
uniform float source_step;
uniform mat4 world_to_terrain;
uniform vec2 cell_origin;
uniform vec2 drift;
uniform vec2 weights;
uniform float density_cap;
uniform float reveal;
float source_coverage(ivec2 q) {
	if (any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,ivec2(source_grid)))) return 0.0;
	return texelFetch(source_mask,q,0).a;
}
void fog() {
	vec3 p=(world_to_terrain*vec4(WORLD_POSITION,1.0)).xyz;
	vec2 xy=vec2(p.x,-p.z);
	vec2 grid=(xy-cell_origin)/source_step;
	ivec2 q=ivec2(floor(grid));
	vec4 source=texelFetch(source_mask,clamp(q,ivec2(0),ivec2(source_grid-1)),0);
	float coverage=source_coverage(q);
	vec2 edge=fract(grid)*source_step;
	float taper=source_step*0.25;
	if (source_coverage(q+ivec2(-1,0))<0.5) coverage*=smoothstep(0.0,taper,edge.x);
	if (source_coverage(q+ivec2(1,0))<0.5) coverage*=smoothstep(0.0,taper,source_step-edge.x);
	if (source_coverage(q+ivec2(0,-1))<0.5) coverage*=smoothstep(0.0,taper,edge.y);
	if (source_coverage(q+ivec2(0,1))<0.5) coverage*=smoothstep(0.0,taper,source_step-edge.y);
	float height=p.y-source.b;
	float layer=smoothstep(0.0,0.30,height)*(1.0-smoothstep(3.0,4.0,height))*exp(-max(height,0.0)*0.30);
	// Broad world-anchored wisps. No engine TIME or high-frequency noise.
	float wisp=0.55+0.35*sin(dot(xy+drift,vec2(0.12,0.08)))+0.10*cos(dot(xy+drift,vec2(-0.07,0.10)));
	DENSITY=density_cap*dot(source.rg,weights)*coverage*layer*wisp*reveal;
	ALBEDO=vec3(0.90,0.93,0.94);
	EMISSION=vec3(0.0);
}
"""
var game: Game
var world: GameWorld
var sources: Sources
var root: Node3D
var volumes := {}
var cache := {}
var clock := -INF
var hours := -INF
var rain := 0.0
var wetness := 0.0
var drift := Vector2.ZERO
var enabled := false
var weights := Vector2.ZERO
var _signature := []
var _shader: Shader


func _init(g: Game = null) -> void:
	game=g; name="WeatherMist"; process_mode=Node.PROCESS_MODE_PAUSABLE
	process_priority=4


func _ready() -> void:
	GameData.options_changed.connect(refresh)
	refresh()


static func available(option: bool, volumetric: bool, renderer: String) -> bool:
	return option and volumetric and renderer=="forward_plus"


func refresh() -> void:
	var next:=available(Gfx.on("gfx_weather_mist"),Gfx.on("gfx_volumetric"),RenderingServer.get_current_rendering_method())
	if next!=enabled or not next: clear()
	enabled=next
	set_process(enabled and DisplayServer.get_name()!="headless")


func _exit_tree() -> void: clear()


func clear() -> void:
	if is_instance_valid(root): root.hide(); root.queue_free()
	root=null; world=null; sources=null; volumes.clear(); cache.clear()
	clock=-INF; hours=-INF; rain=0.0; wetness=0.0; drift=Vector2.ZERO
	weights=Vector2.ZERO; _signature=[]


func _process(_dt: float) -> void:
	var current: GameWorld=game.world if is_instance_valid(game) else null
	if not is_instance_valid(current) or not is_instance_valid(current.terrain): clear(); return
	if not current.can_process(): return
	var session:=current.session
	if not session or not session.state or session.loading_game or session._zone_holding or session._remote_loading or session.movie_active(): return
	if session.lmp_travel and not session.lmp_travel.can_tick(current): return
	var intensity:=0.0
	if is_instance_valid(game.sound) and game.sound.weather and game.sound.weather.world==current:
		intensity=Wind.precipitation(game.sound.weather,game.sound._ticks+game.sound._tick_acc/GameSound.TICK,1)
	var p:=current.terrain.to_local(game.rig.global_position)
	step(current,Vector2(p.x,-p.z),current.terrain._waves.time_ticks()*EIWaterWaves.TICK,
		(session.state.day-1)*24.0+session.state.world_time,intensity,current.terrain.wind_frame().state)


static func morning(game_hours: float) -> float:
	if not is_finite(game_hours) or game_hours<0: return 0.0
	# R1's deterministic per-day chance, using the shared overflow-safe hash.
	var h:=Wind.mul32(int(game_hours/24.0),0x9e3779b1)
	h=Wind.mul32(h^(h>>15),0x85ebca77); h=Wind.mul32(h^(h>>13),0xc2b2ae3d); h^=h>>16
	if float(h>>8)/16777216.0>=0.60: return 0.0
	var hour:=fposmod(game_hours,24.0)
	return smoothstep(3.0,5.0,hour)*(1.0-smoothstep(7.5,10.0,hour))


static func density_weights(game_hours: float, wet: float) -> Vector2:
	var hour:=fposmod(game_hours,24.0)
	var night:=1.0-smoothstep(2.0,6.0,hour) if hour<12.0 else smoothstep(18.0,22.0,hour)
	var dawn:=morning(game_hours)
	# Native FogVolume drops <=0.001 density and quantizes in1/1024 steps.
	# Keep a useful saturated post-rain/swamp envelope within the same cap;
	# very weak twilight and the final wetness tail still disappear first.
	return Vector2(clampf(dawn+0.6*night+wet,0.0,1.0),clampf(0.65+0.2*night+0.35*dawn+0.35*wet,0.0,1.0))


func step(current: GameWorld, centre: Vector2, seconds: float, game_hours: float, intensity: float, wind: Vector4) -> void:
	if not enabled or not is_finite(seconds) or not is_finite(game_hours): return
	if not is_instance_valid(current) or not is_instance_valid(current.terrain): return
	if current!=world or sources==null or not is_instance_valid(sources.field.terrain) or sources.field.terrain!=current.terrain:
		clear(); world=current; sources=Sources.new(world.terrain)
		if not sources.allowed(): return
		root=Node3D.new(); root.name="LocalWeatherMist"; world.terrain.add_child(root)
	if not is_instance_valid(root): return
	# Scripted floods and authored surface changes invalidate immediately,
	# including while held. Rebuilding waits for the next advancing clock.
	var signature:=[world.terrain.surface_rev,world.terrain.water_offsets.duplicate()]
	if signature!=_signature:
		_signature=signature; _clear_volumes(); cache.clear(); sources.building=false
		sources.field._water.begin_frame(false)
	if seconds==clock: return
	var delta:=seconds-clock if is_finite(clock) else 0.0
	var elapsed:=game_hours-hours if is_finite(hours) else 0.0
	if is_finite(clock) and (delta<0.0 or delta>0.5 or elapsed<0.0 or elapsed>0.25):
		clear(); step(current,centre,seconds,game_hours,intensity,wind); return
	clock=seconds; hours=game_hours
	rain=move_toward(rain,clampf(intensity,0.0,1.0),maxf(elapsed,0.0)/0.25)
	wetness=rain if rain>=wetness else rain+(wetness-rain)*exp(-3.0*maxf(elapsed,0.0)/2.0)
	drift+=Vector2(wind.x,wind.y)*delta*(0.12+0.10*clampf(wind.w,0.0,1.0))
	drift=Vector2(fposmod(drift.x,DRIFT_PERIOD),fposmod(drift.y,DRIFT_PERIOD))
	weights=density_weights(game_hours,wetness)
	_admit(centre)
	for key: Vector2i in volumes:
		var row: Dictionary=volumes[key]; var material: ShaderMaterial=row.material
		var distance:=centre.distance_to((Vector2(key)+Vector2.ONE*0.5)*Sources.CELL)
		material.set_shader_parameter("weights",weights)
		material.set_shader_parameter("drift",drift)
		material.set_shader_parameter("reveal",smoothstep(0.0,1.0,clock-float(row.birth))*(1.0-smoothstep(RANGE-8.0,RANGE,distance)))


func _clear_volumes() -> void:
	for row: Dictionary in volumes.values(): (row.node as FogVolume).hide(); (row.node as FogVolume).queue_free()
	volumes.clear()


func _admit(centre: Vector2) -> void:
	var origin:=Vector2i((centre/Sources.CELL).floor()); var candidates:=[]
	for y in range(origin.y-1,origin.y+2):
		for x in range(origin.x-1,origin.x+2):
			var key:=Vector2i(x,y); var distance:=centre.distance_to((Vector2(key)+Vector2.ONE*0.5)*Sources.CELL)
			if distance<RANGE: candidates.append({"key":key,"distance":distance})
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	var wanted:=[]
	for row: Dictionary in candidates:
		if cache.has(row.key) and not (cache[row.key] as Dictionary).is_empty() and wanted.size()<MAX_VOLUMES: wanted.append(row.key)
	for key: Vector2i in volumes.keys():
		if key not in wanted:
			(volumes[key].node as FogVolume).hide(); (volumes[key].node as FogVolume).queue_free(); volumes.erase(key)
	for key: Vector2i in wanted:
		if not volumes.has(key): _install(key,cache[key])
	if sources.building:
		if sources.advance(): cache[sources.key]=sources.result()
	else:
		for row: Dictionary in candidates:
			if not cache.has(row.key): sources.begin(row.key); break
	while cache.size()>CACHE_CELLS:
		var farthest: Vector2i=cache.keys()[0]; var far:=0.0
		for key: Vector2i in cache:
			var distance:=centre.distance_squared_to((Vector2(key)+Vector2.ONE*0.5)*Sources.CELL)
			if distance>far: far=distance; farthest=key
		cache.erase(farthest)


func _install(key: Vector2i, source: Dictionary) -> void:
	if _shader==null: _shader=Shader.new(); _shader.code=SHADER
	var material:=ShaderMaterial.new(); material.shader=_shader
	material.set_shader_parameter("source_mask",ImageTexture.create_from_image(source.image))
	material.set_shader_parameter("source_grid",Sources.GRID)
	material.set_shader_parameter("source_step",Sources.STEP)
	material.set_shader_parameter("world_to_terrain",world.terrain.global_transform.affine_inverse())
	material.set_shader_parameter("cell_origin",Vector2(key)*Sources.CELL)
	material.set_shader_parameter("density_cap",MAX_DENSITY)
	material.set_shader_parameter("reveal",0.0)
	var node:=FogVolume.new(); node.name="WaterMist_%s_%s"%[key.x,key.y]
	node.shape=RenderingServer.FOG_VOLUME_SHAPE_BOX
	node.size=Vector3(Sources.CELL,float(source.high)-float(source.low)+Sources.LAYER_HEIGHT,Sources.CELL)
	var xy:=(Vector2(key)+Vector2.ONE*0.5)*Sources.CELL
	node.position=Vector3(xy.x,float(source.low)+node.size.y*0.5,-xy.y)
	node.material=material; root.add_child(node)
	volumes[key]={"node":node,"material":material,"birth":clock}
