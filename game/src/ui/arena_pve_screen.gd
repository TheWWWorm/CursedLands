class_name ArenaPveScreen
extends Control
## The expedition owns preparation; the battle remains fully AI controlled.

signal exit_requested
signal sandbox_requested

const GOLD := ArenaCreatureCard.GOLD
const PAPER := ArenaCreatureCard.PAPER
const MUTED := ArenaCreatureCard.MUTED
var run := ArenaRun.new()
var battle: ArenaPveMatch
var field: ArenaPveField
var selected_uid := 0
var landing := true
var _saved := false
var _board_key := ""
var _inspected := ""
var _header: Label
var _gold: Label
var _lives: Label
var _round_badge: VBoxContainer
var _round_panel: ArenaHudPanel
var _phase: Label
var _menu: MenuButton
var _inspect_actions: VBoxContainer
var _wave_title: Label
var _clock: Label
var _army_row: HBoxContainer
var _army_title: Button
var _showing_company := false
var _shop: HBoxContainer
var _shop_section: VBoxContainer
var _dock: VBoxContainer
var _outcome: PanelContainer
var _inspector: PanelContainer
var _inspect_box: VBoxContainer
var _message: Label
var _start: Button
var _pause: Button
var _refresh_button: Button
var _speed: OptionButton
var _sound: GameSound
var _sound_world: GameWorld
var _new_run_dialog: ConfirmationDialog
var _pending_starter := 0
var _rail: PanelContainer
var _rail_box: VBoxContainer
var _shop_panel: PanelContainer
var _bench_panel: PanelContainer
var _fight_panel: PanelContainer
var _bench_bar: HBoxContainer
var _bench_scroll: ScrollContainer
var _landing_layer: Control
var _landing_models: HBoxContainer
var _starter_buttons: Array[Button] = []
var _landing_description: Label
var _landing_start: Button
var _previous_border := Vector2.ZERO
var _previous_border_dist := -1.0
var _seed_input: LineEdit
var _challenge: OptionButton


