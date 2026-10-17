class_name ArenaPveScreen
extends Control
## The expedition owns preparation; the battle remains fully AI controlled.

signal exit_requested

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
var _menu: Button
var _hud: Control
var _ui_scale := 1.0
var _heading_font: Font
var _tooltips: ArenaTooltips
var _hit_numbers: ArenaHitNumbers
var _modal_layer: Control
var _modal_panel: ArenaHudPanel
var _modal_box: VBoxContainer
var _menu_items := {}
var _menu_was_fighting := false
var _modal_focus: Array[Dictionary] = []
var _guide_scroll: ScrollContainer
var _quality: Label
var _reserve_count: Label
var _alliance_list: VBoxContainer
var _alliance_panel: PanelContainer
var _training_panel: PanelContainer
var _train_button: ArenaRoundButton
var _last_level := 0
var _result_remaining := 4.0
var _result_key := -1
var _live_health: Label
var _inspected_unit: GameUnit
var _outcome_shade: ColorRect
var _inspect_actions: VBoxContainer
var _wave_title: Label
var _clock: Label
var _army_row: HBoxContainer
var _army_title: Button
var _showing_company := false
var _shop: HBoxContainer
var _shop_section: VBoxContainer
var _dock: VBoxContainer
var _outcome: ArenaHudPanel
var _inspector: PanelContainer
var _inspect_box: VBoxContainer
var _message: Label
var _start: Button
var _pause: Button
var _refresh_button: ArenaRoundButton
var _speed: Button
var _sound: GameSound
var _sound_world: GameWorld
var _rail: PanelContainer
var _rail_box: VBoxContainer
var _shop_panel: PanelContainer
var _bench_panel: PanelContainer
var _fight_panel: PanelContainer
var _bench_bar: HBoxContainer
var _bench_scroll: ScrollContainer
var _landing_layer: Control
var _landing_panel: ArenaHudPanel
var _evolution_notice: ArenaEvolutionNotice
var _landing_start: Button
var _previous_border := Vector2.ZERO
var _previous_border_dist := -1.0
var _seed_input: LineEdit
var _sell_target: Button
var _income: Label
var _hover_key := ""
var _dismissed_hover := ""
var _hover_wait := 0.0
var _hover_missing := 0.0
var _timer_save_wait := 0.0
var _challenge: OptionButton
var _standings: PanelContainer
var _standing_rows: VBoxContainer
var _tournament_battles: ArenaTournamentBattles


func _ready() -> void:
	name = "ArenaExpedition"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_previous_border = Gfx._border_size
	_previous_border_dist = Gfx._border_menu
	theme = Theme.new()
	theme.default_font_size = 16
	theme.default_font = ThemeDB.fallback_font.duplicate()
	_heading_font = preload("res://fonts/LiberationSerif-Regular.ttf").duplicate()
	theme.set_color("font_color", "Label", PAPER)
	for kind in ["Button", "OptionButton", "LineEdit"]:
		theme.set_color("font_color", kind, PAPER)
		theme.set_color("font_disabled_color", kind, Color("858b80"))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("9c8a60")
		thumb.content_margin_left = 3; thumb.content_margin_right = 3
		theme.set_stylebox(state, "VScrollBar", thumb)
	if GameData.arena_mode == 1: run = ArenaTournamentRun.new()
	_setup_tournament_battles()
	battle = ArenaPveMatch.new()
	battle.run = run
	add_child(battle)
	battle.set_speed(float(GameData.arena_speed))
	run.deployment_check = battle.recruitment_clear
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
	_hit_numbers = ArenaHitNumbers.new()
	_hit_numbers.field = field
	add_child(_hit_numbers)
	_hit_numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle.visual_event.connect(func(event):
		if event.get("t") == "hitnum": _hit_numbers.add(event))
	battle.world_replacing.connect(func(): _hit_numbers._items.clear())
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_landing_layer = Control.new()
	_hud.add_child(_landing_layer)
	_landing_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing_layer.offset_top = 78
	_landing_layer.offset_bottom = -24
	_header = _label(_hud, RemakeText.t("Trials of the Allods"), 26, GOLD)
	_header.position = Vector2(28, 18)
	_header.add_theme_font_override("font", _heading_font)
	_round_panel = ArenaHudPanel.new()
	_round_panel.surface = Color(0.055, 0.055, 0.04, 0.85)
	_round_panel.minimum_size_changed.connect(_layout_round_badge.call_deferred)
	_hud.add_child(_round_panel)
	_round_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_round_panel.offset_left = -276; _round_panel.offset_right = -116
	_round_panel.offset_top = 16; _round_panel.offset_bottom = 60
	_round_badge = VBoxContainer.new()
	_round_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_badge.add_theme_constant_override("separation", 3)
	_round_panel.add_child(_round_badge)
	_wave_title = _label(_round_badge, "", 20, PAPER)
	_wave_title.add_theme_font_override("font", _heading_font)
	_phase = _label(_round_badge, "", 14, MUTED)
	_clock = _label(_round_badge, "", 16, GOLD)
	_menu = _button(_hud, RemakeText.t("Menu"), _show_menu, "")
	_menu.custom_minimum_size = Vector2(88, 44)
	_menu.add_theme_font_override("font", _heading_font)
	_menu.add_theme_font_size_override("font_size", 20)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu.offset_left = -104; _menu.offset_right = -16
	_menu.offset_top = 16; _menu.offset_bottom = 60
	_shop_panel = _unframed(_hud)
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
	_shop.resized.connect(_fit_reserve_slots)
	_shop_section.add_child(_shop)
	var shop_tools := VBoxContainer.new()
	shop_tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shop_tools.add_theme_constant_override("separation", 6)
	recruitment.add_child(shop_tools)
	_refresh_button = ArenaRoundButton.new()
	_refresh_button.emblem = preload("res://assets/arena/refresh.svg")
	_refresh_button.pressed.connect(_reroll)
	shop_tools.add_child(_refresh_button)
	_quality = _label(shop_tools, RemakeText.t("Shop odds"), 13, MUTED)
	_quality.mouse_filter = Control.MOUSE_FILTER_STOP
	_quality.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality.custom_minimum_size = Vector2(76, 26)
	_quality.add_theme_font_size_override("font_size", 14)
	_rail = ArenaHudPanel.new()
	_rail.custom_minimum_size.x = 264
	_hud.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_rail.offset_left = -284; _rail.offset_right = -16
	_rail.offset_top = 170; _rail.offset_bottom = -176
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
	_standings = PanelContainer.new()
	_standings.add_theme_stylebox_override("panel", ArenaCreatureCard.style(Color(0.04,0.06,0.06,0.94), Color(0,0,0,0), Vector2(10,8)))
	_hud.add_child(_standings)
	_standings.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_standings.offset_left = -232; _standings.offset_right = -16
	_standings.offset_top = 124
	_standing_rows = VBoxContainer.new()
	_standing_rows.add_theme_constant_override("separation", 2)
	_standings.add_child(_standing_rows)
	_bench_panel = _unframed(_hud)
	_bench_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bench_panel.offset_left = 24; _bench_panel.offset_right = -24
	_bench_panel.offset_top = -172; _bench_panel.offset_bottom = -12
	_bench_bar = HBoxContainer.new()
	_bench_bar.add_theme_constant_override("separation", 20)
	_bench_panel.add_child(_bench_bar)
	var company_status := VBoxContainer.new()
	company_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	company_status.add_theme_constant_override("separation", 1)
	_bench_bar.add_child(company_status)
	_army_title = _button(company_status, "", func(): pass, "")
	_army_title.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_army_title.set_meta("arena_company", true)
	_army_title.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_army_title.add_theme_font_size_override("font_size", 16)
	_army_title.icon = preload("res://assets/arena/company.svg")
	_army_title.add_theme_constant_override("icon_max_width", 18)
	_army_title.custom_minimum_size.x = 90
	_army_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reserve_count = _label(company_status, "", 13, MUTED)
	_reserve_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_training_panel = _unframed(company_status)
	company_status.move_child(_training_panel, 0)
	_train_button = ArenaRoundButton.new()
	_train_button.name = "TrainArmy"
	_train_button.pressed.connect(_show_training)
	_training_panel.add_child(_train_button)
	_alliance_list = VBoxContainer.new()
	_alliance_list.add_theme_constant_override("separation", 6)
	_alliance_panel = PanelContainer.new()
	_alliance_panel.add_theme_stylebox_override("panel", ArenaCreatureCard.style(Color(0.04,0.06,0.06,0.9), Color(0,0,0,0), Vector2(10,8)))
	_hud.add_child(_alliance_panel)
	_alliance_panel.position = Vector2(24, 190)
	_alliance_panel.add_child(_alliance_list)
	for key: String in ArenaAlliances.RULES:
		var row := HBoxContainer.new()
		row.name = key
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.set_meta("arena_alliance", key)
		_alliance_list.add_child(row)
		_icon(row, load("res://assets/arena/alliance_%s.svg" % key))
		var label := _label(row, "", 14, PAPER)
	_bench_scroll = ScrollContainer.new()
	_bench_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bench_scroll.resized.connect(_fit_reserve_slots)
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
	var treasury := VBoxContainer.new()
	treasury.add_theme_constant_override("separation", 0)
	purse.add_child(treasury)
	_gold = _label(treasury, "", 19, GOLD)
	_income = _label(treasury, "", 12, MUTED)
	var gap := Control.new()
	gap.custom_minimum_size.x = 2
	purse.add_child(gap)
	_icon(purse, preload("res://assets/arena/life.svg"))
	_lives = _label(purse, "", 17, PAPER)
	_start = _button(actions, RemakeText.t("Start battle"), _fight, "", true)
	_start.custom_minimum_size = Vector2(152, 44)
	_start.add_theme_font_size_override("font_size", 21)
	_start.add_theme_font_override("font", _heading_font)
	_fight_panel = _unframed(actions)
	var time_bar := HBoxContainer.new()
	time_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	time_bar.add_theme_constant_override("separation", 12)
	_fight_panel.add_child(time_bar)
	_pause = _icon_button(time_bar, preload("res://assets/arena/pause.svg"), func(): battle.toggle_pause(), RemakeText.t("Space"))
	_speed = _button(time_bar, "", _toggle_speed, "")
	_speed.custom_minimum_size = Vector2(66, 44)
	_update_speed()
	_sell_target = _button(_hud, "", _sell_selected, "", true)
	_sell_target.name = "SellTarget"
	_sell_target.icon = preload("res://assets/arena/sell.svg")
	_sell_target.add_theme_constant_override("icon_max_width", 20)
	_sell_target.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_sell_target.offset_left = -218; _sell_target.offset_right = -24
	_sell_target.offset_top = -226; _sell_target.offset_bottom = -178
	_sell_target.hide()
	_outcome_shade = ColorRect.new()
	_outcome_shade.color = Color(0.02, 0.025, 0.02, 0.32)
	_hud.add_child(_outcome_shade)
	_outcome_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_outcome = ArenaHudPanel.new()
	_outcome.surface.a = 1.0
	_outcome.minimum_size_changed.connect(_layout_outcome.call_deferred)
	_hud.add_child(_outcome)
	_outcome.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_dock = VBoxContainer.new()
	_dock.add_theme_constant_override("separation", 16)
	_outcome.add_child(_dock)
	_message = _label(_hud, "", 13, PAPER)
	_message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_message.offset_left = 24; _message.offset_right = -24
	_message.offset_top = -26; _message.offset_bottom = -6
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.add_theme_color_override("font_shadow_color", Color.BLACK)
	_message.add_theme_constant_override("shadow_offset_y", 2)
	_hud.move_child(_menu, _hud.get_child_count() - 1)
	_modal_layer = Control.new()
	_hud.add_child(_modal_layer)
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.03, 0.025, 0.65)
	_modal_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _close_modal())
	_modal_panel = ArenaHudPanel.new()
	_modal_panel.surface.a = 1.0
	_modal_panel.minimum_size_changed.connect(_layout_modal.call_deferred)
	_modal_layer.add_child(_modal_panel)
	_modal_box = VBoxContainer.new()
	_modal_box.add_theme_constant_override("separation", 12)
	_modal_panel.add_child(_modal_box)
	_modal_layer.hide()
	_evolution_notice = ArenaEvolutionNotice.new()
	_evolution_notice.below = _alliance_panel
	_hud.add_child(_evolution_notice)
	_hud.move_child(_evolution_notice, _modal_layer.get_index())
	_evolution_notice.shown.connect(_highlight_evolution)
	_tooltips = ArenaTooltips.new()
	_tooltips.scope = _hud
	_tooltips.world_hint = _world_hint
	_hud.add_child(_tooltips)
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
	battle.presentation_finished.connect(_refresh)
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
	if not landing and run.auto_save: run.save()
	if _sound: _sound.on_world(null)
	Gfx.set_border(_previous_border, _previous_border_dist)


