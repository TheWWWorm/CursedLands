extends Node
## Optional client decoration. A pausable terrain clock owns every position,
## animation, cooldown and particle phase; nothing is saved or replicated.
const Habitats = preload("res://src/game/fx/ambient_habitats.gd")
const Model = preload("res://src/game/fx/ambient_models.gd")
const Particles = preload("res://src/game/fx/ambient_particles.gd")
const Wind = preload("res://src/game/fx/weather_wind.gd")
const MAX_GROUND := 2
const MAX_BIRDS := 3
const MAX_THREATS := 16
const MAX_COOLDOWNS := 128
const RANGE := 42.0
var game: Game
var world: GameWorld
var field: Habitats
var root: Node3D
var particles: Particles
var residents := {}
var flock: Array[Dictionary] = []
var cooldowns := {}
var wildlife := false
var regional := false
var clock := -INF
var _next_admission := 0.0
var _next_sources := 0.0
var _flock_key := Vector2i(0x7fffffff,0x7fffffff)
var last_update_us := 0
var threats := PackedVector4Array()
var _unavailable := {}


func _init(g: Game = null) -> void:
	game = g; name = "AmbientLife"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 4 # after posed units and UnitFog


func _ready() -> void:
	GameData.options_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var next_wildlife := Gfx.on("gfx_ambient_wildlife")
	var next_regional := Gfx.on("gfx_ambient_particles")
	if wildlife!=next_wildlife or regional!=next_regional: clear()
	wildlife=next_wildlife; regional=next_regional
	set_process((wildlife or regional) and DisplayServer.get_name()!="headless")
	# Other terrain options may move the visible loose layer while the
	# options dialog holds game time. Re-seat without advancing any pose.
	call_deferred("_resurface")


func _resurface() -> void:
	if field==null or not is_instance_valid(field.terrain): return
	for row: Dictionary in residents.values():
		var hit:=field.ground(row.p,true)
		if not hit.is_empty() and is_instance_valid(row.node): row.node.position.y=float(hit.height)


func _exit_tree() -> void:
	clear()


func clear() -> void:
	if is_instance_valid(root): root.hide(); root.queue_free()
	root = null; particles = null; field = null; world = null
	residents.clear(); flock.clear(); cooldowns.clear(); threats.clear()
	_unavailable.clear()
	clock = -INF; _next_admission = 0.0; _next_sources = 0.0
	_flock_key = Vector2i(0x7fffffff,0x7fffffff)


func _process(_dt: float) -> void:
	var current: GameWorld = game.world if is_instance_valid(game) else null
	if not is_instance_valid(current) or not is_instance_valid(current.terrain): clear(); return
	if not current.can_process(): return
	var session := current.session
	if session and (session.loading_game or session._zone_holding or session._remote_loading or session.movie_active()): return
	if session and session.lmp_travel and not session.lmp_travel.can_tick(current): return
	var p := current.terrain.to_local(game.rig.global_position)
	step(current,Vector2(p.x,-p.z),current.terrain._waves.time_ticks()*EIWaterWaves.TICK,
		session.state.world_time if session and session.state else 12.0)


static func night_at(hour: float) -> float:
	var day := smoothstep(5.0,7.0,hour)*(1.0-smoothstep(18.0,20.0,hour))
	return 1.0-day


static func shown(unit: GameUnit) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() and unit.is_visible_in_tree() \
		and not unit.hidden and not unit.fogged and not unit.dead and is_instance_valid(unit.model) and unit.model.is_visible_in_tree()


static func threat_radius(unit: GameUnit) -> float:
	if unit.action in ["attack","hit"] or unit.action.begins_with("cast"): return 9.0
	if unit.action in ["walk","run","move"] or unit._draw_motion_active:
		return 1.8 if unit.sneaking else (5.5 if unit.running else 3.5)
	return 1.4


func _threats(centre: Vector2) -> void:
	threats.clear()
	var rows := []
	for unit: GameUnit in world.visible_units():
		if not shown(unit) or not unit.near_screen(): continue
		var p := world.terrain.to_local(unit.get_global_transform_interpolated().origin)
		var distance := centre.distance_squared_to(Vector2(p.x,-p.z))
		if distance>55.0*55.0: continue
		rows.append({"distance":distance,"point":Vector4(p.x,p.y,-p.z,threat_radius(unit))})
		if rows.size()>=64: break
	rows.sort_custom(func(a,b): return a.distance<b.distance)
	for i in mini(rows.size(),MAX_THREATS): threats.append(rows[i].point)


