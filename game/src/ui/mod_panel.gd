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
var _page := "mods"
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
var _download: ModDownload
var _download_progress: ProgressBar
var _download_status: Label

func _ready() -> void:
	build_shell("Mods and rules", Vector2(920, 660))
	_summary = _label("", dialog_body)
	_summary.add_theme_color_override("font_color", MUTED)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 8)
	_tabs.add_theme_constant_override("v_separation", 8)
	dialog_body.add_child(_tabs)
	for page in ["mods", "rules", "profiles", "options", "sandbox"]:
		var button := _button({"mods":"Mods", "profiles":"Profiles", "rules":"Game rules", "options":"Mod options", "sandbox":"Sandbox"}[page], _tabs, func(): _show_page(page))
		button.set_meta("page", page)
		button.toggle_mode = true
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	dialog_body.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)
	_body.minimum_size_changed.connect(_fit_height.call_deferred)
	_status = _label("", dialog_body)
	_status.add_theme_color_override("font_color", GOLD)
	_status.add_theme_font_size_override("font_size", 18)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	dialog_body.add_child(actions)
	_button("Back", actions, close)
	_apply = _button("Apply changes", actions, _apply_current)
	resized.connect(_layout_rows)
	_download = ModDownload.new()
	add_child(_download)
	_download.changed.connect(_download_changed)
	_download.completed.connect(_download_completed)

func _fit_height() -> void:
	var height := minf(660.0, maxf(360.0, _surface.get_combined_minimum_size().y + _body.get_combined_minimum_size().y))
	if absf(_preferred.y - height) < 1.0: return
	_preferred.y = height
	layout_shell()

func _layout_rows() -> void:
	for row in _rows:
		if is_instance_valid(row): row.vertical = _surface.size.x < 700
	layout_shell.call_deferred()

func open(page := "mods") -> void:
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
	_download.cancel()
	visible = false
	closed.emit()

func _label(text: String, parent: Node) -> Label:
	return make_label(text, parent)

func _button(text: String, parent: Node, action: Callable) -> Button:
	return make_button(text, parent, action)

func _show_page(page: String) -> void:
	if page == "downloads": page = "mods"
	_page = page
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_controls.clear()
	_rows.clear()
	_summary.text = "%s · %s · %s: %d%s" % [CampaignChoices.title(GameData.campaign_id), RemakeText.t("Original saves") if ModStore.active_id() == "default" else str(ModStore.effective().name), RemakeText.t("Mods"), ModStore.effective().packages.size(),
		" · " + RemakeText.t("Sandbox saves") if ModStore.effective().get("sandbox", false) else ""]
	for button in _tabs.get_children():
		button.set_pressed_no_signal(button.get_meta("page") == page)
		button.visible = (button.get_meta("page") != "sandbox" or ModStore.effective().get("sandbox", false)) and (button.get_meta("page") != "options" or not ModStore.option_definitions().is_empty())
	_apply.visible = page in ["mods", "rules", "options", "sandbox"]
	_apply.text = RemakeText.t("Apply & restart" if page == "mods" else "Apply changes")
	_apply.disabled = false
	match page:
		"profiles": _profiles_page()
		"mods": _mods_page()
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

func _process(_dt: float) -> void:
	if not visible: return
	_status.visible = not _status.text.is_empty()
	if _page == "mods":
		_apply.disabled = _download.busy or ModStore.session() != null or _packages == ModStore.profile().packages

func _apply_current() -> void:
	if _page != "mods":
		_accept()
		return
	var error := _save_packages()
	if error != "": _status.text = RemakeText.t(error)
	else: ModStore.restart(get_tree())

## Validate before creating anything; failed selections cannot switch profiles.
func _save_packages() -> String:
	var profile := ModStore.profile().duplicate(true)
	profile.packages = _packages
	var error: String = ModStore.resolve(profile).error
	if error != "": return error
	if ModStore.active_id() == "default":
		return ModStore.create_profile(RemakeText.t("Modded game"), false, _packages)
	return ModStore.set_packages(_packages)

func _row(parent: Node) -> BoxContainer:
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_rows.append(row)
	return row

