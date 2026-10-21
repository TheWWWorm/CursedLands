class_name ArenaPveScreen
extends Control
## The expedition owns preparation; the battle remains fully AI controlled.

signal exit_requested

const GOLD := ArenaCreatureCard.GOLD
const PAPER := ArenaCreatureCard.PAPER
const MUTED := ArenaCreatureCard.MUTED
var run := ArenaRun.new()
var network_play := false
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
var _wiki: WikiPanel
var _modal_panel: ArenaHudPanel
var _modal_box: VBoxContainer
var _menu_items := {}
var _menu_was_fighting := false
var _modal_focus: Array[Dictionary] = []
var _guide_scroll: ScrollContainer
var _reserve_count: Label
var _alliance_list: GridContainer
var _battle_sidebar: PanelContainer
var _sidebar_content: VBoxContainer
var _damage_panel: ArenaDamagePanel
var _damage_wait := 0.0
var _round_banner: ArenaRoundBanner
var _result_volley: ArenaResultVolley
var _health_seen := {}
var _health_session := ""
var _name_flashes := {}
const STANDING_WIN := Color("24612f")
const STANDING_LOSS := Color("9e2832")
var _eliminated_seen := {}
var _elimination_queue: Array[String] = []
var _elimination_notice: Label
var _elimination_left := 0.0
var _alliance_panel: PanelContainer
var _train_button: ArenaRoundButton
var _last_level := 0
var _level_sound: AudioStreamPlayer
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
var _inspect_scroll: ScrollContainer
var _message: Label
var _start: Button
var _pause: Button
var _refresh_button: ArenaRoundButton
var _speed: Button
var _shop_toggle: Button
var _shop_open := true
var _shown_stage := ""
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
var _standing_scroll: ScrollContainer
var _tournament_battles: ArenaTournamentBattles
var _standings_expanded := false
var _league_paused := false
var _scout_bar: PanelContainer
var _overview_bar: HBoxContainer
var _vignette: ColorRect
var _scout_name: Label
var _scout_details: Label
var _scout_return: Button
var _opponent: Label
var _encounter_key := 0
var _clock_pulse := 0.0
var _clock_urgency := -1
var _camera_keys := {}
var _cursor: GameCursor


func _ready() -> void:
	add_child(ArenaAnimationWarmup.new())
	oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	_cursor=GameCursor.new();_cursor.control_shapes=[Input.CURSOR_ARROW,Input.CURSOR_POINTING_HAND]
	add_child(_cursor);_cursor.set_kind("cursor_default")
	name = "ArenaExpedition"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_previous_border = Gfx._border_size
	_previous_border_dist = Gfx._border_menu
	theme = Theme.new()
	theme.default_font_size = 16
	theme.default_font = preload("res://fonts/LiberationSans-Regular.ttf").duplicate()
	_heading_font = preload("res://fonts/LiberationSerif-Regular.ttf").duplicate()
	# A single distance-field atlas keeps glyphs stable when the logical
	# canvas has a fractional scale and new modal text populates the cache.
	# Private resources leave the original pixel-sized interface unchanged.
	theme.default_font.multichannel_signed_distance_field = true
	_heading_font.multichannel_signed_distance_field = true
	theme.set_color("font_color", "Label", PAPER)
	for kind in ["Button", "OptionButton", "LineEdit"]:
		theme.set_color("font_color", kind, PAPER)
		theme.set_color("font_disabled_color", kind, Color("858b80"))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("9c8a60")
		thumb.content_margin_left = 3; thumb.content_margin_right = 3
		theme.set_stylebox(state, "VScrollBar", thumb)
	if not network_play and GameData.arena_mode == 1: run = ArenaTournamentRun.new()
	battle = _create_battle()
	battle.run = run
	add_child(battle)
	battle.set_speed(float(GameData.arena_speed))
	run.deployment_check = battle.recruitment_clear
	field = ArenaPveField.new()
	field.match_state = battle
	add_child(field)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle._world_parent = field.stage
	_setup_tournament_battles()
	field.ground_clicked.connect(_place)
	field.creature_clicked.connect(_select_world)
	field.cancel_requested.connect(_clear_selection)
	field.board_chosen.connect(_show_player)
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = ShaderMaterial.new()
	_vignette.material.shader = preload("res://src/ui/arena_vignette.gdshader")
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_numbers = ArenaHitNumbers.new()
	_hit_numbers.field = field
	add_child(_hit_numbers)
	_hit_numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle.visual_event.connect(func(event):
		if field.match_state == battle and event.get("t") == "hitnum": _hit_numbers.add(event))
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
	_opponent = _label(_round_badge, "", 14, GOLD)
	_opponent.custom_minimum_size.x = 150
	_opponent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu = _button(_hud, RemakeText.t("Menu"), _show_menu, "")
	_menu.custom_minimum_size = Vector2(88, 44)
	_menu.add_theme_font_override("font", _heading_font)
	_menu.add_theme_font_size_override("font_size", 20)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu.offset_left = -104; _menu.offset_right = -16
	_menu.offset_top = 16; _menu.offset_bottom = 60
	_shop_toggle = _button(_hud, RemakeText.t("Shop"), _toggle_shop, "")
	_shop_toggle.name = "ToggleShop"
	_shop_toggle.toggle_mode = true
	_shop_toggle.custom_minimum_size = Vector2(88, 40)
	_shop_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_shop_toggle.offset_left = -104; _shop_toggle.offset_right = -16
	_shop_toggle.offset_top = 68; _shop_toggle.offset_bottom = 108
	_shop_panel = _unframed(_hud)
	_shop_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_shop_panel.offset_left = 24; _shop_panel.offset_top = 12
	_shop_panel.offset_bottom = 138
	_shop_panel.resized.connect(_layout_battle_sidebar.call_deferred)
	_shop_panel.visibility_changed.connect(_layout_battle_sidebar.call_deferred)

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
	_train_button = ArenaRoundButton.new()
	_train_button.name = "UpgradeCompany"
	_train_button.set_meta("arena_company", true)
	_train_button.pressed.connect(_show_training)
	shop_tools.add_child(_train_button)
	_rail = ArenaHudPanel.new()
	_rail.z_index = 2
	_rail.custom_minimum_size.x = 320
	_hud.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_rail.offset_left = -336; _rail.offset_right = -16
	_rail.offset_top = 174; _rail.offset_bottom = 294
	_rail_box = VBoxContainer.new()
	_rail_box.add_theme_constant_override("separation", 6)
	_rail.add_child(_rail_box)
	_inspector = _unframed(_rail_box)
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspect_scroll = ScrollContainer.new()
	_inspect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.add_child(_inspect_scroll)
	_inspect_box = VBoxContainer.new()
	_inspect_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect_box.add_theme_constant_override("separation", 4)
	_inspect_box.minimum_size_changed.connect(_layout_inspector.call_deferred)
	_inspect_scroll.add_child(_inspect_box)
	_inspect_actions = VBoxContainer.new()
	_inspect_actions.add_theme_constant_override("separation", 6)
	_rail_box.add_child(_inspect_actions)
	_inspect_actions.hide()
	_inspector.hide()
	_standings = PanelContainer.new()
	_standings.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud.add_child(_standings)
	_standings.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_standings.offset_left = -180; _standings.offset_right = -16
	_standings.offset_top = 124
	_standing_rows = VBoxContainer.new()
	_standing_rows.add_theme_constant_override("separation", 2)
	_standing_scroll = ScrollContainer.new()
	_standing_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_standing_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_standing_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_standings.add_child(_standing_scroll)
	_standing_scroll.add_child(_standing_rows)
	_bench_panel = _unframed(_hud)
	_bench_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bench_panel.offset_left = 24; _bench_panel.offset_right = -24
	_bench_panel.offset_top = -188; _bench_panel.offset_bottom = -14
	_bench_bar = HBoxContainer.new()
	_bench_bar.add_theme_constant_override("separation", 20)
	var bench_column := VBoxContainer.new()
	bench_column.add_theme_constant_override("separation", 4)
	_bench_panel.add_child(bench_column)
	bench_column.add_child(_bench_bar)
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
	ArenaCreatureCard.snow_ink(_army_title, PAPER)
	_reserve_count = _label(company_status, "", 13, MUTED)
	_reserve_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_sidebar = PanelContainer.new()
	_battle_sidebar.position=Vector2(16,182)
	_battle_sidebar.custom_minimum_size.x=262
	var sidebar_spacing := StyleBoxEmpty.new()
	sidebar_spacing.content_margin_left=12; sidebar_spacing.content_margin_right=12
	sidebar_spacing.content_margin_top=10; sidebar_spacing.content_margin_bottom=10
	_battle_sidebar.add_theme_stylebox_override("panel",sidebar_spacing)
	_hud.add_child(_battle_sidebar)
	_sidebar_content=VBoxContainer.new(); _sidebar_content.add_theme_constant_override("separation",12)
	_battle_sidebar.add_child(_sidebar_content)
	_damage_panel = ArenaDamagePanel.new(); _sidebar_content.add_child(_damage_panel)
	_round_banner = ArenaRoundBanner.new(); _hud.add_child(_round_banner)
	_elimination_notice = _label(_hud, "", 18, PAPER)
	_elimination_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elimination_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_elimination_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_elimination_notice.hide()
	_result_volley = ArenaResultVolley.new()
	add_child(_result_volley)
	_result_volley.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_alliance_panel = PanelContainer.new()
	_alliance_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_sidebar_content.add_child(_alliance_panel)
	var alliance_box := VBoxContainer.new(); _alliance_panel.add_child(alliance_box)
	var alliance_heading := _label(alliance_box,RemakeText.t("Alliances"),21,GOLD)
	alliance_heading.add_theme_font_override("font",_heading_font)
	ArenaCreatureCard.outline(alliance_heading)
	_alliance_list = GridContainer.new(); _alliance_list.columns=3
	_alliance_list.add_theme_constant_override("h_separation",10)
	_alliance_list.add_theme_constant_override("v_separation",6)
	alliance_box.add_child(_alliance_list)
	for key: String in ArenaAlliances.RULES:
		var badge := ArenaAllianceBadge.new(); badge.key=key; badge.name=key
		_alliance_list.add_child(badge)
	_bench_scroll = ScrollContainer.new()
	_bench_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Let the row shrink after a window resize; disabled scrolling feeds the
	# previous slot widths back into the parent's minimum size.
	_bench_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_bench_scroll.resized.connect(_fit_reserve_slots)
	bench_column.add_child(_bench_scroll)
	_army_row = HBoxContainer.new()
	_army_row.add_theme_constant_override("separation", 8)
	_bench_scroll.add_child(_army_row)
	_army_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_army_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 18)
	_bench_bar.add_child(actions)
	var purse := HBoxContainer.new()
	purse.alignment = BoxContainer.ALIGNMENT_CENTER
	purse.add_theme_constant_override("separation", 10)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(purse)
	ArenaCreatureCard.ink_icon(_icon(purse, preload("res://assets/arena/coin.svg")), ArenaCreatureCard.SNOW_INK)
	var treasury := VBoxContainer.new()
	treasury.add_theme_constant_override("separation", 0)
	purse.add_child(treasury)
	_gold = _label(treasury, "", 19, GOLD)
	_income = _label(treasury, "", 12, MUTED)
	var gap := Control.new()
	gap.custom_minimum_size.x = 2
	purse.add_child(gap)
	ArenaCreatureCard.ink_icon(_icon(purse, preload("res://assets/arena/life.svg")), ArenaCreatureCard.SNOW_INK)
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
	_pause = _icon_button(time_bar, preload("res://assets/arena/pause.svg"), _toggle_pause, RemakeText.t("Space"))
	_speed = _button(time_bar, "", _toggle_speed, "")
	_speed.custom_minimum_size = Vector2(66, 44)
	_update_speed()
	_sell_target = _button(_hud, "", _sell_selected, "", true)
	_sell_target.name = "SellTarget"
	_sell_target.icon = preload("res://assets/arena/sell.svg")
	_sell_target.add_theme_constant_override("icon_max_width", 20)
	_sell_target.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_sell_target.offset_left = -218; _sell_target.offset_right = -24
	_sell_target.offset_top = -298; _sell_target.offset_bottom = -254
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
	_scout_bar = _unframed(_sidebar_content)
	_sidebar_content.move_child(_scout_bar, 0)
	var scout_row := HBoxContainer.new()
	_scout_bar.add_child(scout_row)
	var scout_text := VBoxContainer.new()
	scout_row.add_child(scout_text)
	_scout_name = _label(scout_text, "", 14, PAPER)
	_scout_details = _label(scout_text, "", 13, PAPER)
	_scout_return = _icon_button(scout_row, preload("res://assets/arena/return.svg"), _show_player.bind(0), RemakeText.t("Return to your army."))
	_scout_return.custom_minimum_size = Vector2(28, 28)
	_scout_return.add_theme_constant_override("icon_max_width", 16)
	_scout_return.name = "ReturnToBoard"
	for label in [_scout_name, _scout_details]: _standing_ink(label)
	for label in [_gold, _income, _lives]: ArenaCreatureCard.snow_ink(label)
	for label in [_army_title, _reserve_count]:
		label.add_theme_color_override("font_color", PAPER)
		ArenaCreatureCard.outline(label)
	for button in [_scout_return]:
		for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]: button.add_theme_color_override(key, ArenaCreatureCard.SNOW_INK)
	_scout_bar.hide()
	_overview_bar = HBoxContainer.new()
	_overview_bar.position = Vector2(24, 16)
	_overview_bar.add_theme_constant_override("separation", 16)
	_hud.add_child(_overview_bar)
	_button(_overview_bar, RemakeText.t("Your board"), _show_player.bind(0), RemakeText.t("Return to your army."))
	var board_hint := _label(_overview_bar, RemakeText.t("Click a board to watch it."), 16, PAPER)
	board_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ArenaCreatureCard.outline(board_hint)
	_overview_bar.hide()
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
	_evolution_notice.below = _battle_sidebar
	_hud.add_child(_evolution_notice)
	_hud.move_child(_evolution_notice, _modal_layer.get_index())
	_evolution_notice.shown.connect(_highlight_evolution)
	_tooltips = ArenaTooltips.new()
	_tooltips.z_index = 3
	_tooltips.scope = _hud
	_tooltips.world_hint = _world_hint
	_tooltips.viewport_pointer = field.viewport_pointer
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
		if field.match_state != battle: return
		_listen_to(battle.world)
		_sound.on_event(event))
	battle.finished.connect(_round_finished)
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
	_saved = not network_play and run.load_saved() and run.stage not in ["won", "lost"]
	if not network_play and not _saved: run.begin(1)
	run.changed.connect(_refresh)
	_refresh()
	# Compile the known combat effects while entering the mode. The first
	# battle then only needs variants introduced by its staged creatures.
	field.prepare_battle_presentation()


