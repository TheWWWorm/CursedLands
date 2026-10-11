class_name ModPanel
extends SettingsDialog
## Generated controls share the game's font/plate style and work with focus,
## touch and PadUI. Package changes are explicit restart transactions.
signal closed
var _body: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _summary: Label
var _tabs: HFlowContainer
var _apply: Button
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
var draft: Dictionary = {}
var _rows: Array[BoxContainer] = []

func _ready() -> void:
	build_shell("Mods and rules", Vector2(980, 740))
	_summary = _label("", dialog_body)
	_summary.add_theme_color_override("font_color", MUTED)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 8)
	_tabs.add_theme_constant_override("v_separation", 8)
	dialog_body.add_child(_tabs)
	for page in ["rules", "profiles", "options", "sandbox"]:
		var button := _button({"profiles":"Profiles & mods", "rules":"Game rules", "options":"Mod options", "sandbox":"Sandbox"}[page], _tabs, func(): _show_page(page))
		button.set_meta("page", page)
		button.toggle_mode = true
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	dialog_body.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_scroll.add_child(_body)
	_status = _label("", dialog_body)
	_status.add_theme_color_override("font_color", GOLD)
	_status.custom_minimum_size.y = 28
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	dialog_body.add_child(actions)
	_button("Back", actions, close)
	_apply = _button("Apply changes", actions, _accept)
	resized.connect(_layout_rows)

func _layout_rows() -> void:
	for row in _rows:
		if is_instance_valid(row): row.vertical = _surface.size.x < 700
	layout_shell.call_deferred()

func open(page := "rules") -> void:
	capture_background()
	visible = true
	var s := ModStore.session()
	if s != null and not s.mod_rules_result.is_connected(_applied): s.mod_rules_result.connect(_applied)
	var config := ModStore.effective()
	_rules = draft.get("rules", config.rules).duplicate(true)
	_values = draft.get("values", config.values).duplicate(true)
	_base_rules = _rules.duplicate(true)
	_base_values = _values.duplicate(true)
	_base_revision = int(config.revision)
	_status.text = ""
	_packages = ModStore.profile().packages.duplicate()
	_pending_profile = ModStore.active_id()
	_show_page(page)
	if ModStore.startup_error != "": _status.text = ModStore.startup_error

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()

func _label(text: String, parent: Node) -> Label:
	return make_label(text, parent)

func _button(text: String, parent: Node, action: Callable) -> Button:
	return make_button(text, parent, action)

func _show_page(page: String) -> void:
	_page = page
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_controls.clear()
	_rows.clear()
	_summary.text = "%s · %s · %s: %d%s" % [CampaignChoices.title(GameData.campaign_id), RemakeText.t(str(ModStore.effective().name)), RemakeText.t("Mods"), ModStore.effective().packages.size(),
		" · " + RemakeText.t("Sandbox saves") if ModStore.effective().get("sandbox", false) else ""]
	for button in _tabs.get_children():
		button.set_pressed_no_signal(button.get_meta("page") == page)
		button.visible = button.get_meta("page") != "sandbox" or ModStore.effective().get("sandbox", false)
	_apply.visible = page in ["rules", "options"]
	match page:
		"profiles": _profiles_page()
		"rules": _rules_page(false)
		"options": _options_page()
		"sandbox": _rules_page(true)
	_layout_rows()
	_collect_controls(self)
	_scroll.scroll_vertical = 0
	for button in _tabs.get_children():
		if button.get_meta("page") == page: button.grab_focus.call_deferred()

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
	var create := HFlowContainer.new()
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
		var section := card(_body)
		section.add_child(row)
		row.toggled.connect(func(on):
			if on: _packages.append(key)
			else: _packages.erase(key))
		_label(str(m.get("description", "")), section)
		var campaigns := PackedStringArray()
		for id in m.campaigns: campaigns.append(CampaignChoices.title(id))
		_label(RemakeText.t("Shared gameplay" if ModSchema.gameplay(m) else "Your device") + " · " + ", ".join(campaigns), section)
		for relation in ["requires", "after", "conflicts"]:
			if not m.get(relation, []).is_empty(): _label(relation.capitalize() + ": " + ", ".join(m[relation]), section)
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
		if not draft.is_empty(): draft.merge(ModStore.new_game_defaults(), true)
		open("profiles")
		_status.text = RemakeText.t("Profile created. Start a new game or copy an existing save below.")