func _profiles_page() -> void:
	if _download.busy:
		_label("Finish or cancel the download before changing profiles.", _body)
		_button("Show download", _body, func(): _show_page("mods"))
		return
	if ModStore.session() != null:
		_label("Return to the main menu to change profiles or installed packages. Game rules and mod options remain available here.", _body)
		return
	make_label("Profiles have separate saves and enabled mods. Switching profiles restarts the game.", _body, true)
	var selection := _row(_body)
	_chooser = OptionButton.new()
	_chooser.custom_minimum_size = Vector2(180, 44)
	_chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chooser.fit_to_longest_item = false
	selection.add_child(_chooser)
	_chooser.add_item(RemakeText.t("Original saves"))
	_chooser.set_item_metadata(0, "default")
	for id in ModStore.profiles:
		_chooser.add_item(str(ModStore.profiles[id].name))
		_chooser.set_item_metadata(_chooser.item_count - 1, id)
		if id == ModStore.active_id(): _chooser.select(_chooser.item_count - 1)
	var use := _button("Switch & restart", selection, func():
		var error := ModStore.select_profile(_pending_profile)
		if error != "": _status.text = RemakeText.t(error)
		else: ModStore.restart(get_tree()))
	use.disabled = true
	_chooser.item_selected.connect(func(index):
		_pending_profile = str(_chooser.get_item_metadata(index))
		use.disabled = _pending_profile == ModStore.active_id())
	var create := _row(_body)
	_profile_name = LineEdit.new()
	_profile_name.placeholder_text = RemakeText.t("Name for a new profile")
	_profile_name.max_length = 80
	_profile_name.custom_minimum_size = Vector2(180, 44)
	_profile_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.add_child(_profile_name)
	_button("Create profile", create, func(): _create(false))
	var advanced := HFlowContainer.new()
	_body.add_child(advanced)
	_button("Create sandbox profile", advanced, func(): _create(true))
	make_label("Sandbox profiles allow cheats and keep their saves separate.", _body, true)
	if ModStore.active_id() != "default": _copy_page()

func _mods_page() -> void:
	var running := ModStore.session() != null
	if running:
		make_label("Return to the main menu to install or enable mods.", _body, true)
	elif ModStore.active_id() == "default":
		make_label("Enabling mods creates a separate game profile. Your existing saves stay unchanged.", _body, true)
	else:
		make_label("Choose mods for this profile, then apply and restart.", _body, true)
	if _download.busy:
		var progress_card := card(_body)
		_label(str(_download.item.title), progress_card)
		_download_status = _label("", progress_card)
		_download_progress = ProgressBar.new()
		_download_progress.custom_minimum_size.y = 24
		progress_card.add_child(_download_progress)
		_button("Cancel download", progress_card, _download.cancel)
		_download_changed()
	var keys := ModStore.catalog.keys()
	keys.sort()
	for key in keys:
		var m: Dictionary = ModStore.catalog[key]
		var section := card(_body)
		var row := _row(section)
		var title := _label("%s  %s" % [RemakeText.t(m.title), m.version], row)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var toggle := CheckButton.new()
		toggle.custom_minimum_size = Vector2(130, 44)
		toggle.set_pressed_no_signal(key in _packages)
		toggle.text = RemakeText.t("On" if toggle.button_pressed else "Off")
		toggle.tooltip_text = RemakeText.t(m.title)
		toggle.disabled = running or _download.busy or GameData.campaign_id not in m.campaigns
		row.add_child(toggle)
		toggle.toggled.connect(func(on):
			if on and key not in _packages: _packages.append(key)
			elif not on: _packages.erase(key)
			toggle.text = RemakeText.t("On" if on else "Off"))
		make_label(str(m.get("description", "")), section, true)
		if GameData.campaign_id not in m.campaigns:
			make_label("This mod is for a different campaign.", section, true)
		# Show relevant relationships with readable titles. A conflict with a
		# legacy package that is not even installed is not an error message.
		for relation in ["requires", "conflicts"]:
			var titles := PackedStringArray()
			for id in m.get(relation, []):
				var found := false
				for other in ModStore.catalog.values():
					if other.id == id:
						titles.append(RemakeText.t(other.title)); found = true; break
				if not found and relation == "requires": titles.append(id)
			if not titles.is_empty():
				make_label(RemakeText.t("Requires: %s" if relation == "requires" else "Cannot use together with: %s") % ", ".join(titles), section, true)
	if not running:
		for item in ModCatalog.ENTRIES:
			if ModStore.catalog.has(ModCatalog.key(item)): continue
			var section := card(_body)
			_label(RemakeText.t(item.title) + "  " + item.version, section)
			make_label(item.description, section, true)
			var actions := HFlowContainer.new()
			actions.add_theme_constant_override("h_separation", 12)
			section.add_child(actions)
			var error := ModCatalog.unavailable(item)
			var button := _button("Download & install", actions, func(): _start_download(item.id))
			button.disabled = _download.busy or not error.is_empty()
			_button("Source page", actions, func(): OS.shell_open(item.source))
			if not error.is_empty(): make_label(error, section, true)
			make_label(RemakeText.t("By %s · Download %s · Allow %s free space") % [item.author, String.humanize_size(item.bytes), String.humanize_size(item.space_bytes)], section, true)
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 12)
		_body.add_child(actions)
		_button("Import mod package…", actions, _import).disabled = _download.busy
		if not OS.has_feature("web") and not Portability.constrained():
			_button("Open mods folder", actions, func():
				DirAccess.make_dir_recursive_absolute(ModStore.ROOT)
				OS.shell_open(ProjectSettings.globalize_path(ModStore.ROOT)))
	for problem in ModStore.errors: _label(problem, _body)

