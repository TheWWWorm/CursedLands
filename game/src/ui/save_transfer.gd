class_name SaveTransfer
extends HBoxContainer
## Backups contain engine saves only, never installation files. Imports use
## new slot names so a backup cannot overwrite the player's existing saves.
signal imported
var _callback: JavaScriptObject
var _status: AcceptDialog
var _export_text := ""
const LIMIT := 67108864

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -310
	offset_right = -12
	offset_top = 8
	var export_button := Button.new()
	export_button.text = RemakeText.t("Export saves")
	export_button.custom_minimum_size.y = 44
	export_button.pressed.connect(_export)
	add_child(export_button)
	var import_button := Button.new()
	import_button.text = RemakeText.t("Import saves")
	import_button.custom_minimum_size.y = 44
	import_button.pressed.connect(_import)
	add_child(import_button)
	_status = AcceptDialog.new()
	add_child(_status)
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(func(args: Array):
			if args.size() >= 2:
				_notice(restore(str(args[1])) if str(args[0]) == "complete" else str(args[1])))

func _process(_dt: float) -> void:
	if not is_visible_in_tree() or not TouchInput.enabled:
		return
	var parent := get_parent() as Control
	var safe := Rect2(Vector2.ZERO, parent.size) if get_canvas_layer_node() is GameHUD else Portability.safe_rect(parent.size)
	var target := TouchInput.target_pixels()
	offset_right = -(parent.size.x - safe.end.x) - 12
	offset_left = offset_right - target * 5.8
	offset_top = safe.position.y + 8
	for child in get_children():
		if child is Button:
			child.custom_minimum_size.y = target
			child.add_theme_font_size_override("font_size", maxi(14, int(target / 3)))

static func backup() -> String:
	var files := {}
	for file in DirAccess.get_files_at(SaveInfo.DIR):
		if _valid_name(file):
			files[file] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(SaveInfo.DIR.path_join(file)))
	return JSON.stringify({"format": "cursed-lands-saves", "version": 1, "files": files})

static func _valid_name(name: String) -> bool:
	if name.length() > 96 or name.contains("/") or name.contains("\\") or name.contains(":") or name.contains(".."):
		return false
	return name.ends_with(".sav") or name.ends_with(".shot.png")

func restore(text: String) -> String:
	if text.to_utf8_buffer().size() > LIMIT:
		return "Save backup is too large."
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or data.get("format") != "cursed-lands-saves" or data.get("version") != 1 or not data.get("files") is Dictionary:
		return "This is not a Cursed Lands save backup."
	var files: Dictionary = data.files
	if files.size() > 1000:
		return "Too many saves in the backup."
	var decoded := {}
	var total := 0
	var base64 := RegEx.create_from_string("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")
	for name: Variant in files:
		if not name is String or not _valid_name(name) or not files[name] is String:
			return "Invalid file in the save backup."
		if base64.search(files[name]) == null:
			return "Damaged save backup."
		var bytes := Marshalls.base64_to_raw(files[name])
		if bytes.is_empty() or Marshalls.raw_to_base64(bytes) != files[name]:
			return "Damaged save backup."
		total += bytes.size()
		if total > LIMIT:
			return "Save backup is too large."
		decoded[name] = bytes
	var prefix := "import_%d_" % Time.get_unix_time_from_system()
	var count := 0
	DirAccess.make_dir_recursive_absolute(SaveInfo.DIR)
	var written := PackedStringArray()
	# Preflight every destination before writing any member of the backup.
	for name: String in decoded:
		if FileAccess.file_exists(SaveInfo.DIR.path_join(prefix + name)):
			return "These saves were just imported. Try again in a moment."
	for name: String in decoded:
		var dest := SaveInfo.DIR.path_join(prefix + name)
		var file := FileAccess.open(dest, FileAccess.WRITE)
		if file == null:
			for path in written: DirAccess.remove_absolute(path)
			return "Could not write saves. Check free storage."
		file.store_buffer(decoded[name])
		var error := file.get_error()
		file.close()
		written.append(dest)
		if error != OK:
			for path in written: DirAccess.remove_absolute(path)
			return "Could not write saves. Check free storage."
		if name.ends_with(".sav") and not name.ends_with(".info.sav"):
			count += 1
	imported.emit()
	return RemakeText.t("%d saves imported into new slots.") % count

func _export() -> void:
	_export_text = backup()
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("CursedFiles").download("cursed-lands.eisaves", _export_text)
	else:
		var dialog := _dialog(FileDialog.FILE_MODE_SAVE_FILE)
		dialog.current_file = "cursed-lands.eisaves"
		dialog.file_selected.connect(func(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_string(_export_text)
				_notice("Saves exported." if file.get_error() == OK else "Could not export saves.")
			else: _notice("Could not open the chosen document."))
		dialog.popup_centered_ratio(0.8)

func _import() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("CursedFiles").chooseSave(_callback)
	else:
		var dialog := _dialog(FileDialog.FILE_MODE_OPEN_FILE)
		dialog.file_selected.connect(func(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > LIMIT:
				_notice("The backup cannot be read or is too large.")
			else: _notice(restore(file.get_as_text())))
		dialog.popup_centered_ratio(0.8)

func _dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.eisaves ; " + RemakeText.t("Cursed Lands saves")])
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(_path): dialog.queue_free())
	add_child(dialog)
	return dialog

func _notice(message: String) -> void:
	_status.dialog_text = RemakeText.t(message)
	_status.popup_centered()
