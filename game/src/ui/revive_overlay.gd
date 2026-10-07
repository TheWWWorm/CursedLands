class_name ReviveOverlay
extends Interface800
## Remake option "revive" (Revive): over a fallen party member that a selected
## hero or mercenary can help, the action's name under the cursor — drawn as the
## village screen's name label (VillageName: font 1, centred in 250 units, the
## label's top 20 units above the pointer) — and, over every unit at that work,
## a small bar of its progress (the action string "revive:<clip>:<n>",
## so co-op clients see it too).

const HOVER := "Help %s up"
const NOTICE_HINT := "A companion can still help the hero up: select one and click the body."
const BAR_W := 40.0   # 800×600 units
const BAR_H := 5.0
const BAR_UP := 1.8   # metres above the unit's feet

var game: Game
var _label := ""
var _at := Vector2.ZERO
var _bars: Array = []   # [screen point, progress]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_dt: float) -> void:
	var s := ""
	var at := Vector2.ZERO
	var bars := []
	if game and game.session and game.world and Revive.enabled(game.session):
		var p := get_viewport().get_mouse_position()
		if not game.hud.blocks_input() and get_viewport().gui_get_hovered_control() == null:
			var t := game.revive_target(game.pick_unit(p))
			if t:
				s = RemakeText.t(HOVER) % t.display_name
				at = (p - global_position) / kv()
		var cam := get_viewport().get_camera_3d()
		if cam:
			for u: GameUnit in game.world.visible_units():
				var f := Revive.progress(u)
				if f < 0.0 or not u.visible or u.hidden:
					continue
				var wp := u.get_global_transform_interpolated().origin + Vector3(0.0, BAR_UP, 0.0)
				if cam.is_position_behind(wp):
					continue
				bars.append([(cam.unproject_position(wp) - global_position) / kv(), f])
	if s != _label or (s and at != _at) or bars != _bars or not _bars.is_empty():
		_label = s
		_at = at
		_bars = bars
		queue_redraw()


func _draw() -> void:
	for b: Array in _bars:
		var c: Vector2 = b[0]
		var r := r8(Rect2(c.x - BAR_W * 0.5, c.y - BAR_H, BAR_W, BAR_H))
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(r.position, Vector2(r.size.x * float(b[1]), r.size.y)), TEXT)
	if _label:
		text(Rect2(_at.x - 125.0, _at.y - 20.0, 250.0, 30.0), _label, 1, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