func _ready() -> void:
	name = "ArenaExpedition"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_previous_border = Gfx._border_size
	_previous_border_dist = Gfx._border_menu
	theme = Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", PAPER)
	battle = ArenaPveMatch.new()
	battle.run = run
	add_child(battle)
	field = ArenaPveField.new()
	field.match_state = battle
	add_child(field)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle._world_parent = field.stage
	field.ground_clicked.connect(_place)
	field.creature_clicked.connect(_select_world)
	field.cancel_requested.connect(_clear_selection)
	var vignette := ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = ShaderMaterial.new()
	vignette.material.shader = preload("res://src/ui/arena_vignette.gdshader")
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing_layer = Control.new()
	add_child(_landing_layer)
	_landing_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing_layer.offset_top = 78
	_landing_layer.offset_bottom = -24
	_header = _label(self, RemakeText.t("Trials of Gipath"), 26, GOLD)
	_header.position = Vector2(28, 18)
	_header.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_round_panel = ArenaHudPanel.new()
	_round_panel.surface = Color(0.055, 0.055, 0.04, 0.85)
	add_child(_round_panel)
	_round_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_round_panel.offset_left = -232; _round_panel.offset_right = -72
	_round_panel.offset_top = 16; _round_panel.offset_bottom = 86
	_round_badge = VBoxContainer.new()
	_round_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_badge.add_theme_constant_override("separation", 3)
	_round_panel.add_child(_round_badge)
	_wave_title = _label(_round_badge, "", 20, PAPER)
	_wave_title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_phase = _label(_round_badge, "", 14, MUTED)
	_clock = _label(_round_badge, "", 16, GOLD)
	_menu = MenuButton.new()
	_menu.icon = preload("res://assets/arena/menu.svg")
	_menu.tooltip_text = RemakeText.t("Menu")
	_menu.custom_minimum_size = Vector2(44, 44)
	_menu.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0.055, 0.055, 0.04, 0.85), Color(0, 0, 0, 0)))
	_menu.draw.connect(func(): ArenaHudPanel.draw_frame(_menu, Rect2(Vector2.ZERO, _menu.size)))
	add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu.offset_left = -60; _menu.offset_right = -16
	_menu.offset_top = 16; _menu.offset_bottom = 60
	var popup := _menu.get_popup()
	popup.add_item(RemakeText.t("Guide"), 0)
	popup.add_item(RemakeText.t("Auto arrange"), 3)
	popup.set_item_tooltip(1, RemakeText.t("Deploy your strongest forms with ranged creatures behind the front line. Keep your pact active when your army can meet its condition."))
	popup.add_item(RemakeText.t("Undo"), 4)
	popup.set_item_tooltip(2, RemakeText.t("Undo a preparation action. Shop refreshes cannot be refunded."))
	popup.add_item(RemakeText.t("Company"), 5)
	popup.add_separator()
	popup.add_item(RemakeText.t("Sandbox"), 1)
	popup.add_item(RemakeText.t("Main menu"), 2)
	popup.id_pressed.connect(func(id):
		if id == 0: _guide()
		elif id == 1: sandbox_requested.emit()
		elif id == 2: exit_requested.emit()
		elif id == 3: run.arrange()
		elif id == 4: run.undo()
		elif id == 5: _show_company())
	_shop_panel = _unframed(self)
	_shop_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_shop_panel.offset_left = 24; _shop_panel.offset_top = 12
	_shop_panel.offset_bottom = 138
	_shop_panel.draw.connect(func():
		var texture := Interface800.tex("saveload")
		if texture:
			_shop_panel.draw_texture_rect_region(texture, Rect2(0, _shop_panel.size.y, _shop_panel.size.x, 2), Interface800.atlas_region(texture, Rect2(2, 249, 178, 5))))
	var recruitment := HBoxContainer.new()
	recruitment.add_theme_constant_override("separation", 12)
	_shop_panel.add_child(recruitment)
	_shop_section = VBoxContainer.new()
	_shop_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recruitment.add_child(_shop_section)
	_shop = HBoxContainer.new()
	_shop.add_theme_constant_override("separation", 8)
	_shop_section.add_child(_shop)
	_refresh_button = _icon_button(recruitment, preload("res://assets/arena/refresh.svg"), func(): _feedback(run.refresh()), RemakeText.t("Replace unlocked offers. One offer can be locked between shops."))
	_refresh_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_refresh_button.custom_minimum_size = Vector2(56, 44)
	_rail = ArenaHudPanel.new()
	_rail.custom_minimum_size.x = 264
	add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_rail.offset_left = -284; _rail.offset_right = -16
	_rail.offset_top = 170; _rail.offset_bottom = -142
	_rail_box = VBoxContainer.new()
	_rail_box.add_theme_constant_override("separation", 10)
	_rail.add_child(_rail_box)
	_inspector = _unframed(_rail_box)
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inspect_scroll := ScrollContainer.new()
	inspect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.add_child(inspect_scroll)
	_inspect_box = VBoxContainer.new()
	_inspect_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect_box.add_theme_constant_override("separation", 8)
	inspect_scroll.add_child(_inspect_box)
	_inspect_actions = VBoxContainer.new()
	_inspect_actions.add_theme_constant_override("separation", 6)
	_rail_box.add_child(_inspect_actions)
	_inspector.hide()
	_bench_panel = _unframed(self)
	_bench_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bench_panel.offset_left = 24; _bench_panel.offset_right = -24
	_bench_panel.offset_top = -104; _bench_panel.offset_bottom = -20
	_bench_bar = HBoxContainer.new()
	_bench_bar.add_theme_constant_override("separation", 20)
	_bench_panel.add_child(_bench_bar)
	_army_title = _button(_bench_bar, "", _show_company, RemakeText.t("Inspect your company pact and expedition upgrades."))
	_army_title.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_army_title.add_theme_font_size_override("font_size", 16)
	_army_title.icon = preload("res://assets/arena/company.svg")
	_army_title.add_theme_constant_override("icon_max_width", 18)
	_army_title.custom_minimum_size.x = 90
	_army_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bench_scroll = ScrollContainer.new()
	_bench_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bench_bar.add_child(_bench_scroll)
	_army_row = HBoxContainer.new()
	_army_row.add_theme_constant_override("separation", 8)
	_bench_scroll.add_child(_army_row)
	var actions := HBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 18)
	_bench_bar.add_child(actions)
	var purse := HBoxContainer.new()
	purse.alignment = BoxContainer.ALIGNMENT_CENTER
	purse.add_theme_constant_override("separation", 10)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(purse)
	_icon(purse, preload("res://assets/arena/coin.svg"))
	_gold = _label(purse, "", 19, GOLD)
	var gap := Control.new()
	gap.custom_minimum_size.x = 2
	purse.add_child(gap)
	_icon(purse, preload("res://assets/arena/life.svg"))
	_lives = _label(purse, "", 17, PAPER)
	_start = _button(actions, RemakeText.t("Start battle"), _fight, RemakeText.t("Your deployed army fights the previewed enemies under AI control."), true)
	_start.custom_minimum_size = Vector2(152, 44)
	_start.add_theme_font_size_override("font_size", 21)
	_start.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_fight_panel = _unframed(actions)
	var time_bar := HBoxContainer.new()
	time_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	time_bar.add_theme_constant_override("separation", 12)
	_fight_panel.add_child(time_bar)
	_pause = _icon_button(time_bar, preload("res://assets/arena/pause.svg"), func(): battle.toggle_pause(), RemakeText.t("Pause or resume the battle. Space also works."))
	_speed = OptionButton.new()
	for value in ["1×", "2×"]: _speed.add_item(value)
	_speed.custom_minimum_size = Vector2(74, 44)
	_speed.tooltip_text = RemakeText.t("Watch at normal or double speed. Creature stats and battle rules stay the same.")
	_speed.item_selected.connect(func(i): battle.set_speed(1.0 if i == 0 else 2.0))
	time_bar.add_child(_speed)
	_outcome = ArenaHudPanel.new()
	add_child(_outcome)
	_outcome.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dock = VBoxContainer.new()
	_dock.add_theme_constant_override("separation", 10)
	_outcome.add_child(_dock)
	_message = _label(self, "", 13, PAPER)
	_message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_message.offset_left = 24; _message.offset_right = -24
	_message.offset_top = -26; _message.offset_bottom = -6
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.add_theme_color_override("font_shadow_color", Color.BLACK)
	_message.add_theme_constant_override("shadow_offset_y", 2)
	resized.connect(_layout_hud)
	_layout_hud()
	_sound = GameSound.new()
	add_child(_sound)
	_sound.set_process(false)
	battle.world_replacing.connect(func():
		_sound.on_world(null)
		_sound_world = null)
	battle.visual_event.connect(func(event):
		if battle.world != _sound_world:
			_sound_world = battle.world
			_sound.on_world(_sound_world)
		_sound.on_event(event))
	battle.changed.connect(_battle_changed)
	_new_run_dialog = ConfirmationDialog.new()
	_new_run_dialog.dialog_text = RemakeText.t("Start a new expedition? This replaces your current expedition.")
	_new_run_dialog.ok_button_text = RemakeText.t("Begin expedition")
	_new_run_dialog.cancel_button_text = RemakeText.t("Cancel")
	_new_run_dialog.confirmed.connect(func(): _begin(_pending_starter))
	add_child(_new_run_dialog)
	if not ArenaRules.available():
		_rail.hide(); _shop_section.hide(); _pause.hide(); _speed.hide(); _bench_bar.hide()
		_shop_panel.hide(); _bench_panel.hide(); _fight_panel.hide(); _round_panel.hide()
		_outcome.show()
		_layout_outcome()
		_wrap(_dock, RemakeText.t("This expedition needs the original Evil Islands game files. Choose the original campaign in the main menu."), 18)
		return
	run.auto_save = false
	_saved = run.load_saved() and run.stage not in ["won", "lost"]
	if not _saved: run.begin(1)
	run.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _sound: _sound.on_world(null)
	Gfx.set_border(_previous_border, _previous_border_dist)


