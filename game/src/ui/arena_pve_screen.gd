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
var _quality: Button
var _reserve_count: Label
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
var _hover_wait := 0.0
var _hover_missing := 0.0
var _challenge: OptionButton


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
	_hud.add_child(_round_panel)
	_round_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_round_panel.offset_left = -276; _round_panel.offset_right = -116
	_round_panel.offset_top = 16; _round_panel.offset_bottom = 86
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
	_shop_section.add_child(_shop)
	var shop_tools := VBoxContainer.new()
	shop_tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shop_tools.add_theme_constant_override("separation", 6)
	recruitment.add_child(shop_tools)
	_refresh_button = _icon_button(shop_tools, preload("res://assets/arena/refresh.svg"), func(): _feedback(run.refresh()), RemakeText.t("Refresh offers. A locked recruit stays."))
	_refresh_button.custom_minimum_size = Vector2(76, 44)
	_quality = _button(shop_tools, "", _show_recruitment, RemakeText.t("Improve the shop"))
	_quality.custom_minimum_size = Vector2(76, 36)
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
	_bench_panel = _unframed(_hud)
	_bench_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bench_panel.offset_left = 24; _bench_panel.offset_right = -24
	_bench_panel.offset_top = -104; _bench_panel.offset_bottom = -20
	_bench_bar = HBoxContainer.new()
	_bench_bar.add_theme_constant_override("separation", 20)
	_bench_panel.add_child(_bench_bar)
	var company_status := VBoxContainer.new()
	company_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	company_status.add_theme_constant_override("separation", 3)
	_bench_bar.add_child(company_status)
	_army_title = _button(company_status, "", _show_training, "")
	_army_title.set_meta("arena_company", true)
	_army_title.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_army_title.add_theme_font_size_override("font_size", 16)
	_army_title.icon = preload("res://assets/arena/company.svg")
	_army_title.add_theme_constant_override("icon_max_width", 18)
	_army_title.custom_minimum_size.x = 90
	_army_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reserve_count = _label(company_status, "", 13, MUTED)
	_reserve_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	_speed = OptionButton.new()
	for value in ["1×", "2×"]: _speed.add_item(value)
	_speed.custom_minimum_size = Vector2(74, 44)
	_speed.tooltip_text = RemakeText.t("Battle speed")
	_speed.item_selected.connect(func(i): battle.set_speed(1.0 if i == 0 else 2.0))
	time_bar.add_child(_speed)
	_sell_target = _button(_hud, "", _sell_selected, "", true)
	_sell_target.name = "SellTarget"
	_sell_target.icon = preload("res://assets/arena/sell.svg")
	_sell_target.add_theme_constant_override("icon_max_width", 20)
	_sell_target.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_sell_target.offset_left = -218; _sell_target.offset_right = -24
	_sell_target.offset_top = -162; _sell_target.offset_bottom = -114
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
	if _sound: _sound.on_world(null)
	Gfx.set_border(_previous_border, _previous_border_dist)


func _refresh() -> void:
	_header.visible = landing
	_gold.text = str(run.gold)
	_lives.text = "%d/3" % run.lives
	var income := run.income_preview(run.battle_savings if run.stage == "fight" else -1)
	_income.text = RemakeText.t("Income +%d") % int(income.total)
	_income.visible = run.wave < run.wave_limit
	_gold.get_parent().tooltip_text = _income_details(income) + "\n" + RemakeText.t("Savings earn 1 gold per 10, up to 3. Win three battles in a row for +1 gold, or six for +2. Defeat breaks the streak.")
	_wave_title.text = RemakeText.t("Wave %d/%d") % [run.wave, run.wave_limit]
	_round_panel.tooltip_text = RemakeText.t("Wave %d/%d · %s") % [run.wave, run.wave_limit, RemakeText.t(ArenaRules.WAVES[run.wave - 1][0])] + "\n" + ArenaRules.region_name(ArenaRules.region(run.wave)) + " · " + RemakeText.t("Seed %s") % str(run.run_seed)
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
	_outcome_shade.visible = _dock.visible
	_layout_outcome()
	_pause.visible = fighting
	_speed.visible = fighting
	_rail.visible = not landing and _inspector.visible
	_landing_layer.visible = landing
	_clock.visible = fighting
	field.show_markers = preparing or fighting or battle.settle_remaining > 0
	_message.visible = preparing or fighting or run.save_error
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
		elif run.stage in ["result", "won", "lost"] and battle.settle_remaining <= 0: _build_result()
	_start.disabled = run.deployed_count() == 0
	_quality.text = RemakeText.t("Shop %d") % (run.shop_level + 1)
	_reserve_count.text = RemakeText.t("Reserves %d/%d") % [run.bench_count(), run.bench_limit()]
	_refresh_button.text = str(run.refresh_cost())
	_refresh_button.tooltip_text = RemakeText.t("Refresh · %d gold") % run.refresh_cost() + "\n" + RemakeText.t("Refresh offers. A locked recruit stays.")
	var refresh_error := run.spending_error(run.refresh_cost())
	_refresh_button.disabled = not refresh_error.is_empty()
	if not refresh_error.is_empty(): _refresh_button.tooltip_text += "\n" + refresh_error
	_army_title.text = RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()]
	_army_title.tooltip_text = ""
	_army_title.remove_meta("arena_help")
	_army_title.add_theme_color_override("icon_normal_color", GOLD if run.pact_active() else MUTED)
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
	if run.save_error: _feedback(RemakeText.t("The expedition could not be saved. Check free disk space before leaving."))