func _refresh() -> void:
	_header.visible = false # The opening composition carries the expedition title.
	_gold.text = str(run.gold)
	_lives.text = str(run.lives) if run is ArenaTournamentRun else "%d/3" % run.lives
	_lives.tooltip_text = RemakeText.t("Health %d/100") % run.lives if run is ArenaTournamentRun else RemakeText.t("Lives %d/%d") % [run.lives, 3]
	var income := run.income_preview(run.battle_savings if run.stage == "fight" else -1)
	_income.text = RemakeText.t("Income +%d") % int(income.total)
	_income.visible = run.wave < run.wave_limit
	_gold.get_parent().tooltip_text = _income_details(income) + "\n" + RemakeText.t("Savings earn 1 gold per 10, up to 3. Win three battles in a row for +1 gold, or six for +2. Defeat breaks the streak.")
	_wave_title.text = run.round_title()
	_round_panel.tooltip_text = run.round_title() + " · " + run.encounter_title() + "\n" + RemakeText.t("Seed %s") % str(run.run_seed)
	var preparing := run.stage == "prepare" and not landing
	var fighting := run.stage == "fight" and not landing
	if not preparing: _evolution_notice.clear()
	else: _evolution_notice.retain(run)
	_bench_panel.visible = preparing or fighting
	_bench_bar.visible = not landing
	_shop_panel.visible = preparing
	_fight_panel.visible = fighting
	_round_panel.visible = not landing
	_start.visible = preparing
	_shop_section.visible = preparing
	_dock.visible = not preparing and not fighting and not landing and battle.settle_remaining <= 0
	_outcome.visible = _dock.visible
	_outcome_shade.visible = _dock.visible and run.stage == "reward"
	_layout_outcome()
	_pause.visible = fighting
	_speed.visible = fighting
	_rail.visible = not landing and _inspector.visible
	_landing_layer.visible = landing
	_clock.visible = fighting or preparing
	field.show_markers = preparing or fighting or battle.settle_remaining > 0
	_message.visible = preparing or fighting or run.save_error
	_battle_changed()
	_build_standings()
	if preparing or landing or not is_instance_valid(battle.world):
		var board := [run.run_seed, run.wave, run.army.filter(func(entry): return entry.deployed), run.challenge, run.lives]
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
		elif run.stage in ["result", "won", "lost"] and battle.settle_remaining <= 0: _build_result()
	_start.disabled = run.deployed_count() == 0
	_quality.tooltip_text = _shop_odds_text()
	_training_panel.visible = preparing or fighting
	_train_button.disabled = not preparing or run.experience() >= ArenaRules.MAX_TRAINING or not run.spending_error(ArenaRules.TRAINING_COST).is_empty()
	_train_button.price = -1 if run.level_needed() == 0 else ArenaRules.TRAINING_COST
	_train_button.value = str(run.capacity())
	_train_button.progress = 1.0 if run.level_needed() == 0 else float(run.level_progress()) / run.level_needed()
	_train_button.caption = RemakeText.t("Max level") if run.level_needed() == 0 else RemakeText.t("XP %d/%d") % [run.level_progress(), run.level_needed()]
	_train_button.queue_redraw()
	if _last_level > 0 and run.capacity() > _last_level and not landing and _sound:
		_sound.ui("buttons\\camp\\perk.wav")
	_last_level = run.capacity()
	_train_button.tooltip_text = RemakeText.t("Level %d") % run.capacity() + "\n" + RemakeText.t("Train · %d gold") % ArenaRules.TRAINING_COST + "\n" + RemakeText.t("Gain %d XP. Company level increases army capacity and improves shop odds.") % ArenaRules.TRAINING_XP
	if run.experience() >= ArenaRules.MAX_TRAINING: _train_button.tooltip_text = RemakeText.t("Your army is at full strength.")
	elif not run.spending_error(ArenaRules.TRAINING_COST).is_empty(): _train_button.tooltip_text += "\n" + run.spending_error(ArenaRules.TRAINING_COST)
	_alliance_panel.visible = (preparing or fighting) and run.deployed_count() > 0
	var counts := run.alliances()
	for row: HBoxContainer in _alliance_list.get_children():
		var key := String(row.name)
		var count := int(counts[key])
		row.visible = count > 0
		var label := row.get_child(1) as Label
		label.text = "%s  %d/%d" % [RemakeText.t(ArenaAlliances.RULES[key].name), count, ArenaAlliances.target(key, count)]
		var color := GOLD if ArenaAlliances.rank(key, count) > 0 else MUTED
		label.add_theme_color_override("font_color", color)
		row.get_child(0).modulate = color
	_reserve_count.text = RemakeText.t("Reserves %d/%d") % [run.bench_count(), run.bench_limit()]
	_refresh_button.price = run.refresh_cost()
	_refresh_button.queue_redraw()
	_refresh_button.tooltip_text = RemakeText.t("Refresh · %d gold") % run.refresh_cost() + "\n" + RemakeText.t("Refresh offers. A locked recruit stays.")
	var refresh_error := run.spending_error(run.refresh_cost())
	_refresh_button.disabled = not refresh_error.is_empty()
	if not refresh_error.is_empty(): _refresh_button.tooltip_text += "\n" + refresh_error
	_army_title.text = RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()]
	_army_title.tooltip_text = ""
	_army_title.remove_meta("arena_help")
	_army_title.add_theme_color_override("icon_normal_color", MUTED)
	_army_title.disabled = not preparing and not fighting

	if _army_title.disabled:
		_army_title.tooltip_text = ""
		_army_title.remove_meta("arena_help")
	_army_title.mouse_filter = Control.MOUSE_FILTER_IGNORE if _army_title.disabled else Control.MOUSE_FILTER_STOP
	if run.stage != "prepare" or landing: field.select_creature("")
	elif selected_uid > 0 and not run.unit(selected_uid).is_empty(): field.select_creature(run.unit(selected_uid).prototype)
	if selected_uid > 0 and run.unit(selected_uid).is_empty(): _clear_selection()
	_update_sell_target()
	_hide_inspector()
	if preparing and run.army.is_empty(): _hint(RemakeText.t("Recruit your first creature."))
	_tooltips.capture(_hud)
	_layout_outcome.call_deferred()
	if run.save_error: _feedback(RemakeText.t("The game could not be saved. Check free disk space before leaving."))


