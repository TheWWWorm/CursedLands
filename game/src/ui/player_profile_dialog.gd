class_name PlayerProfileDialog
extends SettingsDialog
## One device profile shared by campaign co-op and Trials.
signal closed
const HELP := "Saved on this device and used automatically for multiplayer and autochess."
var name_edit: LineEdit
var save_button: Button

func _ready() -> void:
	build_shell(RemakeText.t("Player name"),Vector2(600,300))
	make_label(HELP,dialog_body,true)
	name_edit=LineEdit.new()
	name_edit.max_length=24
	name_edit.custom_minimum_size.y=46
	name_edit.text=GameData.player_name
	dialog_body.add_child(name_edit)
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",12)
	dialog_body.add_child(actions)
	save_button=make_button("Save",actions,_save)
	make_button("Cancel",actions,_close)
	name_edit.text_changed.connect(func(value):save_button.disabled=value.strip_edges().is_empty())
	name_edit.text_submitted.connect(func(_value):_save())

func open() -> void:
	capture_background();show();layout_shell()
	name_edit.grab_focus();name_edit.select_all()

func _save() -> void:
	if name_edit.text.strip_edges().is_empty(): return
	GameData.player_name=ArenaOnlineSession.clean_name(name_edit.text)
	GameData.save_settings();_close()

func _close() -> void:
	hide();closed.emit();queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled();_close()