func _create_battle() -> ArenaPveMatch:
	return ArenaPveMatch.new()


func _create_boards() -> ArenaTournamentBattles:
	return ArenaSoloBattles.new() if ArenaLocalHost.available() else ArenaTournamentBattles.new()


func _exit_tree() -> void:
	if not landing and run.auto_save: run.save()
	if _sound: _sound.on_world(null)
	Gfx.set_border(_previous_border, _previous_border_dist)


func _refresh() -> void:
	_capture_health_changes()
	_encounter_key = 0
	_header.visible = false # The opening composition carries the expedition title.
	_gold.text = str(run.gold)
	_lives.text = str(run.lives) if run is ArenaTournamentRun else "%d/3" % run.lives
	_lives.tooltip_text = RemakeText.t("Health %d/100") % run.lives if run is ArenaTournamentRun else RemakeText.t("Lives %d/%d") % [run.lives, 3]
	var income := run.income_preview(run.battle_savings if run.stage == "fight" else -1)
	_income.text = RemakeText.t("Income +%d") % int(income.total)
	_income.visible = run.wave < run.wave_limit
	_gold.get_parent().tooltip_text = _income_details(income) + "\n" + RemakeText.t("Savings earn 1 gold per 10, up to 5. Win three battles in a row for +1 gold, or six for +2. Defeat breaks the streak.")
	_wave_title.text = run.round_title()
	_opponent.visible = run is ArenaTournamentRun and not landing
	var preparing := run.stage == "prepare" and not landing
	var fighting := run.stage == "fight" and not landing
	if not run.can_shop(): _evolution_notice.clear()
	else: _evolution_notice.retain(run)
	if _shown_stage != run.stage:
		if preparing: _shop_open = true
		elif fighting: _shop_open = false
		_shown_stage = run.stage
	if run.stage == "result" and _result_key != run.history.size():
		_result_key = run.history.size()
		_result_remaining = 4.0
	_bench_panel.visible = not landing
	_bench_bar.visible = not landing
	_shop_toggle.visible = not landing
	_shop_toggle.set_pressed_no_signal(_shop_open)
	_shop_toggle.tooltip_text = RemakeText.t("Close shop" if _shop_open else "Open shop")
	_shop_panel.visible = not landing and _shop_open
	_fight_panel.visible = not landing and not preparing
	_round_panel.visible = not landing
	_start.visible = preparing
	_start.disabled = run.preparing_battle
	_shop_section.visible = not landing
	_dock.visible = not landing and run.stage in ["reward", "won", "lost"] and battle.settle_remaining <= 0
	_outcome.visible = _dock.visible
	_outcome_shade.visible = _dock.visible and run.stage == "reward"
	_layout_outcome()
	_pause.visible = not preparing and not network_play
	_pause.disabled = not fighting
	_speed.visible = not preparing and not network_play
	_speed.disabled = false
	_rail.visible = not landing and _inspector.visible
	_landing_layer.visible = landing
	_clock.visible = not landing
	field.show_markers = not landing
	_message.visible = not landing or run.save_error
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
	if not landing: _build_shop()
	else: _clear(_shop)
	_clear(_dock)
	if landing: _build_landing()
	else: _clear(_landing_layer)
	if not landing:
		if run.stage == "reward": _build_rewards()
		elif run.stage in ["won", "lost"] and battle.settle_remaining <= 0: _build_result()
	_start.disabled = run.preparing_battle or run.deployed_count() == 0 or (network_play and run.lives <= 0)
	_train_button.disabled = not run.can_shop() or run.experience() >= ArenaRules.MAX_TRAINING or not run.spending_error(ArenaRules.TRAINING_COST).is_empty()
	_train_button.price = -1 if run.level_needed() == 0 else ArenaRules.TRAINING_COST
	_train_button.value = str(run.capacity())
	_train_button.progress = 1.0 if run.level_needed() == 0 else float(run.level_progress()) / run.level_needed()
	_train_button.caption = RemakeText.t("Max level") if run.level_needed() == 0 else RemakeText.t("XP %d/%d") % [run.level_progress(), run.level_needed()]
	_train_button.queue_redraw()
	if _last_level > 0 and run.capacity() > _last_level and not landing:
		if not is_instance_valid(_level_sound):
			_level_sound = AudioStreamPlayer.new()
			_level_sound.bus = &"SFX"
			_level_sound.stream = EIAudio.sfx("buttons/subcomplete.wav")
			add_child(_level_sound)
		_level_sound.play()
	_last_level = run.capacity()
	_train_button.tooltip_text = RemakeText.t("Level %d") % run.capacity() + "\n" + RemakeText.t("Train · %d gold") % ArenaRules.TRAINING_COST + "\n" + RemakeText.t("Gain %d XP. Company level increases army capacity and improves shop odds.") % ArenaRules.TRAINING_XP
	if run.experience() >= ArenaRules.MAX_TRAINING: _train_button.tooltip_text = RemakeText.t("Your army is at full strength.")
	elif not run.spending_error(ArenaRules.TRAINING_COST).is_empty(): _train_button.tooltip_text += "\n" + run.spending_error(ArenaRules.TRAINING_COST)
	_refresh_alliances()
	_reserve_count.text = RemakeText.t("Reserves %d/%d") % [run.bench_count(), run.bench_limit()]
	_refresh_button.price = run.refresh_cost()
	_refresh_button.queue_redraw()
	_refresh_button.tooltip_text = RemakeText.t("Refresh · %d gold") % run.refresh_cost() + "\n" + RemakeText.t("Refresh unlocked offers. All locked recruits stay.")
	var refresh_error := RemakeText.t("Unlock an offer before refreshing.") if run.shop.all(func(offer): return offer.locked) else run.spending_error(run.refresh_cost())
	_refresh_button.disabled = not run.can_shop() or not refresh_error.is_empty()
	_refresh_button.accessibility_name = RemakeText.t("Refresh · %d gold") % run.refresh_cost()
	if not refresh_error.is_empty(): _refresh_button.tooltip_text += "\n" + refresh_error
	_army_title.text = RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()]
	_army_title.tooltip_text = ""
	_army_title.remove_meta("arena_help")
	_army_title.add_theme_color_override("icon_normal_color", MUTED)
	_army_title.disabled = landing

	if _army_title.disabled:
		_army_title.tooltip_text = ""
		_army_title.remove_meta("arena_help")
	_army_title.mouse_filter = Control.MOUSE_FILTER_IGNORE if _army_title.disabled else Control.MOUSE_FILTER_STOP
	if run.stage != "prepare" or landing or field.match_state != battle: field.select_creature("")
	elif selected_uid > 0 and not run.unit(selected_uid).is_empty():
		var entry := run.unit(selected_uid)
		field.select_creature(entry.prototype, int(entry.family), int(entry.rank))
	if selected_uid > 0 and run.unit(selected_uid).is_empty(): _clear_selection()
	_update_sell_target()
	# A network roster refresh must not reset a stable world hover.
	if landing: _hide_inspector()
	if preparing and run.army.is_empty(): _hint(RemakeText.t("Recruit your first creature."))
	_tooltips.capture(_hud)
	if is_instance_valid(_tournament_battles) and not landing:
		_tournament_battles.synchronize()
		# Keep the overview open when roster, gold or round state changes.
		# watch() collapses the worlds back onto one board without moving the
		# overview camera, leaving most of its map empty.
		if not _tournament_battles.overview:
			_tournament_battles.watch(_tournament_battles.viewed_player)
	_update_scout()
	_layout_outcome.call_deferred()
	if run.save_error: _feedback(RemakeText.t("The game could not be saved. Check free disk space before leaving."))