func _build_army() -> void:
	_clear(_army_row)
	var benched := run.army.filter(func(u): return not u.deployed)
	var slot_width := clampf((_hud.size.x - 550.0) / maxi(run.bench_limit(), benched.size()) - 8.0, 44, 88)
	for i in maxi(run.bench_limit(), benched.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(slot_width, 84)
		button.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0,0,0,0), Color(0,0,0,0), Vector2(3,3)))
		button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color(0.12, 0.16, 0.17, 0.45), Color(0, 0, 0, 0), Vector2(3,3)))
		button.add_theme_stylebox_override("focus", ArenaCreatureCard.style(Color(0, 0, 0, 0), PAPER, Vector2(3,3)))
		button.add_theme_stylebox_override("disabled", ArenaCreatureCard.style(Color(0,0,0,0), Color(0,0,0,0), Vector2(3,3)))
		button.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("344248"), GOLD, Vector2(3,3)))
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
			var selected := run.unit(selected_uid)
			var returning: bool = run.stage == "prepare" and not selected.is_empty() and selected.deployed
			button.disabled = not returning
			button.tooltip_text = RemakeText.t("Return the selected creature to reserves.") if returning else RemakeText.t("Recruits wait here until you deploy them.")
			if returning:
				button.pressed.connect(func(): _return_to_reserves())
				marker.color = GOLD
				if i == benched.size():
					button.text = RemakeText.t("Return")
					button.add_theme_font_size_override("font_size", 13)
			continue
		var entry: Dictionary = benched[i]
		button.set_meta("arena_creature", {"id": entry.prototype, "uid": int(entry.uid)})
		button.pressed.connect(func(): _select(entry.uid))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = landing or run.stage not in ["prepare", "fight"]
		var preview := WikiPreview.new()
		preview.fit_slot = true
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_top = 14; preview.offset_bottom = -6
		button.add_child(preview)
		preview.show_model({"kind": "creature", "value": entry.prototype})
		preview.turn_by(-0.35)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ArenaStars.add_to(button, int(entry.rank) + 1, Vector2(5, 1))
		if int(entry.uid) == selected_uid:
			marker.color = GOLD
			marker.offset_top = -4
	_fit_reserve_slots.call_deferred()
	if _tooltips: _tooltips.capture(_army_row)


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
		var rank := int(offer.get("rank", 0))
		var card := ArenaCreatureCard.new()
		card.prototype = rule.forms[rank]
		card.quality = rank
		var count := run.army.filter(func(entry): return entry.family == family and entry.rank == rank).size()
		card.caption = RemakeText.t("%s · %d owned") % [RemakeText.t(rule.role), count]
		card.caption = RemakeText.t(rule.name) + "\n" + card.caption
		if not run.pact.is_empty() and family in ArenaRules.PACTS[run.pact].families:
			card.caption += "\n" + RemakeText.t("Your pact needs a two-star recruit from this family." if int(ArenaRules.PACTS[run.pact].min_rank) > 0 else "This family belongs to your pact.")
		var needed := ArenaRules.evolution_copies(family, rank)
		card.footer = RemakeText.t("%d gold") % run.offer_cost(offer)
		if needed > 0: card.footer += "\n" + RemakeText.t("Copies: %d/%d") % [mini(needed, count), needed]
		card.set_meta("arena_creature", {"id": card.prototype, "family": family, "rank": rank, "offer": index})
		card.cost = run.offer_cost(offer)
		card.copies = count
		card.copies_needed = needed
		card.disabled = not run.purchase_error(index).is_empty()
		card.pressed.connect(func(): _recruit_offer(index))
		box.add_child(card)
		card.tooltip_text = ""
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var lock := _icon_button(box, preload("res://assets/arena/lock.svg"), func(): pass, RemakeText.t("Lock recruit"))
		lock.toggle_mode = true
		lock.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("464f34"), GOLD, Vector2(3, 3)))
		lock.custom_minimum_size = Vector2(28, 28)
		lock.add_theme_constant_override("icon_max_width", 16)
		lock.tooltip_text = RemakeText.t("Lock recruit")
		lock.button_pressed = offer.locked
		lock.toggled.connect(func(_on): run.lock_offer(index))
		lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -30; lock.offset_right = -2
		lock.offset_top = 0; lock.offset_bottom = 28
		lock.modulate.a = 1 if offer.locked else 0.65