func _build_army() -> void:
	var benched := run.army.filter(func(u): return not u.deployed)
	var existing := {}
	for button: Button in _army_row.get_children(): existing[button.get_meta("slot_key", "")] = button
	var selected := run.unit(selected_uid)
	var returning: bool = run.stage == "prepare" and not selected.is_empty() and selected.deployed
	for i in maxi(run.bench_limit(), benched.size()):
		var entry: Dictionary = benched[i] if i < benched.size() else {}
		var key := "empty:%d" % i if entry.is_empty() else "%d:%s" % [entry.uid, entry.prototype]
		var button: Button = existing.get(key)
		existing.erase(key)
		if button == null:
			button = Button.new()
			button.set_meta("slot_key", key)
			button.custom_minimum_size = Vector2(96, 148)
			button.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0,0,0,0), Color(0,0,0,0), Vector2(3,3)))
			button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color(0.12, 0.16, 0.17, 0.45), Color(0, 0, 0, 0), Vector2(3,3)))
			button.add_theme_stylebox_override("focus", ArenaCreatureCard.style(Color(0, 0, 0, 0), PAPER, Vector2(3,3)))
			button.add_theme_stylebox_override("disabled", ArenaCreatureCard.style(Color(0,0,0,0), Color(0,0,0,0), Vector2(3,3)))
			button.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("344248"), GOLD, Vector2(3,3)))
			button.add_theme_font_size_override("font_size", 13)
			_army_row.add_child(button)
			var line := ColorRect.new()
			line.name = "SlotLine"
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(line)
			line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			line.offset_left = 10; line.offset_right = -10
			line.offset_bottom = -2
			if entry.is_empty():
				button.pressed.connect(_return_to_reserves)
			else:
				button.set_meta("arena_creature", {"id": entry.prototype, "uid": int(entry.uid)})
				button.pressed.connect(_select.bind(int(entry.uid)))
				var preview := WikiPreview.new()
				preview.fit_slot = true
				button.add_child(preview)
				preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				preview.offset_top = 14; preview.offset_bottom = -36
				preview.show_model({"kind": "creature", "value": entry.prototype})
				preview.turn_by(-0.35)
				preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
				for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ArenaStars.add_to(button, int(entry.rank) + 1, Vector2(5, 1))
		_army_row.move_child(button, i)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if landing or run.stage not in ["prepare", "fight"] else Control.MOUSE_FILTER_STOP
		button.disabled = not returning if entry.is_empty() else landing or run.stage not in ["prepare", "fight"]
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
		button.set_meta("return_slot", returning and i == benched.size())
		button.tooltip_text = (RemakeText.t("Return the selected creature to reserves.") if returning else RemakeText.t("Recruits wait here until you deploy them.")) if entry.is_empty() else ""
		var marker := button.get_node("SlotLine") as ColorRect
		var active := returning if entry.is_empty() else int(entry.uid) == selected_uid
		marker.color = GOLD if active else Color(0.72, 0.75, 0.72, 0.32)
		marker.offset_top = -4 if active else -3
	for button: Button in existing.values():
		_army_row.remove_child(button)
		button.queue_free()
	_fit_reserve_slots()
	if _tooltips: _tooltips.capture(_army_row)


func _build_shop() -> void:
	# Reuse each offer's render target while only prices, counts or locks change.
	while _shop.get_child_count() > run.shop.size():
		var extra := _shop.get_child(_shop.get_child_count() - 1)
		_shop.remove_child(extra); extra.queue_free()
	for index in run.shop.size():
		var offer: Dictionary = run.shop[index]
		var family := int(offer.family)
		var rank := int(offer.get("rank", 0))
		var key := "%d:%d" % [family, rank]
		var box: Control = _shop.get_child(index) if index < _shop.get_child_count() else null
		if box != null and box.get_meta("offer_key", "") != key:
			_shop.remove_child(box); box.queue_free(); box = null
		var fresh := box == null
		if fresh:
			box = Control.new()
			box.set_meta("offer_key", key)
			box.custom_minimum_size = Vector2(96, 148)
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_shop.add_child(box)
			_shop.move_child(box, index)
		if family < 0:
			if fresh:
				var bought := _label(box, RemakeText.t("Recruited"), 13, MUTED)
				bought.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				bought.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				bought.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			continue
		var rule: Dictionary = ArenaRules.FAMILIES[family]
		var card := ArenaCreatureCard.new() if fresh else box.get_child(0) as ArenaCreatureCard
		card.prototype = rule.forms[rank]
		card.quality = rank
		card.cost = run.offer_cost(offer)
		card.copies = run.army.filter(func(entry): return entry.family == family and entry.rank == rank).size()
		card.copies_needed = ArenaRules.evolution_copies(family, rank)
		card.disabled = not run.purchase_error(index).is_empty()
		card.caption = ArenaAlliances.names(family)
		card.family = family
		card.footer = RemakeText.t("%d gold") % card.cost
		if fresh:
			card.set_meta("arena_creature", {"id": card.prototype, "family": family, "rank": rank, "offer": index})
			card.pressed.connect(_recruit_offer.bind(index))
			box.add_child(card)
			card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.tooltip_text = ""
		card.update_offer()
		var lock: Button
		if fresh:
			lock = _icon_button(box, preload("res://assets/arena/lock.svg"), func(): pass, RemakeText.t("Lock recruit"))
			lock.toggle_mode = true
			lock.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("464f34"), GOLD, Vector2(3, 3)))
			lock.custom_minimum_size = Vector2(28, 28)
			lock.add_theme_constant_override("icon_max_width", 16)
			lock.toggled.connect(func(_on): run.lock_offer(index))
			lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			lock.offset_left = -30; lock.offset_right = -2
			lock.offset_top = 0; lock.offset_bottom = 28
		else: lock = box.get_child(1)
		lock.set_pressed_no_signal(offer.locked)
		lock.modulate.a = 1 if offer.locked else 0.65