func _build_army() -> void:
	var benched := run.reserve_slots()
	var existing := {}
	for button: Button in _army_row.get_children(): existing[button.get_meta("slot_key", "")] = button
	var selected := run.unit(selected_uid)
	var returning: bool = run.stage == "prepare" and not selected.is_empty() and selected.deployed
	for i in benched.size():
		var entry: Dictionary = benched[i] if i < benched.size() else {}
		var key := "empty:%d" % i if entry.is_empty() else "%d:%s:%d" % [entry.uid, entry.prototype, entry.rank]
		var button: Button = existing.get(key)
		existing.erase(key)
		if button == null:
			button = Button.new()
			button.set_meta("slot_key", key)
			button.custom_minimum_size = Vector2(96, 120)
			button.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color(0,0,0,0), Color(0,0,0,0), Vector2(3,3)))
			button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color(0.12, 0.16, 0.17, 0.45), Color(0, 0, 0, 0), Vector2(3,3)))
			button.add_theme_stylebox_override("focus", ArenaCreatureCard.style(Color(0, 0, 0, 0), PAPER, Vector2(3,3)))
			button.add_theme_stylebox_override("disabled", ArenaCreatureCard.style(Color(0,0,0,0), Color(0,0,0,0), Vector2(3,3)))
			button.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("344248"), GOLD, Vector2(3,3)))
			button.add_theme_font_size_override("font_size", 14)
			_army_row.add_child(button)
			var line := ColorRect.new()
			line.name = "SlotLine"
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(line)
			line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			line.offset_left = 10; line.offset_right = -10
			line.offset_bottom = -2
			if entry.is_empty():
				button.pressed.connect(_return_to_reserves.bind(i))
			else:
				button.set_meta("arena_creature", {"id": entry.prototype, "uid": int(entry.uid)})
				button.pressed.connect(_select.bind(int(entry.uid)))
				var preview := WikiPreview.new()
				preview.fit_slot = true
				button.add_child(preview)
				preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				preview.offset_top = 14; preview.offset_bottom = -20
				preview.show_model(ArenaAppearance.preview(entry.prototype, int(entry.family), int(entry.rank)))
				preview.turn_by(-0.35)
				preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
				for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ArenaStars.add_to(button, int(entry.rank) + 1, Vector2(5, 1), ArenaStars.for_family(int(entry.family)))
		_army_row.move_child(button, i)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if landing or not run.can_shop() else Control.MOUSE_FILTER_STOP
		button.disabled = not returning if entry.is_empty() else landing or not run.can_shop()
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
		button.set_meta("return_slot", returning and entry.is_empty())
		button.set_meta("bench_slot", i)
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
	# Keep each live offer's render target across rerolls and round changes.
	# The shop always belongs to the player, even while scouting another board.
	var represented := ArenaAlliances.counts(run.army)
	while _shop.get_child_count() > run.shop.size():
		var extra := _shop.get_child(_shop.get_child_count() - 1)
		_shop.remove_child(extra); extra.queue_free()
	for index in run.shop.size():
		var offer: Dictionary = run.shop[index]
		var family := int(offer.family)
		var rank := int(offer.get("rank", 0))
		var key := "%d:%d" % [family, rank]
		var box: Control = _shop.get_child(index) if index < _shop.get_child_count() else null
		if box != null and (family < 0) != (box.get_child(0) is Label):
			_shop.remove_child(box); box.queue_free(); box = null
		var fresh := box == null
		if fresh:
			box = Control.new()
			box.custom_minimum_size = Vector2(112, 144)
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_shop.add_child(box)
			_shop.move_child(box, index)
		box.set_meta("offer_key", key)
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
		card.tier = int(rule.tier)
		card.copies = run.army.filter(func(entry): return entry.family == family and entry.rank == rank).size()
		card.copies_needed = ArenaRules.evolution_copies(family, rank)
		card.upgrade_ready = run.shop_completes_upgrade(index)
		card.owned_army = run.army
		card.disabled = not run.purchase_error(index).is_empty()
		card.caption = ArenaAlliances.names(family)
		card.family = family
		card.represented_traits = represented
		card.footer = RemakeText.t("%d gold") % card.cost
		card.set_meta("arena_creature", {"id": card.prototype, "family": family, "rank": rank, "offer": index})
		if fresh:
			card.pressed.connect(_recruit_offer.bind(index))
			box.add_child(card)
			card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.tooltip_text = ""
		card.update_offer()
		var lock: Button
		if fresh:
			lock = _icon_button(box, preload("res://assets/arena/lock.svg"), func(): pass, RemakeText.t("Lock recruit"))
			lock.toggle_mode = true
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var border := GOLD if state in ["pressed", "hover_pressed"] else PAPER if state == "focus" else Color.TRANSPARENT
				lock.add_theme_stylebox_override(state, ArenaCreatureCard.style(Color.TRANSPARENT, border, Vector2(3, 3)))
			lock.custom_minimum_size = Vector2(28, 28)
			lock.add_theme_constant_override("icon_max_width", 16)
			lock.toggled.connect(func(_on): run.lock_offer(index))
			lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			lock.offset_left = -30; lock.offset_right = -2
			lock.offset_top = 0; lock.offset_bottom = 28
		else: lock = box.get_child(1)
		lock.set_pressed_no_signal(offer.locked)
		lock.icon = preload("res://assets/arena/lock.svg") if offer.locked else preload("res://assets/arena/unlock.svg")
		lock.tooltip_text = RemakeText.t("Unlock recruit") if offer.locked else RemakeText.t("Lock recruit")
		lock.disabled = not run.can_shop()
		lock.get_theme_stylebox("disabled").border_color = GOLD if offer.locked else Color.TRANSPARENT
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			lock.add_theme_color_override("icon_" + state + "_color", GOLD if offer.locked else MUTED)


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
		var mode_button := _button(modes, RemakeText.t("Expedition") if index == 0 else RemakeText.t("Autochess"), _switch_mode.bind(index), RemakeText.t("Survive 30 rounds. You can lose twice.") if index == 0 else RemakeText.t("Face eight computer opponents. The last player standing wins."), false)
		mode_button.name = "ExpeditionMode" if index == 0 else "AutochessMode"
		mode_button.toggle_mode = true
		mode_button.set_pressed_no_signal(index == int(run is ArenaTournamentRun))
		mode_button.custom_minimum_size = Vector2(180, 44)
		mode_button.size_flags_horizontal = Control.SIZE_FILL
		mode_button.add_theme_stylebox_override("pressed", ArenaCreatureCard.style(Color("424033"), GOLD, Vector2(8,4)))
		mode_button.add_theme_stylebox_override("normal", ArenaCreatureCard.style(Color("202726"), Color("4b5143"), Vector2(8,4)))

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
	if run is ArenaTournamentRun:
		_button(choices, RemakeText.t("Play online"), func():
			if get_parent().has_method("open_arena_online"): get_parent().open_arena_online(), RemakeText.t("Host or join a nine-player tournament. Computers fill empty seats."))
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
		preview.show_model(ArenaAppearance.preview(spec[0]))
		preview.turn_by(-0.25)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child: Control in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var regions := _wrap(showcase, " · ".join([ArenaRules.region_name(0), ArenaRules.region_name(1), ArenaRules.region_name(2)]), 15, GOLD)
	regions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule(showcase)
	var facts := _wrap(showcase, RemakeText.t("Face eight computer opponents. The last player standing wins.") if run is ArenaTournamentRun else RemakeText.t("Survive 30 rounds. You can lose twice."), 16, PAPER)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help := _wrap(showcase, RemakeText.t("Start with 100 health. Fight creeps in rounds 1–3 and every fifth round, and other players in between.") if run is ArenaTournamentRun else RemakeText.t("Recruit and arrange your team before the timer ends. The creatures handle the fighting."), 14, MUTED)
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
	_health_session = ""
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
	row.add_theme_constant_override("separation", 12)
	_dock.add_child(row)
	for index in run.rewards.size():
		var reward: Dictionary = run.rewards[index]
		var card := ArenaRewardCard.new()
		card.name = "Reward%d" % index
		card.reward = reward
		card.disabled = reward.kind == "companion" and run.bench_count() > run.bench_limit()
		if card.disabled: card.tooltip_text = RemakeText.t("Your reserves already hold an extra ally. Choose another reward.")
		card.pressed.connect(_choose_reward.bind(index))
		row.add_child(card)


