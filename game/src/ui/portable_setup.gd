extends Control
## First-run screen on Android / web: the player's own game data is imported
## into the app's storage (PrivateDataImport, web/files.js).
## Remake: Options › Remake › "Game files…" shows it again
## (`back_text` set) with the current data, a button back (`cancelled`) and
## "Delete imported data" (confirmed in a message box). A new import is
## staged apart from the current data (user://import-<n>, a new IndexedDB
## generation on the web) and replaces it only through DataSwitch.switch_to.
signal opened
signal cancelled
signal deleted
## Re-import from the options: the label of the button that goes back.
var back_text := ""
var selected_campaign := ""
var _choices: CampaignChoices
var _play: Button
var _iso_button: Button
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
	_choices = CampaignChoices.new()
	if selected_campaign.is_empty():
		selected_campaign = GameData.campaign_id
	_choices.current = selected_campaign
	_choices.selected.connect(_choose_campaign)
	box.add_child(_choices)
	_play = Button.new()
	_play.text = RemakeText.t("Play selected game")
	_play.custom_minimum_size.y = 48
	_play.pressed.connect(func(): _open(DataSwitch.installed(selected_campaign)))
	box.add_child(_play)
	_buttons.append(_play)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = RemakeText.t("Import the data from your own copy of Evil Islands. Your files stay on this device.")
	info.text += "\n" + (RemakeText.t("Choose your GOG installer (setup_evil_islands_*.exe): the browser unpacks it without running it. The installed game folder or a private .eipack also work.") if OS.has_feature("web") else RemakeText.t("Choose your GOG installer (.exe) or a private .eipack. The installer is unpacked without running it."))
	box.add_child(info)
	if back_text:
		var current := Label.new()
		current.name = "Current"
		current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		current.modulate = Color(0.75, 0.85, 0.95)
		current.text = RemakeText.t("Current game files: %s") % DataSwitch.describe()
		box.add_child(current)
	_import = PrivateDataImport.new()
	add_child(_import)
	_import.progress.connect(func(message): _status.text = message)
	_import.failed.connect(func(message): _busy(false); _status.text = RemakeText.t(message))
	_import.completed.connect(_open)
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_browser_result)
		_add(box, "Choose installer / data pack…", func(): _choose_web(false))
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
		var isos := FileDialog.new()
		isos.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		isos.access = FileDialog.ACCESS_FILESYSTEM
		isos.use_native_dialog = true
		isos.filters = PackedStringArray(["*.iso ; " + RemakeText.t("Lost in Astral disc images")])
		isos.files_selected.connect(func(paths): _busy(true); _import.import_isos(paths))
		add_child(isos)
		_add(box, "Import Lost in Astral ISO images…", func(): isos.popup_centered_ratio(0.8))
		_iso_button = _buttons.back()
	_cancel = Button.new()
	_cancel.text = RemakeText.t("Cancel import")
	_cancel.custom_minimum_size.y = 48
	_cancel.hide()
	_cancel.pressed.connect(func():
		_import.cancelled = true
		if OS.has_feature("web"): JavaScriptBridge.get_interface("CursedFiles").cancel())
	box.add_child(_cancel)
	if back_text:
		if DataSwitch.imported():
			_add(box, "Delete imported data", _ask_delete)
		_add(box, back_text, func(): cancelled.emit())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_choose_campaign(selected_campaign)
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
	_choices.set_busy(value)
	_play.disabled = value or DataSwitch.installed(selected_campaign).is_empty()
	_cancel.visible = value


func _choose_campaign(id: String) -> void:
	selected_campaign = id
	_choices.choose(id)
	_play.disabled = DataSwitch.installed(id).is_empty()
	if _iso_button:
		_iso_button.visible = id == CampaignProfile.ASTRAL
	_status.text = RemakeText.t("Installed") if not _play.disabled else RemakeText.t("Not installed")

func _choose_web(folder: bool) -> void:
	JavaScriptBridge.get_interface("CursedFiles").choose(_callback, folder, selected_campaign)

## CursedFiles callbacks: (kind, English text, optional format argument).
func _browser_result(args: Array) -> void:
	if args.size() < 2:
		return
	var message := RemakeText.t(str(args[1]))
	if args.size() > 2 and args[2] != null and message.contains("%"):
		message = message % (int(args[2]) if args[2] is float else args[2])
	_status.text = message
	_busy(str(args[0]) == "progress")
	if str(args[0]) == "complete":
		GameFiles.initialize()
		_open(GameFiles.active_root())

func _open(folder: String) -> void:
	_status.text = RemakeText.t("Opening game data…")
	var error := DataSwitch.switch_to(folder, selected_campaign)
	if error:
		_busy(false)
		_status.text = RemakeText.t(error)
		if DataSwitch.managed(folder) and folder != GameData.root:
			DataSwitch.discard(folder)   # the staged import; the old data stays
	else:
		opened.emit()

## "Delete imported data": ✓ deletes it (DataSwitch.forget), ✗ keeps it.
func _ask_delete() -> void:
	var box := MessageBox.new()
	box.name = "DeleteBox"
	box.title = RemakeText.t("Delete imported data")
	box.message = RemakeText.t("The imported game files and the converted movies are deleted from this device (%s). Your saves and settings are kept. The game then asks for the game files again.") % DataSwitch.describe("", false)
	box.esc_closes = true
	add_child(box)
	_scroll.visible = false   # the box alone over the background
	box.dismissed.connect(func(): _scroll.visible = true)
	box.answered.connect(func(yes: bool):   # the box frees itself
		_scroll.visible = true
		if yes:
			DataSwitch.forget()
			deleted.emit())
