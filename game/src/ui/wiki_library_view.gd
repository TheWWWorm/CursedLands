class_name WikiLibraryView
extends AcceptDialog
signal creation_opened(record: Dictionary)
signal creation_added(record: Dictionary)
var _query: LineEdit
var _type: OptionButton
var _list: VBoxContainer
var _status: Label

func _ready() -> void:
	title=RemakeText.t("Saved creations");get_ok_button().text=RemakeText.t("Close")
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",14);add_child(body)
	var help := Label.new();help.text=RemakeText.t("Items, spells and characters saved on this device. Open a creation to edit it, or add a recipe to your current build.");help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(help)
	_query=LineEdit.new();_query.placeholder_text=RemakeText.t("Search saved creations");_query.text_changed.connect(func(_value):refresh());body.add_child(_query)
	_type=ScrollOptionButton.new();_type.fit_to_longest_item=false
	for key: String in ["All creations","Items","Spells","Characters"]:_type.add_item(RemakeText.t(key))
	_type.tooltip_text=RemakeText.t("Filter saved items, spells or characters.");_type.item_selected.connect(func(_index):refresh());body.add_child(_type)
	_status=Label.new();_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(_status)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.custom_minimum_size.y=200;body.add_child(scroll)
	_list=VBoxContainer.new();_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_list.add_theme_constant_override("separation",16);scroll.add_child(_list)
	refresh()

func refresh() -> void:
	for child in _list.get_children():_list.remove_child(child);child.queue_free()
	var state := WikiLibrary.read();_status.text=RemakeText.t(state.error) if state.error else ""
	if state.error:return
	var count := 0
	for record: Dictionary in state.records:
		if _type.selected>0 and record.type!=["","item","spell","character"][_type.selected]:continue
		if WikiSearch.score(_query.text,record.name,"")<0:continue
		count+=1
		var row := VBoxContainer.new();_list.add_child(row)
		var name_label := Label.new();name_label.text=record.name;name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;name_label.add_theme_font_size_override("font_size",20);row.add_child(name_label)
		var description := Label.new();description.text=RemakeText.t({"item":"Item","spell":"Spell","character":"Character build"}[record.type])+" · "+RemakeText.t("Base game" if record.plan.campaign==CampaignProfile.ORIGINAL else "Lost in Astral");row.add_child(description)
		var actions := HFlowContainer.new();row.add_child(actions)
		_action(actions,"Open",func():creation_opened.emit(record))
		if record.type!="character":_action(actions,"Add to plan",func():creation_added.emit(record))
		_action(actions,"Remove",func():
			var confirm := ConfirmationDialog.new();confirm.dialog_text=RemakeText.t("Remove this saved creation?");confirm.get_ok_button().text=RemakeText.t("Remove");confirm.get_cancel_button().text=RemakeText.t("Cancel");add_child(confirm)
			confirm.confirmed.connect(func():var error := WikiLibrary.remove(record.id);refresh();_status.text=RemakeText.t(error) if error else RemakeText.t("Saved creation removed.");confirm.queue_free())
			confirm.canceled.connect(confirm.queue_free);confirm.popup_centered())
	if count==0:_status.text=RemakeText.t("Nothing saved yet. Choose Save locally in an item, spell or character planner.") if state.records.is_empty() else RemakeText.t("No saved creations match this search.")

func _action(parent: Control,key: String,callback: Callable) -> void:
	var button := Button.new();button.text=RemakeText.t(key);button.pressed.connect(callback);parent.add_child(button)