func _field_army() -> Array[Dictionary]:
	if run.stage == "prepare":
		if run is ArenaTournamentRun and is_instance_valid(_tournament_battles): return run.company(_tournament_battles.viewed_player).army
		return run.army
	return _viewed_battle().round_army


func _show_alliance(key: String) -> void:
	_rail.accented = false; _rail.queue_redraw()
	_showing_company = true
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	_inspect_scroll.scroll_vertical = 0
	var rule: Dictionary = ArenaAlliances.RULES[key]
	var count := int(ArenaAlliances.counts(_field_army())[key])
	var heading := _wrap(_inspect_box, RemakeText.t(rule.name), 22, GOLD)
	heading.add_theme_font_override("font", _heading_font)
	_wrap(_inspect_box, RemakeText.t("On field: %d/%d") % [count, ArenaAlliances.target(key, count)], 14, PAPER)
	_wrap(_inspect_box, ArenaAlliances.effect(key, ArenaAlliances.rank(key, count)), 14, GOLD)
	_wrap(_inspect_box, RemakeText.t(rule.help), 13, PAPER)
	var thresholds: Array[String] = []
	for threshold: int in rule.thresholds: thresholds.append(str(threshold))
	_wrap(_inspect_box, RemakeText.t("Bonuses at %s different creatures.") % " / ".join(thresholds), 12, GOLD)
	_wrap(_inspect_box, RemakeText.t("Only deployed creatures count. Copies and evolved forms of the same creature count once."), 12, MUTED)
	_rule(_inspect_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	_inspect_box.add_child(grid)
	var company: ArenaRun = run.company(_tournament_battles.viewed_player) if is_instance_valid(_tournament_battles) else run
	for family: int in rule.families:
		if family not in ArenaRules.ACTIVE_FAMILIES: continue
		var owned := company.army.filter(func(entry): return int(entry.family) == family)
		var deployed := _field_army().any(func(entry): return int(entry.family) == family and entry.deployed)
		var status := "On field" if deployed else "In reserves" if not owned.is_empty() else "Not recruited"
		var title := _wrap(grid, RemakeText.t(ArenaRules.FAMILIES[family].name), 13, GOLD if deployed else MUTED)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(grid, RemakeText.t(status), 12, GOLD if deployed else MUTED)


func _show_company() -> void:
	if landing: return
	_rail.accented = false; _rail.queue_redraw()
	_showing_company = true
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	_inspect_scroll.scroll_vertical = 0
	_wrap(_inspect_box, RemakeText.t("Level %d") % run.capacity(), 22, GOLD)
	_wrap(_inspect_box, RemakeText.t("28 creature species cost 1–5 gold. Each species has one shop entry and equal odds within its tier."), 13, PAPER)
	_wrap(_inspect_box, RemakeText.t("Three identical one-star creatures make a two-star creature. Three two-star creatures make a three-star creature of the same species."), 13, PAPER)
	_wrap(_inspect_box, RemakeText.t("Stars strengthen health, attacks and spells. The strongest forms are evolution-only."), 13, GOLD)
	_wrap(_inspect_box, RemakeText.t("Army %d/%d") % [run.deployed_count(), run.capacity()], 14, PAPER)
	if run.level_needed() > 0:
		_wrap(_inspect_box, RemakeText.t("XP %d/%d") % [run.level_progress(), run.level_needed()], 13, PAPER)
		_wrap(_inspect_box, RemakeText.t("Upgrade company"), 15, GOLD)
		_wrap(_inspect_box, RemakeText.t("Buy %d XP · %d gold") % [ArenaRules.TRAINING_XP, ArenaRules.TRAINING_COST], 13, PAPER)
		_wrap(_inspect_box, RemakeText.t("Next level: %d XP") % (run.level_needed() - run.level_progress()), 12, MUTED)
		var error := run.spending_error(ArenaRules.TRAINING_COST)
		if not error.is_empty(): _wrap(_inspect_box, error, 12, GOLD)
	else: _wrap(_inspect_box, RemakeText.t("Maximum level"), 13, GOLD)
	_wrap(_inspect_box, RemakeText.t("Each completed round grants 1 XP. Higher levels add army slots and improve shop odds."), 12, MUTED)
	_rule(_inspect_box)
	_wrap(_inspect_box, RemakeText.t("Shop odds"), 15, GOLD)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	_inspect_box.add_child(grid)
	for word in ["Tier", "Gold", "Chance"]:
		var label := _label(grid, RemakeText.t(word), 12, MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var odds: Array = ArenaRules.SHOP_ODDS[run.capacity()]
	for tier in 5:
		for value in [str(tier + 1), ArenaRules.tier_price_label(tier + 1), "%d%%" % int(odds[tier])]:
			_label(grid, value, 13, PAPER if int(odds[tier]) > 0 else MUTED)
	if not run.boons.is_empty():
		_rule(_inspect_box)
		for boon: String in run.boons:
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][0]), 13, GOLD)
			_wrap(_inspect_box, RemakeText.t(ArenaRules.BOONS[boon][1]), 12, MUTED)


func _shop_odds_text() -> String:
	var text := RemakeText.t("Shop odds") + " · " + RemakeText.t("Level %d") % run.capacity()
	var odds: Array = ArenaRules.SHOP_ODDS[run.capacity()]
	for tier in 5: text += "\n" + RemakeText.t("Tier %d · %s gold · %d%%") % [tier + 1, ArenaRules.tier_price_label(tier + 1), int(odds[tier])]
	return text + "\n\n" + RemakeText.t("New offers use your company level. Recruits start at one star; matching copies evolve them.")


func _result_countdown() -> String:
	var text := "Next round in %ds" if run is ArenaTournamentRun else "Camp in %ds" if run.wave % 5 == 0 else "Next wave in %ds"
	return RemakeText.t(text) % ceili(_result_remaining)


func _update_result_countdown() -> void:
	if run.stage == "result": _clock.text = _result_countdown()


func _creature_preview(parent: Node, id: String, height: float, family := -1, rank := 0) -> WikiPreview:
	var preview := WikiPreview.new()
	preview.fit_slot = true
	preview.custom_minimum_size = Vector2(80, height)
	parent.add_child(preview)
	preview.show_model(ArenaAppearance.preview(id, family, rank))
	preview.turn_by(-0.35)
	return preview


func _select(uid: int) -> void:
	if landing or not run.can_shop(): return
	var selected := run.unit(selected_uid)
	var clicked := run.unit(uid)
	if run.stage == "prepare" and not selected.is_empty() and not clicked.is_empty() and selected.deployed and not clicked.deployed:
		var error := run.swap_from_bench(uid, selected_uid)
		if error.is_empty(): _clear_selection()
		_feedback(error)
		return
	selected_uid = uid
	battle.selected_run_uid = uid
	field.highlighted_run_uid = uid
	var entry := run.unit(uid)
	if entry.is_empty(): return
	if run.stage == "prepare" and not landing: field.select_creature(entry.prototype, int(entry.family), int(entry.rank))
	_build_army()
	_tooltips.capture(_hud)
	_update_sell_target()
	_hint("")


func _select_world(unit: GameUnit) -> void:
	if field.match_state != battle: return
	if landing or not run.can_shop(): return
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
	_standings.hide()
	_showing_company = false
	_inspected = id
	_rail.show(); _inspector.show()
	_clear(_inspect_box); _clear(_inspect_actions)
	_inspect_scroll.scroll_vertical = 0
	var family := int(entry.get("family", -1))
	var accent := ArenaStars.for_family(family)
	_rail.accented = true; _rail.edge = accent; _rail.queue_redraw()
	var rank := int(_inspected_unit.get_meta("arena_placement", {}).get("rank", ArenaUnitInfo.rank_of(id))) if is_instance_valid(_inspected_unit) else int(entry.get("rank", ArenaUnitInfo.rank_of(id)))
	var title := _wrap(_inspect_box, ArenaRules.title(id, family, rank), 21, accent)
	title.add_theme_font_override("font", _heading_font)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_inspect_box.add_child(header)
	var preview := _creature_preview(header, id, 56, family, rank)
	preview.custom_minimum_size.x = 64
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	header.add_child(details)
	if family >= 0:
		ArenaCreatureCard.tribe_names(details, family, 13)
		_wrap(details, RemakeText.t("Tier %d · %d gold") % [int(ArenaRules.FAMILIES[family].tier), int(ArenaRules.FAMILIES[family].cost)], 12, MUTED)
		if ArenaRules.FAMILIES[family].has("region"):
			_wrap(details, ArenaRules.region_name(int(ArenaRules.FAMILIES[family].region)), 12, MUTED)
	var stars := Control.new()
	stars.custom_minimum_size.y = 14
	details.add_child(stars)
	ArenaStars.add_to(stars, rank + 1, Vector2.ZERO, accent)
	_rule(_inspect_box)
	if family >= 0: _wrap(_inspect_box, RemakeText.t(ArenaRules.FAMILIES[family].hook), 13, accent)
	_live_health = _wrap(_inspect_box, ArenaUnitInfo.summary(id, _inspected_unit, family, rank), 13)
	if is_instance_valid(_inspected_unit) and family >= 0 and ArenaAlliances.counts(_field_army()).values().any(func(n): return int(n) >= 2):
		_wrap(_inspect_box, RemakeText.t("Active bonuses are included in these stats."), 12, MUTED)

	var spells := _spell_titles(ArenaRules.recruit_prototype(family,rank,GameData.db.find("monster_prototypes", id)))
	if not spells.is_empty(): _wrap(_inspect_box, spells, 13, GOLD)
	if family >= 0:
		_rule(_inspect_box)
		var counts := run.army
		if is_instance_valid(_inspected_unit) and run is ArenaTournamentRun and is_instance_valid(_tournament_battles):
			counts = run.company(_tournament_battles.viewed_player).army
		var path := ArenaEvolutionPath.new()
		path.name = "EvolutionPath"
		path.portrait_size = 36; path.interactive = true
		_inspect_box.add_child(path)
		path.update_path(family, counts)
		if entry.has("offer") and run.shop_completes_upgrade(int(entry.offer)):
			_wrap(_inspect_box, RemakeText.t("The highlighted shop copies complete an evolution."), 12, Color("9bfff0"))
	if is_instance_valid(_inspected_unit) and (entry.get("prototype", id) != id or int(entry.get("rank", rank)) != rank):
		_wrap(_inspect_box, RemakeText.t("Next round: %s") % (ArenaRules.title(entry.prototype, int(entry.family), int(entry.rank)) + " " + "★".repeat(int(entry.rank) + 1)), 13, GOLD)
	if entry.has("offer"):
		var error := run.purchase_error(int(entry.offer))
		if not error.is_empty(): _wrap(_inspect_box, error, 12, MUTED)
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
	# Inspection is read-only. Eliminated spectators cannot shop, but still
	# need to inspect the watched army and its alliances.
	if landing or _modal_layer.visible:
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
		var uid := int(unit.get_meta("arena_placement", {}).get("run_uid", 0))
		var viewed_run: ArenaRun = run.company(_tournament_battles.viewed_player) if run is ArenaTournamentRun and _tournament_battles.viewed_player != 0 else run
		entry = viewed_run.unit(uid)
		if entry.is_empty():
			for original: Dictionary in field.match_state.round_army:
				if int(original.uid) == uid: entry = original; break
		if unit.get_meta("arena_placement", {}).has("source_uid"): entry = {"family":unit.get_meta("arena_placement", {}).get("family", -1), "rank":unit.get_meta("arena_placement", {}).get("rank", 0)}
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
	if landing or field.match_state != battle or run.stage != "prepare" or selected_uid <= 0: return
	var error := battle.placement_error(point)
	if error.is_empty(): error = run.deploy(selected_uid, point)
	if error.is_empty(): _clear_selection()
	_feedback(error)


