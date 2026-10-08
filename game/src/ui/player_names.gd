class_name PlayerNames
extends Control
## Remake (co-op, option "coop_player_names", default on): each player's name
## above the head of their main hero, so the heroes are easy to tell apart.
## the original draws no names over units (VillageName is the village screen's
## name at the pointer, FlyingHP the hit numbers); the look follows those:
## the interface font (Interface800.font), a 1 px shadow, the
## player's chat colour (NetStatus.colour) as in the player list and chat.
## The size is fixed on screen (font 1 of the 800×600 layout scaled by the
## shorter window side, 11..22 px), so it stays readable at any distance.
## Drawn on a canvas layer below the HUD (as FlyingHP), centred a little
## above the top of the hero's "hd" part (else its figure), only while the
## hero is drawn (UnitFog: units outside the party's sight are hidden), in
## front of the camera and on the screen; not on the village screen, not in
## single player.

const OPTION := "coop_player_names"
const LIFT := 3.0   # px above the head's top, at 600 px

var game: Game


## The node of a game (created on first use, on a canvas layer below the HUD).
static func of(g: Game) -> PlayerNames:
	var layer := g.get_node_or_null("PlayerNamesLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "PlayerNamesLayer"
		layer.layer = -1
		var n := PlayerNames.new()
		n.name = "PlayerNames"
		n.game = g
		layer.add_child(n)
		g.add_child(layer)
	return layer.get_node("PlayerNames") as PlayerNames


## The name of the player with slot `index` ("" when nobody has it).
static func player_name(s: Session, index: int) -> String:
	if s == null or index < 0:
		return ""
	for p: Dictionary in s.players.values():
		if int(p.get("index", -1)) == index:
			return String(p.get("name", ""))
	return ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func active() -> bool:
	var s := game.session if game else null
	return s != null and s.multiplayer_game and game.world != null and GameData.option(OPTION) != 0 \
			and not s.shop_available() and not (game.hud and game.hud._movie and game.hud._movie.visible)


func _process(_dt: float) -> void:
	visible = active()
	if visible:
		queue_redraw()


## [unit, name, colour] of every player's main hero.
func entries() -> Array:
	var out := []
	for u: GameUnit in game.world.party_units():
		if u.controller < 0 or not u.has_meta("hero") or (u.get_meta("hero") as Dictionary).has("merc"):
			continue
		var n := player_name(game.session, u.controller)
		if n:
			out.append([u, n, NetStatus.colour(u.controller, game.session.players)])
	return out


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or game == null or game.world == null:
		return
	var vs := get_viewport_rect().size
	var k := minf(vs.x, vs.y) / 600.0
	var f := Interface800.font()
	var fs := clampi(int(round(800.0 * k * Interface800.FONT_EM[1])), 11, 22)
	var sh := maxf(1.0, round(k))
	for e: Array in entries():
		var u: GameUnit = e[0]
		if not is_instance_valid(u) or not u.visible or u.hidden or u.model == null or not u.model.is_visible_in_tree():
			continue
		var top := _head_top(u)
		if cam.is_position_behind(top):
			continue
		var at := cam.unproject_position(top) - Vector2(0.0, LIFT * k)
		var name: String = e[1]
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2(at.x - w * 0.5, at.y - f.get_descent(fs))
		if base.x + w < 0.0 or base.x > vs.x or base.y < 0.0 or base.y - f.get_ascent(fs) > vs.y:
			continue
		draw_string(f, base + Vector2(sh, sh), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Interface800.SHADOW)
		draw_string(f, base, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, e[2])


## World point over the hero: the top of its "hd" part's meshes (it follows
## the pose: crouching, lying), else of the whole figure.
func _head_top(u: GameUnit) -> Vector3:
	var hd := u.model.find_child("hd", true, false) as Node3D
	var best := -INF
	var c := u.global_position
	for mi: Node in (hd.get_children() if hd else u.model.find_children("*", "MeshInstance3D", true, false)):
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh and (mi as MeshInstance3D).is_visible_in_tree():
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			if b.end.y > best:
				best = b.end.y
				c = Vector3(b.get_center().x, b.end.y, b.get_center().z)
	if best == -INF:
		return u.global_position + Vector3(0.0, 1.9, 0.0)
	return c
