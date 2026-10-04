extends Control
## First-run screen: the player points the remake at their own Evil Islands,
## either an installed game folder or the GOG installer (setup_*.original), whose
## files are unpacked once into the user data folder (EIInnoSetup), or a
## private .eipack (PrivateDataImport, as on Android / web).
## Remake: Options › Remake › "Game files…" shows it again
## (`back_text` set): the current files on top and a button back to where
## it came from (`cancelled`); the old files stay in use until the new ones
## pass DataSwitch.switch_to, and an installer is unpacked into a new folder
## that is removed again when the import fails or is cancelled.

signal opened
signal cancelled

## Re-import from the options: the label of the button that goes back.
var back_text := ""

var _path: LineEdit
var _status: Label
var _dialog: FileDialog
var _exe: LineEdit
var _exe_dialog: FileDialog
var _bar: ProgressBar
var _buttons: Array = []
var _setup: EIInnoSetup
var _dest := ""
var _cancel: Button
var _cancelled := false
var _pack: PrivateDataImport


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = RemakeText.t("Evil Islands - Remake")
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = RemakeText.t("This remake uses the data files of your own copy of Evil Islands (GOG / original CD). Select the game's install folder - the one containing game.exe, res/ and maps/ - or the GOG installer (setup_evil_islands_*.exe) to unpack its files once.") + "\n" + RemakeText.t("A private data pack (.eipack) also works.")
	box.add_child(info)
	if back_text:
		var current := Label.new()
		current.name = "Current"
		current.autowrap_mode = TextServer.AUTOWRAP_WORD
		current.modulate = Color(0.75, 0.85, 0.95)
		current.text = RemakeText.t("Current game files: %s") % DataSwitch.describe()
		box.add_child(current)

	var row := HBoxContainer.new()
	box.add_child(row)
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = RemakeText.t("/path/to/Evil Islands")
	_path.text = GameData.root
	row.add_child(_path)
	var browse := Button.new()
	browse.text = RemakeText.t("Browse...")
	browse.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
	row.add_child(browse)

	var go := Button.new()
	go.text = RemakeText.t("Use this folder")
	go.pressed.connect(_try_open)
	box.add_child(go)
	_buttons += [browse, go]

	var or_label := Label.new()
	or_label.text = RemakeText.t("- or -")
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(or_label)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	_exe = LineEdit.new()
	_exe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exe.placeholder_text = RemakeText.t("/path/to/setup_evil_islands_2.0.0.5.exe or .eipack")
	row2.add_child(_exe)
	var browse_exe := Button.new()
	browse_exe.text = RemakeText.t("Browse...")
	browse_exe.pressed.connect(func(): _exe_dialog.popup_centered_ratio(0.7))
	row2.add_child(browse_exe)
	var imp := Button.new()
	imp.text = RemakeText.t("Import from installer or data pack")
	imp.pressed.connect(_try_import)
	box.add_child(imp)
	_buttons += [browse_exe, imp]
	_bar = ProgressBar.new()
	_bar.visible = false
	box.add_child(_bar)
	_cancel = Button.new()
	_cancel.text = RemakeText.t("Cancel import")
	_cancel.visible = false
	_cancel.pressed.connect(func():
		if _setup:
			_cancelled = true
			_setup.cancel()
		if _pack and _pack.busy:
			_pack.cancelled = true)
	box.add_child(_cancel)
	if back_text:
		var back := Button.new()
		back.name = "Back"
		back.text = back_text
		back.pressed.connect(func(): cancelled.emit())
		box.add_child(back)
		_buttons.append(back)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.modulate = Color(1, 0.6, 0.5)
	box.add_child(_status)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.dir_selected.connect(func(d: String): _path.text = d; _try_open())
	add_child(_dialog)
	_exe_dialog = FileDialog.new()
	_exe_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_exe_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_exe_dialog.use_native_dialog = true
	_exe_dialog.filters = PackedStringArray(["*.exe,*.eipack ; " + RemakeText.t("Evil Islands installer or data pack")])
	_exe_dialog.file_selected.connect(func(f: String): _exe.text = f; _try_import())
	add_child(_exe_dialog)
	set_process(false)


func _try_open() -> void:
	var err := DataSwitch.switch_to(_path.text.strip_edges())
	_status.text = err
	if err.is_empty():
		opened.emit()


## Unpacks the installer into a new folder in the user data folder
## ("game-<n>", DataSwitch.new_import_dir), then opens it.
func _try_import() -> void:
	var file := _exe.text.strip_edges()
	var head := FileAccess.open(file, FileAccess.READ)
	if head and head.get_length() >= 8 and head.get_buffer(8).get_string_from_ascii() == "EIPACK01":
		head.close()
		_import_pack(file)
		return
	head = null
	_setup = EIInnoSetup.open(file)
	if _setup.error:
		_status.text = _setup.error
		_setup = null
		return
	_dest = DataSwitch.new_import_dir()
	_cancelled = false
	_status.modulate = Color(0.85, 0.85, 0.8)
	_status.text = RemakeText.t("Unpacking %d files into %s ... (a few minutes, once)") % [_setup.files.size(), _dest]
	for b: Button in _buttons:
		b.disabled = true
	_bar.visible = true
	_bar.value = 0
	_cancel.visible = true
	_setup.extract(_dest)
	set_process(true)


func _process(_dt: float) -> void:
	if _setup == null:
		return
	_bar.value = _setup.progress() * 100.0
	if not _setup.finished():
		return
	set_process(false)
	var err := _setup.failure()
	if _cancelled:
		err = RemakeText.t("Import cancelled.")
	_setup = null
	_bar.visible = false
	_cancel.visible = false
	for b: Button in _buttons:
		b.disabled = false
	_status.modulate = Color(1, 0.6, 0.5)
	if err.is_empty():
		err = DataSwitch.switch_to(_dest)
	if err:
		_status.text = err
		DataSwitch.discard(_dest)   # the old files stay as they were
		return
	_path.text = _dest
	opened.emit()


## A private .eipack: unpacked by PrivateDataImport into its own managed
## "import-<n>" folder, which is removed again when it fails or is cancelled.
func _import_pack(file: String) -> void:
	if _pack == null:
		_pack = PrivateDataImport.new()
		add_child(_pack)
		_pack.progress.connect(func(t: String): _status.text = t)
		_pack.failed.connect(func(message: String): _pack_done("", RemakeText.t(message)))
		_pack.completed.connect(func(folder: String): _pack_done(folder, ""))
	_status.modulate = Color(0.85, 0.85, 0.8)
	_status.text = RemakeText.t("Importing %s") % file.get_file()
	for b: Button in _buttons:
		b.disabled = true
	_cancel.visible = true
	_pack.import_file(file)


func _pack_done(folder: String, err: String) -> void:
	_cancel.visible = false
	for b: Button in _buttons:
		b.disabled = false
	_status.modulate = Color(1, 0.6, 0.5)
	if err.is_empty():
		err = DataSwitch.switch_to(folder)
		if err:
			DataSwitch.discard(folder)   # the old files stay as they were
	if err:
		_status.text = err
		return
	_path.text = folder
	opened.emit()


func _exit_tree() -> void:
	if _setup:
		_setup.cancel()
		while not _setup.finished():
			OS.delay_msec(50)
		_setup = null
		DataSwitch.discard(_dest)