func _fight() -> void:
	if landing: return
	_show_player(0)
	_clear_selection()
	var started := _tournament_battles.request_start() if is_instance_valid(_tournament_battles) else battle.start()
	if not started: _feedback(RemakeText.t("Deploy at least one creature before starting."))


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
		_pause.icon = preload("res://assets/arena/play.svg") if (battle.phase == ArenaMatch.Phase.PAUSED or _league_paused) else preload("res://assets/arena/pause.svg")
		_pause.tooltip_text = RemakeText.t("Resume" if battle.phase == ArenaMatch.Phase.PAUSED or _league_paused else "Pause") + " · " + RemakeText.t("Space")
		if _tooltips: _tooltips.capture(_pause)
	_update_encounter_status()
	if _sound: _sound.music.tick(2 if battle.phase == ArenaMatch.Phase.FIGHT else 0)


func _viewed_battle() -> ArenaPveMatch:
	return field.match_state as ArenaPveMatch if field and field.match_state else battle


func _update_encounter_status() -> void:
	if not _phase: return
	var watched := _viewed_battle()
	if not watched: return
	var player := _tournament_battles.viewed_player if is_instance_valid(_tournament_battles) else 0
	var key := hash([watched.get_instance_id(), run.wave, run.stage, watched.phase, watched.winner, _league_paused, player])
	if key == _encounter_key: return
	_encounter_key = key
	var encounter: String = run.board_encounter(player) if run is ArenaTournamentRun else run.encounter_title()
	_opponent.text = encounter if run is ArenaTournamentRun else ""
	_round_panel.set_meta("arena_help", run.round_title() + " · " + encounter + "\n" + RemakeText.t("Seed %s") % str(run.run_seed) + "\n" + RemakeText.t("Battles last at most 90 seconds. Ten seconds without damage ends a battle in a draw."))
	var status := RemakeText.t("Preparing")
	if run.stage != "prepare":
		if watched.phase == ArenaMatch.Phase.PAUSED or _league_paused: status = RemakeText.t("Paused")
		elif watched.phase == ArenaMatch.Phase.FIGHT: status = RemakeText.t("Battle")
		else:
			status = RemakeText.t("Draw" if watched.winner == -1 else "Victory" if watched.winner == 0 else "Defeat")
	if _phase.text != status:
		_phase.text = status
		_layout_round_badge.call_deferred()
		_layout_standings.call_deferred()
	_phase.add_theme_color_override("font_color", GOLD if watched.phase == ArenaMatch.Phase.FINISHED else MUTED)


func _process(dt: float) -> void:
	_cursor.set_kind("cursor_camera" if field._right_dragged or field._orbit else "cursor_default")
	if _camera_input_allowed():
		var turn := float(_camera_keys.has(KEY_E)) - float(_camera_keys.has(KEY_Q))
		var movement := Vector2(float(_camera_keys.has(KEY_D))-float(_camera_keys.has(KEY_A)),float(_camera_keys.has(KEY_S))-float(_camera_keys.has(KEY_W)))
		field.advance_camera(dt / maxf(Engine.time_scale, 0.001), turn, movement)
	else:
		_clear_camera_input()
	_damage_wait -= dt / maxf(Engine.time_scale,0.001)
	_battle_sidebar.visible = not landing and not field.showing_boards() and not _modal_layer.visible
	if _damage_wait <= 0 and _battle_sidebar.visible:
		_damage_wait = 0.2
		var alliance_height := _alliance_panel.get_combined_minimum_size().y if _alliance_panel.visible else 0.0
		var scout_height := _scout_bar.size.y + 12 if _scout_bar.visible else 0.0
		_damage_panel.update_damage(_viewed_battle(), _field_army(), maxf(45,_bench_panel.position.y-_battle_sidebar.position.y-alliance_height-scout_height-58))
	_round_banner.size = Vector2(maxf(240, minf(460, _hud.size.x - 580)), 0)
	var notice_top := 204.0 if _shop_panel.visible else 28.0
	_round_banner.position = Vector2(roundf((_hud.size.x - _round_banner.size.x) * 0.5), notice_top)
	_round_banner.update_round(run, dt / maxf(Engine.time_scale, 0.001), _result_remaining, landing or _modal_layer.visible or field.showing_boards())
	_update_eliminations(dt / maxf(Engine.time_scale, 0.001), landing or _modal_layer.visible)
	_update_name_flashes(dt / maxf(Engine.time_scale, 0.001))
	_hover_inspector(dt)
	if run is ArenaTournamentRun and run.stage == "fight": _update_fighting_icons()
	_standings.visible = run is ArenaTournamentRun and not landing and not _rail.visible and not _modal_layer.visible and not _outcome.visible
	if is_instance_valid(_tournament_battles):
		_tournament_battles.paused = landing or _modal_layer.visible or battle.phase == ArenaMatch.Phase.PAUSED or _league_paused
		if not network_play and run.stage == "fight": Engine.time_scale = float(GameData.arena_speed)
	_update_scout()
	_update_encounter_status()
	_overview_bar.visible = field.showing_boards() and not landing
	_hit_numbers.visible = not field.showing_boards()
	_vignette.visible = not field.showing_boards()
	if field.showing_boards():
		for control in [_shop_panel, _bench_panel, _round_panel, _fight_panel, _shop_toggle, _start, _battle_sidebar, _alliance_panel, _scout_bar, _standings, _rail, _message]: control.hide()
	if not network_play and not landing and run.stage == "result" and battle.settle_remaining <= 0 and not _modal_layer.visible:
		_result_remaining = maxf(0.0, _result_remaining - dt / maxf(Engine.time_scale, 0.001))
		_update_result_countdown()
		if _result_remaining <= 0: run.advance()
	if not network_play and not landing and run.stage == "prepare" and not _modal_layer.visible:
		if run.elapse_preparation(dt / maxf(Engine.time_scale, 0.001)):
			_clear_selection()
			if is_instance_valid(_tournament_battles): _tournament_battles.request_start(true)
			else: battle.expire_preparation()
		_timer_save_wait += dt
		if _timer_save_wait >= 5.0:
			_timer_save_wait = 0
			if run.auto_save: run.save_error = not run.save()
	if _evolution_notice.visible:
		_evolution_notice.covered = _modal_layer.visible or field.showing_boards()
	if is_instance_valid(_live_health) and is_instance_valid(_inspected_unit) and _rail.visible:
		var unit := _inspected_unit
		_live_health.text = ArenaUnitInfo.summary(_inspected, unit)
	var watched := _viewed_battle()
	if _clock and watched and is_instance_valid(watched.world):
		if run.stage == "prepare": _clock.text = RemakeText.t("Battle in %ds") % ceili(run.preparation_left)
		elif run.stage == "result": _clock.text = _result_countdown()
		elif run.stage in ["won", "lost"]: _clock.text = RemakeText.t("First place" if run.stage == "won" else "Eliminated") if run is ArenaTournamentRun else RemakeText.t("Expedition complete" if run.stage == "won" else "The expedition ends")
		else: _clock.text = "%d:%02d / %d:%02d" % [int(watched.world.time) / 60, int(watched.world.time) % 60, int(watched.time_limit()) / 60, int(watched.time_limit()) % 60]
		var urgent := (run.stage == "prepare" and run.preparation_left <= 10) or (run.stage == "fight" and watched.phase == ArenaMatch.Phase.FIGHT and watched.time_limit() - watched.world.time <= 10)
		if not _modal_layer.visible and not _league_paused and watched.phase != ArenaMatch.Phase.PAUSED:
			_clock_pulse += dt / maxf(Engine.time_scale, 0.001)
		# Reapplying a theme override emits a theme change even when equal,
		# invalidating text/layout three times on every battle frame.
		if _clock_urgency != int(urgent):
			_clock_urgency = int(urgent)
			_clock.begin_bulk_theme_override()
			_clock.add_theme_color_override("font_color", Color("ff9377") if urgent else GOLD)
			_clock.add_theme_color_override("font_outline_color", Color("35140e"))
			_clock.add_theme_constant_override("outline_size", 2 if urgent else 0)
			_clock.end_bulk_theme_override()
		_clock.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * cos(_clock_pulse * TAU * 1.5)) if urgent else 1.0

	if _sound and watched and is_instance_valid(watched.world):
		_listen_to(watched.world)
		_sound.mixer.set_listener(Vector3(32, 32, 2), Vector2(0, 1).rotated(field.yaw), Vector2(1, 0).rotated(field.yaw))
		if watched.phase == ArenaMatch.Phase.FIGHT:
			if _sound.mixer.suspended: _sound.mixer.resume()
			_sound.units.tick()
			_sound.spells.tick(dt)
			_sound._ack_tick()
		elif not _sound.mixer.suspended:
			_sound.mixer.suspend()