func _refresh() -> void:
	_header.visible = landing
	_gold.text = str(run.gold)
	_lives.text = "%d/3" % run.lives
	_gold.get_parent().tooltip_text = RemakeText.t("Gold %d   ·   Lives %d/%d") % [run.gold, run.lives, 3]
	_wave_title.text = RemakeText.t("Wave %d/%d") % [run.wave, ArenaRules.WAVE_COUNT]
	_round_panel.tooltip_text = RemakeText.t("Wave %d/%d · %s") % [run.wave, ArenaRules.WAVE_COUNT, RemakeText.t(ArenaRules.WAVES[run.wave - 1][0])] + "\n" + RemakeText.t("Seed %s") % str(run.run_seed)
	var preparing := run.stage == "prepare" and not landing
	var fighting := run.stage == "fight" and not landing
	_bench_panel.visible = not landing
	_bench_bar.visible = not landing
	_shop_panel.visible = preparing
	_fight_panel.visible = fighting
	_round_panel.visible = not landing
	_start.visible = preparing
	_shop_section.visible = preparing
	_dock.visible = not preparing and not fighting and not landing
	_outcome.visible = _dock.visible
	_layout_outcome()
	_pause.visible = fighting
	_speed.visible = fighting
	_rail.visible = not landing and _inspector.visible
	_landing_layer.visible = landing
	_clock.visible = fighting
	field.show_markers = not landing
	_battle_changed()
	if preparing or landing or not is_instance_valid(battle.world):
		var board := [run.run_seed, run.wave, run.army.filter(func(entry): return entry.deployed), run.challenge, run.lives, run.pact, run.pact_rank]
		var key := JSON.stringify(board)
		if key != _board_key:
			battle.prepare()
			_board_key = key
			field._update_camera()
	for u: GameUnit in battle.world.unit_rows(): u.visible = not landing
	_build_army()
	if preparing: _build_shop()
	else: _clear(_shop)
	_clear(_dock)
	if landing: _build_landing()
	else: _clear(_landing_layer)
	if not landing:
		if run.stage == "reward": _build_rewards()
		elif run.stage in ["result", "won", "lost"]: _build_result()
	_start.disabled = run.deployed_count() == 0
	_menu.get_popup().set_item_disabled(1, not preparing)
	_menu.get_popup().set_item_disabled(2, not preparing or not run.can_undo())
	_refresh_button.text = str(run.refresh_cost())
	_refresh_button.tooltip_text = RemakeText.t("Refresh · %d gold") % run.refresh_cost() + "\n" + RemakeText.t("Replace unlocked offers. One offer can be locked between shops.")
	_refresh_button.disabled = run.gold < run.refresh_cost()
	_army_title.text = RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()]
	_army_title.tooltip_text = RemakeText.t("Army %d/%d   ·   Bench %d/%d") % [run.deployed_count(), run.capacity(), run.bench_count(), run.bench_limit()]
	_army_title.tooltip_text += "\n" + RemakeText.t("Inspect your company pact and expedition upgrades.")
	_army_title.add_theme_color_override("icon_normal_color", GOLD if run.pact_active() else MUTED)
	_army_title.disabled = not preparing and not fighting
	if not run.pact.is_empty():
		_army_title.tooltip_text += "\n" + RemakeText.t(ArenaRules.PACTS[run.pact].name) + " · " + _pact_status()
	if _army_title.disabled: _army_title.tooltip_text = ""
	_army_title.mouse_filter = Control.MOUSE_FILTER_IGNORE if _army_title.disabled else Control.MOUSE_FILTER_STOP
	if run.stage != "prepare" or landing: field.select_creature("")
	elif selected_uid > 0 and not run.unit(selected_uid).is_empty(): field.select_creature(run.unit(selected_uid).prototype)
	if selected_uid > 0:
		var entry := run.unit(selected_uid)
		if entry.is_empty(): _clear_selection()
		else: _inspect(entry.prototype, entry)
	elif _showing_company: _show_company()
	_rail.visible = not landing and not _outcome.visible and _inspector.visible
	if run.save_error: _feedback(RemakeText.t("The expedition could not be saved. Check free disk space before leaving."))