func _build_landing() -> void:
	_clear(_landing_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.055, 0.075, 0.052, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing_layer.add_child(shade)
	_landing_panel = ArenaHudPanel.new()
	_landing_panel.surface.a = 0.98
	_landing_panel.custom_minimum_size.x = 560
	_landing_panel.minimum_size_changed.connect(_layout_landing.call_deferred)
	_landing_layer.add_child(_landing_panel)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 18)
	_landing_panel.add_child(choices)
	var title := _wrap(choices, RemakeText.t("Build your company"), 38, PAPER)
	title.add_theme_font_override("font", _heading_font)
	_wrap(choices, RemakeText.t("Build a company from three allods. Survive thirty battles."), 17, MUTED)
	_wrap(choices, RemakeText.t("Starting gold: %d") % ArenaRules.OPENING_GOLD, 22, GOLD)
	_wrap(choices, RemakeText.t("Buy your first creatures from the shop and place them on the battlefield."), 16, PAPER)
	if _saved:
		_button(choices, RemakeText.t("Continue · wave %d") % run.wave, func():
			landing = false; run.auto_save = true; _refresh(), RemakeText.t("Resume your saved expedition with the same army and shop."), true)
	_rule(choices)
	_challenge = OptionButton.new()
	var maximum := int(ArenaRun.profile().get("challenge", 0))
	for text: String in ["Standard expedition", "Veteran expedition", "Champion expedition"]:
		_challenge.add_item(RemakeText.t(text))
	for i in 3: _challenge.set_item_disabled(i, i > maximum)
	_challenge.custom_minimum_size.y = 40
	_challenge.tooltip_text = RemakeText.t("Win an expedition to unlock the next difficulty.")
	choices.add_child(_challenge)
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = RemakeText.t("Random seed")
	_seed_input.tooltip_text = RemakeText.t("Optional: enter a whole number to replay the same shops and encounters.")
	_seed_input.custom_minimum_size.y = 38
	choices.add_child(_seed_input)
	_landing_start = _button(choices, RemakeText.t("Begin expedition"), func():
		if not _seed_input.text.strip_edges().is_empty() and not _seed_input.text.strip_edges().is_valid_int():
			_feedback(RemakeText.t("Enter a whole number for the seed."))
		elif _saved: _confirm_new_run()
		else: _begin(), "", true)
	_landing_start.custom_minimum_size.y = 52
	_landing_start.add_theme_font_size_override("font_size", 20)
	_layout_landing.call_deferred()


func _layout_landing() -> void:
	if not is_instance_valid(_landing_panel): return
	_landing_panel.size = Vector2(560, 0)
	_landing_panel.position = (_landing_layer.size - _landing_panel.size) / 2


func _begin() -> void:
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
	run.begin(chosen, 0, challenge_index)
	_hint("")