func _listen_to(world: GameWorld) -> void:
	if not _sound or not is_instance_valid(world): return
	if _sound_world != world:
		_sound_world = world
		_sound.on_world(world)
	# Campaign zone entry mutes SFX for ten ticks. Arena spectators have no
	# campaign audio clock, so every event-driven world switch must unmute.
	_sound.mixer.sfx_on = true
	_sound.music.hold = false


func _camera_input_allowed() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return not landing and not _modal_layer.visible and not field.showing_boards() \
		and not (is_instance_valid(_wiki) and _wiki.visible) \
		and not (focus is LineEdit or focus is TextEdit)


func _clear_camera_input() -> void:
	_camera_keys.clear()
	if is_instance_valid(field): field.stop_camera_motion()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _clear_camera_input()


func _input(event: InputEvent) -> void:
	# Releases must reach us even when a focused widget consumes the event.
	if event is InputEventKey and not event.pressed:
		_camera_keys.erase(event.physical_keycode if event.physical_keycode else event.keycode)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_wiki) and _wiki.visible: return
	if event is InputEventKey and event.pressed and _camera_input_allowed():
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_HOME]:
			if key == KEY_HOME:
				_clear_camera_input()
				field.reset_camera()
			else: _camera_keys[key] = true
			get_viewport().set_input_as_handled()
			return
	if not _modal_layer.visible and WikiContext.matches(event, get_viewport()):
		_open_wiki()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and run.stage == "fight" and not _modal_layer.visible:
			_toggle_pause(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _modal_layer.visible: _close_modal()
			elif selected_uid > 0 or not _hover_key.is_empty() or _inspector.visible:
				_dismissed_hover = _hover_key
				_clear_selection()
			elif field.showing_boards() or field.match_state != battle: _show_player(0)
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
		["Economy", "Every round pays a bounty and interest on savings at battle start. Victories add a win bonus and a streak bonus. Defeat costs one life, then advances to the next wave."],
		["Preparation", "Preparation lasts 60 seconds on Standard, 45 on Veteran and 30 on Champion. Start early when ready. Menus pause the countdown. An empty field deploys reserves at expiry; with no recruits, you lose the wave."],
		["Recruitment", "New recruits join the field if there is room, or wait in reserves. Company level determines shop odds. Train for stronger offers, or refresh to find matching copies."],
		["Shop", "Open the shop during battle to recruit, refresh or buy XP. Reserves can be sold. Deployed creatures and their bonuses stay unchanged until the next round."],
		["Evolution", "Collect matching creatures to evolve them. Stars mark each stronger form. The creature details show how many you need."],
		["Your army", "Select a creature, then its place on the field. Select a reserve, then an ally to swap them. An empty reserve slot withdraws a creature. Select a creature to reveal the sell area."],
		["Battle", "Both teams fight under AI control. Damaging spells cannot hurt allies in Trials. Hover a creature for details. Space pauses combat; the speed control switches between normal and double speed."],
		["Alliances", "Different deployed creatures with matching traits activate bonuses. Multiple alliances can be active together. Reserves and duplicates do not add to the count."],
		["Company", "Visit camp every five rounds for experience, supplies or company upgrades. Survive all thirty waves to unlock harder expeditions."]]
	if run is ArenaTournamentRun:
		topics[0] = [RemakeText.t("Economy"), RemakeText.t("Every round pays 5 gold, plus interest. Wins add 1 gold and can earn a streak bonus. Every round also grants 1 XP.")]
		topics[1] = [RemakeText.t("Preparation"), RemakeText.t("You have 60 seconds to recruit and arrange your army. Rivals prepare at the same time. Menus pause the countdown; watching another board does not.")]
		topics[-1] = [RemakeText.t("Players"), RemakeText.t("Eight computer opponents build their own armies. Losing costs health based on the round and surviving enemy stars. At zero health you are eliminated. Click a player to inspect their army.")]
		topics.append([RemakeText.t("Rounds"), RemakeText.t("Rounds 1–3 and every fifth round are against creeps. Other rounds pair surviving players. With an odd player count, one army fights a copy without damaging its owner. After round 30, defeat damage increases each round.")])
	if run is ArenaTournamentRun: topics.append([RemakeText.t("Draw"), RemakeText.t("A draw costs both players 10 health.")])
	if network_play:
		topics[1] = ["Preparation", "Everyone has 60 seconds to recruit and arrange their army. The round starts early when all surviving human players are ready. Changing your army cancels ready. Menus and scouting do not pause the timer."]
		topics[6] = ["Battle", "Both teams fight under AI control. The host runs all battles on the same clock and can switch between normal and double speed. Hover a creature for details. Online battles cannot be paused."]
		topics[8] = ["Players", "Up to nine players compete with their own armies. Computers fill empty seats and take over disconnected players. At zero health you are eliminated and can keep watching. If the host leaves, the game ends for everyone."]
	topics.append(["Camera", "Use WASD to move the camera. Hold Q/E or drag with the right or middle mouse button to rotate. Right-drag also tilts the camera; Shift + middle-drag pans. Use the wheel to zoom. Home restores the starting view."])
	for topic in topics:
		_label(content, RemakeText.t(topic[0]), 18, GOLD)
		_wrap(content, RemakeText.t(topic[1]), 15, PAPER)
		if topic[0] == "Battle":
			_wrap(content, RemakeText.t("In Trials, armor absorbs at most 80% of each damage type. This applies to both teams, including spells."), 15, PAPER)
			_wrap(content, RemakeText.t("Battles last at most 90 seconds. Ten seconds without damage ends a battle in a draw."), 15, PAPER)
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
	button.add_theme_stylebox_override("disabled", ArenaCreatureCard.style(Color("1a201f"), Color("4b5143")))
	button.add_theme_stylebox_override("hover_pressed", ArenaCreatureCard.style(Color("424033"), GOLD))
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
		_play_cue("buy")
		_clear_selection()
		if not network_play: _present_evolutions(before)


func _present_evolutions(before: Array) -> void:
	var events: Array[Dictionary] = []
	for old: Dictionary in before:
		var entry := run.unit(int(old.uid))
		if entry.is_empty() or int(entry.rank)<=int(old.rank): continue
		events.append({"uid":int(entry.uid),"family":int(entry.family),"from":old.prototype,"to":entry.prototype,"old_rank":old.rank,"rank":entry.rank,"next_round":run.stage!="prepare" and entry.deployed})
	if not events.is_empty():
		_play_cue("upgrade")
		_evolution_notice.present(events)


func _choose_reward(index: int) -> void:
	_feedback(run.choose_reward(index))


func _highlight_evolution(event: Dictionary) -> void:
	if not event.get("next_round", false): field.evolution_pulses[int(event.uid)] = 1.6
	for button: Button in _army_row.get_children():
		if int(button.get_meta("arena_creature", {}).get("uid", -1)) != int(event.uid): continue
		var glow := ArenaCreatureCard.style(Color(GOLD, 0.12), GOLD, Vector2(3, 3))
		button.add_theme_stylebox_override("normal", glow)
		var tween := button.create_tween().set_parallel()
		tween.tween_property(glow, "border_color:a", 0.0, 1.6)
		tween.tween_property(glow, "bg_color:a", 0.0, 1.6)


func _return_to_reserves(slot := -1) -> void:
	var error := run.bench(selected_uid, slot)
	if error.is_empty(): _clear_selection()
	_feedback(error)


func _layout_round_badge() -> void:
	if not _round_panel: return
	var minimum := _round_panel.get_combined_minimum_size()
	_round_panel.offset_left = -116 - maxf(160, minimum.x)
	_round_panel.offset_right = -116
	_round_panel.offset_bottom = 16 + maxf(44, minimum.y)
	_layout_standings.call_deferred()


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
	_ui_scale = maxf(1.0, minf(size.x / 1440.0, size.y / 900.0))
	_hud.scale = Vector2.ONE * _ui_scale
	_hud.size = size / _ui_scale
	field.ui_scale = _ui_scale
	field._update_camera()
	_shop_panel.offset_right = minf(960, _hud.size.x - 300)
	_layout_battle_sidebar.call_deferred()
	if _army_row and not run.army.is_empty(): _build_army()
	_layout_outcome()
	_layout_modal()
	_layout_landing()
	_layout_inspector.call_deferred()
	if _tooltips: _tooltips.capture(_hud)


func _layout_inspector() -> void:
	if not _inspect_box or not _hud: return
	# Use the real free space above the reserve/actions row. A fixed 240-pixel
	# bottom margin clipped the upgrade strip even with empty space below it.
	var bottom := _bench_panel.position.y - 8 if is_instance_valid(_bench_panel) else _hud.size.y - 188
	var maximum := maxf(120, bottom - _rail.offset_top)
	var content := _inspect_box.get_combined_minimum_size().y + 20
	_rail.offset_bottom = _rail.offset_top + clampf(content, 80, maximum)


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
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(44, 44)
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
	if is_instance_valid(_wiki): _wiki.dismiss()
	_modal_panel.show()
	battle.formation_motion.paused = not network_play
	if not network_play and battle.phase == ArenaMatch.Phase.DEPLOY: battle.world.process_mode = Node.PROCESS_MODE_DISABLED
	if not _modal_layer.visible:
		_menu_was_fighting = battle.phase == ArenaMatch.Phase.FIGHT
		if not network_play and _menu_was_fighting: battle.toggle_pause()
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
	var close := _icon_button(row, preload("res://assets/arena/close.svg"), _close_modal, RemakeText.t("Close"))
	close.name = "CloseModal"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule(_modal_box)
	_layout_modal.call_deferred()
	_tooltips.capture.call_deferred(_hud)
	_focus_modal.call_deferred()