func _build_army() -> void:
	_clear(_army_row)
	var benched := run.army.filter(func(u): return not u.deployed)
	var slot_width := clampf((size.x - 534.0) / maxi(run.bench_limit(), benched.size()) - 8.0, 44, 88)
	for i in maxi(run.bench_limit(), benched.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(slot_width, 84)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color(0.12, 0.16, 0.17, 0.45), Color(0, 0, 0, 0)))
		button.add_theme_stylebox_override("focus", ArenaCreatureCard.style(Color(0, 0, 0, 0), PAPER))
		button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		if landing or run.stage not in ["prepare", "fight"]: button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_army_row.add_child(button)
		var marker := ColorRect.new()
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(marker)
		marker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		marker.offset_left = 10; marker.offset_right = -10
		marker.offset_top = -3; marker.offset_bottom = -2
		marker.color = Color(0.72, 0.75, 0.72, 0.32)
		if i >= benched.size():
			button.disabled = true
			button.tooltip_text = RemakeText.t("Recruits wait here until you deploy them.")
			continue
		var entry: Dictionary = benched[i]
		button.tooltip_text = ArenaRules.title(entry.prototype) + "\n" + RemakeText.t("Select this creature, then click the battlefield to place it.")
		button.pressed.connect(func(): _select(entry.uid))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = landing or run.stage not in ["prepare", "fight"]
		var preview := WikiPreview.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(preview)
		preview.show_model({"kind": "creature", "value": entry.prototype})
		preview.turn_by(-0.35)
		preview.zoom_by(0.55)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if int(entry.uid) == selected_uid:
			marker.color = GOLD
			marker.offset_top = -4


func _build_shop() -> void:
	_clear(_shop)
	for index in run.shop.size():
		var offer: Dictionary = run.shop[index]
		var box := Control.new()
		box.custom_minimum_size = Vector2(96, 126)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shop.add_child(box)
		var family := int(offer.family)
		if family < 0:
			var bought := _label(box, RemakeText.t("Recruited"), 13, MUTED)
			bought.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bought.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bought.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			continue
		var rule: Dictionary = ArenaRules.FAMILIES[family]
		var card := ArenaCreatureCard.new()
		card.prototype = rule.forms[0]
		var count := run.army.filter(func(entry): return entry.family == family and entry.rank == 0).size()
		card.caption = RemakeText.t("%s · %d owned") % [RemakeText.t(rule.role), count]
		card.caption = RemakeText.t(rule.name) + "\n" + card.caption
		if not run.pact.is_empty() and family in ArenaRules.PACTS[run.pact].families:
			card.caption += "\n" + RemakeText.t("Evolve this creature to contribute to your pact." if int(ArenaRules.PACTS[run.pact].min_rank) > 0 else "Deploy this family to contribute to your pact.")
		var needed := ArenaRules.evolution_copies(family, 0)
		card.footer = RemakeText.t("%d gold · %d/%d") % [int(rule.cost), mini(needed, count), needed]
		card.cost = int(rule.cost)
		card.copies = count
		card.copies_needed = needed
		card.disabled = run.gold < int(rule.cost) or run.bench_count() >= run.bench_limit()
		card.pressed.connect(func(): _recruit_offer(index))
		box.add_child(card)
		if card.disabled:
			card.tooltip_text += "\n" + RemakeText.t("Not enough gold." if run.gold < int(rule.cost) else "Bench full. Deploy, evolve or sell a creature first.")
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var lock := _icon_button(box, preload("res://assets/arena/lock.svg"), func(): pass, RemakeText.t("Keep offer"))
		lock.toggle_mode = true
		lock.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		lock.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("464f34"), GOLD))
		lock.custom_minimum_size = Vector2(28, 28)
		lock.add_theme_constant_override("icon_max_width", 16)
		lock.tooltip_text = RemakeText.t("Replace unlocked offers. One offer can be locked between shops.")
		lock.button_pressed = offer.locked
		lock.toggled.connect(func(_on): run.lock_offer(index))
		lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -30; lock.offset_right = -2
		lock.offset_top = 0; lock.offset_bottom = 28
		lock.modulate.a = 1 if offer.locked else 0.45