func _build_landing() -> void:
	_clear(_landing_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.06, 0.52)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing_layer.add_child(shade)
	_landing_panel = ArenaHudPanel.new()
	_landing_panel.surface = Color(0.035, 0.055, 0.065, 0.96)
	_landing_panel.custom_minimum_size.x = 900
	_landing_panel.minimum_size_changed.connect(_layout_landing.call_deferred)
	_landing_layer.add_child(_landing_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	_landing_panel.add_child(margin)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 22)
	margin.add_child(contents)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	contents.add_child(modes)
	var mode_label := _label(modes, RemakeText.t("Mode"), 14, GOLD)
	mode_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for index in 2:
		var mode_button := _button(modes, RemakeText.t("Expedition") if index == 0 else RemakeText.t("Autochess"), _switch_mode.bind(index), RemakeText.t("Win 30 battles. You can lose twice.") if index == 0 else RemakeText.t("Face nine computer opponents. The last player standing wins."), index == int(run is ArenaTournamentRun))
		mode_button.name = "ExpeditionMode" if index == 0 else "AutochessMode"
		mode_button.disabled = index == int(run is ArenaTournamentRun)

	var title := _wrap(contents, RemakeText.t("Autochess") if run is ArenaTournamentRun else RemakeText.t("Trials of the Allods"), 46, PAPER)
	title.add_theme_font_override("font", _heading_font)
	_rule(contents)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	contents.add_child(columns)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 320
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 16)
	columns.add_child(choices)
	var heading := _wrap(choices, RemakeText.t("Recruit your army"), 28, GOLD)
	heading.add_theme_font_override("font", _heading_font)
	_wrap(choices, RemakeText.t("Recruit creatures and collect matching copies to make them stronger."), 17, PAPER)
	_wrap(choices, RemakeText.t("Starting gold: %d") % ArenaRules.OPENING_GOLD, 24, GOLD)
	if _saved:
		_button(choices, (RemakeText.t("Continue · round %d") if run is ArenaTournamentRun else RemakeText.t("Continue · wave %d")) % run.wave, func():
			landing = false; run.auto_save = true; _refresh(), RemakeText.t("Resume with the same army and shop."), true)
	_challenge = OptionButton.new()
	var maximum := int(ArenaRun.profile().get("challenge", 0))
	for text: String in ["Standard expedition", "Veteran expedition", "Champion expedition"]:
		_challenge.add_item(RemakeText.t(text))
	for i in 3: _challenge.set_item_disabled(i, i > maximum)
	_challenge.custom_minimum_size.y = 40
	_challenge.tooltip_text = RemakeText.t("Win an expedition to unlock the next difficulty.")
	choices.add_child(_challenge)
	_challenge.visible = not run is ArenaTournamentRun
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = RemakeText.t("Random seed")
	_seed_input.tooltip_text = RemakeText.t("Optional: enter a whole number to replay the same shops and encounters.")
	_seed_input.custom_minimum_size.y = 38
	var seed_toggle := _button(choices, RemakeText.t("Set seed"), func():
		_seed_input.visible = not _seed_input.visible
		_layout_landing.call_deferred(), _seed_input.tooltip_text)
	seed_toggle.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	seed_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	seed_toggle.custom_minimum_size.y = 28
	choices.add_child(_seed_input)
	_seed_input.hide()
	_landing_start = _button(choices, RemakeText.t("Start game") if run is ArenaTournamentRun else RemakeText.t("Begin expedition"), func():
		if not _seed_input.text.strip_edges().is_empty() and not _seed_input.text.strip_edges().is_valid_int():
			_feedback(RemakeText.t("Enter a whole number for the seed."))
		elif _saved: _confirm_new_run()
		else: _begin(), "", true)
	_landing_start.custom_minimum_size.y = 52
	_landing_start.add_theme_font_size_override("font_size", 20)
	# Original models form one scene, rather than three starter-choice cards.
	var showcase := VBoxContainer.new()
	showcase.custom_minimum_size.x = 430
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.size_flags_stretch_ratio = 1.25
	columns.add_child(showcase)
	var stage := Control.new()
	stage.custom_minimum_size.y = 260
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase.add_child(stage)
	# The flying figure uses a wider frame above and beside the grounded pair.
	# Its transparent viewport overlaps the stage edge, keeping the wings large.
	for spec in [["boarredf3", 0.0, 0.39, 0.4, 1.0], ["trollbluef12", 0.23, 0.8, 0.2, 1.0], ["succubgreym13", 0.2, 1.2, -0.25, 0.6]]:
		var preview := WikiPreview.new()
		preview.fit_slot = true
		stage.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.anchor_left = spec[1]; preview.anchor_right = spec[2]
		preview.anchor_top = spec[3]; preview.anchor_bottom = spec[4]
		preview.show_model({"kind":"creature", "value":spec[0]})
		preview.turn_by(-0.25)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var regions := _wrap(showcase, " · ".join([ArenaRules.region_name(0), ArenaRules.region_name(1), ArenaRules.region_name(2)]), 15, GOLD)
	regions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule(showcase)
	var facts := _wrap(showcase, RemakeText.t("Face nine computer opponents. The last player standing wins.") if run is ArenaTournamentRun else RemakeText.t("Win 30 battles. You can lose twice."), 16, PAPER)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help := _wrap(showcase, RemakeText.t("Start with 100 health. Fight creeps in rounds 1–3 and every fifth round, and other players in between.") if run is ArenaTournamentRun else RemakeText.t("You have 45 seconds between battles to recruit and move creatures. They fight automatically."), 14, MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layout_landing.call_deferred()


func _layout_landing() -> void:
	if not is_instance_valid(_landing_panel): return
	_landing_panel.size = Vector2(minf(940, _landing_layer.size.x - 48), 0)
	_landing_panel.position = (_landing_layer.size - _landing_panel.size) / 2


func _begin() -> void:
	var value := _seed_input.text.strip_edges()
	if not value.is_empty() and not value.is_valid_int():
		_feedback(RemakeText.t("Enter a whole number for the seed."))
		return
	var chosen := randi_range(1, 99999999) if value.is_empty() else clampi(int(value), 1, 99999999)
	var challenge_index := _challenge.selected
	landing = false
	battle._round_key = ""
	_board_key = ""
	_saved = false
	_last_level = 0
	_result_key = -1; _result_remaining = 4.0
	_clear_selection()
	run.auto_save = true
	run.begin(chosen, 0, challenge_index)
	_setup_tournament_battles()
	_hint("")


func _build_result() -> void:
	var result: Dictionary = run.last_result
	var won := int(result.get("winner", -1)) == 0
	var terminal := run.stage in ["won", "lost"]
	var text := "Expedition complete" if run.stage == "won" else "The expedition ends" if run.stage == "lost" else "Victory" if won else "Defeat"
	if run is ArenaTournamentRun and terminal: text = "First place" if run.stage == "won" else "Eliminated"
	var summary: Node = _dock
	if not terminal:
		summary = HBoxContainer.new()
		summary.add_theme_constant_override("separation", 12)
		_dock.add_child(summary)
	var title := _wrap(summary, RemakeText.t(text), 28, GOLD if won else PAPER) if terminal else _label(summary, RemakeText.t(text), 26, GOLD if won else PAPER)
	title.add_theme_font_override("font", _heading_font)
	var reward := HBoxContainer.new()
	reward.add_theme_constant_override("separation", 6)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not terminal:
		reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward.alignment = BoxContainer.ALIGNMENT_END
	summary.add_child(reward)
	_icon(reward, preload("res://assets/arena/coin.svg") if won else preload("res://assets/arena/life.svg")).custom_minimum_size = Vector2(18, 18)
	var reward_text := RemakeText.t("+%d gold") % int(result.get("gold", 0)) if won and run.stage != "won" else RemakeText.t("Lives %d/%d") % [run.lives, 3]
	if run is ArenaTournamentRun: reward_text = RemakeText.t("+%d gold") % int(result.get("gold", 0)) if won else RemakeText.t("Health %d/100") % run.lives
	_label(reward, reward_text, 18, GOLD if won else PAPER)
	var details := RemakeText.t("Battle: %d seconds · Damage dealt: %d · Damage taken: %d") % [int(result.get("seconds", 0)), int(result.get("damage", [0, 0])[0]), int(result.get("damage", [0, 0])[1])]
	if result.has("income"): details = _income_details(result.income) + "\n" + details
	details = run.round_title() + " · " + run.encounter_title() + "\n" + details
	reward.tooltip_text = details
	if result.get("empty_army", false): _wrap(_dock, RemakeText.t("No creatures were recruited."), 15, MUTED)
	elif not won and run.stage != "lost" and not run is ArenaTournamentRun: _wrap(_dock, RemakeText.t("Your next shop refresh is free."), 15, MUTED)
	if run is ArenaTournamentRun and terminal:
		_wrap(_dock, RemakeText.t("Place %d of %d") % [run.placements[0], ArenaTournamentRun.PLAYER_COUNT], 20, GOLD)
	if run.stage == "won" and not run is ArenaTournamentRun: _wrap(_dock, RemakeText.t("The ruins are yours.") if run.challenge == 2 else RemakeText.t("A harder expedition awaits."), 16)
	if run.stage in ["won", "lost"]:
		var action := _button(_dock, RemakeText.t("New game") if run is ArenaTournamentRun else RemakeText.t("New expedition"), func(): landing = true; _saved = false; _clear_selection(); _refresh(), "", true)
		action.custom_minimum_size.y = 44
	else:
		if _result_key != run.history.size():
			_result_key = run.history.size()
			_result_remaining = 4.0
		var timer := _wrap(_dock, "", 14, MUTED)
		timer.name = "ResultCountdown"
		_update_result_countdown()
	# Snow remains visible behind the notice; a fine dark edge keeps the type
	# legible without restoring a rectangular panel or a screen-wide shade.
	for label: Label in _dock.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.035, 0.04, 0.95))
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_y", 2)


