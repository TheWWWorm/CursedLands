class_name ModPanel
extends Control
## Generated controls share the game's font/plate style and work with focus,
## touch and PadUI. Package changes are explicit restart transactions.
signal closed
var _body: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _summary: Label
var _tabs: GridContainer
var _apply: Button
var _continue: Button
var _page := "rules"
var _rules := {}
var _values := {}
var _base_rules := {}
var _base_values := {}
var _base_revision := 0
var _packages: Array = []
var _controls: Array[Control] = []
var _profile_name: LineEdit
var _chooser: OptionButton
var _pending_profile := ""
var _web_callback: JavaScriptObject
var _modal: FileDialog
var continue_action: Callable

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("pad_panel")
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := _label("Mods and rules", box)
	title.add_theme_font_size_override("font_size", 26)
	_summary = _label("", box)
	_tabs = GridContainer.new()
	_tabs.columns = 4 if size.x >= 1000 else 2
	resized.connect(func(): _tabs.columns = 4 if size.x >= 1000 else 2)
	box.add_child(_tabs)
	for page in ["profiles", "rules", "options", "sandbox"]:
		var button := _button({"profiles":"Profiles and mods", "rules":"Game rules", "options":"Mod options", "sandbox":"Sandbox"}[page], _tabs, func(): _show_page(page))
		button.set_meta("page", page)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	_status = _label("", box)
	_status.custom_minimum_size.y = 42
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_apply = _button("Apply", actions, _accept)
	_button("Cancel / Back", actions, close)
	_continue = _button("Continue", actions, func():
		if _accept() and continue_action.is_valid():
			var action := continue_action
			continue_action = Callable()
			close()
			action.call())
	visible = false

func open(page := "rules") -> void:
	visible = true
	var s := ModStore.session()
	if s != null and not s.mod_rules_result.is_connected(_applied): s.mod_rules_result.connect(_applied)
	_continue.visible = continue_action.is_valid()
	var config := ModStore.effective()
	_rules = config.rules.duplicate(true)
	_values = config.values.duplicate(true)
	_base_rules = _rules.duplicate(true)
	_base_values = _values.duplicate(true)
	_base_revision = int(config.revision)
	_packages = ModStore.profile().packages.duplicate()
	_pending_profile = ModStore.active_id()
	_show_page(page)
	if ModStore.startup_error != "": _status.text = ModStore.startup_error

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()

func _label(text: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = RemakeText.t(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Interface800.font())
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Interface800.TEXT)
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, action: Callable) -> Button:
	var button := Button.new()
	button.text = RemakeText.t(text)
	button.custom_minimum_size.y = 44
	CampaignChoices.style_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _show_page(page: String) -> void:
	_page = page
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_controls.clear()
	_summary.text = "%s · %s · %s: %d%s" % [CampaignChoices.title(GameData.campaign_id), ModStore.effective().name, RemakeText.t("Mods"), ModStore.effective().packages.size(),
		" · " + RemakeText.t("Sandbox saves") if ModStore.effective().get("sandbox", false) else ""]
	for button in _tabs.get_children():
		button.disabled = button.get_meta("page") == page
		button.visible = button.get_meta("page") != "sandbox" or ModStore.effective().get("sandbox", false)
	_apply.visible = page in ["rules", "options"]
	match page:
		"profiles": _profiles_page()
		"rules": _rules_page(false)
		"options": _options_page()
		"sandbox": _rules_page(true)
	_collect_controls(self)
	_scroll.scroll_vertical = 0
	if not _controls.is_empty(): _controls[0].grab_focus.call_deferred()

