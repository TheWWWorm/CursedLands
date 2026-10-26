class_name ArenaAllianceBadge
extends Button
signal scrolled(direction: int)
var key := ""
var count := 0
var _icon: Texture2D
func _ready() -> void:
	custom_minimum_size=Vector2(70,50)
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	set_meta("arena_alliance",key)
	_icon=load("res://assets/arena/alliance_%s.svg" % key)

func update_count(value: int) -> void:
	count=value
	tooltip_text = "%s · %d/%d\n%s" % [RemakeText.t(ArenaAlliances.RULES[key].name),count,ArenaAlliances.target(key,count),ArenaAlliances.effect(key,ArenaAlliances.rank(key,count))]
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scrolled.emit(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		accept_event()

func _draw() -> void:
	var active := ArenaAlliances.rank(key,count)>0
	var ink: Color = ArenaCreatureCard.TRIBE_COLORS[key]
	var box := Rect2(0,2,38,38)
	draw_rect(box,Color(ink*0.23,0.92) if active else Color(0.03,0.04,0.04,0.8))
	draw_rect(box,ink if active else Color("65706a"),false,1)
	if has_focus(): draw_rect(box.grow(3), ArenaCreatureCard.PAPER, false, 1)
	if _icon: draw_texture_rect(_icon,box.grow(-6),false,ink if active else Color("929a92"))
	var thresholds: Array=ArenaAlliances.RULES[key].thresholds
	for group in thresholds.size():
		var previous := 0 if group==0 else int(thresholds[group-1])
		for pip in int(thresholds[group])-previous:
			var r := Rect2(42+group*6,23-pip*17,4,14)
			draw_rect(r,ink if count>previous+pip else Color("3b403c"))
	var font := get_theme_font("font")
	draw_string(font,Vector2((box.size.x - font.get_string_size(str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,12).x) * 0.5,49),str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,12,ArenaCreatureCard.PAPER)
