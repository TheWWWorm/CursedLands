class_name WorldLabels
extends Control
## Remake (gamepad, docs/gamepad_design.md §3.1): while L3 is held
## (PadField.world_info, BG3's "world information"), a name label over
## everything around the party that can be acted on: living units (enemies
## in red, the others in the interface's text colour), bodies that can be
## looted or revived (with the original "use" cursor beside the name),
## levers / chests / doors that can be used ("use" cursor) and open zone
## exits (the "move" cursor and the zone's name). the original draws no labels
## over the world; the look follows the remake's co-op name tags
## (PlayerNames): the interface font, a 1 px shadow, a fixed size
## on screen. Only what lies within RANGE m of a party member and, under the
## fog of war (UnitFog), inside the party's sight; nothing off screen or
## behind the camera. Labels that would overlap are lifted above each other.
## Drawn on a canvas layer below the HUD (PadField adds it).

const RANGE := 30.0
const LIFT := 4.0   # px above the point, at 600 px

var field: Node   # PadField
## The texts drawn last (tests).
var drawn: PackedStringArray = []
var _icons := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func active() -> bool:
	return field != null and bool(field.get("world_info")) and PadInput.active == "pad" and field.call("takes_input")


func _process(_dt: float) -> void:
	var on := active()
	if visible != on:
		visible = on
		if not on:
			drawn = PackedStringArray()
	if on:
		queue_redraw()


func _icon(kind: String) -> Texture2D:
	if not _icons.has(kind):
		var f := GameCursor.frames(kind)
		_icons[kind] = ImageTexture.create_from_image(f[0]) if not f.is_empty() else null
	return _icons[kind]


## The party's eyes: [position, range²] (UnitFog's rule), and whether the fog
## of war is on.
func _eyes(g: Game) -> Array:
	var out: Array = []
	for m: GameUnit in g.my_units():
		var r := UnitFog.range_of(m)
		out.append([m.pos, r * r])
	return out


func _near(eyes: Array, at: Vector2, fog: bool) -> bool:
	for e: Array in eyes:
		var d := (e[0] as Vector2).distance_squared_to(at)
		if d < RANGE * RANGE and (not fog or d < float(e[1])):
			return true
	return false


static func unit_name(u: GameUnit) -> String:
	var t := VillageName.title_of(u)
	return t if t != "" else u.display_name


## What a lever-type map object is, by its door flag and figure name.
static func lever_title(w: GameWorld, nid: int) -> String:
	var lv: Dictionary = w.levers.get(nid, {})
	var obj = w.objects.get(nid)
	var fig := ""
	if obj is Node and (obj as Node).has_meta("ei"):
		fig = String(((obj as Node).get_meta("ei") as Dictionary).get("template", "")).to_lower()
	if "chest" in fig or "box" in fig:
		return RemakeText.t("Chest")
	if int(lv.get("door", 0)) != 0 or "door" in fig:
		return RemakeText.t("Door")
	if "gate" in fig:
		return RemakeText.t("Gate")
	return RemakeText.t("Lever")