func _collect_controls(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control and child.is_visible_in_tree() and child.focus_mode == Control.FOCUS_ALL:
			if child is BaseButton and child.disabled: continue
			_controls.append(child)
		_collect_controls(child)

func _profiles_page() -> void:
	var running := ModStore.session() != null
	if running:
		_label("Return to the main menu to change profiles or installed packages. Game rules and mod options remain available here.", _body)
		for p in ModStore.effective().packages: _label(p.id + " " + p.version, _body)
		return
	_label("Profiles keep separate saves and network characters. Activation restarts the game. Installed versions stay available for old saves.", _body)
	_chooser = OptionButton.new()
	_chooser.custom_minimum_size.y = 44
	_body.add_child(_chooser)
	_chooser.add_item(RemakeText.t("Current defaults"))
	_chooser.set_item_metadata(0, "default")
	for id in ModStore.profiles:
		_chooser.add_item(str(ModStore.profiles[id].name))
		_chooser.set_item_metadata(_chooser.item_count - 1, id)
		if id == ModStore.active_id(): _chooser.select(_chooser.item_count - 1)
	_chooser.item_selected.connect(func(index): _pending_profile = str(_chooser.get_item_metadata(index)))
	_button("Use selected profile and restart", _body, func():
		var error := ModStore.select_profile(_pending_profile)
		if error != "": _status.text = error
		else: ModStore.restart(get_tree()))
	_profile_name = LineEdit.new()
	_profile_name.placeholder_text = RemakeText.t("Name for a new profile")
	_profile_name.max_length = 80
	_profile_name.custom_minimum_size.y = 44
	_body.add_child(_profile_name)
	var create := VBoxContainer.new()
	_body.add_child(create)
	_button("Create profile", create, func(): _create(false))
	_button("Create sandbox profile", create, func(): _create(true))
	_button("Import mod package…", _body, _import)
	if not OS.has_feature("web") and not Portability.constrained():
		_button("Open mods folder", _body, func():
			DirAccess.make_dir_recursive_absolute(ModStore.ROOT)
			OS.shell_open(ProjectSettings.globalize_path(ModStore.ROOT)))
	if ModStore.catalog.is_empty(): _label("No mods installed. Import a .eimod or ZIP package containing mod.json.", _body)
	var keys := ModStore.catalog.keys()
	keys.sort()
	for key in keys:
		var m: Dictionary = ModStore.catalog[key]
		var row := CheckButton.new()
		row.text = "%s  %s" % [m.title, m.version]
		row.clip_text = true
		row.tooltip_text = row.text
		row.custom_minimum_size.y = 44
		row.button_pressed = key in _packages
		row.disabled = ModStore.active_id() == "default"
		_body.add_child(row)
		row.toggled.connect(func(on):
			if on: _packages.append(key)
			else: _packages.erase(key))
		_label(str(m.get("description", "")), _body)
		var campaigns := PackedStringArray()
		for id in m.campaigns: campaigns.append(CampaignChoices.title(id))
		_label(("Shared gameplay" if ModSchema.gameplay(m) else "Your device") + " · " + ", ".join(campaigns), _body)
		for relation in ["requires", "after", "conflicts"]:
			if not m.get(relation, []).is_empty(): _label(relation.capitalize() + ": " + ", ".join(m[relation]), _body)
	if not keys.is_empty():
		_button("Activate selected mods and restart", _body, func():
			var error := ModStore.set_packages(_packages)
			if error != "": _status.text = error
			else: ModStore.restart(get_tree()))
	if ModStore.active_id() != "default": _copy_page()
	for problem in ModStore.errors: _label(problem, _body)

func _create(sandbox: bool) -> void:
	var error := ModStore.create_profile(_profile_name.text, sandbox)
	if error != "": _status.text = error
	else:
		open("profiles")
		_status.text = RemakeText.t("Profile created. Start a new game or copy an existing save below.")

func _rules_page(sandbox: bool) -> void:
	_label("Changes affect this run when playing, or the next run from the main menu. Guests can inspect shared rules; only the host changes them.", _body)
	if sandbox: _label("This profile keeps sandbox saves and characters separate. Turning a cheat off does not undo items or experience already earned.", _body)
	for key in ModSchema.RULES:
		if key.begins_with("sandbox_") != sandbox: continue
		var definition: Array = ModSchema.RULES[key]
		_label(definition[0] + " · " + {"camp":"At camp", "live":"Live", "new_game":"New game"}[definition[2]], _body)
		var row := OptionButton.new()
		row.custom_minimum_size.y = 44
		for label in definition[1]: row.add_item(RemakeText.t(label))
		row.select(int(_rules.get(key, 0)))
		var locked := ModStore.editable(key)
		row.disabled = locked != ""
		row.item_selected.connect(func(index): _rules[key] = index)
		_body.add_child(row)
		if locked != "": _label(locked, _body)
	if sandbox:
		_apply.visible = true
		for action in ["heal", "gold"]:
			var button := _button("Heal living party" if action == "heal" else "Give 1,000 gold", _body, func(): _sandbox(action))
			button.disabled = ModStore.session() == null or not ModStore.session().can_manage_game()
	else:
		_button("Restore game defaults in this editor", _body, func():
			for o in GameData.OPTIONS:
				if ModSchema.RULES.has(o[0]) and ModStore.editable(o[0]) == "": _rules[o[0]] = o[5]
			_show_page("rules"))

func _options_page() -> void:
	var definitions := ModStore.option_definitions()
	if definitions.is_empty():
		_label("No enabled mods provide configurable options. Use Profiles and mods to enable an installed package.", _body)
		return
	for o in definitions:
		_label(o.mod_title + " · " + o.label + " · " + RemakeText.t("At camp"), _body)
		_label(o.get("help", ""), _body)
		var row := HBoxContainer.new()
		_body.add_child(row)
		var slider := HSlider.new()
		slider.min_value = o.min
		slider.max_value = o.max
		slider.step = o.get("step", 1.0)
		slider.value = float(_values.get(o.key, o.default))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 44
		row.add_child(slider)
		var number := SpinBox.new()
		number.min_value = slider.min_value
		number.max_value = slider.max_value
		number.step = slider.step
		number.value = slider.value
		number.custom_minimum_size = Vector2(160, 44)
		row.add_child(number)
		slider.share(number)
		var locked := ModStore.editable("revive")
		slider.editable = locked == ""
		number.editable = locked == ""
		slider.value_changed.connect(func(value): _values[o.key] = value)
		var reset := _button("Default: %s" % str(o.default), _body, func():
			_values[o.key] = o.default
			slider.value = float(o.default))
		reset.disabled = locked != ""
		if locked != "": _label(locked, _body)

func _accept() -> bool:
	var now := ModStore.effective()
	var rules := {}
	var values := {}
	for key in _rules:
		if _rules[key] != _base_rules.get(key): rules[key] = _rules[key]
	for key in _values:
		if _values[key] != _base_values.get(key): values[key] = _values[key]
	if int(now.revision) != _base_revision and (not rules.is_empty() or not values.is_empty()):
		_status.text = RemakeText.t("Rules changed; reopen the menu and try again.")
		return false
	var error := ModStore.rule_error(rules)
	if error == "": error = ModStore.values_error(values)
	for key in rules:
		if error == "": error = ModStore.editable(key)
	if error == "" and not values.is_empty(): error = ModStore.editable("revive")
	if error != "": _status.text = error; return false
	error = ModStore.apply_settings(rules, values)
	var s := ModStore.session()
	var pending: bool = s != null and s.local_host.frontend and (not rules.is_empty() or not values.is_empty())
	if error == "" and not pending:
		_base_rules = _rules.duplicate(true)
		_base_values = _values.duplicate(true)
		_base_revision = int(ModStore.effective().revision)
	_status.text = error if error != "" else RemakeText.t("Changes sent to the host." if pending else "Settings applied.")
	return error == ""

func _applied(problem: String) -> void:
	if not visible: return
	if problem == "": open(_page)
	_status.text = problem if problem != "" else RemakeText.t("Settings applied.")

func _sandbox(action: String) -> void:
	var s := ModStore.session()
	if s == null: return
	var error := ""
	if s.local_host.frontend:
		var answer: Dictionary = await s.local_host.request("sandbox", {"action": action})
		error = str(answer.get("error", "")) if answer.get("ok", false) else str(answer.get("error", "Sandbox action failed."))
	else: error = s.sandbox_action(action)
	_status.text = error if error != "" else RemakeText.t("Sandbox action completed.")

func _copy_page() -> void:
	var base := CampaignProfile.save_directory(GameData.campaign_id)
	var files := DirAccess.get_files_at(base) if DirAccess.dir_exists_absolute(base) else PackedStringArray()
	var choices := OptionButton.new()
	choices.custom_minimum_size.y = 44
	for file in files:
		if file.ends_with(".sav") and not file.ends_with(".info.sav"): choices.add_item(file.trim_suffix(".sav"))
	if choices.item_count == 0: choices.free(); return
	_label("Copy a Current defaults save into this profile. The original save is kept.", _body)
	_body.add_child(choices)
	_button("Copy selected save", _body, func(): _status.text = ModStore.copy_default_save(choices.get_item_text(choices.selected)))

func _import() -> void:
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(func(args: Array):
			if args.size() < 2: return
			if str(args[0]) != "ok": _status.text = str(args[1]); return
			var path := "user://mod-import.zip"
			var error := ModStore.atomic_write(path, JavaScriptBridge.js_buffer_to_packed_byte_array(args[1]))
			if error == "": error = ModStore.import_package(path)
			DirAccess.remove_absolute(path)
			_imported(error))
		JavaScriptBridge.eval("""window.CursedModImport={choose:function(cb){const i=document.createElement('input');i.type='file';i.accept='.eimod,.zip';i.onchange=async()=>{try{const f=i.files[0];if(!f)return;if(f.size>134217728){cb('error','Package is too large.');return;}cb('ok',await f.arrayBuffer());}catch(e){cb('error','Could not read package.');}};i.click();}};""", true)
		JavaScriptBridge.get_interface("CursedModImport").choose(_web_callback)
		return
	_modal = FileDialog.new()
	_modal.use_native_dialog = true
	_modal.access = FileDialog.ACCESS_FILESYSTEM
	_modal.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_modal.filters = PackedStringArray(["*.eimod,*.zip ; Cursed Lands mods"])
	add_child(_modal)
	_modal.file_selected.connect(func(path): _imported(ModStore.import_package(path)); _modal.queue_free(); _modal = null)
	_modal.canceled.connect(func(): _modal.queue_free(); _modal = null)
	_modal.popup_centered_ratio(0.85)

func _imported(error: String) -> void:
	_show_page("profiles")
	_status.text = error if error != "" else RemakeText.t("Mod installed. Enable it in a named profile when ready.")

func _input(event: InputEvent) -> void:
	if not visible or is_instance_valid(_modal): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _unhandled_key_input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()

func pad_targets() -> Array:
	return []

func pad_press(action: String, phase: String) -> bool:
	if not visible or is_instance_valid(_modal): return false
	if phase not in ["down", "repeat"]: return true
	var focus := get_viewport().gui_get_focus_owner()
	if action in ["cancel", "menu"]: close(); return true
	if action == "pause": _accept(); return true
	if action in ["up", "down"]:
		var index := _controls.find(focus)
		if not _controls.is_empty(): _controls[posmod(index + (-1 if action == "up" else 1), _controls.size())].grab_focus()
		return true
	if action in ["left", "right"]:
		var direction := -1 if action == "left" else 1
		if focus is OptionButton and not focus.disabled:
			focus.select(posmod(focus.selected + direction, focus.item_count))
			focus.item_selected.emit(focus.selected)
		elif (focus is Slider or focus is SpinBox) and focus.editable: focus.value += direction * focus.step
		return true
	if action == "interact" and focus is BaseButton:
		if not focus.disabled:
			if focus is OptionButton:
				focus.select(posmod(focus.selected + 1, focus.item_count))
				focus.item_selected.emit(focus.selected)
			elif focus.toggle_mode: focus.button_pressed = not focus.button_pressed
			else: focus.pressed.emit()
		return true
	return false
