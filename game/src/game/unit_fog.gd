class_name UnitFog
extends Node
## Which units this player sees (client-side; the host still simulates all).
## the original: the server keeps per player a list of relevant objects
## (player, diffed into add / remove messages
## ); the client sets object flag on the
## listed objects and clears it on the others. In a network
## game (set (.., 1)) the list holds
## the player's own units and, around every unit of the player's party, all
## objects within 2 x max(sight x sight factor (x), life sense
## ) + 5 (a plain radius: no vision cone, no terrain
## ray, no stealth). The unit renderer then skips units without
## the flag, hover / the unit panel need it, and
## the minimap draws only the listed units. An object leaves
## the list the moment it is out of range: no linger, no fade, no marker.
## Single player (= 0) draws every unit; the remake option
## "unit_fog" (Gameplay, "Fog of war (single player)", default on) applies
## the network rule in single player too (--unit-fog forces it for tests).
## In a village (world mode 3, lists every object) nothing is
## fogged, online or not.
## Remake, single player only: while a script holds the camera (CameraRig.held,
## i.e. a conversation; the original's SetCameraPosition / SetCameraOrientation
## PlayCamera are called by no shipped .mob script)
## nothing is fogged, so story scenes never show empty spots.
## Native server relevance always includes the player's own units and its
## noticed / seen-corpse list
## and map units with script names (server
## ). The temporary player list is not yet reproduced
## only units are hidden, map objects never. Remake party sight (single
## player option / campaign co-op) does not reveal script-named units merely
## because they need to remain available to the server's scripts.
## Campaign sight clips both the nearby relevance radius and retained
## perception against geometry. Only explicit life sense sees through walls.

const REFRESH := 0.1
const CAMERA_RANGE := 100.0   # single player: list radius round the camera

var game: Game
var _t := 0.0
var _was_on := false
var _always := {}
static var _force := "--unit-fog" in OS.get_cmdline_user_args()


func _init(g: Game) -> void:
	game = g
	name = "UnitFog"


func active() -> bool:
	# World mode 3 (the village screen) lists every object.
	return sight_active(game.session)


static func sight_active(s: Session) -> bool:
	return s != null and not s.shop_available() \
		and (s.online or _force or GameData.option("unit_fog") == 1)


func _process(dt: float) -> void:
	var w := game.world
	if w == null:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = REFRESH
	var on := active()
	_always = sight_list_for(game.session, game.session.my_index) if on and game.session.lmp.is_empty() \
		else always_for(game.session, game.session.my_index)
	if not on and not _was_on:
		return
	_was_on = on
	# The party's eyes once per refresh: [position, range², observer].
	var eyes := party_eyes(game) if on else []
	# Single player: while a script holds the camera (a conversation; the
	# shipped scripts use no other camera command) the whole cast shows,
	# wherever the actors stand (DialogPanel hides the others itself). Remake.
	var talk := not game.session.online and game.rig != null and game.rig.held
	for u: GameUnit in w.unit_rows():
		u.fogged = on and not talk and not _always.has(u.uid) and not sees(eyes, u)
		var want := not u.hidden and not u.fogged
		if u.visible != want:
			# Shown: drawn where it stands now, not where it was last drawn
			# before it was hidden (GameUnit.resync_drawn, on the visibility
			# change).
			u.visible = want


## Remake co-op shares sight between the players' living party members.
## Selection and commands still use Game.my_units and the local controller.
## A dead / hidden unit or a departed player's AI unit provides no sight.
static func party_eyes(g: Game) -> Array:
	if g == null or g.world == null or g.session == null:
		return []
	return party_eyes_for(g.world, g.session.my_index, g.session.online and g.session.lmp.is_empty())


static func party_eyes_for(w: GameWorld, player: int, shared := false) -> Array:
	var eyes := []
	if w == null:
		return eyes
	for m: GameUnit in w.party_units():
		if m.dead or m.hidden or m.controller < 0:
			continue
		if not shared and m.controller != player:
			continue
		var r := range_of(m)
		eyes.append([m.pos, r * r, m])
	return eyes


## Player, used by NPC reaction acknowledgements.
## It includes retained perception, not every unit inside a camera radius.
static func noticed_for(s: Session, player: int, living_sources_only := false) -> Array[GameUnit]:
	var out: Array[GameUnit] = []
	if s == null or s.world == null:
		return out
	var ids := {}
	var w := s.world
	var shared := s.online and s.lmp.is_empty()
	for m: GameUnit in w.party_units():
		if not is_instance_valid(m) or m.controller < 0 or (not shared and m.controller != player):
			continue
		ids[m.uid] = true
		if living_sources_only and (m.dead or m.hidden):
			continue
		if not w.authority:
			for id: int in m.get_meta("net_noticed", []):
				if w.units.has(id):
					ids[id] = true
			continue
		var perceived: Dictionary = w.ai.player_perceive(m) if w.authority and not m.dead else m.get_meta("noticed", {})
		for o in perceived.values():
			if is_instance_valid(o):
				ids[o.uid] = true
		for o in (m.get_meta("seen_corpses", {}) as Dictionary).values():
			if is_instance_valid(o):
				ids[o.uid] = true
	for u: GameUnit in w.unit_rows():
		if is_instance_valid(u) and not u.hidden and ids.has(u.uid):
			out.append(u)
	return out