func _focus_modal() -> void:
	if not _modal_layer.visible: return
	if is_instance_valid(_wiki) and _wiki.visible: return
	for control in _modal_box.find_children("*", "Button", true, false):
		if not control.disabled:
			control.grab_focus()
			return


func _close_modal() -> void:
	if is_instance_valid(_wiki): _wiki.dismiss()
	_modal_panel.show()
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
			button.disabled = landing or run.stage != "prepare" or run.preparing_battle
			button.tooltip_text = RemakeText.t("Deploy your strongest creatures with ranged allies behind the front line.")
		elif id == 4:
			button.disabled = landing or not run.can_undo()
			button.tooltip_text = RemakeText.t("Undo a preparation action. Shop refreshes cannot be refunded.")
		elif id == 5:
			button.disabled = landing or run.stage != "prepare" or run.preparing_battle
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
		var value := WikiCatalog.spell_title(parsed.code) if parsed.has("code") else ""
		if not value.is_empty() and value not in names: names.append(value)
	return ", ".join(names)


func _update_sell_target() -> void:
	if not _sell_target: return
	var entry := run.unit(selected_uid)
	_sell_target.visible = not landing and run.can_shop() and not entry.is_empty() and (run.stage == "prepare" or not entry.deployed)
	if _sell_target.visible:
		_sell_target.text = RemakeText.t("Sell · +%d gold") % run.sale_value(entry)
		_sell_target.tooltip_text = ArenaRules.title(entry.prototype, int(entry.family), int(entry.rank))
		if _tooltips: _tooltips.capture(_sell_target)


func _sell_selected() -> void:
	var error := run.sell(selected_uid)
	if error.is_empty():
		_play_cue("sell")
		_clear_selection()
	_feedback(error)


func _income_details(income: Dictionary) -> String:
	return RemakeText.t("Bounty %d · Victory %d · Interest %d · Streak %d") % [int(income.get("base", 0)), int(income.get("victory", 0)), int(income.get("interest", 0)), int(income.get("streak", 0))]


func _show_training() -> void:
	if landing or not run.can_shop(): return
	var level := run.capacity()
	var error := run.train()
	_feedback(error)
	if error.is_empty() and run.capacity() == level and _sound:
		_sound.ui("buttons\\camp\\buy.wav")


func _toggle_shop() -> void:
	_shop_open = not _shop_open
	_shop_panel.visible = _shop_open
	_shop_toggle.set_pressed_no_signal(_shop_open)
	_shop_toggle.tooltip_text = RemakeText.t("Close shop" if _shop_open else "Open shop")
	_hide_inspector()
	_tooltips.capture(_shop_toggle)


const CUES := {"buy": "buttons/camp/buy.wav", "sell": "buttons/camp/put_off.wav",
	"upgrade": "buttons/camp/perk.wav", "reject": "buttons/messbox/cancel.wav", "win": "buttons/subcomplete.wav", "lose": "buttons/gameover.wav"}


func _play_cue(kind: String) -> void:
	if _sound: _sound.ui(CUES[kind])


func _round_finished(side: int) -> void:
	# Stop the battle mix before starting the result cue. Suspending it on
	# the following frame would cut off this one-shot along with combat SFX.
	if _sound: _sound.mixer.suspend()
	_play_cue("win" if side == 0 else "lose")


func _fit_reserve_slots() -> void:
	if not _army_row or not _bench_scroll or _bench_scroll.size.x <= 0: return
	var buttons := _army_row.get_children()
	if buttons.is_empty(): return
	# Match shop height and width while fitting every reserve on screen.
	var count := maxi(1, run.shop.size())
	var shop_width := floorf((_shop.size.x - 8 * (count - 1)) / count)
	var width := minf(shop_width, floorf((_bench_scroll.size.x - 8 * (buttons.size() - 1)) / buttons.size()))
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
	_play_cue("buy" if error.is_empty() else "reject")


func _toggle_speed() -> void:
	if network_play: return
	GameData.arena_speed = 1 if GameData.arena_speed == 2 else 2
	GameData.save_settings()
	battle.set_speed(float(GameData.arena_speed))
	_update_speed()


func _update_speed() -> void:
	_speed.text = RemakeText.t("1×") if GameData.arena_speed == 1 else RemakeText.t("2×")
	_speed.tooltip_text = RemakeText.t("Battle speed") + "\n" + RemakeText.t("Click to switch between normal and double speed. This choice is remembered for all runs.")
	if _tooltips: _tooltips.capture(_speed)


func _setup_tournament_battles() -> void:
	_league_paused = false
	if is_instance_valid(_tournament_battles):
		remove_child(_tournament_battles)
		_tournament_battles.queue_free()
	_tournament_battles = null
	if field:
		field.tournament = null
		field.match_state = battle
	if battle and is_instance_valid(battle.world): battle.presentation_root().show()
	if run is ArenaTournamentRun:
		battle.staged_preparation = true
		run.live_boards = true
		_tournament_battles = _create_boards()
		_tournament_battles.prepare_presentation = field.prepare_battle_presentation
		if _tournament_battles is ArenaSoloBattles: _tournament_battles.failed.connect(_feedback)
		_tournament_battles.run = run
		_tournament_battles.parent_stage = field.stage
		_tournament_battles.home = battle
		field.tournament = _tournament_battles
		_tournament_battles.paused = true
		add_child(_tournament_battles)
		_tournament_battles.board_changed.connect(func(player):
			if player == _tournament_battles.viewed_player:
				field.match_state = _tournament_battles.watched_match()
				field.hovered = null
				if _alliance_panel: _refresh_alliances())
		_tournament_battles.board_event.connect(func(event):
			if event.get("t") == "hitnum" and _hit_numbers: _hit_numbers.add(event)
			if _sound:
				_listen_to(field.match_state.world)
				_sound.on_event(event))


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
	var width := 240.0 if _standings_expanded else 164.0
	_standings.custom_minimum_size.x = width
	_standings.size.x = width
	_standings.offset_left = -16 - width
	_standings.offset_right = -16
	_standings.size.y = 0
	var toolbar := HBoxContainer.new()
	_standing_rows.add_child(toolbar)
	var heading := _button(toolbar, RemakeText.t("Players") + " · %d" % league.alive_players().size(), func(): _standings_expanded = not _standings_expanded; _build_standings(), RemakeText.t("Expand or collapse player details."))
	heading.add_theme_font_size_override("font_size", 14)
	heading.custom_minimum_size.y = 24
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var surface := heading.get_theme_stylebox(state).duplicate()
		surface.content_margin_left = 4; surface.content_margin_right = 4
		surface.content_margin_top = 2; surface.content_margin_bottom = 2
		heading.add_theme_stylebox_override(state, surface)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var map_button := _icon_button(toolbar, preload("res://assets/arena/boards.svg"), _show_boards, RemakeText.t("All boards") + "\n" + RemakeText.t("See all nine boards. Click a board to watch it."))
	map_button.add_theme_font_size_override("font_size", 14)
	map_button.custom_minimum_size = Vector2(28, 28)
	map_button.add_theme_constant_override("icon_max_width", 18)
	var players := range(ArenaTournamentRun.PLAYER_COUNT)
	players.sort_custom(func(a,b): return league.health(a) > league.health(b) if league.health(a) != league.health(b) else a < b)
	for player: int in players:
		var row := HBoxContainer.new()
		_standing_rows.add_child(row)
		var button := _button(row, league.player_title(player), _show_player.bind(player), RemakeText.t("Watch this player's board.") + "\n" + league.player_title(player))
		button.set_meta("board_player", player)
		var last_result := _standing_result(player)
		if last_result != -2:
			button.tooltip_text += "\n" + RemakeText.t("Last battle: %s") % RemakeText.t("Victory" if last_result == 0 else "Defeat" if last_result > 0 else "Draw")
		button.add_theme_constant_override("icon_max_width", 16)
		button.expand_icon = true
		button.icon = preload("res://assets/arena/alliance_warrior.svg") if league.player_fighting(player) else null
		_standing_ink(button)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 22)
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", ArenaCreatureCard.style(Color.TRANSPARENT, ArenaCreatureCard.SNOW_INK, Vector2(2,1)))
		button.add_theme_stylebox_override("pressed", button.get_theme_stylebox("hover"))
		button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		button.disabled = league.health(player) <= 0
		var rank := int(league.placements[player])
		var health := _label(row, str(league.health(player)) if league.health(player) > 0 else "#%d" % rank if rank > 0 else RemakeText.t("Out"), 14, PAPER)
		if league.health(player) <= 0 and rank == 0:
			health.tooltip_text = RemakeText.t("Final place is determined when the round ends.")
		_standing_ink(health, Color("712b35") if league.health(player) < 25 else ArenaCreatureCard.SNOW_INK)
		health.custom_minimum_size.x = 24
		health.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		health.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if _standings_expanded:
			var company := league.company(player)
			var details := _label(_standing_rows, RemakeText.t("Level %d") % company.capacity() + " · " + RemakeText.t("%d gold") % company.gold, 13, ArenaCreatureCard.SNOW_INK)
			_standing_ink(details)
			details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mark_watched_player()
	_layout_standings.call_deferred()


func _update_fighting_icons() -> void:
	for button: Button in _standing_rows.find_children("*", "Button", true, false):
		if button.has_meta("board_player"):
			button.icon = preload("res://assets/arena/alliance_warrior.svg") if run.player_fighting(int(button.get_meta("board_player"))) else null


func _standing_ink(control: Control, color := ArenaCreatureCard.SNOW_INK) -> void:
	ArenaCreatureCard.snow_ink(control, color)
	# Inherit the HUD font rasterized at the actual display scale.
	control.remove_theme_font_override("font")
	control.add_theme_constant_override("outline_size", 1)


func _mark_watched_player() -> void:
	if not is_instance_valid(_tournament_battles): return
	for button: Button in _standing_rows.find_children("*", "Button", true, false):
		if not button.has_meta("board_player"): continue
		var player := int(button.get_meta("board_player"))
		button.icon = preload("res://assets/arena/alliance_warrior.svg") if run.player_fighting(player) else null
		var selected := player == _tournament_battles.viewed_player
		var line := StyleBoxFlat.new()
		line.bg_color = Color.TRANSPARENT
		line.content_margin_left = 7
		line.border_width_left = 3 if selected else 0
		line.border_color = ArenaCreatureCard.SNOW_ACCENT
		button.add_theme_stylebox_override("normal", line)
		_standing_ink(button, _standing_color(player))


