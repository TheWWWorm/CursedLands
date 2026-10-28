extends SettingsDialog
## One explicit choice, with the consequences beside each action.
signal chosen(full: bool)
const Refund := preload("res://src/game/training_refund.gd")
var original_button: Button
var full_button: Button
var cancel_button: Button

func _ready() -> void:
	# Let the container's wrapped content determine its height in each language.
	build_shell("Reset skills", Vector2(660, 0))
	# Match MessageBox: black inset, original saveload bevel and amber title.
	# Inset the fill so it cannot paint over the existing five-pixel frame.
	var inset := plate(Color.BLACK, Color.TRANSPARENT, 24)
	inset.set_expand_margin_all(-5)
	_surface.add_theme_stylebox_override("panel", inset)
	var heading := dialog_body.get_child(0) as Label
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Interface800.colorref(0x31b3ff))
	theme.set_color("font_shadow_color", "Label", Interface800.SHADOW)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	make_label("Base attributes, equipment and earned XP stay unchanged.", dialog_body, true)
	original_button = make_button("Restore starting skills", dialog_body, func(): _choose(false))
	make_label("Keep the character's original skills and abilities. Refund points spent beyond those starting ranks.", dialog_body)
	full_button = make_button("Full reset", dialog_body, func(): _choose(true))
	make_label("Set every skill and ability to zero and refund all their points, including starting ranks and skill gifts.", dialog_body)
	cancel_button = make_button("Cancel", dialog_body, _cancel)
	for child in dialog_body.get_children():
		if child is Label: child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func open(hero: Dictionary) -> void:
	for pair in [[original_button, false], [full_button, true]]:
		var reason := Refund.reason(hero, pair[1])
		pair[0].disabled = not reason.is_empty()
		# Disabled choices explain their state in visible, wrapped text too.
		if not reason.is_empty():
			var note := make_label(reason, dialog_body, true)
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dialog_body.move_child(note, pair[0].get_index() + 2)
	capture_background()
	show()
	layout_shell()
	(original_button if not original_button.disabled else full_button).grab_focus()

func _choose(full: bool) -> void:
	if GameSound.instance: GameSound.instance.ui("buttons\\messbox\\ok.wav")
	chosen.emit(full)
	hide()
	queue_free()

func _cancel() -> void:
	if GameSound.instance: GameSound.instance.ui("buttons\\messbox\\cancel.wav")
	hide()
	queue_free()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and UiInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_cancel()
