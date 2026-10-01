class_name ActionStrip
extends Control
## Left action strip of the battle HUD (the original
## ): 40×40 cells at x 0..40 stacked up from y 470..510 of the
## 800×600 layout.: with one unit selected the cell is its
## Use/Steal — textures.res "skill0009", tip "<perk Science> <level>" + tip
## 10511, interaction mode 7 (keyboard.ini use_science); with several units
## selected it is Follow — "skill0011", tip 10510, mode 8: the next clicked
## unit is followed by the selection. Approx.: the picture is drawn flat
## instead of on the original's rotated plate model.

var game: Game


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


var _shown := false
var _follow := false


func _process(_dt: float) -> void:
	var follow := game != null and game.selected.filter(func(x): return is_instance_valid(x)).size() > 1
	var shown := follow or _hero() != null
	if shown != _shown or follow != _follow:
		_shown = shown
		_follow = follow
		queue_redraw()


func _hero() -> GameUnit:
	if game == null or game.selected.is_empty() or not is_instance_valid(game.selected[0]):
		return null
	var u: GameUnit = game.selected[0]
	return u if u.has_meta("hero") else null


func _cell() -> Rect2:
	return Rect2(Vector2(0, size.y - size.x), Vector2(size.x, size.x))


func _has_point(p: Vector2) -> bool:
	return _shown and _cell().has_point(p)


func _get_tooltip(_p: Vector2) -> String:
	if _follow:
		return GameData.text("tip 10510").strip_edges()
	var u := _hero()
	if u == null:
		return ""
	return "%s %d\n%s" % [Skills.title("science"), Skills.level(u.get_meta("hero"), "science"),
		GameData.text("tip 10511").strip_edges()]


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		game._key_action("follow" if _follow else "use_science")
		accept_event()


func _draw() -> void:
	if not _shown:
		return
	var r := _cell().grow(-2)   # no cell frame: only makes hit rectangles
	var tex := SpellSlots.icon("skill0011" if _follow else "skill0009")   # 2D pictures come out of EIMmp upside down
	if tex:
		draw_texture_rect(tex, r.grow(-2), false)
