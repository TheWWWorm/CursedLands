class_name TutorialPanel
extends Control
## A transient, pointer-transparent hint. It never owns pause, input or focus.
## Existing script and screen calls only make a topic eligible for display.
const SCREEN_IDS := ["options", "camp_weapons", "camp_skills", "camp_spell_trade",
	"camp_spell_constr", "camp_item_trade", "camp_item_constr", "camp_repair", "quest_global_map", "quest_mission"]
const DWELL := 9.0
const FADE := 0.45
const QUIET := 8.0
const STALE := 24.0
const CUE_SOUND := "buttons\\tutorial\\next.wav"
static var auto_show := true
static var persist := true
static var _seen := {}
var hud: GameHUD
var current_id := ""
var last_id := ""
var expanded := false
var _screen_id := ""
var _pending := ""
var _pending_age := 0.0
var _remaining := 0.0
var _quiet := 0.0
var _sample_time := 0.0
var _world := 0
var _manual := false
var _context := {}
var _observer := TutorialContext.new()
var _card: PanelContainer
var _heading: Label
var _body: Label
var _details: Label
var _help: Button
var _dismiss: Button
var _guide: Button
var _book: Button
var _standalone_wiki: WikiPanel
var _signature := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("context_help")
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("211b11f5")
	style.border_color = Color("82734a")
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	_card.add_theme_stylebox_override("panel", style)
	_card.add_theme_font_override("font", Interface800.font())
	_card.add_theme_color_override("font_color", Color("fff9bb"))
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_card.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	column.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://icons/wiki/book.svg")
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color("d8bd6b")
	row.add_child(icon)
	_heading = Label.new()
	_heading.add_theme_font_override("font", Interface800.font())
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color("dfc576"))
	_heading.add_theme_font_size_override("font_size", 16)
	row.add_child(_heading)
	_help = _button("?", show_last)
	row.add_child(_help)
	_dismiss = _button("×", close)
	_dismiss.tooltip_text = RemakeText.t("Hide hint")
	row.add_child(_dismiss)
	_body = Label.new()
	_body.add_theme_font_override("font", Interface800.font())
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 16)
	column.add_child(_body)
	_details = Label.new()
	_details.add_theme_font_override("font", Interface800.font())
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 16)
	column.add_child(_details)
	_guide = _button(RemakeText.t("Guide"), open_guide)
	column.add_child(_guide)
	_transparent(column)
	hide()
	if hud:
		_book = _button("", open_guide)
		_book.icon = load("res://icons/wiki/book.svg")
		_book.expand_icon = true
		_book.add_theme_constant_override("icon_max_width", 20)
		_book.tooltip_text = RemakeText.t("Getting started")
		get_parent().add_child.call_deferred(_book)

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", Interface800.font())
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("dfc576"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("211b11e8") if state == "normal" else Color("53482a")
		box.border_color = Color("82734a")
		box.set_border_width_all(1 if state != "normal" else 0)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: box.set_content_margin(side, 4)
		button.add_theme_stylebox_override(state, box)
	button.custom_minimum_size = Vector2(28, 24)
	button.pressed.connect(action)
	return button

func _transparent(node: Control) -> void:
	if not node is Button: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control: _transparent(child)

static func pages(id: String) -> Array:
	return TutorialGuide.pages(id)

static func seen(id: String) -> bool:
	return _seen.has(id) or TutorialProgress.has(id)

static func mark_all_seen() -> void:
	persist = false
	TutorialProgress.persist = false
	for id: String in SCREEN_IDS: _seen[id] = true

static func forget(id: String) -> void:
	_seen.erase(id)
	TutorialProgress.records().erase(id)

func show_tutorial(id: String) -> void:
	id = TutorialGuide.canonical(id)
	if not TutorialGuide.available(id): return
	TutorialProgress.persist = persist
	TutorialProgress.encounter(id)
	last_id = id
	if not auto_show or not GameData.option("show_tutorial") or TutorialProgress.has(id, "shown") or TutorialProgress.has(id, "acted"): return
	# Latest eligible request only. Burst events remain in the guide, never
	# become a timed slideshow after the player has left the encounter.
	_pending = id
	_pending_age = 0.0

func show_screen(id: String, forced := false) -> void:
	if id != _screen_id:
		close(false)
		_quiet = 0.0
		_pending = ""
	_screen_id = TutorialGuide.canonical(id)
	last_id = _screen_id
	if forced:
		open_guide()
		return
	if seen(_screen_id) or not auto_show: return
	show_tutorial(_screen_id)
	# The options already explain each setting on selection.
	if _screen_id == "options": _pending = ""

func show_help(id: String) -> void:
	last_id = TutorialGuide.canonical(id)
	open_guide()

func show_last() -> void:
	if not _screen_id.is_empty():
		open_guide()
		return
	if last_id.is_empty():
		open_guide()
		return
	if visible and expanded:
		close()
		return
	_present(current_id if visible and current_id else last_id, true)

func _present(id: String, manual := false) -> void:
	current_id = id
	last_id = id
	expanded = manual
	_manual = manual
	_remaining = DWELL
	_signature = ""
	TutorialProgress.record(id, "shown")
	if manual: TutorialProgress.record(id, "read")
	_refresh()
	show()
	modulate.a = 1.0
	if not manual and GameSound.instance: GameSound.instance.ui(CUE_SOUND)

func close(dismissed := true) -> void:
	if dismissed and current_id: TutorialProgress.record(current_id, "dismissed")
	hide()
	expanded = false
	_remaining = 0.0
	_quiet = QUIET
	current_id = ""
	queue_redraw()

func reset_context() -> void:
	close(false)
	_pending = ""
	last_id = ""
	_context = {}
	_sample_time = 0.0
	_observer.reset()

## Compatibility for existing panel guards: hints never block gameplay.
func blocks_input() -> bool:
	return false

func open_guide() -> void:
	var id := current_id if current_id else last_id
	var key := "guide/" + id if id else "guide/recent"
	if id: TutorialProgress.record(id, "read")
	close(false)
	var owner_hud := hud
	var node := get_parent()
	while node and owner_hud == null:
		if node is GameHUD: owner_hud = node
		node = node.get_parent()
	if owner_hud:
		owner_hud.open_wiki_article(key)
	else:
		# Main-menu options and standalone screens have no field HUD.
		if not is_instance_valid(_standalone_wiki):
			_standalone_wiki = WikiPanel.new()
			get_parent().add_child(_standalone_wiki)
		_standalone_wiki.open()
		_standalone_wiki.navigate(key)

func _process(dt: float) -> void:
	var real := minf(dt / maxf(Engine.time_scale, 0.001), 0.25)
	# Requests can become stale while a menu or conversation is open, too.
	if _pending:
		_pending_age += real
		if _pending_age > STALE: _pending = ""
	if hud and hud.game and is_instance_valid(hud.game.world):
		var identity := hud.game.world.get_instance_id()
		if _world != identity:
			if _world: reset_context()
			_world = identity
	var usable := _usable()
	if is_instance_valid(_book):
		_book.visible = usable
		var side := 44.0 if TouchInput.enabled else 28.0
		_book.size = Vector2.ONE * side
		_book.position = Vector2(size.x - side - 8, hud.top_bottom() + 8) if hud.portrait() else Vector2(hud._actions.offset_right + 10, hud.top_bottom() + 8)
	if not usable:
		if visible: _card.hide()
		# A hidden screen's old hint must not return on its next visit.
		if not hud and not get_parent().is_visible_in_tree():
			close(false)
			_pending = ""
		return
	_card.show()
	_quiet = maxf(0.0, _quiet - real)
	if hud:
		_sample_time += real
		if _sample_time >= 0.25:
			_context = _observer.sample(hud.game, _sample_time)
			_sample_time = 0.0
			for id in _context.get("acted", []):
				TutorialProgress.record(id, "acted")
				if current_id == id and not _manual: close(false)
			if _context.get("healing_ready", false) and not TutorialProgress.has("zt7", "shown"):
				show_tutorial("zt7")
			if current_id == "zt7" and not _manual and (_context.get("recovered", false) or not _context.get("needs_healing", false)):
				close(false)
	if visible and not _manual and _context.get("combat", false): close(false)
	if _pending:
		if TutorialProgress.has(_pending, "acted"):
			_pending = ""
		elif not visible and _quiet <= 0.0 and not _context.get("combat", false) and _eligible(_pending):
			var id := _pending
			_pending = ""
			_present(id)
	if not visible: return
	if not GameData.option("show_tutorial") and not _manual:
		close(false)
		return
	if not _manual:
		_remaining -= real
		if _remaining <= 0.0:
			close(false)
			return
		modulate.a = clampf(_remaining / FADE, 0.0, 1.0)
	_refresh()
	_layout()
	queue_redraw()

func _eligible(id: String) -> bool:
	if id == "zt7": return _context.get("healing_ready", false)
	if get_parent() is CampView:
		var camp := get_parent() as CampView
		return camp._hover_item.is_empty() and camp._hover_desc.is_empty() and camp.selected_id.is_empty()
	return true

func _usable() -> bool:
	if not is_visible_in_tree() and not get_parent().is_visible_in_tree(): return false
	if is_instance_valid(_standalone_wiki) and _standalone_wiki.visible: return false
	if not hud: return get_parent().is_visible_in_tree()
	var game := hud.game
	return game and game.session and is_instance_valid(game.world) and not game.session.loading_game \
		and not game.my_units().is_empty() and not game.session.movie_active() and not hud.blocks_camera() and not hud._dialog.visible \
		and not hud._travel.visible and not game.session.shop_available() \
		and not (is_instance_valid(PadInput.field) and PadInput.field.wheel_kind() != "")

func _refresh() -> void:
	var direct := hud != null and hud.game.direct != null and hud.game.direct.active()
	var brief := TutorialGuide.prompt(current_id, _context, direct)
	var binding := TutorialGuide.help_binding(direct)
	var signature := str([current_id, brief, expanded, binding, RemakeText.lang, TouchInput.enabled])
	if signature == _signature: return
	_signature = signature
	_heading.text = TutorialGuide.title(current_id)
	_body.text = brief
	_help.text = binding if binding else "?"
	_help.tooltip_text = RemakeText.t("Read more")
	_dismiss.tooltip_text = RemakeText.t("Hide hint")
	_details.text = "\n".join(TutorialGuide.tips(current_id).map(func(t): return "• " + t))
	_details.visible = expanded
	_guide.text = RemakeText.t("Guide")
	_guide.visible = expanded
	for button in [_help, _dismiss, _guide]:
		button.custom_minimum_size.y = 44 if TouchInput.enabled else 24

func _layout() -> void:
	var width := minf(320.0, size.x - 24.0)
	var scale_factor := 1.0
	var x := hud._actions.offset_right + 10 if hud else 54.0
	var bottom := size.y - maxf(110.0, size.y * 168.0 / 600.0)
	if hud and hud.portrait():
		x = 12.0
		width = size.x - 24.0
		bottom = maxf(hud.top_bottom() + 100.0, size.y * 0.62)
	elif get_parent() is CampView:
		# The shop's right description column is empty until an item is
		# inspected. Retire this hint as soon as those descriptions are needed.
		var camp := get_parent() as CampView
		if camp._hover_item or camp.selected_id or not camp._hover_desc.is_empty():
			close(false)
			return
		var frame := Interface800.fit_rect(Rect2(Vector2.ZERO, size))
		var k := frame.size.x / 800.0
		scale_factor = k
		width = 180.0
		x = frame.position.x + 610.0 * k
		bottom = frame.position.y + 300.0 * k
	_card.size.x = width
	_card.size.y = _card.get_combined_minimum_size().y
	_card.scale = Vector2.ONE * scale_factor
	_card.position = Vector2(clampf(x, 8, size.x - width * scale_factor - 8), maxf(8, bottom - _card.size.y * scale_factor))

## Resolve the teaching cue from the live control, never archive coordinates.
func cue_rect() -> Rect2:
	if not hud:
		if get_parent() is CampView:
			var camp := get_parent() as CampView
			var slot := "cbp" if current_id == "camp_item_constr" else "skey" if current_id == "camp_spell_constr" else ""
			if slot:
				return get_global_transform().affine_inverse() * camp.get_global_transform() * camp._r(camp._slot_rect(slot))
		return Rect2()
	var target: Control
	match current_id:
		"zt1", "zt9", "zt13": target = hud._move_dial
		"zt4": target = hud._clock_dial
		"zt7": target = hud._slots
		"zt10": target = hud.minimap
		"zt11": target = hud.text_window
		"zt12": target = hud.unit_panel
		"zt14", "zt22": target = hud._actions
		"zt17": target = hud._weapons
		"zt18": target = hud._belt
		"zt20": target = hud._faces
	if not target or not target.is_visible_in_tree(): return Rect2()
	var local_rect := Rect2(Vector2.ZERO, target.size)
	if current_id == "zt10":
		local_rect = hud.minimap._r(Minimap.MAP) if hud.minimap.open else hud.minimap._r(Minimap.BUTTONS.toggle[0], true)
	elif current_id == "zt11":
		local_rect = hud.text_window._r(MessageLog.BUTTONS.messages[0]) if hud.text_window.open else hud.text_window._toggle_rect()
	elif current_id == "zt12":
		local_rect = hud.unit_panel._r(UnitPanel.TABS.parts[0]) if hud.unit_panel.open else hud.unit_panel._r(UnitPanel.TABS.toggle[0], true)
	elif current_id == "zt20":
		local_rect = Rect2()
		for i in hud._faces._cells.size():
			if not hud._faces._cells[i][2]: continue
			var cell := hud._faces._r(hud._faces._cell(i))
			local_rect = local_rect.merge(cell) if local_rect.has_area() else cell
	elif current_id == "zt7":
		var slot := -1
		for i in hud._slots._entries.size():
			if hud._slots._entries[i][0] == _context.get("spell", ""): slot = i; break
		if slot < 0: return Rect2()
		local_rect = hud._slots._cell_rect(slot)
	elif current_id in ["zt14", "zt22"]:
		var slot := hud._actions._cells.find("science")
		if slot < 0: return Rect2()
		var side := target.size.x
		local_rect = Rect2(0, target.size.y - (slot + 1) * side, side, side)
	return get_global_transform().affine_inverse() * target.get_global_transform() * local_rect

func _draw() -> void:
	if not visible or not _card.visible: return
	var rect := cue_rect()
	if not rect.has_area(): return
	# A slow breathing outline, no rapid flashing or screen dimmer. It lasts
	# with the hint and cannot reveal an offscreen/hidden gameplay target.
	var breath := 0.65 + 0.25 * sin((DWELL - _remaining) * TAU / 2.4)
	draw_rect(rect.grow(3), Color(0.95, 0.81, 0.42, 0.12), true)
	draw_rect(rect.grow(3), Color(0.98, 0.84, 0.44, breath), false, 2.0)
	draw_rect(rect.grow(6), Color(0.98, 0.84, 0.44, breath * 0.35), false, 1.0)

func _exit_tree() -> void:
	if is_instance_valid(_book): _book.queue_free()