func _build_result() -> void:
	var result: Dictionary = run.last_result
	var won := int(result.get("winner", -1)) == 0
	var text := "Expedition complete" if run.stage == "won" else "The expedition ends" if run.stage == "lost" else "Victory" if won else "Defeat"
	var title := _wrap(_dock, RemakeText.t(text), 42, GOLD if won else PAPER)
	title.add_theme_font_override("font", _heading_font)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var encounter := _wrap(_dock, RemakeText.t("Wave %d/%d · %s") % [run.wave, run.wave_limit, RemakeText.t(ArenaRules.WAVES[run.wave - 1][0])], 16, MUTED)
	encounter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule(_dock)
	var reward := HBoxContainer.new()
	reward.alignment = BoxContainer.ALIGNMENT_CENTER
	reward.add_theme_constant_override("separation", 12)
	_dock.add_child(reward)
	_icon(reward, preload("res://assets/arena/coin.svg") if won else preload("res://assets/arena/life.svg"))
	_label(reward, RemakeText.t("+%d gold") % int(result.get("gold", 0)) if won and run.stage != "won" else RemakeText.t("Lives %d/%d") % [run.lives, 3], 20, GOLD if won else PAPER)
	if result.has("income"):
		var breakdown := _wrap(_dock, _income_details(result.income), 14, MUTED)
		breakdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var details := _wrap(_dock, RemakeText.t("Battle: %d seconds · Damage dealt: %d · Damage taken: %d") % [int(result.get("seconds", 0)), int(result.get("damage", [0, 0])[0]), int(result.get("damage", [0, 0])[1])], 14, MUTED)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if run.stage == "lost": pass
	elif not won: _wrap(_dock, RemakeText.t("Your company has recovered. Regroup and face this wave again."), 16)
	if run.stage == "won": _wrap(_dock, RemakeText.t("The ruins are yours.") if run.challenge == 2 else RemakeText.t("A harder expedition awaits."), 16)
	if won and run.wave < run.wave_limit:
		var arriving: Array[String] = []
		for family: Dictionary in ArenaRules.FAMILIES:
			if int(family.get("unlock", 1)) == run.wave + 1: arriving.append(RemakeText.t(family.name))
		if not arriving.is_empty():
			_wrap(_dock, RemakeText.t("New recruits: %s") % ", ".join(arriving), 16, GOLD)
	var action: Button
	if run.stage in ["won", "lost"]:
		action = _button(_dock, RemakeText.t("New expedition"), func(): landing = true; _saved = false; _clear_selection(); _refresh(), "", true)
	else:
		action = _button(_dock, RemakeText.t("Visit camp" if won and run.wave % 3 == 0 else "Next wave" if won else "Prepare again"), func(): run.advance(), "", true)
	action.name = "ContinueResult"
	action.custom_minimum_size.y = 48
	action.add_theme_font_override("font", _heading_font)
	action.add_theme_font_size_override("font_size", 23)
	action.grab_focus()


func _build_rewards() -> void:
	var choosing_pact := String(run.rewards[0].kind) == "pact"
	var heading := _label(_dock, RemakeText.t("Choose your pact" if choosing_pact else "A moment at camp"), 28, GOLD)
	heading.add_theme_font_override("font", _heading_font)
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
		elif reward.kind == "pact_upgrade": id = run.pact_prototype(run.pact_rank + 1)
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
		var action := _button(box, RemakeText.t("Choose pact" if choosing_pact else "Choose reward"), func(): _choose_reward(index), help, true)
		action.name = "ChooseReward"
		if not id.is_empty():
			action.tooltip_text += "\n\n" + ArenaUnitInfo.summary(id)
		if reward.kind == "pact":
			action.tooltip_text += "\n" + RemakeText.t("Your pact ally needs no army slot. It leaves when the pact is inactive.")
		elif reward.kind == "companion" and run.bench_count() > run.bench_limit():
			action.disabled = true
			action.tooltip_text = RemakeText.t("Your reserves already hold an extra ally. Choose another reward.")


func _pact_status() -> String:
	return RemakeText.t("Pact active · one extra ally") if run.pact_active() else RemakeText.t("Pact inactive · %d/%d families") % [run.pact_families().size(), int(ArenaRules.PACTS[run.pact].needed)]