func _standing_result(player: int) -> int:
	if not run is ArenaTournamentRun: return -2
	var result: Dictionary = run.company(player).last_result
	if result.is_empty(): return -2
	var wave := int(result.get("wave", -1))
	if wave < run.wave - 1: return -2
	var staging := run.preparing_battle or (is_instance_valid(_tournament_battles) and _tournament_battles.starting)
	if run.stage == "fight" and wave != run.wave and not staging: return -2
	return int(result.get("winner",-1))


func _standing_color(player: int) -> Color:
	var result := _standing_result(player)
	if result == 0: return STANDING_WIN
	if result > 0: return STANDING_LOSS
	return ArenaCreatureCard.SNOW_ACCENT if is_instance_valid(_tournament_battles) and _tournament_battles.viewed_player == player else ArenaCreatureCard.SNOW_INK


func _layout_standings() -> void:
	if not _standings.visible: return
	var width := 240.0 if _standings_expanded else 164.0
	var top := _round_panel.offset_bottom + 12
	var height := minf(_standing_rows.get_combined_minimum_size().y, maxf(120, _hud.size.y - 240 - top))
	_standing_scroll.custom_minimum_size.y = height
	_standings.offset_top = top
	_standings.offset_left = -16 - width
	_standings.offset_right = -16
	_standings.offset_bottom = top + height
	_standings.size = Vector2(width, height)


func _show_player(player: int) -> void:
	if not run is ArenaTournamentRun or landing: return
	if player > 0 and run.health(player) <= 0: return
	_clear_selection()
	var from_overview := field.showing_boards()
	_tournament_battles.synchronize()
	_tournament_battles.watch(player)
	_damage_wait = 0.0
	field.match_state = _tournament_battles.watched_match()
	field.stop_camera_motion()
	field._update_camera()
	_refresh_alliances()
	_mark_watched_player()
	_listen_to(field.match_state.world)
	_hit_numbers._items.clear()
	_update_scout()
	_update_encounter_status()
	if from_overview: _refresh()


func _show_boards() -> void:
	if not run is ArenaTournamentRun or landing: return
	_clear_selection()
	_tournament_battles.synchronize()
	_tournament_battles.show_all()
	field.stop_camera_motion()
	field._update_camera()
	_hit_numbers._items.clear()


func _update_scout() -> void:
	if not _scout_bar: return
	var scouting := is_instance_valid(_tournament_battles) and _tournament_battles.viewed_player != 0 and not landing and not field.showing_boards()
	_scout_bar.visible = scouting
	_layout_battle_sidebar()
	if not scouting: return
	var player := _tournament_battles.viewed_player
	var company: ArenaRun = run.company(player)
	_scout_name.text = run.player_title(player)
	_scout_name.tooltip_text = run.board_encounter(player) + "\n" + RemakeText.t("Level %d") % company.capacity() + " · " + RemakeText.t("%d gold") % company.gold
	_scout_details.text = RemakeText.t("Level %d") % company.capacity() + " · " + RemakeText.t("%d gold") % company.gold


func _layout_battle_sidebar() -> void:
	if not is_instance_valid(_battle_sidebar): return
	# The scout identity and combat statistics share one container below the
	# complete shop, including the space used by names on hover/focus.
	var top := 24.0
	if is_instance_valid(_shop_panel) and _shop_panel.visible:
		top = _shop_panel.position.y + _shop_panel.size.y + ArenaCreatureCard.HOVER_TITLE_HEIGHT + 8.0
	_battle_sidebar.position.y = top


func _refresh_alliances() -> void:
	_alliance_panel.visible = not landing and not _field_army().is_empty()
	var counts := ArenaAlliances.counts(_field_army())
	for plaque: ArenaAllianceBadge in _alliance_list.get_children():
		plaque.update_count(int(counts[plaque.key]))
	_layout_alliances.call_deferred()


func _layout_alliances() -> void:
	if is_instance_valid(_alliance_panel): _alliance_panel.size = _alliance_panel.get_combined_minimum_size()


func _toggle_pause() -> void:
	if network_play: return
	if run.stage != "fight": return
	if run is ArenaTournamentRun and battle.phase == ArenaMatch.Phase.FINISHED:
		_league_paused = not _league_paused
		_battle_changed()
	else: battle.toggle_pause()


func _open_wiki() -> void:
	var context := {}
	var control := get_viewport().gui_get_hovered_control()
	if control == field and is_instance_valid(field.hovered):
		context = WikiContext.for_unit(field.hovered)
	elif _rail.visible and not _showing_company and control and (control == _rail or _rail.is_ancestor_of(control)):
		context = {"key": "creature/" + _inspected.to_lower().uri_encode()}
	else:
		while control and control != _hud:
			if control.has_meta("arena_creature"):
				context = {"key": "creature/" + String(control.get_meta("arena_creature").id).to_lower().uri_encode()}
				break
			control = control.get_parent() as Control
	# Reuse the existing modal pause/focus ownership. Online clocks keep running.
	_open_modal(RemakeText.t("Game wiki"))
	_modal_panel.hide()
	if not is_instance_valid(_wiki):
		_wiki = WikiPanel.new()
		# WikiPanel scales itself from the physical viewport. Keep it outside
		# the scaled arena HUD so large windows do not scale it twice.
		add_child(_wiki)
		_wiki.closed.connect(func(): _modal_panel.show(); _close_modal())
	_wiki.open()
	WikiContext.navigate(_wiki, context)


func _capture_health_changes() -> void:
	if not run is ArenaTournamentRun or not is_instance_valid(_result_volley): return
	var session := "%d:%d" % [run.get_instance_id(), run.run_seed]
	if session != _health_session or landing:
		_health_session = session; _health_seen.clear(); _name_flashes.clear()
		_eliminated_seen.clear(); _elimination_queue.clear(); _elimination_left = 0.0
		_elimination_notice.hide()
		_result_volley.clear()
	var initialized := not _health_seen.is_empty()
	for player in ArenaTournamentRun.PLAYER_COUNT:
		if player > run.rivals.size(): continue
		var health: int = run.health(player)
		var previous := int(_health_seen.get(player, health))
		_health_seen[player] = health
		if health > 0: _eliminated_seen.erase(player)
		if health <= 0 and not _eliminated_seen.has(player):
			_eliminated_seen[player] = true
			if initialized and not landing:
				var rank := int(run.placements[player])
				_elimination_queue.append(RemakeText.t("%s has been eliminated (place #%d).") % [run.player_title(player), rank] if rank > 0 else RemakeText.t("%s has been eliminated.") % run.player_title(player))
		if health >= previous or landing: continue
		_name_flashes[player] = 2.0
		var starts := PackedVector2Array()
		var watched := _viewed_battle()
		var viewed := _tournament_battles.viewed_player if is_instance_valid(_tournament_battles) else 0
		var team := 1 if player == viewed else 0 if player == run.opponent_for(viewed) else -1
		if team >= 0 and not field.showing_boards() and is_instance_valid(watched) and is_instance_valid(watched.world):
			var particles := ParticleFx.of(watched.world)
			for unit: GameUnit in watched.world.unit_rows():
				if unit.dead or int(unit.get_meta("arena_placement", {}).get("team", -1)) != team: continue
				var origin := ParticleFx.godot(particles.cast_point(unit)) + particles.display_origin()
				var at := field.camera.unproject_position(origin)
				if Rect2(Vector2.ZERO, field.size).has_point(at):
					starts.append(_result_volley.get_global_transform_with_canvas().affine_inverse() * (field.get_global_transform_with_canvas() * at))
		# Standings are rebuilt by this refresh. Resolve the target after the
		# containers have laid out, rather than retaining a freed button.
		_show_health_loss.call_deferred(player, previous - health, starts)

func _show_health_loss(player: int, loss: int, starts: PackedVector2Array) -> void:
	var session := _health_session
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or session != _health_session or landing or not is_instance_valid(_result_volley): return
	for button: Button in _standing_rows.find_children("*", "Button", true, false):
		if int(button.get_meta("board_player", -1)) != player: continue
		var at := _volley_target(player)
		if not _standings.visible: return
		_result_volley.present(starts, at, loss, player == 0, _hud.scale.x, _volley_target.bind(player))
		return

func _volley_target(player: int) -> Vector2:
	for button: Button in _standing_rows.find_children("*", "Button", true, false):
		if int(button.get_meta("board_player", -1)) == player:
			return _result_volley.get_global_transform_with_canvas().affine_inverse() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	return Vector2.ZERO

func _update_eliminations(dt: float, covered: bool) -> void:
	if not covered:
		_elimination_left = maxf(0.0, _elimination_left - dt)
		if _elimination_left <= 0 and not _elimination_queue.is_empty():
			_elimination_notice.text = _elimination_queue.pop_front()
			_elimination_left = 3.5
	_elimination_notice.position = _round_banner.position + Vector2(0,82)
	_elimination_notice.size = Vector2(_round_banner.size.x,0)
	_elimination_notice.visible = not covered and _elimination_left > 0
	_elimination_notice.modulate.a = clampf(_elimination_left / 0.3,0,1)

func _update_name_flashes(dt: float) -> void:
	for player in _name_flashes.keys():
		_name_flashes[player] -= dt
		if _name_flashes[player] <= 0: _name_flashes.erase(player)
	for button: Button in _standing_rows.find_children("*", "Button", true, false):
		if not button.has_meta("board_player"): continue
		var player := int(button.get_meta("board_player"))
		var flashing := _name_flashes.has(player)
		var color := _standing_color(player)
		if flashing:
			var pulse := 0.65 + 0.35 * absf(sin(float(_name_flashes[player]) * 9.0))
			color = color.lerp(Color("ff6e69"), pulse)
		if button.get_theme_color("font_color") != color: _standing_ink(button,color)
		button.set_meta("loss_flash", flashing)