func _build_landing() -> void:
	_clear(_landing_layer)
	_starter_buttons.clear()
	var shade := ColorRect.new()
	shade.color = Color(0.055, 0.075, 0.052, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing_layer.add_child(shade)
	var margin := _margin(_landing_layer, 28)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	margin.add_child(columns)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 310
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_stretch_ratio = 0.8
	choices.add_theme_constant_override("separation", 12)
	columns.add_child(choices)
	var title := _wrap(choices, RemakeText.t("Choose your company"), 38, PAPER)
	title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_wrap(choices, RemakeText.t("Recruit strange allies. Shape their evolution. Survive eighteen battles together."), 15, MUTED)
	if _saved:
		_button(choices, RemakeText.t("Continue · wave %d") % run.wave, func():
			landing = false; run.auto_save = true; _refresh(), RemakeText.t("Resume your saved expedition with the same army and shop."), true)
	for index in ArenaRules.STARTERS.size():
		var rule: Dictionary = ArenaRules.STARTERS[index]
		var button := _button(choices, "", func(): _choose_starter(index), RemakeText.t(rule.help))
		button.custom_minimum_size.y = 88
		button.toggle_mode = true
		var inside := _margin(button, 12)
		inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := VBoxContainer.new()
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_constant_override("separation", 6)
		inside.add_child(text)
		_label(text, RemakeText.t(rule.name), 21, PAPER)
		var roles: Array[String] = []
		for family: int in rule.families: roles.append(RemakeText.t(ArenaRules.FAMILIES[family].role))
		_wrap(text, " · ".join(roles), 13, MUTED)
		_starter_buttons.append(button)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_child(fill)
	_challenge = OptionButton.new()
	var maximum := int(ArenaRun.profile().get("challenge", 0))
	for text: String in ["Standard expedition", "Veteran expedition", "Champion expedition"]:
		_challenge.add_item(RemakeText.t(text))
	for i in 3: _challenge.set_item_disabled(i, i > maximum)
	_challenge.custom_minimum_size.y = 36
	_challenge.tooltip_text = RemakeText.t("Win an expedition to unlock the next difficulty. Stronger enemy formations keep their native stats.")
	choices.add_child(_challenge)
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = RemakeText.t("Random seed")
	_seed_input.tooltip_text = RemakeText.t("Optional: enter a whole number to replay the same shops and encounters.")
	_seed_input.custom_minimum_size.y = 34
	choices.add_child(_seed_input)
	var company := VBoxContainer.new()
	company.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	company.size_flags_stretch_ratio = 1.45
	company.add_theme_constant_override("separation", 18)
	columns.add_child(company)
	_landing_models = HBoxContainer.new()
	_landing_models.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_landing_models.add_theme_constant_override("separation", 14)
	company.add_child(_landing_models)
	_landing_description = _wrap(company, "", 17, PAPER)
	_landing_description.custom_minimum_size.y = 52
	_rule(company)
	_label(company, RemakeText.t("Three creatures · 6 gold · 3 lives"), 15, MUTED)
	_landing_start = _button(company, RemakeText.t("Begin expedition"), func():
		if not _seed_input.text.strip_edges().is_empty() and not _seed_input.text.strip_edges().is_valid_int():
			_feedback(RemakeText.t("Enter a whole number for the seed."))
		elif _saved: _new_run_dialog.popup_centered()
		else: _begin(_pending_starter), RemakeText.t("Choose a new starter army and begin another run."), true)
	_landing_start.custom_minimum_size.y = 52
	_landing_start.add_theme_font_size_override("font_size", 20)
	_choose_starter(_pending_starter)


func _choose_starter(index: int) -> void:
	_pending_starter = index
	for i in _starter_buttons.size():
		_starter_buttons[i].set_pressed_no_signal(i == index)
		_starter_buttons[i].add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color("272e23"), GOLD if i == index else Color("4b5143")))
	_clear(_landing_models)
	var rule: Dictionary = ArenaRules.STARTERS[index]
	_landing_description.text = RemakeText.t(rule.help)
	for family: int in rule.families:
		var id := ArenaRules.prototype(family, 0)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_landing_models.add_child(box)
		var preview := WikiPreview.new()
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.custom_minimum_size = Vector2(100, 180)
		box.add_child(preview)
		preview.show_model({"kind": "creature", "value": id})
		preview.turn_by(-0.35)
		preview.zoom_by(0.78)
		var title := _wrap(box, ArenaRules.title(id), 17, PAPER)
		title.custom_minimum_size.y = 48
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var role := _label(box, RemakeText.t(ArenaRules.FAMILIES[family].role), 13, GOLD)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _begin(starter_index: int) -> void:
	var value := _seed_input.text.strip_edges()
	if not value.is_empty() and not value.is_valid_int():
		_feedback(RemakeText.t("Enter a whole number for the seed."))
		return
	var chosen := randi_range(1, 99999999) if value.is_empty() else clampi(int(value), 1, 99999999)
	var challenge_index := _challenge.selected
	landing = false
	_saved = false
	_clear_selection()
	run.auto_save = true
	run.begin(chosen, starter_index, challenge_index)
	_hint("")


func _build_result() -> void:
	var won := int(run.last_result.get("winner", -1)) == 0
	var text := "Expedition complete" if run.stage == "won" else "The expedition ends" if run.stage == "lost" else "Victory" if won else "Regroup and try again"
	var title := _label(_dock, RemakeText.t(text), 28, GOLD)
	title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	var result: Dictionary = run.last_result
	title.tooltip_text = RemakeText.t("Battle: %d seconds · Damage dealt: %d · Damage taken: %d") % [int(result.get("seconds", 0)), int(result.get("damage", [0, 0])[0]), int(result.get("damage", [0, 0])[1])]
	if won and run.stage != "won": _label(_dock, RemakeText.t("Victory income: %d gold") % int(result.get("gold", 0)), 16, GOLD)
	elif run.stage == "lost": _wrap(_dock, RemakeText.t("Your expedition has ended. Start a new expedition with a different army."), 15)
	elif not won: _wrap(_dock, RemakeText.t("Your creatures recover fully. Reposition or recruit before trying the same enemies again."), 15)
	if run.stage == "won": _wrap(_dock, RemakeText.t("You conquered the ruins with your creatures’ original strength.") if run.challenge == 2 else RemakeText.t("A harder expedition is unlocked. Your creatures kept their original stats throughout the run."), 16)
	var row := HBoxContainer.new()
	_dock.add_child(row)
	if run.stage in ["won", "lost"]:
		_button(row, RemakeText.t("New expedition"), func(): landing = true; _saved = false; _clear_selection(); _refresh(), RemakeText.t("Choose a new starter army and begin another run."), true)
	else:
		_button(row, RemakeText.t("Visit camp" if won and run.wave % 3 == 0 else "Next wave" if won else "Prepare again"), func(): run.advance(), RemakeText.t("Return to preparation with your army restored."), true)