func _show_company() -> void:
	if landing or run.stage not in ["prepare", "fight"]: return
	_showing_company = true
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	var heading := HBoxContainer.new()
	_inspect_box.add_child(heading)
	var title := _wrap(heading, RemakeText.t("Company"), 23, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", _heading_font)

	_wrap(_inspect_box, RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()], 18, PAPER)
	_wrap(_inspect_box, RemakeText.t("Experience %d/%d") % [run.experience(), ArenaRules.MAX_TRAINING], 14, GOLD)
	if run.experience() < ArenaRules.MAX_TRAINING:
		_wrap(_inspect_box, RemakeText.t("Click the army counter to train your company."), 14, MUTED)
	if run.pact.is_empty():
		_wrap(_inspect_box, RemakeText.t("Choose a pact at your next camp."), 15, MUTED)
	else:
		var rule: Dictionary = ArenaRules.PACTS[run.pact]
		_wrap(_inspect_box, RemakeText.t(rule.name), 20, PAPER)
		_wrap(_inspect_box, _pact_status(), 14, GOLD)
		_wrap(_inspect_box, RemakeText.t(rule.help), 14, MUTED)
		var present := run.pact_families()
		for family: int in rule.families:
			if int(ArenaRules.FAMILIES[family].get("unlock", 1)) > run.wave: continue
			var state := RemakeText.t("Ready") if family in present else RemakeText.t("Not contributing")
			_wrap(_inspect_box, "%s · %s" % [RemakeText.t(ArenaRules.FAMILIES[family].name), state], 13, PAPER if family in present else MUTED)
		_creature_preview(_inspect_box, run.pact_prototype(), 90)
		_wrap(_inspect_box, ArenaRules.title(run.pact_prototype()), 17, GOLD)
		_wrap(_inspect_box, RemakeText.t("Your pact ally needs no army slot. It leaves when the pact is inactive."), 13, MUTED)
		if run.pact_rank < 2:
			_wrap(_inspect_box, RemakeText.t("Strengthen your pact at camp. As new allods join the hunt, a stronger ally answers its call."), 13, MUTED)
	if not run.boons.is_empty():
		_rule(_inspect_box)
		_label(_inspect_box, RemakeText.t("Expedition upgrades"), 17, GOLD)
		for boon: String in run.boons:
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][0]), 15, PAPER)
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][1]), 13, MUTED)

	_tooltips.capture(_hud)


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
		_wrap(_inspect_box, "%s · %s" % [RemakeText.t(ArenaRules.FAMILIES[family].name), RemakeText.t(ArenaRules.FAMILIES[family].role)], 13, MUTED)
		_wrap(_inspect_box, ArenaRules.region_name(int(ArenaRules.FAMILIES[family].get("region", 0))), 13, MUTED)
	if rank >= 0:
		var stars := Control.new()
		stars.custom_minimum_size.y = 12
		_inspect_box.add_child(stars)
		ArenaStars.add_to(stars, rank + 1, Vector2.ZERO)
	_creature_preview(_inspect_box, id, 64)
	_live_health = _wrap(_inspect_box, ArenaUnitInfo.summary(id, _inspected_unit), 15)
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
		entry = run.unit(int(unit.get_meta("arena_placement", {}).get("run_uid", 0)))
		if unit.get_meta("arena_placement", {}).has("pact"): entry = {"rank": run.pact_rank}
		key = "world:%d" % unit.get_instance_id()
	else:
		while control and control != _hud:
			if control.has_meta("arena_creature"):
				entry = control.get_meta("arena_creature")
				id = entry.id
				if entry.has("uid"): entry = run.unit(int(entry.uid))
				key = "preview:" + id + ":" + str(entry.get("uid", entry.get("offer", -1)))
				break
			if control.has_meta("arena_company"):
				key = "company"
				break
			control = control.get_parent() as Control
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
		if key == "company": _show_company()
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
	if _inspector: _inspector.hide()
	if _rail: _rail.hide()
	_update_sell_target()


func _battle_changed() -> void:
	if _pause:
		_pause.icon = preload("res://assets/arena/play.svg") if battle.phase == ArenaMatch.Phase.PAUSED else preload("res://assets/arena/pause.svg")
		_pause.tooltip_text = RemakeText.t("Resume" if battle.phase == ArenaMatch.Phase.PAUSED else "Pause") + " · " + RemakeText.t("Space")
		if _tooltips: _tooltips.capture(_pause)
	if _phase:
		_phase.text = RemakeText.t("Preparing") if run.stage == "prepare" else RemakeText.t("Paused") if battle.phase == ArenaMatch.Phase.PAUSED else RemakeText.t("Battle") if run.stage == "fight" else RemakeText.t("Victory" if battle.winner == 0 else "Defeat") if battle.settle_remaining > 0 else ""
	if _sound: _sound.music.tick(2 if battle.phase == ArenaMatch.Phase.FIGHT else 0)


