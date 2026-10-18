class_name ArenaAllianceBadge
extends Control
var key := ""
var count := 0
var icon: Texture2D
func _ready() -> void:
	custom_minimum_size=Vector2(70,50)
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_meta("arena_alliance",key)
	icon=load("res://assets/arena/alliance_%s.svg" % key)

func update_count(value: int) -> void:
	count=value
	tooltip_text = "%s · %d/%d\n%s" % [RemakeText.t(ArenaAlliances.RULES[key].name),count,ArenaAlliances.target(key,count),ArenaAlliances.effect(key,ArenaAlliances.rank(key,count))]
	queue_redraw()

func _draw() -> void:
	var active := ArenaAlliances.rank(key,count)>0
	var ink: Color = ArenaCreatureCard.TRIBE_COLORS[key]
	var box := Rect2(0,2,38,38)
	draw_rect(box,Color(ink*0.23,0.92) if active else Color(0.03,0.04,0.04,0.8))
	draw_rect(box,ink if active else Color("65706a"),false,1)
	if icon: draw_texture_rect(icon,box.grow(-6),false,ink if active else Color("929a92"))
	var thresholds: Array=ArenaAlliances.RULES[key].thresholds
	for group in thresholds.size():
		var previous := 0 if group==0 else int(thresholds[group-1])
		for pip in int(thresholds[group])-previous:
			var r := Rect2(42+group*6,23-pip*17,4,14)
			draw_rect(r,ink if count>previous+pip else Color("3b403c"))
	var font := get_theme_font("font")
	draw_string(font,Vector2(12,49),str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,12,ArenaCreatureCard.PAPER)