func _start_download(id: String) -> void:
	var error := _download.start(id)
	_status.text = RemakeText.t(error)
	_show_page("downloads")

func _download_changed() -> void:
	if not _download.busy or _page != "mods": return
	if is_instance_valid(_download_status): _download_status.text = RemakeText.t(_download.status)
	if is_instance_valid(_download_progress): _download_progress.value = _download.fraction * 100.0

func _download_completed(_error: String) -> void:
	if visible:
		_show_page(_page)
		_status.text = RemakeText.t(_download.status if _error != "" else "Installed. Turn the mod on, then apply and restart.")

func _create(sandbox: bool) -> void:
	var error := ModStore.create_profile(_profile_name.text, sandbox)
	if error != "": _status.text = RemakeText.t(error)
	else:
		if not draft.is_empty(): draft.merge(ModStore.new_game_defaults(), true)
		open("profiles")
		_status.text = RemakeText.t("Profile created. Start a new game or copy an existing save below.")

func _rules_page(sandbox: bool) -> void:
	_label("Choose the rules for this game. Changes stay in setup until you start." if not draft.is_empty() else "Adjust this run. Rules marked At camp can only change in a village.", _body)
	if sandbox: _label("Sandbox saves stay separate. Turning a cheat off does not undo rewards already earned.", _body)
	var groups := {"Campaign": ["difficulty", "unit_fog", "start_zones", "mechanism_motion", "distant_ai", "auto_exit"],
		"Party": ["sp_full_xp", "revive", "merc_travel", "free_run", "stamina_regen", "armor_formula"],
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
			if key in ["stamina_regen", "armor_formula"]:
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
		_label("No enabled mods provide configurable options.", _body)
		return
	for o in definitions:
		var section := card(_body)
		_label(RemakeText.t(o.mod_title) + " · " + RemakeText.t(o.label), section)
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
	if error != "": _status.text = RemakeText.t(error); return false
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
	_status.text = RemakeText.t(error) if error != "" else RemakeText.t("Changes sent to the host." if pending else "Settings applied.")
	return error == ""

func _applied(problem: String) -> void:
	if not visible: return
	if problem == "": open(_page)
	_status.text = RemakeText.t(problem) if problem != "" else RemakeText.t("Settings applied.")

func _sandbox(action: String) -> void:
	var s := ModStore.session()
	if s == null: return
	var error := ""
	if s.local_host.frontend:
		var answer: Dictionary = await s.local_host.request("sandbox", {"action": action})
		error = str(answer.get("error", "")) if answer.get("ok", false) else str(answer.get("error", "Sandbox action failed."))
	else: error = s.sandbox_action(action)
	_status.text = RemakeText.t(error) if error != "" else RemakeText.t("Sandbox action completed.")

func _copy_page() -> void:
	var base := CampaignProfile.save_directory(GameData.campaign_id)
	var files := DirAccess.get_files_at(base) if DirAccess.dir_exists_absolute(base) else PackedStringArray()
	var choices := OptionButton.new()
	choices.custom_minimum_size.y = 44
	for file in files:
		if file.ends_with(".sav") and not file.ends_with(".info.sav"): choices.add_item(file.trim_suffix(".sav"))
	if choices.item_count == 0: choices.free(); return
	_label("Copy a save from the original profile. The original is kept.", _body)
	_body.add_child(choices)
	_button("Copy selected save", _body, func(): _status.text = RemakeText.t(ModStore.copy_default_save(choices.get_item_text(choices.selected))))

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
	_show_page("mods")
	_status.text = RemakeText.t(error) if error != "" else RemakeText.t("Installed. Turn the mod on, then apply and restart.")

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
	if action == "pause":
		if _apply.visible and not _apply.disabled: _apply_current()
		return true
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