func _process(dt: float) -> void:
	_hover_inspector(dt)
	if is_instance_valid(_live_health) and is_instance_valid(_inspected_unit) and _rail.visible:
		var unit := _inspected_unit
		_live_health.text = ArenaUnitInfo.summary(_inspected, unit)
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
		if event.keycode == KEY_SPACE and run.stage == "fight" and not _modal_layer.visible:
			battle.toggle_pause(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _modal_layer.visible: _close_modal()
			elif selected_uid > 0 or _inspector.visible: _clear_selection()
			else: _show_menu()
			get_viewport().set_input_as_handled()


func _guide() -> void:
	_open_modal(RemakeText.t("Expedition guide"), 640)
	_guide_scroll = ScrollContainer.new()
	_guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_guide_scroll.custom_minimum_size.y = minf(440, _hud.size.y - 220)
	_modal_box.add_child(_guide_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_guide_scroll.add_child(content)
	var topics := [
		["Economy", "Each victory pays a bounty, plus interest on savings and a winning-streak bonus. Bounties rise as stronger recruits arrive. Failed attempts grant no income."],
		["Recruitment", "Recruits join your reserves. Improve the shop to find two- and three-star creatures."],
		["Evolution", "Collect matching creatures to evolve them. Stars mark each stronger form. The creature details show how many you need."],
		["Your army", "Select a creature, then its place on the field. Select a reserve, then an ally to swap them. An empty reserve slot withdraws a creature. Select a creature to reveal the sell area."],
		["Battle", "Both teams fight under AI control. Hover a creature for details. Space pauses combat; the speed control switches between normal and double speed."],
		["Company", "Visit camp every three victories. Choose a pact, a new ally or supplies. Win all thirty waves to unlock harder expeditions."]]
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
	var uid := run.next_uid
	var before := run.army.duplicate(true)
	var error := run.buy(index)
	_feedback(error)
	if error.is_empty():
		if not run.last_evolutions.is_empty():
			_clear_selection()
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
		elif not run.unit(uid).is_empty(): _select(uid)


func _choose_reward(index: int) -> void:
	var previous := run.pact_prototype()
	var rank := run.pact_rank
	var error := run.choose_reward(index)
	_feedback(error)
	if error.is_empty() and not previous.is_empty() and previous != run.pact_prototype():
		_evolution_notice.present([{"uid": 0, "from": previous, "to": run.pact_prototype(), "old_rank": rank, "rank": run.pact_rank}])


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


func _layout_outcome() -> void:
	if not _outcome or not _hud: return
	var width := minf(900 if run.stage == "reward" else 520, _hud.size.x - 48)
	_outcome.custom_minimum_size.x = width
	_outcome.size = Vector2(width, 0)
	_outcome.position = (_hud.size - _outcome.size) / 2


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
		1: sandbox_requested.emit()
		2: exit_requested.emit()
		3: run.arrange()
		4: run.undo()
		5: _show_training()


func _show_menu() -> void:
	if _modal_layer.visible: _close_modal(); return
	_open_modal(RemakeText.t("Trials of the Allods"))
	_menu_items.clear()
	_button(_modal_box, RemakeText.t("Return to battle" if run.stage == "fight" else "Continue"), _close_modal, "", true).grab_focus()
	for pair in [[5, "Train your company"], [3, "Auto arrange"], [4, "Undo"], [0, "Guide"]]:
		var id := int(pair[0])
		var button := _button(_modal_box, RemakeText.t(pair[1]), func(): _menu_action(id), "")
		if id == 3:
			button.disabled = landing or run.stage != "prepare"
			button.tooltip_text = RemakeText.t("Deploy your strongest forms with ranged creatures behind the front line. Keep your pact active when your army can meet its condition.")
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
	for pair in [[1, "Sandbox"], [2, "Main menu"]]:
		var id := int(pair[0])
		_button(navigation, RemakeText.t(pair[1]), func(): _menu_action(id), "").size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _show_recruitment() -> void:
	_open_modal(RemakeText.t("Improve recruitment"), 500)
	_wrap(_modal_box, RemakeText.t("Better recruits, more often. Improving the shop also replaces its unlocked offers."), 16, PAPER)
	for level in 3:
		var words := ["1 star: 100%", "1 star: 70% · 2 stars: 30%", "1 star: 45% · 2 stars: 45% · 3 stars: 10%"]
		_wrap(_modal_box, RemakeText.t("Shop %d") % (level + 1) + "  ·  " + RemakeText.t(words[level]), 16, GOLD if level == run.shop_level else MUTED)
	_wrap(_modal_box, RemakeText.t("Stars show evolution within a family. Some families have two forms. Later recruits are stronger and cost more."), 14, MUTED)
	_rule(_modal_box)
	for milestone in [10, 13, 19]:
		var names: Array[String] = []
		for family: Dictionary in ArenaRules.FAMILIES:
			if int(family.get("unlock", 1)) == milestone: names.append(RemakeText.t(family.name))
		_wrap(_modal_box, RemakeText.t("Wave %d · %s") % [milestone, ", ".join(names)], 14, GOLD if run.wave >= milestone else MUTED)
	if run.shop_level < 2:
		var action := _button(_modal_box, RemakeText.t("Upgrade · %d gold") % run.shop_upgrade_cost(), func():
			var error := run.upgrade_shop()
			if error.is_empty(): _close_modal()
			_feedback(error), RemakeText.t("Includes a refresh. Cannot be undone."), true)
		action.name = "UpgradeRecruitment"
		var error := run.spending_error(run.shop_upgrade_cost())
		action.disabled = not error.is_empty()
		if action.disabled: _wrap(_modal_box, error, 15, MUTED)
	else:
		_label(_modal_box, RemakeText.t("Recruitment is fully upgraded."), 16, GOLD)


func _confirm_new_run() -> void:
	_open_modal(RemakeText.t("New expedition"), 480)
	_wrap(_modal_box, RemakeText.t("Start a new expedition? This replaces your current expedition."), 16)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_modal_box.add_child(actions)
	_button(actions, RemakeText.t("Cancel"), _close_modal, "").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, RemakeText.t("Begin expedition"), func(): _close_modal(); _begin(), "", true).size_flags_horizontal = Control.SIZE_EXPAND_FILL


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
	_hide_inspector()
	_open_modal(RemakeText.t("Train your company"), 500)
	_wrap(_modal_box, RemakeText.t("Army capacity: %d") % run.capacity(), 22, GOLD)
	_wrap(_modal_box, RemakeText.t("Experience %d/%d") % [run.experience(), ArenaRules.MAX_TRAINING], 16)
	_wrap(_modal_box, RemakeText.t("Each cleared wave grants 1 experience. Every 3 experience adds an army slot, up to 9."), 16, MUTED)
	if run.experience() < ArenaRules.MAX_TRAINING:
		_wrap(_modal_box, RemakeText.t("Train now to field one more creature in the next battle."), 16)
		var train := _button(_modal_box, RemakeText.t("Train · %d gold") % ArenaRules.TRAINING_COST, func():
			var error := run.train()
			if error.is_empty(): _close_modal()
			_feedback(error), "", true)
		train.name = "TrainArmy"
		var error := run.spending_error(ArenaRules.TRAINING_COST)
		train.disabled = not error.is_empty()
		if train.disabled: _wrap(_modal_box, error, 15, MUTED)
	else:
		_wrap(_modal_box, RemakeText.t("Your army is at full strength."), 16, GOLD)


func _fit_reserve_slots() -> void:
	if not _army_row or not _bench_scroll or _bench_scroll.size.x <= 0: return
	var buttons := _army_row.get_children()
	if buttons.is_empty(): return
	var widths: Array[float] = []
	var minimum := 0.0
	for button: Button in buttons:
		var width := ceilf(maxf(40, button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + 6))
		widths.append(width)
		minimum += width
	# Containers round each child's size up. Allocate whole pixels so nine
	# fractional widths do not add a scrollbar to an otherwise fitting row.
	var extra := floorf(maxf(0, (_bench_scroll.size.x - 8 * (buttons.size() - 1) - minimum) / buttons.size()))
	for i in buttons.size(): buttons[i].custom_minimum_size.x = minf(88, widths[i] + extra)