## Rendering under remake party sight uses actual party perception, never
## the native server's script-name registration. Dead / hidden sources may
## retain native perception for scripts, but cannot reveal distant enemies.
static func sight_list_for(s: Session, player: int) -> Dictionary:
	var out := {}
	if s == null or s.world == null: return out
	var eyes := party_eyes_for(s.world, player, s.online)
	for u: GameUnit in noticed_for(s, player, true):
		if u.controller >= 0 and (s.online or u.controller == player):
			out[u.uid] = true
			continue
		for e: Array in eyes:
			if _unoccluded(e, u):
				out[u.uid] = true
				break
	return out


##  appends the party's noticed list and the server's named
## object list before adding objects in the sight / camera radius.
static func always_for(s: Session, player: int) -> Dictionary:
	var out := {}
	if s == null or s.world == null:
		return out
	for u: GameUnit in noticed_for(s, player):
		out[u.uid] = true
	for u: GameUnit in s.world.unit_rows():
		if is_instance_valid(u) and not String(u.info.get("name", "")).is_empty():
			out[u.uid] = true
	return out


## Authoritative equivalent of player. It is computed
## for the issuing player, independent of the host renderer's u.visible / fog.
## Native single player uses the camera's 100 m radius; unit_fog and shared
## co-op sight are the remake options described above. Iteration retains the
## world's relevant-object order so equal distances do not reorder targets.
static func relevant_for(s: Session, player: int, camera := Vector2.INF) -> Array[GameUnit]:
	var out: Array[GameUnit] = []
	if s == null or s.world == null:
		return out
	var village := s.shop_available()
	var sight := sight_active(s)
	var eyes := party_eyes_for(s.world, player, s.online and s.lmp.is_empty()) if sight else []
	if camera == Vector2.INF and s.game != null and s.game.rig != null:
		camera = Vector2(s.game.rig.position.x, -s.game.rig.position.z)
	var talk := not s.online and s.game != null and s.game.rig != null and s.game.rig.held
	var always := (sight_list_for(s, player) if sight and s.lmp.is_empty() else always_for(s, player)) if not village and not talk else {}
	for u: GameUnit in s.world.unit_rows():
		if not is_instance_valid(u) or u.hidden:
			continue
		if village or talk or always.has(u.uid) or (sees(eyes, u) if sight else \
				camera == Vector2.INF or u.pos.distance_squared_to(camera) < CAMERA_RANGE * CAMERA_RANGE):
			out.append(u)
	return out


## Whether `u` is on this player's list (minimap dots, over
## ). Online / unit_fog: the rule above (u.visible). Single player
## (= 0): the player's own units and every object
## within 100 m of the player's camera point.
static func listed(g: Game, u: GameUnit) -> bool:
	if u.hidden or not u.visible:
		return false
	var f: UnitFog = g.get_node_or_null(^"UnitFog")
	if (f and (f.active() or f._always.has(u.uid))) or u.controller == g.session.my_index or g.rig == null:
		return true
	var cam := Vector2(g.rig.position.x, -g.rig.position.z)
	return u.pos.distance_squared_to(cam) < CAMERA_RANGE * CAMERA_RANGE


## Whether a nearby unit is visible, including the geometry between it and
## at least one living party member. The native LMP relevance stays radial.
static func sees(eyes: Array, u: GameUnit) -> bool:
	for e: Array in eyes:
		if (e[0] as Vector2).distance_squared_to(u.pos) < float(e[1]) and _unoccluded(e, u):
			return true
	return false


static func _unoccluded(eye: Array, u: GameUnit) -> bool:
	if eye.size() < 3: return true   # old callers providing a radial relevance sample
	var observer: GameUnit = eye[2]
	var w := observer.world
	if observer == u or w == null or (w.session and not w.session.lmp.is_empty()): return true
	var life := observer.sense(2) * u.detect(2)
	if not u.dead and life > 0.0 and observer.pos.distance_squared_to(u.pos) < life * life:
		return true
	# NavGrid keeps a legacy nonzero floor for an opaque object hit.
	return w.sight_ray(observer, u) > 0.0001


## 2 x max(sight x sight factor, life sense) + 5.
static func range_of(m: GameUnit) -> float:
	var sight := (float(m.stats.get("sight", 15.0)) + m.sense_bonus(0)) * m.sight_factor()
	return 2.0 * maxf(sight, m.sense(2)) + 5.0
