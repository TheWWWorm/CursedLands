extends Control
## First-run screen: the player points the remake at their own Evil Islands,
## either an installed game folder or the GOG installer (setup_*.original), whose
## files are unpacked once into the user data folder (EIInnoSetup).

signal opened

var _path: LineEdit
var _status: Label
var _dialog: FileDialog
var _exe: LineEdit
var _exe_dialog: FileDialog
var _bar: ProgressBar
var _buttons: Array = []
var _setup: EIInnoSetup
var _dest := ""


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
	title.text = "Evil Islands - Remake"
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = "This remake uses the data files of your own copy of Evil Islands (GOG / original CD). Select the game's install folder - the one containing game.exe, res/ and maps/ - or the GOG installer (setup_evil_islands_*.exe) to unpack its files once."
	box.add_child(info)

	var row := HBoxContainer.new()
	box.add_child(row)
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = "/path/to/Evil Islands"
	_path.text = GameData.root
	row.add_child(_path)
	var browse := Button.new()
	browse.text = "Browse..."
	browse.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
	row.add_child(browse)

	var go := Button.new()
	go.text = "Use this folder"
	go.pressed.connect(_try_open)
	box.add_child(go)
	_buttons += [browse, go]

	var or_label := Label.new()
	or_label.text = "- or -"
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(or_label)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	_exe = LineEdit.new()
	_exe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exe.placeholder_text = "/path/to/setup_evil_islands_2.0.0.5.exe"
	row2.add_child(_exe)
	var browse_exe := Button.new()
	browse_exe.text = "Browse..."
	browse_exe.pressed.connect(func(): _exe_dialog.popup_centered_ratio(0.7))
	row2.add_child(browse_exe)
	var imp := Button.new()
	imp.text = "Import from installer"
	imp.pressed.connect(_try_import)
	box.add_child(imp)
	_buttons += [browse_exe, imp]
	_bar = ProgressBar.new()
	_bar.visible = false
	box.add_child(_bar)
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
	_exe_dialog.filters = PackedStringArray(["*.exe ; Installer"])
	_exe_dialog.file_selected.connect(func(f: String): _exe.text = f; _try_import())
	add_child(_exe_dialog)
	set_process(false)


func _try_open() -> void:
	var err := GameData.open(_path.text.strip_edges())
	_status.text = err
	if err.is_empty():
		opened.emit()


## Unpacks the installer into the user data folder ("game"), then opens it.
func _try_import() -> void:
	var file := _exe.text.strip_edges()
	_setup = EIInnoSetup.open(file)
	if _setup.error:
		_status.text = _setup.error
		_setup = null
		return
	_dest = OS.get_user_data_dir().path_join("game")
	_status.modulate = Color(0.85, 0.85, 0.8)
	_status.text = "Unpacking %d files into %s ... (a few minutes, once)" % [_setup.files.size(), _dest]
	for b: Button in _buttons:
		b.disabled = true
	_bar.visible = true
	_bar.value = 0
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
	_setup = null
	_bar.visible = false
	for b: Button in _buttons:
		b.disabled = false
	_status.modulate = Color(1, 0.6, 0.5)
	if err:
		_status.text = err
		return
	_path.text = _dest
	_try_open()


func _exit_tree() -> void:
	if _setup:
		_setup.cancel()
		while not _setup.finished():
			OS.delay_msec(50)
