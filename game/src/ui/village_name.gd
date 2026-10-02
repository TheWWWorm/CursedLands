class_name VillageName
extends Interface800
## The village screen's name under the cursor (the original hover
## the screen's input object): over a living unit whose controller is
## idle (none, or AI state 0 / 11 9) — and, in a
## network game, not the unit whose topic list is open — the talk cursor
## when it has topics (Game._update_cursor), then the name kept for its id
## (unit) in the map (screen), drawn
## (font 1, DT_CENTER, 1 px shadow) into the screen's text widget
## (+4) placed at the mouse − (125, 20) and shown
## . Units without an entry get no label. The map is filled
## every texts.res key "pers *" → id (key
## char 5) (the script name hash, ScriptVM.name_id) → the entry's first line
## e.g. "pers elder" → "Erfar the Silvertongue".
## The widget is the village build's (0,0)-(250,30) text surface
## (: (.., 0, 0, 250, 30, 5, 1)); the empty rect
## draws into the whole surface, so the name is centred in 250 units, top
## aligned, the surface's top 20 units above the pointer.
## **Approx.**: the controller-idle test is not modelled.

var game: Game
var _name := ""
var _at := Vector2.ZERO
static var _pers := {}   # name id -> title


static func title_of(u: GameUnit) -> String:
	if _pers.is_empty() and GameData.texts:
		for k: String in GameData.texts.names_with_suffix(""):
			if k.begins_with("pers "):
				var t := GameData.text(k).get_slice("\n", 0).strip_edges()
				if t:
					_pers[ScriptVM.name_id(k.substr(5))] = t
		if _pers.is_empty():
			_pers[-1] = ""
	var t := String(_pers.get(u.uid, ""))
	if t.is_empty() and u.info.get("name", ""):   # a unit named in the .mob
		t = String(_pers.get(ScriptVM.name_id(String(u.info.name)), ""))
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_dt: float) -> void:
	var s := ""
	var at := Vector2.ZERO
	if game and game.session and game.world and game.session.shop_available() and not game.hud.blocks_input() \
			and get_viewport().gui_get_hovered_control() == null:
		var p := get_viewport().get_mouse_position()
		var u := game.pick_unit(p)
		if u and not u.dead:
			s = title_of(u)
			at = (p - global_position) / kv()
	if s != _name or (s and at != _at):
		_name = s
		_at = at
		queue_redraw()


func _draw() -> void:
	if _name:
		text(Rect2(_at.x - 125.0, _at.y - 20.0, 250.0, 30.0), _name, 1, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