## [world point, text, colour, cursor kind ("" none)] of every label now.
func entries() -> Array:
	var out: Array = []
	var g: Game = field.get("game") if field else null
	if g == null or g.world == null or g.session == null:
		return out
	var w := g.world
	var s := g.session
	var me := s.my_index
	var conn := PadField.conn_id(self, s.online)
	var eyes := _eyes(g)
	var f: UnitFog = g.get_node_or_null(^"UnitFog")
	var fog := f != null and f.active()
	var lead: GameUnit = field.call("leader")
	var tags := g.get_node_or_null(^"PlayerNamesLayer/PlayerNames") as PlayerNames
	var names_shown := tags != null and tags.active()
	for u: GameUnit in w.units.values():
		if u.hidden or not u.visible or u.model == null or not _near(eyes, u.pos, false):
			continue
		var up := Vector3.UP * (0.7 if u.dead else 2.2)
		if u.dead:
			var revive := g.revive_target(u) != null
			if not revive and not Session.lootable(u, me, conn):
				continue
			out.append([u.global_position + up, unit_name(u), Interface800.GREY, "cursor_use"])
			continue
		if u.controller == me:
			if s.shop_available() and not Briefings.pending_for(s.state, u, me).is_empty():
				out.append([u.global_position + up, unit_name(u), Interface800.TEXT, "cursor_talk"])
			continue   # the own party: the faces and the selection show it
		if u.controller >= 0:
			if not names_shown:
				out.append([u.global_position + up, unit_name(u), NetStatus.colour(u.controller, s.players), ""])
			continue
		var enemy := lead != null and w.is_enemy(lead, u)
		var talk := s.shop_available() and not Briefings.pending_for(s.state, u, me).is_empty()
		out.append([u.global_position + up, unit_name(u), Color8(255, 120, 90) if enemy else Interface800.TEXT,
			"cursor_talk" if talk else ""])
	if not s.shop_available():
		for nid in w.levers:
			if w.lever_sys == null or not w.lever_sys.usable(nid):
				continue
			var obj = w.objects.get(nid)
			if obj == null or not is_instance_valid(obj) or not (obj as Node3D).is_visible_in_tree():
				continue
			var p := (obj as Node3D).global_position
			if not _near(eyes, Vector2(p.x, -p.z), fog):
				continue
			out.append([p + Vector3.UP * 1.3, lever_title(w, int(nid)), Interface800.TEXT, "cursor_use"])
	var exits: Dictionary = w.zone.get("exits", {})
	for n in exits:
		var ex: Dictionary = exits[n]
		var to := String(ex.get("to", "none")).to_lower()
		if to == "none" or not ex.has("area") or s.state.get_var(0, "z." + to) == 1.0:
			continue
		var c := Rect2(ex.area).get_center()
		if not _near(eyes, c, fog):
			continue
		var title := s.zone_title(to)
		if title.to_lower() == to:   # no "zone <id>" text (a village's way out)
			title = RemakeText.t("Exit")
		out.append([w.to_global(EISpace.pos(c.x, c.y, w.ground_at(c.x, c.y) + 1.0)), title, Interface800.TEXT, "cursor_move"])
	return out


func _draw() -> void:
	drawn = PackedStringArray()
	var cam := get_viewport().get_camera_3d()
	if cam == null or not active():
		return
	var vs := get_viewport_rect().size
	var k := minf(vs.x, vs.y) / 600.0
	var font := Interface800.font()
	var fs := clampi(int(round(800.0 * k * Interface800.FONT_EM[1])), 11, 22)
	var sh := maxf(1.0, round(k))
	var isz := float(fs) * 1.3
	var placed: Array[Rect2] = []
	var items: Array = []
	for e: Array in entries():
		var p: Vector3 = e[0]
		if cam.is_position_behind(p):
			continue
		var at := cam.unproject_position(p) - Vector2(0.0, LIFT * k)
		var text: String = e[1]
		if text.is_empty():
			continue
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var iw := isz + 2.0 if String(e[3]) != "" else 0.0
		var r := Rect2(at.x - (tw + iw) * 0.5, at.y - font.get_height(fs), tw + iw, font.get_height(fs))
		if r.end.x < 0.0 or r.position.x > vs.x or r.end.y < 0.0 or r.position.y > vs.y:
			continue
		items.append([r, e, at.distance_squared_to(vs * 0.5)])
	# The nearest to the screen's middle first: they keep their place.
	items.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	for it: Array in items:
		var r: Rect2 = it[0]
		var e: Array = it[1]
		for tries in 6:
			var hit := false
			for q in placed:
				if q.grow(1.0).intersects(r):
					r.position.y = q.position.y - r.size.y - 1.0
					hit = true
			if not hit:
				break
		placed.append(r)
		var x := r.position.x
		var kind := String(e[3])
		if kind != "":
			var t := _icon(kind)
			if t:
				draw_texture_rect(t, Rect2(Vector2(x, r.end.y - isz + 2.0 * k), Vector2(isz, isz)), false)
			x += isz + 2.0
		var base := Vector2(x, r.end.y - font.get_descent(fs))
		draw_string(font, base + Vector2(sh, sh), e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Interface800.SHADOW)
		draw_string(font, base, e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, e[2])
		drawn.append(String(e[1]))