func _build_rewards() -> void:
	var heading := _label(_dock, RemakeText.t("A moment at camp"), 28, GOLD)
	heading.add_theme_font_override("font", _heading_font)
	_wrap(_dock, RemakeText.t("Take one reward before the next battle."), 15, MUTED)
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
		if reward.kind == "companion": id = reward.prototype
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
		var action := _button(box, RemakeText.t("Choose reward"), func(): _choose_reward(index), help, true)
		action.name = "ChooseReward"
		if not id.is_empty():
			action.tooltip_text += "\n\n" + ArenaUnitInfo.summary(id)
		if reward.kind == "companion" and run.bench_count() > run.bench_limit():
			action.disabled = true
			action.tooltip_text = RemakeText.t("Your reserves already hold an extra ally. Choose another reward.")


func _show_alliance(key: String) -> void:
	_showing_company = true
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	var rule: Dictionary = ArenaAlliances.RULES[key]
	var count := int(run.alliances()[key])
	var heading := _wrap(_inspect_box, RemakeText.t(rule.name), 24, GOLD)
	heading.add_theme_font_override("font", _heading_font)
	_wrap(_inspect_box, RemakeText.t("On field: %d/%d") % [count, ArenaAlliances.target(key, count)], 17, PAPER)
	_wrap(_inspect_box, ArenaAlliances.effect(key, ArenaAlliances.rank(key, count)), 17, GOLD)
	_wrap(_inspect_box, RemakeText.t(rule.help), 14, PAPER)
	var thresholds: Array[String] = []
	for threshold: int in rule.thresholds: thresholds.append(str(threshold))
	_wrap(_inspect_box, RemakeText.t("Bonuses at %s different creatures.") % " / ".join(thresholds), 13, GOLD)
	_wrap(_inspect_box, RemakeText.t("Only deployed creatures count. Copies and evolved forms of the same creature count once."), 13, MUTED)
	_rule(_inspect_box)
	for family: int in rule.families:
		var owned := run.army.filter(func(entry): return int(entry.family) == family)
		var deployed := owned.any(func(entry): return entry.deployed)
		var status := "On field" if deployed else "In reserves" if not owned.is_empty() else "Not recruited"
		_wrap(_inspect_box, "%s · %s" % [RemakeText.t(ArenaRules.FAMILIES[family].name), RemakeText.t(status)], 14, GOLD if deployed else MUTED)


func _show_company() -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	_showing_company = true
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	_wrap(_inspect_box, RemakeText.t("Level %d") % run.capacity(), 24, GOLD)
	_wrap(_inspect_box, RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()], 18, PAPER)
	_wrap(_inspect_box, RemakeText.t("Each round grants 1 XP. Train to increase your company level. Higher levels add army slots and unlock stronger recruits.") if run is ArenaTournamentRun else RemakeText.t("Each victory grants 1 XP. Train to increase your company level. Higher levels add army slots and unlock stronger recruits."), 15, MUTED)
	_rule(_inspect_box)
	_wrap(_inspect_box, _shop_odds_text(), 15, PAPER)
	if run.capacity() < ArenaRules.MAX_ARMY:
		_wrap(_inspect_box, RemakeText.t("Next level: %d XP") % (run.level_needed() - run.level_progress()), 15, GOLD)
	if not run.boons.is_empty():
		_rule(_inspect_box)
		for boon: String in run.boons:
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][0]), 15, GOLD)
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][1]), 13, MUTED)
	_tooltips.capture(_hud)


func _shop_odds_text() -> String:
	var text := RemakeText.t("Shop odds") + " · " + RemakeText.t("Level %d") % run.capacity()
	var odds: Array = ArenaRules.SHOP_ODDS[run.capacity()]
	for tier in 5: text += "\n" + RemakeText.t("Tier %d · %d gold · %d%%") % [tier + 1, tier + 1, int(odds[tier])]
	return text + "\n\n" + RemakeText.t("New offers use your company level. Recruits start at one star; matching copies evolve them.")


func _update_result_countdown() -> void:
	var label := _dock.get_node_or_null("ResultCountdown") as Label
	if label:
		var text := "Retry in %ds" if int(run.last_result.get("winner", -1)) != 0 else "Camp in %ds" if run.wave % 5 == 0 else "Next wave in %ds"
		if run is ArenaTournamentRun: text = "Next round in %ds"
		label.text = RemakeText.t(text) % ceili(_result_remaining)


func _creature_preview(parent: Node, id: String, height: float) -> WikiPreview:
	var preview := WikiPreview.new()
	preview.fit_slot = true
	preview.custom_minimum_size = Vector2(80, height)
	parent.add_child(preview)
	preview.show_model({"kind": "creature", "value": id})
	preview.turn_by(-0.35)
	return preview


func _select(uid: int) -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	selected_uid = uid
	battle.selected_run_uid = uid
	field.highlighted_run_uid = uid
	var entry := run.unit(uid)
	if entry.is_empty(): return
	if run.stage == "prepare" and not landing: field.select_creature(entry.prototype)
	_build_army()
	_tooltips.capture(_hud)
	_update_sell_target()
	_hint("")


func _select_world(unit: GameUnit) -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	var uid := int(unit.get_meta("arena_placement", {}).get("run_uid", 0))
	var selected := run.unit(selected_uid)
	if uid > 0 and run.stage == "prepare" and not selected.is_empty() and not selected.deployed:
		var error := run.swap_from_bench(selected_uid, uid)
		if error.is_empty(): _clear_selection()
		_feedback(error)
		return
	if uid > 0 and not landing: _select(uid)
	else: _clear_selection()
	_tooltips.capture(_hud)


func _inspect(id: String, entry: Dictionary = {}) -> void:
	if id.is_empty(): return
	_showing_company = false
	_inspected = id
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	var title := _wrap(_inspect_box, ArenaRules.title(id), 22, GOLD)
	title.add_theme_font_override("font", _heading_font)
	var family := int(entry.get("family", -1))
	var rank := int(entry.get("rank", ArenaUnitInfo.rank_of(id)))
	if family >= 0:
		_wrap(_inspect_box, ArenaAlliances.names(family), 15, GOLD)
		_wrap(_inspect_box, RemakeText.t("Tier %d · %d gold") % [int(ArenaRules.FAMILIES[family].tier), int(ArenaRules.FAMILIES[family].cost)], 13, MUTED)
		_wrap(_inspect_box, ArenaRules.region_name(int(ArenaRules.FAMILIES[family].get("region", 0))), 13, MUTED)
	if rank >= 0:
		var stars := Control.new()
		stars.custom_minimum_size.y = 12
		_inspect_box.add_child(stars)
		ArenaStars.add_to(stars, rank + 1, Vector2.ZERO)
	_creature_preview(_inspect_box, id, 64)
	_live_health = _wrap(_inspect_box, ArenaUnitInfo.summary(id, _inspected_unit), 15)
	if is_instance_valid(_inspected_unit) and family >= 0 and run.alliances().values().any(func(n): return int(n) >= 2):
		_wrap(_inspect_box, RemakeText.t("Active bonuses are included in these stats."), 13, MUTED)
	var spells := _spell_titles(GameData.db.find("monster_prototypes", id))
	if not spells.is_empty(): _wrap(_inspect_box, spells, 14, GOLD)
	if family >= 0:
		var needed := ArenaRules.evolution_copies(family, rank)
		if needed > 0:
			_rule(_inspect_box)
			_label(_inspect_box, RemakeText.t("Evolution"), 14, MUTED)
			_wrap(_inspect_box, ArenaRules.title(ArenaRules.prototype(family, rank + 1)), 16, GOLD)
			var count := run.army.filter(func(u): return u.family == family and u.rank == rank).size()
			_wrap(_inspect_box, RemakeText.t("Copies: %d/%d") % [count, needed], 14)
	if entry.has("offer"):
		var error := run.purchase_error(int(entry.offer))
		if not error.is_empty(): _wrap(_inspect_box, error, 14, MUTED)
	_tooltips.capture(_hud)