func threat_at(p: Vector2, margin := 0.0, height := INF) -> Vector2:
	var closest := INF; var away := Vector2.ZERO
	for threat: Vector4 in threats:
		if is_finite(height) and absf(threat.y-height)>3.0: continue
		var delta := p-Vector2(threat.x,threat.z)
		var distance := delta.length()
		if distance<threat.w+margin and distance<closest:
			closest = distance; away = delta.normalized() if distance>0.001 else Vector2(1,0)
	return away


func step(current: GameWorld, centre: Vector2, seconds: float, hour: float) -> void:
	if not wildlife and not regional: return
	if not is_instance_valid(current) or not is_instance_valid(current.terrain) or not is_finite(seconds): return
	if world!=current or field==null:
		clear(); world=current; field=Habitats.new(world.terrain)
		root=Node3D.new(); root.name="LocalAmbientDecoration"; world.terrain.add_child(root)
		if regional: particles=Particles.new(); root.add_child(particles)
	if seconds==clock: return
	# Loads, clock corrections and long frontend stalls get fresh local
	# residents. Never integrate a flee trail through an unseen interval.
	if is_finite(clock) and (seconds<clock or seconds-clock>0.5):
		clear(); step(current,centre,seconds,hour); return
	var started := Time.get_ticks_usec()
	var dt := clampf(seconds-clock,0.0,0.10) if is_finite(clock) else 0.0
	clock=seconds
	var changed := false
	if seconds>=_next_sources:
		changed=field.refresh(); _next_sources=seconds+0.5
	_threats(centre)
	var night := night_at(hour)
	if wildlife:
		if night>0.75:
			for row: Dictionary in flock:
				if (row.flee as Vector2)==Vector2.ZERO:
					row.flee=Vector2.from_angle(float(row.phase)); row.left=2.6
		_update_residents(centre,dt)
		if seconds>=_next_admission:
			_admit(centre,night); _next_admission=seconds+0.75
	if particles:
		particles.rebuild(field,centre,changed)
		var hazards := PackedVector4Array()
		for threat: Vector4 in threats:
			var p := world.terrain.to_global(Vector3(threat.x,threat.y,-threat.z))
			hazards.append(Vector4(p.x,p.y+0.8,p.z,5.0 if threat.w>=9.0 else 1.1))
		var rain := 0.0; var snow := 0.0
		if is_instance_valid(game) and is_instance_valid(game.sound) and game.sound.weather:
			var weather := game.sound.weather
			if weather.world==world:
				var now := game.sound._ticks+game.sound._tick_acc/GameSound.TICK
				rain=Wind.precipitation(weather,now,1); snow=Wind.precipitation(weather,now,2)
		var focus := world.terrain.to_global(Vector3(centre.x,0,-centre.y))
		particles.update(seconds,focus,Vector4(night,rain,snow,0),world.terrain.wind_frame().state,hazards)
	last_update_us=Time.get_ticks_usec()-started


func _admit(centre: Vector2, night: float) -> void:
	for key in cooldowns.keys():
		if float(cooldowns[key])<=clock: cooldowns.erase(key)
	var origin := Vector2i((centre/Habitats.CELL).floor())
	var view_floor := field.ground(centre)
	var candidates := []
	for y in range(origin.y-1,origin.y+2):
		for x in range(origin.x-1,origin.x+2):
			var key := Vector2i(x,y); var p := field.anchor(key)
			if p.distance_to(centre)>RANGE-8.0 or cooldowns.has(key): continue
			candidates.append({"key":key,"point":p,"distance":p.distance_squared_to(centre)})
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	for row: Dictionary in candidates:
		var key: Vector2i=row.key; var p: Vector2=row.point
		if residents.has(key): continue
		var hit := field.habitat(p)
		if hit.is_empty() or threat_at(p,3.0,float(hit.height))!=Vector2.ZERO: continue
		# Cave rim plateaus and deep pits can be horizontally near the view
		# while belonging to a completely different floor.
		if not view_floor.is_empty() and absf(float(hit.height)-float(view_floor.height))>4.0: continue
		var kind := field.species(p,hit,field.random(key,3),night)
		if not kind.is_empty() and residents.size()<MAX_GROUND:
			var resident := _create(kind,p,key,0)
			if not resident.is_empty(): residents[key]=resident
		if flock.is_empty() and field.region=="outdoor" and night<0.25 and not hit.is_empty() \
				and not hit.wet and hit.clear and hit.area in ["grass","dry","bare"]:
			for i in MAX_BIRDS:
				var resident := _create("bird",p,key,i)
				if not resident.is_empty(): flock.append(resident)
			_flock_key=key