func _rules_page(sandbox: bool) -> void:
	_label("Choose the rules for this game. Changes stay in setup until you start." if not draft.is_empty() else "Adjust this run. Rules marked At camp can only change in a village.", _body)
	if sandbox: _label("Sandbox saves stay separate. Turning a cheat off does not undo rewards already earned.", _body)
	var groups := {"Campaign": ["difficulty", "unit_fog", "start_zones", "mechanism_motion", "distant_ai", "auto_exit"],
		"Party": ["sp_full_xp", "revive", "merc_travel", "free_run", "stamina_regen"],
		"Co-op": ["coop_full_xp", "coop_scale", "coop_share_loot", "coop_clock"]}
	if sandbox: groups = {"Sandbox": ["sandbox_invulnerable", "sandbox_mana"]}
	for group in groups:
		var section := card(_body)
		var heading := _label(group, section)
		heading.add_theme_color_override("font_color", GOLD)
		for key in groups[group]:
			var definition: Array = ModSchema.RULES[key]
			var row := BoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			section.add_child(row)
			_rows.append(row)
			var text := VBoxContainer.new()
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text)
			_label(definition[0], text)
			if key == "stamina_regen":
				_label(GameData.REMAKE_OPTIONS[key][1], text)
			var locked := ModStore.editable(key)
			var help: String = locked if locked != "" else {"camp":"At camp", "live":"Any time", "new_game":"Before starting"}[definition[2]]
			var note := _label(help, text)
			note.add_theme_color_override("font_color", MUTED)
			note.add_theme_font_size_override("font_size", 16)
			var choice := OptionButton.new()
			choice.custom_minimum_size = Vector2(220, 46)
			choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			choice.size_flags_horizontal = Control.SIZE_FILL
			choice.fit_to_longest_item = false
			for label in definition[1]: choice.add_item(RemakeText.t(label))
			choice.select(int(_rules.get(key, 0)))
			choice.disabled = locked != ""
			choice.item_selected.connect(func(index): _rules[key] = index)
			row.add_child(choice)
	if sandbox:
		_apply.visible = true
		for action in ["heal", "gold"]:
			var button := _button("Heal living party" if action == "heal" else "Give 1,000 gold", _body, func(): _sandbox(action))
			button.disabled = ModStore.session() == null or not ModStore.session().can_manage_game()
	else:
		_button("Restore default rules", _body, func():
			for key in ModStore.new_game_defaults().rules:
				if ModStore.editable(key) == "": _rules[key] = ModStore.new_game_defaults().rules[key]
			_show_page("rules"))

func _options_page() -> void:
	var definitions := ModStore.option_definitions()
	if definitions.is_empty():
		_label("No enabled mods provide configurable options. Use Profiles and mods to enable an installed package.", _body)
		return
	for o in definitions:
		var section := card(_body)
		_label(o.mod_title + " · " + o.label, section)
		make_label(o.get("help", ""), section, true)
		var row := HBoxContainer.new()
		section.add_child(row)
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
		var reset := _button(RemakeText.t("Reset to %s") % str(o.default), section, func():
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
	if not draft.is_empty():
		draft.rules = _rules.duplicate(true)
		draft.values = _values.duplicate(true)
		_base_rules = _rules.duplicate(true)
		_base_values = _values.duplicate(true)
		_status.text = RemakeText.t("Changes kept for this game. Back returns to setup.")
		return true
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
