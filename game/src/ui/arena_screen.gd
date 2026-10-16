class_name ArenaScreen
extends Control
## Roster/deployment tools and spectator controls, separate from Game's
## player-order HUD. All changes belong to this disposable arena session.

signal exit_requested

const GOLD := Color("d9bd83")
const INK := Color("111820")
const MUTED := Color("9caab6")
var match_state: ArenaMatch
var field: ArenaField
var selected_id := ""
var selected_team := 0
var _query: LineEdit
var _list: ItemList
var _preview: WikiPreview
var _creature_title: Label
var _stats: Label
var _roster_count: Label
var _message: Label
var _phase_label: Label
var _timer: Label
var _start: Button
var _pause: Button
var _edit: Button
var _rematch: Button
var _undo: Button
var _clear: Button
var _erase: Button
var _speed: OptionButton
var _team_buttons: Array[Button] = []
var _team_counts: Array[Label] = []
var _health: Array[ProgressBar] = []
var _result: PanelContainer
var _result_title: Label
var _result_detail: Label
var _sidebar: PanelContainer
var _subtitle: Label
var _status_age := 0.0
var _sound: GameSound
var _sound_world: GameWorld


func _ready() -> void:
	name = "Arena"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("e5e9e8"))
	var bg := ColorRect.new()
	bg.color = INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	match_state = ArenaMatch.new()
	add_child(match_state)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	root.add_child(heading)
	var title := _label(heading, RemakeText.t("Arena"), 36, GOLD)
	title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_subtitle = _label(heading, RemakeText.t("Build two armies. Let the creatures decide."), 16, MUTED)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, RemakeText.t("PvE expedition"), func():
		if get_parent().has_method("open_arena_pve"): get_parent().open_arena_pve(),
		RemakeText.t("Recruit creatures from Gipath, Ingos and Suslanger. Survive thirty battles."), GOLD)
	_button(heading, RemakeText.t("Main menu"), func(): exit_requested.emit(), RemakeText.t("Leave the arena and return to the main menu."))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_build_roster(body)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	_build_scoreboard(right)
	field = ArenaField.new()
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(240, 220)
	right.add_child(field)
	field.match_state = match_state
	match_state.create_world(field.stage)
	field.ground_clicked.connect(_place)
	field.creature_clicked.connect(_unit_clicked)
	field.cancel_requested.connect(_cancel_placement)
	_build_result()
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 8)
	toolbar.add_theme_constant_override("v_separation", 6)
	right.add_child(toolbar)
	_start = _button(toolbar, RemakeText.t("Start battle"), func(): match_state.start(), RemakeText.t("Both teams fight under AI control. Place at least one creature on each team."), GOLD)
	_pause = _button(toolbar, RemakeText.t("Pause"), match_state.toggle_pause, RemakeText.t("Pause or resume the battle. Space also works."))
	_edit = _button(toolbar, RemakeText.t("Edit teams"), match_state.reset, RemakeText.t("Restore the original formation and return to deployment."))
	_rematch = _button(toolbar, RemakeText.t("Rematch"), match_state.rematch, RemakeText.t("Restore the original formation and fight again."))
	_label(toolbar, RemakeText.t("Battle speed"), 14, MUTED)
	_speed = OptionButton.new()
	_speed.custom_minimum_size = Vector2(76, 38)
	_speed.tooltip_text = RemakeText.t("Watch at half, normal or double speed. Combat rules stay the same.")
	for text: String in ["0.5×", "1×", "2×"]: _speed.add_item(text)
	_speed.select(1)
	_speed.item_selected.connect(func(i): match_state.set_speed([0.5, 1.0, 2.0][i]))
	toolbar.add_child(_speed)
	_button(toolbar, "⌖", field.reset_camera, RemakeText.t("Reset arena camera"))
	_message = _label(right, "", 15, GOLD)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 40
	var help := _label(right, RemakeText.t("Wheel: zoom  ·  Middle drag: orbit  ·  Right click: cancel  ·  Space: pause"), 12, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sound = GameSound.new()
	add_child(_sound)
	_sound.set_process(false)
	match_state.world_replacing.connect(func():
		_sound.on_world(null)
		_sound_world = null)
	match_state.visual_event.connect(func(event):
		_sync_sound()
		_sound.on_event(event))
	match_state.changed.connect(_refresh)
	_fill_roster()
	_refresh()
	# The legacy HUD suppresses native tooltips globally. Arena help is also
	# shown in its persistent status line, including each option's help.
	for control: Control in find_children("*", "Control", true, false):
		if not control.tooltip_text.is_empty():
			control.mouse_entered.connect(_hint.bind(control.tooltip_text))
	resized.connect(_resize)
	_resize()


func _build_roster(parent: Control) -> void:
	_sidebar = PanelContainer.new()
	_sidebar.custom_minimum_size.x = 300
	_sidebar.add_theme_stylebox_override("panel", _style(Color("19232c"), Color("34434e"), 14))
	parent.add_child(_sidebar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	_sidebar.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	_label(heading, RemakeText.t("Creatures"), 22, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_count = _label(heading, "", 13, MUTED)
	_query = LineEdit.new()
	_query.placeholder_text = RemakeText.t("Search creatures…")
	_query.tooltip_text = RemakeText.t("Search creature names from the loaded campaign.")
	_query.custom_minimum_size.y = 38
	_query.text_changed.connect(func(_text): _fill_roster())
	box.add_child(_query)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 90
	_list.allow_reselect = true
	_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_list.add_theme_constant_override("v_separation", 7)
	_list.add_theme_font_size_override("font_size", 15)
	_list.add_theme_stylebox_override("panel", _style(Color("131c24"), Color("27343f"), 6))
	_list.add_theme_stylebox_override("selected", _style(Color("344149"), GOLD, 4))
	_list.item_selected.connect(func(index): _select(String(_list.get_item_metadata(index))))
	box.add_child(_list)
	_preview = WikiPreview.new()
	_preview.custom_minimum_size.y = 142
	box.add_child(_preview)
	_creature_title = _label(box, RemakeText.t("Choose a creature"), 17, Color("f0e2c6"))
	_creature_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_creature_title.custom_minimum_size.y = 40
	_stats = _label(box, RemakeText.t("Click a creature, choose its team, then click the battlefield."), 13, MUTED)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.custom_minimum_size.y = 48
	_label(box, RemakeText.t("Place on team"), 13, MUTED)
	var teams := HBoxContainer.new()
	box.add_child(teams)
	for i in 2:
		var button := _button(teams, _team_name(i), _choose_team.bind(i), RemakeText.t("New creatures join the selected team."), _team_color(i))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_team_buttons.append(button)
	var tools := HBoxContainer.new()
	box.add_child(tools)
	_erase = _button(tools, RemakeText.t("Remove"), _toggle_erase, RemakeText.t("Click a placed creature to remove it. Right click cancels."))
	_erase.toggle_mode = true
	_undo = _button(tools, RemakeText.t("Undo"), match_state.undo, RemakeText.t("Remove the last creature placed."))
	_clear = _button(box, RemakeText.t("Clear team"), func(): match_state.clear_team(selected_team), RemakeText.t("Remove every creature from the selected team."))


func _build_scoreboard(parent: Control) -> void:
	var scores := HBoxContainer.new()
	scores.add_theme_constant_override("separation", 12)
	parent.add_child(scores)
	for i in 2:
		if i == 1:
			var center := VBoxContainer.new()
			center.custom_minimum_size.x = 110
			scores.add_child(center)
			_phase_label = _label(center, "", 12, GOLD)
			_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_timer = _label(center, "00:00", 24)
			_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _style(Color("1c2933") if i == 0 else Color("302526"), _team_color(i).darkened(0.45), 12))
		scores.add_child(card)
		var box := VBoxContainer.new()
		card.add_child(box)
		_label(box, _team_name(i), 17, _team_color(i))
		_team_counts.append(_label(box, "", 13, Color("d3d9dc")))
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 4
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _style(INK, INK, 0))
		bar.add_theme_stylebox_override("fill", _style(_team_color(i), _team_color(i), 0))
		box.add_child(bar)
		_health.append(bar)


func _build_result() -> void:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field.add_child(center)
	_result = PanelContainer.new()
	_result.add_theme_stylebox_override("panel", _style(Color("151e27"), GOLD, 24))
	center.add_child(_result)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_result.add_child(box)
	_result_title = _label(box, "", 32, GOLD)
	_result_title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail = _label(box, "", 15, MUTED)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_button(buttons, RemakeText.t("Rematch"), match_state.rematch, RemakeText.t("Restore the original formation and fight again."), GOLD)
	_button(buttons, RemakeText.t("Edit teams"), match_state.reset, RemakeText.t("Restore the original formation and return to deployment."))
	_result.hide()


func _fill_roster() -> void:
	var rows := match_state.catalog.search(_query.text)
	_list.clear()
	for row: Dictionary in rows:
		var index := _list.add_item(row.title)
		_list.set_item_metadata(index, row.id)
		_list.set_item_tooltip(index, row.title)
		if row.id == selected_id: _list.select(index)
	_roster_count.text = str(rows.size())
	if rows.is_empty():
		_list.add_item(RemakeText.t("No creatures found"))
		_list.set_item_disabled(0, true)


func _select(id: String) -> void:
	if not match_state.catalog.by_id.has(id): return
	selected_id = id
	for i in _list.item_count:
		if _list.get_item_metadata(i) == id:
			_list.select(i)
			_list.ensure_current_is_visible()
	field.erase = false
	_erase.button_pressed = false
	var entry: Dictionary = match_state.catalog.by_id[id]
	_creature_title.text = entry.title
	var row: Dictionary = entry.row
	_stats.text = RemakeText.t("Health: %s   ·   Stamina: %s") % [WikiCatalog.num(row.get("hp", 0)), WikiCatalog.num(row.get("mana", 0))]
	_stats.text += "\n" + RemakeText.t("Damage: %s–%s   ·   Armor: %s") % [WikiCatalog.num(row.get("damage_min", 0)), WikiCatalog.num(float(row.get("damage_min", 0)) + float(row.get("damage_max", 0))), WikiCatalog.num(row.get("absorption", 0))]
	var available := _preview.show_model({"kind": "creature", "value": id})
	field.select_creature(id if available else "")
	if available:
		_hint(RemakeText.t("Click the battlefield to place %s. Click again to add more.") % entry.title)
	else:
		_hint(RemakeText.t("This creature's model is unavailable in the loaded game files."))


func _choose_team(team: int) -> void:
	selected_team = team
	field.team = team
	_refresh()


func _toggle_erase() -> void:
	field.erase = _erase.button_pressed
	_hint(RemakeText.t("Click a placed creature to remove it. Right click cancels.") if field.erase else RemakeText.t("Click a creature, choose its team, then click the battlefield."))


func _cancel_placement() -> void:
	selected_id = ""
	field.select_creature("")
	field.erase = false
	_erase.button_pressed = false
	_list.deselect_all()
	_hint(RemakeText.t("Click a creature, choose its team, then click the battlefield."))


func _place(point: Vector2) -> void:
	if match_state.phase != ArenaMatch.Phase.DEPLOY: return
	if field.erase: return
	var error := match_state.place(selected_id, selected_team, point)
	if error: _hint(error)


func _unit_clicked(unit: GameUnit) -> void:
	if field.erase and match_state.phase == ArenaMatch.Phase.DEPLOY:
		match_state.remove(unit)
	else:
		_hint(RemakeText.t("%s · Health: %d / %d") % [unit.display_name, maxi(0, int(unit.hp)), int(unit.max_hp)])


func _hint(text: String) -> void:
	_message.text = text
	_status_age = 5.0


func _refresh() -> void:
	if _start == null: return
	_sync_sound()
	var deploy := match_state.phase == ArenaMatch.Phase.DEPLOY
	_start.visible = deploy
	_start.disabled = match_state.team_count(0) == 0 or match_state.team_count(1) == 0
	_pause.visible = match_state.phase in [ArenaMatch.Phase.FIGHT, ArenaMatch.Phase.PAUSED]
	_pause.text = RemakeText.t("Resume") if match_state.phase == ArenaMatch.Phase.PAUSED else RemakeText.t("Pause")
	_edit.visible = not deploy
	_rematch.visible = not deploy
	_undo.disabled = not deploy or match_state.formation.is_empty()
	_clear.disabled = not deploy or match_state.team_count(selected_team) == 0
	_erase.disabled = not deploy
	_query.editable = deploy
	_list.mouse_filter = Control.MOUSE_FILTER_STOP if deploy else Control.MOUSE_FILTER_IGNORE
	_list.focus_mode = Control.FOCUS_ALL if deploy else Control.FOCUS_NONE
	for i in 2:
		_team_buttons[i].button_pressed = selected_team == i
		_team_buttons[i].disabled = not deploy
	_phase_label.text = [RemakeText.t("Deployment"), RemakeText.t("Battle"), RemakeText.t("Paused"), RemakeText.t("Battle over")][match_state.phase]
	_result.visible = match_state.phase == ArenaMatch.Phase.FINISHED
	if _result.visible:
		_result_title.text = RemakeText.t("Blue team wins") if match_state.winner == 0 else RemakeText.t("Red team wins") if match_state.winner == 1 else RemakeText.t("Draw")
		_result_title.add_theme_color_override("font_color", GOLD if match_state.winner < 0 else _team_color(match_state.winner))
		_result_detail.text = RemakeText.t("Time limit reached. Neither team was defeated.") if match_state.winner < 0 and match_state.world.time >= ArenaMatch.TIME_LIMIT else RemakeText.t("Battle duration: %s") % _time_text()
	_status_age = 0
	_update_status()
	_update_scores()


func _update_status() -> void:
	if match_state.phase == ArenaMatch.Phase.DEPLOY:
		_message.text = RemakeText.t("Place at least one creature on each team, then start the battle.") if _start.disabled else RemakeText.t("Both teams are ready. Start the battle or keep building your armies.")
	elif match_state.phase == ArenaMatch.Phase.PAUSED:
		_message.text = RemakeText.t("Battle paused. You can inspect the battlefield or edit the teams.")
	else:
		_message.text = RemakeText.t("All creatures are AI controlled. Battles end after five minutes if neither team wins.")


func _update_scores() -> void:
	for i in 2:
		_team_counts[i].text = (RemakeText.t("%d / %d creatures") % [match_state.team_count(i), ArenaMatch.LIMIT]) if match_state.phase == ArenaMatch.Phase.DEPLOY else (RemakeText.t("%d / %d alive") % [match_state.team_count(i, true), match_state.team_count(i)])
		_health[i].value = match_state.health_fraction(i) * 100
	_timer.text = _time_text()


func _time_text() -> String:
	var seconds := int(match_state.world.time)
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _process(dt: float) -> void:
	if match_state == null or match_state.world == null or _sound == null: return
	_update_scores()
	if _status_age > 0:
		_status_age -= dt
		if _status_age <= 0: _update_status()
	_sync_sound()
	_sound.mixer.set_listener(Vector3(16, 16, 2), Vector2(0, 1).rotated(field.yaw), Vector2(1, 0).rotated(field.yaw))
	if match_state.phase == ArenaMatch.Phase.FIGHT:
		if _sound.mixer.suspended: _sound.mixer.resume()
		_sound.units.tick()
		_sound.spells.tick(dt)
		_sound._ack_tick()
	elif not _sound.mixer.suspended:
		_sound.mixer.suspend()


func _sync_sound() -> void:
	if _sound == null: return
	if not is_instance_valid(_sound_world) or _sound_world != match_state.world:
		_sound_world = match_state.world
		_sound.on_world(_sound_world)
		_sound.mixer.sfx_on = true
		_sound.music.hold = false
		_sound.music.tick(2 if match_state.phase == ArenaMatch.Phase.FIGHT else 0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	if event.keycode == KEY_SPACE:
		match_state.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		_cancel_placement()
		if match_state.phase == ArenaMatch.Phase.FIGHT: match_state.toggle_pause()
		get_viewport().set_input_as_handled()


func _resize() -> void:
	_sidebar.custom_minimum_size.x = 280 if size.x < 1200 else 310
	_subtitle.text = RemakeText.t("Build two armies. Let the creatures decide.") if size.x >= 1100 else ""
	_preview.custom_minimum_size.y = 110 if size.y < 720 else 142


static func _team_name(team: int) -> String:
	return RemakeText.t("Blue team") if team == 0 else RemakeText.t("Red team")


static func _team_color(team: int) -> Color:
	return ArenaField.BLUE if team == 0 else ArenaField.RED


static func _style(bg: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(padding)
	return style


static func _label(parent: Node, text: String, font_size := 16, color := Color("e5e9e8")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


static func _button(parent: Node, text: String, action: Callable, tip := "", accent := Color("647786")) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _style(Color("23303a"), accent.darkened(0.4), 9))
	button.add_theme_stylebox_override("hover", _style(Color("344550"), accent, 9))
	button.add_theme_stylebox_override("pressed", _style(accent.darkened(0.65), accent, 9))
	button.add_theme_stylebox_override("disabled", _style(Color("19232c"), Color("34434e"), 9))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 0))
	button.pressed.connect(action)
	parent.add_child(button)
	return button
