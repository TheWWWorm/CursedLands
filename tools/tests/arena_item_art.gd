extends Node
## Native art review sheet: the exact control at reward and inventory sizes.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func label_at(parent: Control, text: String, at: Vector2, width: float, pixels: int, color: Color) -> void:
	var label := Label.new()
	label.text = text; label.position = at; label.size.x = width
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Art review needs a rendered window.")
		get_tree().quit(1); return
	await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720)
	RemakeText.lang = "en"
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("0b1219")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(background)
	label_at(sheet, "Cursed Lands · Equipment", Vector2(36,20), 1200, 28, Color("e8e1cf"))
	label_at(sheet, "Original SVG relics · 96 px reward art / 32–44 px inventory art · native Godot render", Vector2(36,57), 1200, 15, Color("9aa9aa"))
	var index := 0
	for kind: String in ArenaItems.RULES:
		var cell := Panel.new()
		cell.position = Vector2(36+(index%4)*306, 104+(index/4)*292)
		cell.size = Vector2(288,272)
		cell.add_theme_stylebox_override("panel", ArenaCreatureCard.style(Color("151f27"),Color("394647"), Vector2(8,8)))
		sheet.add_child(cell)
		label_at(cell, ArenaItems.title(kind), Vector2(16,15), 256, 19, ArenaItemEmblem.color_for(kind))
		for edge: int in [96,32,44]:
			var art := ArenaItemEmblem.new()
			art.kind = kind
			art.custom_minimum_size = Vector2(edge,edge)
			art.size = art.custom_minimum_size
			art.position = Vector2(96,49) if edge == 96 else Vector2(65,190) if edge == 32 else Vector2(178,184)
			cell.add_child(art)
			check(art.custom_minimum_size == Vector2(edge,edge), "%s keeps %d px caller size" % [kind,edge])
			check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s art does not block input" % kind)
		label_at(cell,"96 px",Vector2(123,149),70,13,Color("788e94"))
		label_at(cell,"32 px",Vector2(62,233),70,13,Color("9aa9aa"))
		label_at(cell,"44 px",Vector2(180,233),70,13,Color("9aa9aa"))
		check(ArenaItemEmblem.ART[kind].get_size() == Vector2(256,256), "%s imports at source size" % kind)
		index += 1
	for frame in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("user://arena-item-art.png")
	check(error == OK,"contact sheet written")
	print("ARENA_ITEM_ART ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
