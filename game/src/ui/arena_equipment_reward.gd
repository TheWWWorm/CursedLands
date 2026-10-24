class_name ArenaEquipmentReward
extends Button
## One choice, with original item art and the game's stone / metal materials.

const SERIF = preload("res://fonts/LiberationSerif-Regular.ttf")
const BOLD = preload("res://fonts/LiberationSans-Bold.ttf")
var kind := ""
var art: ArenaItemEmblem
var description: RichTextLabel
var _content: MarginContainer
var _action: Label
var _accent := ArenaCreatureCard.GOLD
var _stone: Texture2D
var _light := 0.0:
	set(value):
		_light = value
		queue_redraw()
var _motion: Tween


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(250, 458)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = RemakeText.t("Choose %s") % ArenaItems.title(kind)
	_accent = ArenaItemEmblem.color_for(kind)
	_stone = Interface800.tex("campinfo")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_content = MarginContainer.new()
	add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 20)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_content.add_child(column)
	var role := _label(column, (ArenaItems.tier_label(kind) + " · " + role_name(kind)).to_upper(), 12, _accent)
	role.add_theme_font_override("font", BOLD)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art = ArenaItemEmblem.new()
	art.kind = kind
	art.framed = false
	art.custom_minimum_size = Vector2(138, 138)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(art)
	var title := _label(column, ArenaItems.title(kind), 25, ArenaCreatureCard.PAPER)
	title.add_theme_font_override("font", SERIF)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 50
	var line := HSeparator.new()
	var line_style := StyleBoxLine.new()
	line_style.color = Color(_accent, 0.3)
	line_style.thickness = 1
	line.add_theme_stylebox_override("separator", line_style)
	column.add_child(line)
	description = RichTextLabel.new()
	description.name = "ItemEffect"
	description.bbcode_enabled = true
	description.fit_content = true
	description.scroll_active = false
	description.custom_minimum_size.y = 132
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("normal_font_size", 14)
	description.add_theme_font_size_override("bold_font_size", 14)
	description.add_theme_font_override("bold_font", BOLD)
	description.add_theme_color_override("default_color", Color("d9d8ce"))
	description.add_theme_constant_override("line_separation", 2)
	description.text = _effect_text()
	column.add_child(description)
	_action = _label(column, RemakeText.t("Choose item"), 15, ArenaCreatureCard.GOLD)
	_action.name = "ChooseAction"
	_action.add_theme_font_override("font", BOLD)
	_action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action.custom_minimum_size.y = 34
	for child: Control in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.minimum_size_changed.connect(_measure)
	resized.connect(_measure)
	mouse_entered.connect(_state_changed)
	mouse_exited.connect(_state_changed)
	focus_entered.connect(_state_changed)
	focus_exited.connect(_state_changed)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	_measure.call_deferred()
	_state_changed()


func _measure() -> void:
	custom_minimum_size.y = maxf(458, _content.get_combined_minimum_size().y)
	art.pivot_offset = art.size * 0.5
	queue_redraw()


func _state_changed() -> void:
	if is_instance_valid(_motion): _motion.kill()
	var active := not disabled and (is_hovered() or has_focus())
	_motion = create_tween().set_parallel(true)
	_motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "_light", 1.0 if active else 0.0, 0.14)
	_motion.tween_property(art, "scale", Vector2.ONE * (1.04 if active else 1.0), 0.14)
	_action.add_theme_color_override("font_color", Color("fff0bf") if active else ArenaCreatureCard.GOLD)
	_content.modulate.a = 0.45 if disabled else 1.0


func _effect_text() -> String:
	# Emphasize the actual translated values, keeping one source of mechanics.
	var text := ArenaItems.description(kind, false)
	var numbers := RegEx.new()
	numbers.compile("[0-9]+(?:[.,][0-9]+)?%?")
	var matches := numbers.search_all(text)
	matches.reverse()
	for found: RegExMatch in matches:
		text = text.substr(0, found.get_start()) + "[b][color=#f1dfae]" + found.get_string() + "[/color][/b]" + text.substr(found.get_end())
	return text


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	var shadow := ArenaCreatureCard.style(Color("101514"), Color.TRANSPARENT)
	shadow.shadow_color = Color(0, 0, 0, 0.5)
	shadow.shadow_size = 9
	shadow.shadow_offset = Vector2(0, 5)
	draw_style_box(shadow, bounds)
	if _stone:
		var source := Rect2(Vector2(14, 14) * _stone.get_size() / 256.0, Vector2(100, 100) * _stone.get_size() / 256.0)
		for y in ceili(size.y / 100.0):
			for x in ceili(size.x / 100.0):
				var at := Vector2(x, y) * 100.0
				var cell := (size - at).min(Vector2(100, 100))
				draw_texture_rect_region(_stone, Rect2(at, cell), Rect2(source.position, source.size * cell / 100.0), Color(0.55, 0.6, 0.57, 0.22))
	# A soft pool of light presents the actual object without an icon medallion.
	var centre := Vector2(size.x * 0.5, 111)
	for radius in range(115, 12, -4):
		draw_circle(centre, float(radius), Color(_accent, 0.004 + _light * 0.003))
	var edge := _accent.lerp(Color.WHITE, _light * 0.25)
	if ArenaItems.tier(kind) > 1:
		draw_rect(bounds.grow(-2), edge, false, 3)
		draw_rect(bounds.grow(-7), Color(_accent, 0.25 + _light * 0.25), false, 1)
	if is_instance_valid(_action):
		var action := Rect2(get_global_transform().affine_inverse() * _action.global_position, _action.size)
		draw_rect(action, Color(edge, 0.07 + _light * 0.1))
		draw_line(action.position, Vector2(action.end.x, action.position.y), Color(edge, 0.4 + _light * 0.45), 1, true)
	if has_focus(): draw_line(Vector2(28, size.y - 12), Vector2(size.x - 28, size.y - 12), ArenaCreatureCard.PAPER, 3)
	if is_pressed(): draw_rect(bounds.grow(-5), Color(0, 0, 0, 0.14))


static func role_name(item_kind: String) -> String:
	match ArenaItems.effect(item_kind):
		"fang": return RemakeText.t("Life steal")
		"storm": return RemakeText.t("Chain lightning")
		"venom": return RemakeText.t("Healing suppression")
		"ward": return RemakeText.t("Personal shield")
		"guardian": return RemakeText.t("Ally protection")
		"echo": return RemakeText.t("Spell echo")
		"thorn": return RemakeText.t("Melee retaliation")
		"berserker": return RemakeText.t("Battle frenzy")
	var rule: Dictionary = ArenaItems.RULES.get(item_kind, {})
	if rule.has("damage"): return RemakeText.t("Attack damage")
	if rule.has("spell"): return RemakeText.t("Spell damage")
	if rule.has("health"): return RemakeText.t("Health bonus")
	if rule.has("actions"): return RemakeText.t("Action speed")
	if rule.has("physical_armor"): return RemakeText.t("Physical armor")
	if rule.has("elemental_armor"): return RemakeText.t("Elemental armor")
	return ""


func _label(parent: Node, value: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