func _build_rewards() -> void:
	var choosing_pact := String(run.rewards[0].kind) == "pact"
	var heading := _label(_dock, RemakeText.t("Choose your pact" if choosing_pact else "A moment at camp"), 28, GOLD)
	heading.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_wrap(_dock, RemakeText.t(ArenaRules.BOONS.pact[1]) if choosing_pact else RemakeText.t("Take one reward before the next battle."), 15, MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_dock.add_child(row)
	for index in run.rewards.size():
		var reward: Dictionary = run.rewards[index]
		var words: Array = ArenaRules.BOONS[reward.kind]
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		var id := ""
		var title := RemakeText.t(words[0])
		var help := RemakeText.t(words[1])
		if reward.kind == "pact":
			var rule: Dictionary = ArenaRules.PACTS[reward.pact]
			title = RemakeText.t(rule.name)
			help = RemakeText.t(rule.help)
			id = rule.forms[0]
		elif reward.kind == "pact_upgrade": id = ArenaRules.PACTS[run.pact].forms[run.pact_rank + 1]
		elif reward.kind == "companion": id = reward.prototype
		_wrap(box, title, 21, GOLD).custom_minimum_size.y = 52
		if not id.is_empty():
			_creature_preview(box, id, 100)
			_wrap(box, ArenaRules.title(id), 16, PAPER).custom_minimum_size.y = 44
		else:
			var emblem := CenterContainer.new()
			emblem.custom_minimum_size.y = 100
			box.add_child(emblem)
			var icon := _icon(emblem, preload("res://assets/arena/life.svg") if reward.kind == "life" else preload("res://assets/arena/coin.svg") if reward.kind in ["purse", "supplies", "merchant"] else preload("res://assets/arena/company.svg"))
			icon.custom_minimum_size = Vector2(44, 44)
			var spacer := Control.new()
			spacer.custom_minimum_size.y = 44
			box.add_child(spacer)
		_wrap(box, help, 15, MUTED).custom_minimum_size.y = 100
		var action := _button(box, RemakeText.t("Choose pact" if choosing_pact else "Choose reward"), func(): _feedback(run.choose_reward(index)), help, true)
		action.name = "ChooseReward"
		if not id.is_empty():
			var stats := GameData.db.find("monster_prototypes", id)
			action.tooltip_text += "\n\n" + RemakeText.t("Health %d · Armor %d\nDamage %d–%d") % [int(stats.get("hp", 0)), int(stats.get("absorption", 0)), int(stats.get("damage_min", 0)), int(stats.get("damage_min", 0) + stats.get("damage_max", 0))]
		if reward.kind == "pact":
			action.tooltip_text += "\n" + RemakeText.t("One pact per expedition. A pact ally uses no army slot and cannot be sold or evolved.")
		elif reward.kind == "companion" and run.bench_count() > run.bench_limit():
			action.disabled = true
			action.tooltip_text = RemakeText.t("Your reserves already hold an extra ally. Choose another reward.")


func _pact_status() -> String:
	return RemakeText.t("Pact active · one extra ally") if run.pact_active() else RemakeText.t("Pact inactive · %d/%d families") % [run.pact_families().size(), int(ArenaRules.PACTS[run.pact].needed)]


func _show_company() -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	_clear_selection()
	_showing_company = true
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	var heading := HBoxContainer.new()
	_inspect_box.add_child(heading)
	var title := _wrap(heading, RemakeText.t("Company"), 23, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_icon_button(heading, preload("res://assets/arena/close.svg"), _clear_selection, RemakeText.t("Close"))
	if run.pact.is_empty():
		_wrap(_inspect_box, RemakeText.t("Company pacts are offered at the camps after waves 3, 9 and 15 until you choose one."), 15, MUTED)
	else:
		var rule: Dictionary = ArenaRules.PACTS[run.pact]
		_wrap(_inspect_box, RemakeText.t(rule.name), 20, PAPER)
		_wrap(_inspect_box, _pact_status(), 14, GOLD)
		_wrap(_inspect_box, RemakeText.t(rule.help), 14, MUTED)
		var present := run.pact_families()
		for family: int in rule.families:
			var state := RemakeText.t("Ready") if family in present else RemakeText.t("Not contributing")
			_wrap(_inspect_box, "%s · %s" % [RemakeText.t(ArenaRules.FAMILIES[family].name), state], 13, PAPER if family in present else MUTED)
		_creature_preview(_inspect_box, run.pact_prototype(), 90)
		_wrap(_inspect_box, ArenaRules.title(run.pact_prototype()), 17, GOLD)
		_wrap(_inspect_box, RemakeText.t("One pact per expedition. A pact ally uses no army slot and cannot be sold or evolved."), 13, MUTED)
		if run.pact_rank < 2:
			_wrap(_inspect_box, RemakeText.t("Improve your pact ally at the camps after waves 9 and 15, or take another reward."), 13, MUTED)
	if not run.boons.is_empty():
		_rule(_inspect_box)
		_label(_inspect_box, RemakeText.t("Expedition upgrades"), 17, GOLD)
		for boon: String in run.boons:
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][0]), 15, PAPER)
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][1]), 13, MUTED)


func _creature_preview(parent: Node, id: String, height: float) -> WikiPreview:
	var preview := WikiPreview.new()
	preview.custom_minimum_size = Vector2(80, height)
	parent.add_child(preview)
	preview.show_model({"kind": "creature", "value": id})
	preview.turn_by(-0.35)
	preview.zoom_by(0.75)
	return preview


func _select(uid: int) -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	selected_uid = uid
	battle.selected_run_uid = uid
	field.highlighted_run_uid = uid
	var entry := run.unit(uid)
	if entry.is_empty(): return
	_inspect(entry.prototype, entry)
	if run.stage == "prepare" and not landing: field.select_creature(entry.prototype)
	_build_army()
	_hint((RemakeText.t("Click a clear position in the blue deployment area.") if entry.deployed else RemakeText.t("Click the field to deploy, or click an ally to swap places.")) if run.stage == "prepare" else "")


