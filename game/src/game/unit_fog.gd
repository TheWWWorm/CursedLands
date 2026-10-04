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
## Approx.: every player-controlled unit stays visible (the original's always-listed
##  lists are not decoded); only units are hidden, map
## objects never.

const REFRESH := 0.1
const CAMERA_RANGE := 100.0   # single player: list radius round the camera

var game: Game
var _t := 0.0
var _was_on := false
static var _force := "--unit-fog" in OS.get_cmdline_user_args()


func _init(g: Game) -> void:
	game = g
	name = "UnitFog"


func active() -> bool:
	# World mode 3 (the village screen) lists every object.
	if game.session == null or game.session.shop_available():
		return false
	return game.session.online or _force or GameData.option("unit_fog") == 1


func _process(dt: float) -> void:
	var w := game.world
	if w == null:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = REFRESH
	var on := active()
	if not on and not _was_on:
		return
	_was_on = on
	# The party's eyes once per refresh: [position, range²].
	var eyes: Array = []
	if on:
		for m: GameUnit in game.my_units():
			var r := range_of(m)
			eyes.append([m.pos, r * r])
	# Single player: while a script holds the camera (a conversation; the
	# shipped scripts use no other camera command) the whole cast shows,
	# wherever the actors stand (DialogPanel hides the others itself). Remake.
	var talk := not game.session.online and game.rig != null and game.rig.held
	for u: GameUnit in w.units.values():
		u.fogged = on and not talk and not sees(eyes, u)
		var want := not u.hidden and not u.fogged
		if u.visible != want:
			# Shown: drawn where it stands now, not where it was last drawn
			# before it was hidden (GameUnit.resync_drawn, on the visibility
			# change).
			u.visible = want


## Whether `u` is on this player's list (minimap dots, over
## ). Online / unit_fog: the rule above (u.visible). Single player
## (= 0): the player's own units and every object
## within 100 m of the player's camera point.
static func listed(g: Game, u: GameUnit) -> bool:
	if u.hidden or not u.visible:
		return false
	var f: UnitFog = g.get_node_or_null(^"UnitFog")
	if (f and f.active()) or u.controller == g.session.my_index or g.rig == null:
		return true
	var cam := Vector2(g.rig.position.x, -g.rig.position.z)
	return u.pos.distance_squared_to(cam) < CAMERA_RANGE * CAMERA_RANGE


## Whether one of the party's `eyes` ([position, range²]) has `u` in range.
static func sees(eyes: Array, u: GameUnit) -> bool:
	if u.controller >= 0:
		return true
	for e: Array in eyes:
		if (e[0] as Vector2).distance_squared_to(u.pos) < float(e[1]):
			return true
	return false


## 2 x max(sight x sight factor, life sense) + 5.
static func range_of(m: GameUnit) -> float:
	var sight := (float(m.stats.get("sight", 15.0)) + m.sense_bonus(0)) * m.sight_factor()
	return 2.0 * maxf(sight, m.sense(2)) + 5.0