func _hide_inspector() -> void:
	_hover_key = ""
	_hover_wait = 0.0
	_hover_missing = 0.0
	_inspected_unit = null
	_showing_company = false
	if _inspector: _inspector.hide()
	if _rail: _rail.hide()


func _hover_inspector(dt: float) -> void:
	if landing or run.stage not in ["prepare", "fight"] or _modal_layer.visible:
		_hide_inspector()
		return
	var control := get_viewport().gui_get_hovered_control()
	if _rail.visible and control and (control == _rail or _rail.is_ancestor_of(control)):
		_hover_missing = 0
		return
	var entry := {}
	var id := ""
	var key := ""
	var unit: GameUnit
	if control == field and is_instance_valid(field.hovered):
		unit = field.hovered
		id = String(unit.info.get("prototype", ""))
		var placement: Dictionary = unit.get_meta("arena_placement", {})
		entry = run.unit(int(placement.get("run_uid", 0)))
		if placement.has("source_uid"): entry = {"family":placement.get("family", -1), "rank":placement.get("rank", 0)}
		key = "world:%d" % unit.get_instance_id()
	else:
		while control and control != _hud:
			if control.has_meta("arena_creature"):
				entry = control.get_meta("arena_creature")
				id = entry.id
				if entry.has("uid"): entry = run.unit(int(entry.uid))
				key = "preview:" + id + ":" + str(entry.get("uid", entry.get("offer", -1)))
				break
			if control.has_meta("arena_alliance"):
				key = "alliance:" + String(control.get_meta("arena_alliance"))
				break
			if control.has_meta("arena_company"):
				key = "company"
				break
			control = control.get_parent() as Control
	if key != _dismissed_hover: _dismissed_hover = ""
	if not key.is_empty() and key == _dismissed_hover: return
	if key.is_empty():
		_hover_missing += dt
		if _hover_missing > 0.22: _hide_inspector()
		return
	_hover_missing = 0
	if key != _hover_key:
		_hover_key = key
		_hover_wait = 0
		_inspected_unit = null
		_rail.hide(); _inspector.hide()
	_hover_wait += dt
	if _hover_wait >= 0.25 and not _rail.visible:
		_inspected_unit = unit
		if key.begins_with("alliance:"): _show_alliance(key.get_slice(":", 1))
		elif key == "company": _show_company()
		else: _inspect(id, entry)


func _place(point: Vector2) -> void:
	if landing or run.stage != "prepare" or selected_uid <= 0: return
	var error := battle.placement_error(point)
	if error.is_empty(): error = run.deploy(selected_uid, point)
	if error.is_empty(): _clear_selection()
	_feedback(error)


func _fight() -> void:
	if landing: return
	_clear_selection()
	if not battle.start(): _feedback(RemakeText.t("Deploy at least one creature before starting."))


func _clear_selection() -> void:
	_showing_company = false
	_inspected_unit = null
	selected_uid = 0
	if battle: battle.selected_run_uid = 0
	if field:
		field.select_creature("")
		field.highlighted_run_uid = 0
	_hint("")
	if _army_row: _build_army()
	_hide_inspector()
	_update_sell_target()


func _battle_changed() -> void:
	if _pause:
		_pause.icon = preload("res://assets/arena/play.svg") if battle.phase == ArenaMatch.Phase.PAUSED else preload("res://assets/arena/pause.svg")
		_pause.tooltip_text = RemakeText.t("Resume" if battle.phase == ArenaMatch.Phase.PAUSED else "Pause") + " · " + RemakeText.t("Space")
		if _tooltips: _tooltips.capture(_pause)
	if _phase:
		_phase.text = RemakeText.t("Preparing") if run.stage == "prepare" else RemakeText.t("Paused") if battle.phase == ArenaMatch.Phase.PAUSED else RemakeText.t("Battle") if run.stage == "fight" else RemakeText.t("Victory" if battle.winner == 0 else "Defeat") if battle.settle_remaining > 0 else ""
		if run is ArenaTournamentRun and run.stage == "fight" and battle.phase == ArenaMatch.Phase.FINISHED:
			_phase.text = RemakeText.t("Other battles")
		_phase.visible = not _phase.text.is_empty()
		_layout_round_badge.call_deferred()
	if _sound: _sound.music.tick(2 if battle.phase == ArenaMatch.Phase.FIGHT else 0)