func _create(kind: String, p: Vector2, key: Vector2i, lane: int) -> Dictionary:
	if _unavailable.has(kind): return {}
	var node := Model.new()
	if not node.build(kind): node.free(); _unavailable[kind]=true; return {}
	root.add_child(node)
	var result := {"node":node,"home":p,"p":p,"phase":field.random(key,20)*TAU+lane*TAU/MAX_BIRDS,
		"kind":kind,"flee":Vector2.ZERO,"left":0.0,"lane":lane}
	if not _move(result,0.0): node.queue_free(); _cooldown(key); return {}
	return result


func _cooldown(key: Vector2i) -> void:
	if cooldowns.size()>=MAX_COOLDOWNS and not cooldowns.has(key):
		var oldest: Vector2i=cooldowns.keys()[0]
		for other: Vector2i in cooldowns:
			if float(cooldowns[other])<float(cooldowns[oldest]): oldest=other
		cooldowns.erase(oldest)
	cooldowns[key]=clock+35.0


func _update_residents(centre: Vector2, dt: float) -> void:
	for key: Vector2i in residents.keys():
		var row: Dictionary=residents[key]
		if (row.p as Vector2).distance_to(centre)>RANGE or not _move(row,dt):
			(row.node as Node3D).queue_free(); residents.erase(key)
			_cooldown(key)
	var remove := false
	for row: Dictionary in flock:
		if (row.p as Vector2).distance_to(centre)>RANGE or not _move(row,dt): remove=true
	if remove:
		for row: Dictionary in flock: (row.node as Node3D).queue_free()
		flock.clear(); _cooldown(_flock_key)


func _move(row: Dictionary, dt: float) -> bool:
	var p: Vector2=row.p; var bird: bool=row.kind=="bird"
	var standing := field.ground(p)
	var away := threat_at(p,2.0 if bird else 0.0,float(standing.height) if not standing.is_empty() else INF)
	if away!=Vector2.ZERO and (row.flee as Vector2)==Vector2.ZERO:
		row.flee=away; row.left=2.6
	var fleeing := (row.flee as Vector2)!=Vector2.ZERO
	var next := p
	if fleeing:
		row.left=float(row.left)-dt
		if float(row.left)<=0.0: return false
		next += (row.flee as Vector2)*dt*(4.0 if bird else 1.6)
	else:
		var phase := clock*(0.55 if bird else 0.23)+float(row.phase)
		next=(row.home as Vector2)+Vector2(sin(phase),cos(phase if bird else phase*0.93))*(2.0 if bird else 0.45)
	var hit := field.habitat(next)
	if hit.is_empty() or (not bird and (hit.wet or not hit.clear or absf((hit.normal as Vector3).y)<0.94)):
		if fleeing: return false
		next=p; hit=field.habitat(p)
		if hit.is_empty(): return false
	var height := float(hit.height)
	if not bird and not standing.is_empty() and absf(height-float(standing.height))>0.20: return false
	if bird:
		var home_hit := field.ground(row.home)
		if home_hit.is_empty(): return false
		height = float(home_hit.height)+2.0+sin(clock*0.8+float(row.phase))*0.25
		if fleeing: height += (2.6-float(row.left))*0.7
		if height<float(hit.height)+0.4 or not field.clear_at(next,height): return false
	else:
		var drawn:=field.ground(next,true)
		if drawn.is_empty(): return false
		height=float(drawn.height)
		if not field.clear_at(next,height): return false
	var node: Model=row.node
	node.position=Vector3(next.x,height,-next.y)
	var direction := next-p
	if direction.length_squared()>0.000001: node.rotation.y=atan2(direction.x,-direction.y)
	row.p=next
	node.pose(clock+float(row.phase),fleeing or direction.length()>0.002,fleeing)
	return true
