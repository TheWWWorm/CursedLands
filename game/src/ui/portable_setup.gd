extends Control
signal opened
var _status: Label
var _buttons: Array[Button] = []
var _cancel: Button
var _import: PrivateDataImport
var _callback: JavaScriptObject
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.07, 0.05)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Cursed Lands" # l10n: ignore (application name)
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = RemakeText.t("Import the data from your own copy of Evil Islands. Your files stay on this device.")
	info.text += "\n" + (RemakeText.t("Choose the extracted game folder, or a private .eipack made with prepare_game_data.py on your computer.") if OS.has_feature("web") else RemakeText.t("Choose your GOG installer (.exe) or a private .eipack. The installer is unpacked without running it."))
	box.add_child(info)
	_import = PrivateDataImport.new()
	add_child(_import)
	_import.progress.connect(func(message): _status.text = message)
	_import.failed.connect(func(message): _busy(false); _status.text = RemakeText.t(message))
	_import.completed.connect(_open)
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_browser_result)
		_add(box, "Choose data pack…", func(): _choose_web(false))
		_add(box, "Choose game folder…", func(): _choose_web(true))
	else:
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.use_native_dialog = true
		dialog.filters = PackedStringArray(["*.exe,*.eipack ; " + RemakeText.t("Evil Islands installer or data pack")])
		dialog.file_selected.connect(func(path): _busy(true); _import.import_file(path))
		add_child(dialog)
		_add(box, "Choose installer / data pack…", func(): dialog.popup_centered_ratio(0.8))
	_cancel = Button.new()
	_cancel.text = RemakeText.t("Cancel import")
	_cancel.custom_minimum_size.y = 48
	_cancel.hide()
	_cancel.pressed.connect(func():
		_import.cancelled = true
		if OS.has_feature("web"): JavaScriptBridge.get_interface("CursedFiles").cancel())
	box.add_child(_cancel)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	if OS.has_feature("web") and not OS.is_userfs_persistent():
		_status.text = RemakeText.t("Save storage is unavailable. Allow browser storage before playing.")
	_layout()
	resized.connect(_layout)

func _layout() -> void:
	var safe := Portability.safe_rect(size)
	_scroll.offset_left = 28 + safe.position.x
	_scroll.offset_right = -28 - (size.x - safe.end.x)
	_scroll.offset_top = 20 + safe.position.y
	_scroll.offset_bottom = -20 - (size.y - safe.end.y)
	var target := TouchInput.target_pixels()
	for button in _buttons: button.custom_minimum_size.y = target
	_cancel.custom_minimum_size.y = target

func _add(box: VBoxContainer, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = RemakeText.t(title)
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	box.add_child(button)
	_buttons.append(button)

func _busy(value: bool) -> void:
	for button in _buttons: button.disabled = value
	_cancel.visible = value

func _choose_web(folder: bool) -> void:
	JavaScriptBridge.get_interface("CursedFiles").choose(_callback, folder)

func _browser_result(args: Array) -> void:
	if args.size() < 2:
		return
	_status.text = str(args[1])
	_busy(str(args[0]) == "progress")
	if str(args[0]) == "complete":
		GameFiles.initialize()
		_open(GameFiles.WEB_ROOT)

func _open(folder: String) -> void:
	_status.text = RemakeText.t("Opening game data…")
	var error := GameData.open(folder)
	if error:
		_busy(false)
		_status.text = RemakeText.t(error)
	else:
		opened.emit()