func _process(dt: float) -> void:
	_hover_inspector(dt)
	_standings.visible = run is ArenaTournamentRun and not landing and not _rail.visible and not _modal_layer.visible and not _outcome.visible
	if is_instance_valid(_tournament_battles): _tournament_battles.set_process(not _modal_layer.visible and battle.phase != ArenaMatch.Phase.PAUSED)
	if not landing and run.stage == "result" and battle.settle_remaining <= 0 and not _modal_layer.visible:
		_result_remaining = maxf(0.0, _result_remaining - dt / maxf(Engine.time_scale, 0.001))
		_update_result_countdown()
		if _result_remaining <= 0: run.advance()
	if not landing and run.stage == "prepare" and not _modal_layer.visible:
		if run.elapse_preparation(dt / maxf(Engine.time_scale, 0.001)):
			_clear_selection()
			battle.expire_preparation()
		_timer_save_wait += dt
		if _timer_save_wait >= 5.0:
			_timer_save_wait = 0
			if run.auto_save: run.save_error = not run.save()
	if _evolution_notice.visible:
		_evolution_notice.covered = _modal_layer.visible
	if is_instance_valid(_live_health) and is_instance_valid(_inspected_unit) and _rail.visible:
		var unit := _inspected_unit
		_live_health.text = ArenaUnitInfo.summary(_inspected, unit)
	if _clock and battle and is_instance_valid(battle.world):
		_clock.text = RemakeText.t("Battle in %ds") % ceili(run.preparation_left) if run.stage == "prepare" else "%d:%02d" % [int(battle.world.time) / 60, int(battle.world.time) % 60]
		_clock.add_theme_color_override("font_color", Color("efbf87") if run.stage == "prepare" and run.preparation_left <= 10 else GOLD)

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
		if event.keycode == KEY_SPACE and run.stage == "fight" and not _modal_layer.visible:
			battle.toggle_pause(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _modal_layer.visible: _close_modal()
			elif selected_uid > 0 or not _hover_key.is_empty() or _inspector.visible:
				_dismissed_hover = _hover_key
				_clear_selection()
			else: _show_menu()
			get_viewport().set_input_as_handled()


func _guide() -> void:
	_open_modal(RemakeText.t("Autochess guide") if run is ArenaTournamentRun else RemakeText.t("Expedition guide"), 640)
	_guide_scroll = ScrollContainer.new()
	_guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_guide_scroll.custom_minimum_size.y = minf(440, _hud.size.y - 220)
	_modal_box.add_child(_guide_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_guide_scroll.add_child(content)
	var topics := [
		["Economy", "Each victory pays a bounty, plus interest on savings and a winning-streak bonus. Failed attempts grant no income."],
		["Preparation", "You have 45 seconds to recruit and deploy. Start early when ready. Menus pause the countdown. If the field is empty, reserves deploy when time runs out. With no recruits, you lose the wave."],
		["Recruitment", "New recruits join the field if there is room, or wait in reserves. Company level determines shop odds. Train for stronger offers, or refresh to find matching copies."],
		["Evolution", "Collect matching creatures to evolve them. Stars mark each stronger form. The creature details show how many you need."],
		["Your army", "Select a creature, then its place on the field. Select a reserve, then an ally to swap them. An empty reserve slot withdraws a creature. Select a creature to reveal the sell area."],
		["Battle", "Both teams fight under AI control. Hover a creature for details. Space pauses combat; the speed control switches between normal and double speed."],
		["Alliances", "Different deployed creatures with matching traits activate bonuses. Multiple alliances can be active together. Reserves and duplicates do not add to the count."],
		["Company", "Visit camp every five victories for experience, supplies or company upgrades. Win all thirty waves to unlock harder expeditions."]]
	if run is ArenaTournamentRun:
		topics[0] = [RemakeText.t("Economy"), RemakeText.t("Every round pays 5 gold, plus interest. Wins add 1 gold and can earn a streak bonus. Every round also grants 1 XP.")]
		topics[1] = [RemakeText.t("Preparation"), RemakeText.t("You have 45 seconds to recruit and arrange your army. Start early when ready. Menus pause the countdown.")]
		topics[-1] = [RemakeText.t("Players"), RemakeText.t("Nine computer opponents build their own armies. Losing costs health based on the round and surviving enemy stars. At zero health you are eliminated. Click a player to inspect their army.")]
		topics.append([RemakeText.t("Rounds"), RemakeText.t("Rounds 1–3 and every fifth round are against creeps. Other rounds pair surviving players. With an odd player count, one army fights a copy without damaging its owner. After round 30, defeat damage increases each round.")])
	for topic in topics:
		_label(content, RemakeText.t(topic[0]), 18, GOLD)
		_wrap(content, RemakeText.t(topic[1]), 15, PAPER)
	_button(_modal_box, RemakeText.t("Close"), _close_modal, "", true)


func _feedback(error: String) -> void:
	if not error.is_empty():
		_message.text = error
		_message.add_theme_color_override("font_color", Color("efbf87"))
	else:
		_hint("")


func _hint(value: String) -> void:
	if value.is_empty() and not landing and run.stage == "prepare" and run.army.is_empty(): value = RemakeText.t("Recruit your first creature.")
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
	button.custom_minimum_size.y = 40
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
	var before := run.army.duplicate(true)
	var error := run.buy(index)
	_feedback(error)
	if error.is_empty():
		_clear_selection()
		if not run.last_evolutions.is_empty():
			var events: Array[Dictionary] = []
			var seen := {}
			for evolved_uid in run.last_evolutions:
				if seen.has(evolved_uid): continue
				seen[evolved_uid] = true
				var entry := run.unit(evolved_uid)
				for old: Dictionary in before:
					if old.uid == evolved_uid:
						events.append({"uid": evolved_uid, "from": old.prototype, "to": entry.prototype, "old_rank": old.rank, "rank": entry.rank})
			_evolution_notice.present(events)


func _choose_reward(index: int) -> void:
	_feedback(run.choose_reward(index))


func _highlight_evolution(event: Dictionary) -> void:
	if _sound: _sound.ui("buttons\\camp\\perk.wav")
	field.evolution_pulses[int(event.uid)] = 1.6
	for button: Button in _army_row.get_children():
		if int(button.get_meta("arena_creature", {}).get("uid", -1)) != int(event.uid): continue
		var glow := ArenaCreatureCard.style(Color(GOLD, 0.12), GOLD, Vector2(3, 3))
		button.add_theme_stylebox_override("normal", glow)
		var tween := button.create_tween().set_parallel()
		tween.tween_property(glow, "border_color:a", 0.0, 1.6)
		tween.tween_property(glow, "bg_color:a", 0.0, 1.6)


func _return_to_reserves() -> void:
	var error := run.bench(selected_uid)
	if error.is_empty(): _clear_selection()
	_feedback(error)


func _layout_round_badge() -> void:
	if not _round_panel: return
	var minimum := _round_panel.get_combined_minimum_size()
	_round_panel.offset_left = -116 - maxf(160, minimum.x)
	_round_panel.offset_right = -116
	_round_panel.offset_bottom = 16 + maxf(44, minimum.y)


func _layout_outcome() -> void:
	if not _outcome or not _hud: return
	var notice := run.stage in ["result", "won", "lost"]
	if _outcome.decorated == notice:
		_outcome.decorated = not notice
		_outcome.queue_redraw()
		var padding := StyleBoxEmpty.new()
		padding.content_margin_left = 0 if notice else 12
		padding.content_margin_right = 0 if notice else 12
		padding.content_margin_top = 0 if notice else 10
		padding.content_margin_bottom = 0 if notice else 10
		_outcome.add_theme_stylebox_override("panel", padding)
		_dock.add_theme_constant_override("separation", 6 if notice else 16)
	var width := minf(900 if run.stage == "reward" else 248 if run.stage == "result" else 292, _hud.size.x - 48)
	_outcome.custom_minimum_size.x = width
	_outcome.size = Vector2(width, 0)
	_outcome.position = (_hud.size - _outcome.size) / 2 if run.stage == "reward" else Vector2(_hud.size.x - width - 16, minf(158, _hud.size.y - _outcome.size.y - 120))


func _layout_hud() -> void:
	if not _shop_panel: return
	# One logical canvas; type, targets, portraits and spacing scale together.
	# The battlefield still renders at the full physical window resolution.
	_ui_scale = maxf(1.0, minf(size.x / 1280.0, size.y / 800.0))
	_hud.scale = Vector2.ONE * _ui_scale
	_hud.size = size / _ui_scale
	if theme.default_font is FontFile: theme.default_font.oversampling = _ui_scale
	if _heading_font is FontFile: _heading_font.oversampling = _ui_scale
	field.ui_scale = _ui_scale
	field._update_camera()
	_shop_panel.offset_right = minf(960, _hud.size.x - 300)
	if _army_row and not run.army.is_empty(): _build_army()
	_layout_outcome()
	_layout_modal()
	_layout_landing()
	if _tooltips: _tooltips.capture(_hud)


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
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var fill := Color(0, 0, 0, 0) if state in ["normal", "focus", "disabled"] else Color("344248")
		button.add_theme_stylebox_override(state, ArenaCreatureCard.style(fill, PAPER if state == "focus" else Color(0, 0, 0, 0), Vector2(3, 3)))
	button.add_theme_constant_override("icon_max_width", 22)
	return button


func _layout_modal() -> void:
	if not _modal_panel: return
	if is_instance_valid(_guide_scroll): _guide_scroll.custom_minimum_size.y = minf(440, _hud.size.y - 220)
	_modal_panel.size = Vector2(_modal_panel.custom_minimum_size.x, 0)
	_modal_panel.position = (_hud.size - _modal_panel.size) / 2


func _open_modal(title: String, width := 360.0) -> void:
	battle.formation_motion.paused = true
	if battle.phase == ArenaMatch.Phase.DEPLOY: battle.world.process_mode = Node.PROCESS_MODE_DISABLED
	if not _modal_layer.visible:
		_menu_was_fighting = battle.phase == ArenaMatch.Phase.FIGHT
		if _menu_was_fighting: battle.toggle_pause()
		# Keep keyboard navigation inside the same modal as pointer input.
		_modal_focus.clear()
		for control: Control in _hud.find_children("*", "Control", true, false):
			if _modal_layer.is_ancestor_of(control) or control.focus_mode == Control.FOCUS_NONE: continue
			_modal_focus.append({"control": weakref(control), "mode": control.focus_mode})
			control.focus_mode = Control.FOCUS_NONE
	_guide_scroll = null
	_clear(_modal_box)
	_modal_layer.show()
	_modal_panel.custom_minimum_size = Vector2(width, 0)
	var row := HBoxContainer.new()
	_modal_box.add_child(row)
	var heading := _wrap(row, title, 28, GOLD)
	heading.add_theme_font_override("font", _heading_font)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_button(row, preload("res://assets/arena/close.svg"), _close_modal, RemakeText.t("Close"))
	_rule(_modal_box)
	_layout_modal.call_deferred()
	_tooltips.capture.call_deferred(_hud)
	_focus_modal.call_deferred()


func _focus_modal() -> void:
	if not _modal_layer.visible: return
	for control in _modal_box.find_children("*", "Button", true, false):
		if not control.disabled:
			control.grab_focus()
			return


func _close_modal() -> void:
	battle.formation_motion.paused = false
	if battle.phase == ArenaMatch.Phase.DEPLOY: battle.world.process_mode = Node.PROCESS_MODE_INHERIT
	_modal_layer.hide()
	for entry in _modal_focus:
		var control = entry.control.get_ref()
		if is_instance_valid(control): control.focus_mode = entry.mode
	_modal_focus.clear()
	if _menu_was_fighting and battle.phase == ArenaMatch.Phase.PAUSED: battle.toggle_pause()
	_menu_was_fighting = false
	_menu.grab_focus()


func _menu_action(id: int) -> void:
	if id == 0: _guide(); return
	_close_modal()
	match id:
		2: exit_requested.emit()
		3: run.arrange()
		4: run.undo()


func _show_menu() -> void:
	if _modal_layer.visible: _close_modal(); return
	_open_modal(RemakeText.t("Autochess") if run is ArenaTournamentRun else RemakeText.t("Trials of the Allods"))
	_menu_items.clear()
	_button(_modal_box, RemakeText.t("Return to battle" if run.stage == "fight" else "Continue"), _close_modal, "", true).grab_focus()
	for pair in [[3, "Auto arrange"], [4, "Undo"], [0, "Guide"]]:
		var id := int(pair[0])
		var button := _button(_modal_box, RemakeText.t(pair[1]), func(): _menu_action(id), "")
		if id == 3:
			button.disabled = landing or run.stage != "prepare"
			button.tooltip_text = RemakeText.t("Deploy your strongest creatures with ranged allies behind the front line.")
		elif id == 4:
			button.disabled = landing or not run.can_undo()
			button.tooltip_text = RemakeText.t("Undo a preparation action. Shop refreshes cannot be refunded.")
		elif id == 5:
			button.disabled = landing or run.stage != "prepare"
			button.tooltip_text = ""
		_menu_items[id] = button
	_rule(_modal_box)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	_modal_box.add_child(navigation)
	for pair in [[2, "Main menu"]]:
		var id := int(pair[0])
		_button(navigation, RemakeText.t(pair[1]), func(): _menu_action(id), "").size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _confirm_new_run() -> void:
	_open_modal(RemakeText.t("New game") if run is ArenaTournamentRun else RemakeText.t("New expedition"), 480)
	_wrap(_modal_box, RemakeText.t("Start a new game? This replaces your saved autochess game.") if run is ArenaTournamentRun else RemakeText.t("Start a new expedition? This replaces your current expedition."), 16)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_modal_box.add_child(actions)
	_button(actions, RemakeText.t("Cancel"), _close_modal, "").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, RemakeText.t("Start game") if run is ArenaTournamentRun else RemakeText.t("Begin expedition"), func(): _close_modal(); _begin(), "", true).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _world_hint(_control: Control) -> Dictionary:
	return {}


func _spell_titles(row: Dictionary) -> String:
	var names: Array[String] = []
	for spell: String in row.get("spells", []):
		var parsed := Spells.parse(spell)
		var value := RemakeText.t(Spells.title(parsed.code)) if parsed.has("code") else ""
		if not value.is_empty() and value not in names: names.append(value)
	return ", ".join(names)


func _update_sell_target() -> void:
	if not _sell_target: return
	var entry := run.unit(selected_uid)
	_sell_target.visible = not landing and run.stage == "prepare" and not entry.is_empty()
	if _sell_target.visible:
		_sell_target.text = RemakeText.t("Sell · +%d gold") % run.sale_value(entry)
		_sell_target.tooltip_text = ArenaRules.title(entry.prototype)
		if _tooltips: _tooltips.capture(_sell_target)


func _sell_selected() -> void:
	var error := run.sell(selected_uid)
	if error.is_empty(): _clear_selection()
	_feedback(error)


func _income_details(income: Dictionary) -> String:
	return RemakeText.t("Bounty %d · Victory %d · Interest %d · Streak %d") % [int(income.get("base", 0)), int(income.get("victory", 0)), int(income.get("interest", 0)), int(income.get("streak", 0))]


func _show_training() -> void:
	if landing or run.stage != "prepare": return
	var level := run.capacity()
	var error := run.train()
	_feedback(error)
	if error.is_empty() and run.capacity() == level and _sound:
		_sound.ui("buttons\\camp\\buy.wav")


func _fit_reserve_slots() -> void:
	if not _army_row or not _bench_scroll or _bench_scroll.size.x <= 0: return
	var buttons := _army_row.get_children()
	if buttons.is_empty(): return
	# Match the shop shelf; extra reserves scroll instead of shrinking the models.
	var count := maxi(1, run.shop.size())
	var width := maxf(96, floorf((_shop.size.x - 8 * (count - 1)) / count))
	var title := RemakeText.t("Return")
	for button: Button in buttons:
		var returning: bool = button.get_meta("return_slot", false)
		var text_width := button.get_theme_font("font").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 6
		button.text = title if returning and text_width <= width else ""
		button.icon = preload("res://assets/arena/return.svg") if returning and text_width > width else null
		button.add_theme_constant_override("icon_max_width", 22)
		button.custom_minimum_size.x = width


func _reroll() -> void:
	var error := run.refresh()
	_feedback(error)
	if error.is_empty() and _sound: _sound.ui("buttons\\camp\\buy.wav")


func _toggle_speed() -> void:
	GameData.arena_speed = 1 if GameData.arena_speed == 2 else 2
	GameData.save_settings()
	battle.set_speed(float(GameData.arena_speed))
	_update_speed()


func _update_speed() -> void:
	_speed.text = RemakeText.t("1×") if GameData.arena_speed == 1 else RemakeText.t("2×")
	_speed.tooltip_text = RemakeText.t("Battle speed") + "\n" + RemakeText.t("Click to switch between normal and double speed. This choice is remembered for all runs.")
	if _tooltips: _tooltips.capture(_speed)


func _setup_tournament_battles() -> void:
	if is_instance_valid(_tournament_battles):
		remove_child(_tournament_battles)
		_tournament_battles.queue_free()
	_tournament_battles = null
	if run is ArenaTournamentRun:
		_tournament_battles = ArenaTournamentBattles.new()
		_tournament_battles.run = run
		add_child(_tournament_battles)


func _switch_mode(index: int) -> void:
	if not landing or index == int(run is ArenaTournamentRun): return
	if run.changed.is_connected(_refresh): run.changed.disconnect(_refresh)
	run = ArenaRun.new() if index == 0 else ArenaTournamentRun.new()
	run.auto_save = false
	run.deployment_check = battle.recruitment_clear
	battle.run = run
	_setup_tournament_battles()
	_board_key = ""; battle._round_key = ""; _last_level = 0
	_result_key = -1; _result_remaining = 4.0
	_clear_selection()
	_saved = run.load_saved() and run.stage not in ["won", "lost"]
	if not _saved: run.begin(1)
	run.changed.connect(_refresh)
	GameData.arena_mode = index
	GameData.save_settings()
	_refresh()


func _build_standings() -> void:
	_clear(_standing_rows)
	_standings.visible = run is ArenaTournamentRun and not landing and not _outcome.visible
	if not _standings.visible: return
	var league := run as ArenaTournamentRun
	_label(_standing_rows, RemakeText.t("Players left: %d") % league.alive_players().size(), 16, GOLD)
	_label(_standing_rows, league.encounter_title(), 13, MUTED)
	var players := range(ArenaTournamentRun.PLAYER_COUNT)
	players.sort_custom(func(a,b):return league.health(a) > league.health(b) if league.health(a) != league.health(b) else a < b)
	for player: int in players:
		var text := "%s    %d" % [league.player_title(player), league.health(player)]
		if league.placements[player] > 0: text = "%s    #%d" % [league.player_title(player), league.placements[player]]
		var button := _button(_standing_rows, text, _show_player.bind(player), RemakeText.t("Inspect this player's army."))
		button.custom_minimum_size.y = 25
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color("344248"), Color(0,0,0,0), Vector2(4,2)))
		button.add_theme_stylebox_override("pressed", button.get_theme_stylebox("hover"))
		button.modulate.a = 1.0 if league.health(player) > 0 else 0.55


func _show_player(player: int) -> void:
	if not run is ArenaTournamentRun: return
	var league := run as ArenaTournamentRun
	var company := league.company(player)
	_open_modal(league.player_title(player), 580)
	_wrap(_modal_box, RemakeText.t("Health %d/100") % league.health(player) + " · " + RemakeText.t("Level %d") % company.capacity() + " · " + RemakeText.t("%d gold") % company.gold, 17, GOLD)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = minf(380, _hud.size.y - 240)
	_modal_box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for entry: Dictionary in company.army:
		if not entry.deployed: continue
		var figure := VBoxContainer.new()
		figure.custom_minimum_size.x = 164
		grid.add_child(figure)
		_creature_preview(figure, entry.prototype, 100)
		var stars := CenterContainer.new(); figure.add_child(stars)
		ArenaStars.add_to(stars, int(entry.rank) + 1, Vector2.ZERO)
		_wrap(figure, ArenaRules.title(entry.prototype), 14, PAPER)
	_button(_modal_box, RemakeText.t("Close"), _close_modal, "", true)
