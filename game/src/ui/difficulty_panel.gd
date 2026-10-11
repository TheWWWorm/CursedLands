class_name DifficultyPanel
extends SettingsDialog
## Game setup owns a new campaign's draft. Opening/cancelling never writes
## preferences; each new campaign starts from the shipped gameplay defaults.
signal accepted(level: int)
signal cancelled
signal closed
var level := 0
var _new_game := true
var _draft := {}
var _choices: Array[Button] = []
var _mods: ModPanel
var _mods_button: Button
var _summary: Label
var _status: Label
var _start: Button

func _ready() -> void:
	build_shell("Game setup", Vector2(650, 590))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	dialog_body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	_summary = make_label("", content, true)
	var section := card(content)
	make_label("Difficulty", section)
	var group := ButtonGroup.new()
	for choice in [[0, "Normal", "The standard challenge, with the original combat balance."],
			[1, "Easy", "A gentler challenge for exploring the story."]]:
		var button := make_button(choice[1], section, func(): _choose(choice[0]))
		button.toggle_mode = true
		button.button_group = group
		_choices.append(button)
		make_label(choice[2], section, true).add_theme_font_size_override("font_size", 17)
	_mods_button = make_button("Mods and rules…", content, _open_mods)
	_mods_button.tooltip_text = RemakeText.t("Optional profiles, gameplay rules and installed mods.")
	_status = make_label("", content, true)
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	dialog_body.add_child(actions)
	make_button("Back", actions, _cancel).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start = make_button("Start game", actions, _accept)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mods = ModPanel.new()
	add_child(_mods)
	_mods.closed.connect(func():
		_choose(int(_draft.rules.difficulty) if _new_game else GameData.option("difficulty"))
		_refresh_summary()
		_mods_button.grab_focus())

func open(new_game := true) -> void:
	_new_game = new_game
	_draft = ModStore.new_game_defaults() if new_game else {}
	_start.text = RemakeText.t("Start game" if new_game else "Done")
	_status.text = RemakeText.t("Standard rules. Customize them with Mods and rules.") if new_game else ""
	_choose(int(_draft.rules.difficulty) if new_game else GameData.option("difficulty"))
	for button in _choices:
		button.disabled = not new_game and ModStore.editable("difficulty") != ""
	capture_background()
	visible = true
	layout_shell()
	_refresh_summary()
	_start.grab_focus.call_deferred()

func _choose(value: int) -> void:
	level = value
	if _new_game and not _draft.is_empty(): _draft.rules.difficulty = level
	for i in _choices.size(): _choices[i].set_pressed_no_signal(i == level)

func _refresh_summary() -> void:
	_summary.text = CampaignChoices.title(GameData.campaign_id) + "\n" + str(ModStore.profile().name)

func _open_mods() -> void:
	_mods.draft = _draft if _new_game else {}
	_mods.open("rules")

func _accept() -> void:
	if _mods.visible: return
	var error := ""
	if _new_game:
		_draft.rules.difficulty = level
		error = ModStore.apply_settings(_draft.rules, _draft.values)
	elif ModStore.editable("difficulty") == "":
		error = ModStore.apply_rules({"difficulty": level})
	if error != "":
		_status.text = error
		return
	visible = false
	if _new_game: accepted.emit(level)
	closed.emit()

func _cancel() -> void:
	if _mods.visible: return
	visible = false
	cancelled.emit()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _mods.visible or not (event is InputEventKey and event.pressed): return
	if event.keycode == KEY_ESCAPE: _cancel()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]: _accept()
	else: return
	get_viewport().set_input_as_handled()

func pad_targets() -> Array:
	var out := []
	for button in [_choices[0], _choices[1], _mods_button, _start, _start.get_parent().get_child(0)]:
		if not button.disabled: out.append({"rect": button.get_global_rect(), "id": button})
	return out

func pad_press(action: String, phase: String) -> bool:
	if _mods.visible: return false
	if action in ["cancel", "menu"]:
		if phase == "down": _cancel()
		return true
	return false