func _select_world(unit: GameUnit) -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	var uid := int(unit.get_meta("arena_placement", {}).get("run_uid", 0))
	var selected := run.unit(selected_uid)
	if uid > 0 and run.stage == "prepare" and not selected.is_empty() and not selected.deployed:
		_feedback(run.swap_from_bench(selected_uid, uid))
		return
	if uid > 0 and not landing: _select(uid)
	else:
		_clear_selection()
		_inspect(String(unit.info.get("prototype", "")))
		if unit.get_meta("arena_placement", {}).has("pact"):
			_wrap(_inspect_box, RemakeText.t("Pact ally · returns each battle while your pact is active."), 14, GOLD)
			_button(_inspect_actions, RemakeText.t("Company"), _show_company, RemakeText.t("Inspect your company pact and expedition upgrades."))


func _inspect(id: String, entry: Dictionary = {}) -> void:
	if id.is_empty(): return
	_showing_company = false
	_rail.show()
	_inspected = id
	_inspector.show()
	_clear(_inspect_box)
	_clear(_inspect_actions)
	var heading := HBoxContainer.new()
	_inspect_box.add_child(heading)
	var title := _wrap(heading, ArenaRules.title(id), 21, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_button(heading, preload("res://assets/arena/close.svg"), _clear_selection, RemakeText.t("Close the creature details."))
	title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	if not entry.is_empty() and int(entry.family) >= 0:
		var family: Dictionary = ArenaRules.FAMILIES[int(entry.family)]
		_wrap(_inspect_box, "%s · %s" % [RemakeText.t(family.name), RemakeText.t(family.role)], 13, GOLD)
		if not run.pact.is_empty() and int(entry.family) in ArenaRules.PACTS[run.pact].families:
			_wrap(_inspect_box, RemakeText.t("Evolve this creature to contribute to your pact." if int(entry.rank) < int(ArenaRules.PACTS[run.pact].min_rank) else "Deploy this family to contribute to your pact."), 13, MUTED)
	var preview := WikiPreview.new()
	preview.custom_minimum_size.y = 64
	_inspect_box.add_child(preview)
	preview.show_model({"kind": "creature", "value": id})
	preview.zoom_by(0.8)
	var row := GameData.db.find("monster_prototypes", id)
	_wrap(_inspect_box, RemakeText.t("Health %d · Armor %d\nDamage %d–%d") % [int(row.get("hp", 0)), int(row.get("absorption", 0)), int(row.get("damage_min", 0)), int(row.get("damage_min", 0) + row.get("damage_max", 0))], 14)
	var spells: Array = row.get("spells", [])
	if not spells.is_empty():
		# Spell titles resolve through the original text layer, never raw specs.
		var names: Array[String] = []
		for spell: String in spells:
			var parsed := Spells.parse(spell)
			var name := RemakeText.t(Spells.title(parsed.code)) if parsed.has("code") else ""
			if not name.is_empty() and name not in names: names.append(name)
		if not names.is_empty(): _wrap(_inspect_box, ", ".join(names), 13, MUTED)
	if not entry.is_empty() and run.stage == "prepare" and not landing:
		if entry.deployed: _button(_inspect_box, RemakeText.t("Move to bench"), func(): _feedback(run.bench(entry.uid)), RemakeText.t("Free a deployment slot while keeping this creature."))
		_button(_inspect_box, RemakeText.t("Sell · %d gold") % run.sale_value(entry), func(): _feedback(run.sell(entry.uid)), RemakeText.t("Recover part of the recruitment cost. You can undo this before refreshing or fighting."))
	if not entry.is_empty() and ArenaRules.evolution_copies(int(entry.family), int(entry.rank)) > 0:
		_rule(_inspect_box)
		var next := ArenaRules.prototype(entry.family, int(entry.rank) + 1)
		_label(_inspect_box, RemakeText.t("Evolution"), 15, GOLD)
		_wrap(_inspect_box, ArenaRules.title(next), 17, PAPER)
		var stats := GameData.db.find("monster_prototypes", next)
		_wrap(_inspect_box, RemakeText.t("Health %d · Armor %d\nDamage %d–%d") % [int(stats.get("hp", 0)), int(stats.get("absorption", 0)), int(stats.get("damage_min", 0)), int(stats.get("damage_min", 0) + stats.get("damage_max", 0))], 13, MUTED)
		var error := run.evolution_error(entry.uid)
		var needed := ArenaRules.evolution_copies(int(entry.family), int(entry.rank))
		_wrap(_inspect_box, RemakeText.t("Copies: %d/%d") % [mini(needed, run.copies(entry).size()), needed], 13, GOLD)
		_wrap(_inspect_box, error if error else RemakeText.t("Combine matching creatures to recruit this form."), 13, MUTED)
		var merge := _button(_inspect_actions, RemakeText.t("Evolve · %d copies") % needed, func(): _feedback(run.evolve(entry.uid)), RemakeText.t("Consume %d identical forms to recruit the previewed creature.") % needed, true)
		merge.disabled = not error.is_empty()
	elif not entry.is_empty():
		_wrap(_inspect_box, RemakeText.t("This creature has reached its final form."), 13, GOLD)




func _place(point: Vector2) -> void:
	if landing or run.stage != "prepare" or selected_uid <= 0: return
	var error := battle.placement_error(point)
	if error.is_empty(): error = run.deploy(selected_uid, point)
	_feedback(error)


func _fight() -> void:
	if landing: return
	_clear_selection()
	if not battle.start(): _feedback(RemakeText.t("Deploy at least one creature before starting."))


func _clear_selection() -> void:
	_showing_company = false
	selected_uid = 0
	if battle: battle.selected_run_uid = 0
	if field:
		field.select_creature("")
		field.highlighted_run_uid = 0
	_hint("")
	if _army_row: _build_army()
	if _inspector: _inspector.hide()
	if _rail: _rail.hide()


func _battle_changed() -> void:
	if _pause:
		_pause.icon = preload("res://assets/arena/play.svg") if battle.phase == ArenaMatch.Phase.PAUSED else preload("res://assets/arena/pause.svg")
		_pause.tooltip_text = RemakeText.t("Resume" if battle.phase == ArenaMatch.Phase.PAUSED else "Pause") + " · " + RemakeText.t("Pause or resume the battle. Space also works.")
	if _phase:
		_phase.text = RemakeText.t("Preparing") if run.stage == "prepare" else RemakeText.t("Paused") if battle.phase == ArenaMatch.Phase.PAUSED else RemakeText.t("Battle") if run.stage == "fight" else ""
	if _sound: _sound.music.tick(2 if battle.phase == ArenaMatch.Phase.FIGHT else 0)


func _process(dt: float) -> void:
	if _clock and battle and is_instance_valid(battle.world):
		_clock.text = "%d:%02d" % [int(battle.world.time) / 60, int(battle.world.time) % 60]

	if _sound and battle and is_instance_valid(battle.world):
		if not is_instance_valid(_sound_world) or _sound_world != battle.world:
			_sound_world = battle.world
			_sound.on_world(_sound_world)
			_sound.mixer.sfx_on = true
			_sound.music.hold = false
		_sound.mixer.set_listener(Vector3(32, 32, 2), Vector2(0, 1).rotated(field.yaw), Vector2(1, 0).rotated(field.yaw))
		if battle.phase == ArenaMatch.Phase.FIGHT:
			if _sound.mixer.suspended: _sound.mixer.resume()
			_sound.units.tick()
			_sound.spells.tick(dt)
			_sound._ack_tick()
		elif not _sound.mixer.suspended:
			_sound.mixer.suspend()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and run.stage == "fight":
			battle.toggle_pause(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_clear_selection(); get_viewport().set_input_as_handled()


func _guide() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = RemakeText.t("Expedition guide")
	dialog.ok_button_text = RemakeText.t("Close")
	dialog.dialog_autowrap = true
	dialog.dialog_text = RemakeText.t("Recruit creatures into your bench. Select one, then click the blue deployment area.\n\nCombine matching forms to evolve. Shooters and bats need two copies for their first evolution; other recipes need three. First evolutions unlock at wave 4, final evolutions at wave 10. Toads have one evolution. Check the creature panel before combining.\n\nMelee recruits cost 3 gold; shooters and magic creatures cost 4. Victories before the final wave earn 7 gold. Visit camp every three victories: choose a company pact after wave 3, then improve it or take other rewards. Inspect your army counter to see pact requirements and upgrades. Defeat costs one life; your army recovers fully.\n\nPrepare without a timer, then let the AI fight. Win all 18 waves to unlock harder expeditions. Scroll to zoom; hold the middle mouse button to rotate the battlefield.")
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(630, 480))


func _feedback(error: String) -> void:
	if not error.is_empty():
		_message.text = error
		_message.add_theme_color_override("font_color", Color("efbf87"))
	else:
		_hint("")


func _hint(value: String) -> void:
	if _message:
		_message.text = value
		_message.add_theme_color_override("font_color", MUTED)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _label(parent: Node, value: String, pixels := 15, color := PAPER) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _wrap(parent: Node, value: String, pixels := 15, color := PAPER) -> Label:
	var label := _label(parent, value, pixels, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(parent: Node, value: String, action: Callable, help: String, primary := false) -> Button:
	var button := Button.new()
	button.text = value
	button.tooltip_text = help
	button.custom_minimum_size.y = 34
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color("25251e") if primary else Color("202726"), GOLD if primary else Color("4b5143")))
	button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color("424033") if primary else Color("344248"), GOLD))
	button.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("504a35") if primary else Color("485557")))
	button.add_theme_stylebox_override("focus", ArenaCreatureCard.style(Color(0, 0, 0, 0), PAPER))
	if primary: button.draw.connect(func(): ArenaHudPanel.draw_frame(button, Rect2(Vector2.ZERO, button.size)))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _margin(parent: Node, padding: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, padding)
	parent.add_child(margin)
	return margin


func _rule(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = Color("4c5141")
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _recruit_offer(index: int) -> void:
	var uid := run.next_uid
	var error := run.buy(index)
	_feedback(error)
	if error.is_empty():
		_select(uid)
		if run.deployed_count() >= run.capacity():
			_hint(RemakeText.t("Select a reserve, then click one of your deployed creatures to swap them."))


func _layout_outcome() -> void:
	if not _outcome or not field: return
	var width := minf(900 if run.stage == "reward" else 600, field.size.x - 32)
	_outcome.offset_left = -width / 2
	_outcome.offset_right = width / 2
	_outcome.offset_top = -238 if run.stage == "reward" else -120
	_outcome.offset_bottom = 238 if run.stage == "reward" else 120


func _layout_hud() -> void:
	if not _shop_panel: return
	_shop_panel.offset_right = minf(984, size.x - 252)
	if _army_row and not run.army.is_empty(): _build_army()
	_layout_outcome()


func _unframed(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(panel)
	return panel


func _icon(parent: Node, texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


func _icon_button(parent: Node, texture: Texture2D, action: Callable, help: String) -> Button:
	var button := _button(parent, "", action, help)
	button.icon = texture
	button.custom_minimum_size = Vector2(40, 40)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_constant_override("icon_max_width", 22)
	return button
