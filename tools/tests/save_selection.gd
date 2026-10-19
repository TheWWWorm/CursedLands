extends Node
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready()->void:
	var panel:=LoadPanel.new();add_child(panel)
	panel.visible=true
	for i in 8:
		var save:=SaveInfo.new();save.slot="selection_fixture_%d"%i;panel.saves.append(save)
	panel._select(1);panel._select(4,true)
	check(panel.selected.keys()==[1,2,3,4],"Shift selects contiguous range")
	panel._select(2,false,true)
	check(not panel.selected.has(2) and panel.selected.size()==3,"Ctrl toggles one row")
	panel._select(6,true,true)
	check(panel.selected.size()==6 and panel.selected.has(6),"Ctrl-Shift extends from the current anchor")
	check(not panel._single(),"load disabled for multiple saves")
	panel._load();check(not panel.loading and panel.visible,"double-click/load cannot pick an arbitrary save from selection")
	panel._select(3);check(panel._single(),"ordinary click returns to one loadable row")
	panel._select(3,false,true);check(panel.selected.is_empty() and not panel._single(),"Ctrl deselects last row without enabling load")
	panel._select(1);panel._select(4,true);panel._delete()
	check(is_instance_valid(panel._box) and panel._box.message==RemakeText.t("Delete %d selected saves?")%4,"bulk deletion confirms concrete count")
	panel._box._answer(false);check(panel.saves.size()==8,"cancel preserves every save")
	# Confirm through the real deletion path, using only files this test owns.
	var slots:Array[String]=[]
	panel.saves.clear()
	for i in 4:
		var slot:="selection_fixture_%d_%d"%[OS.get_process_id(),i]
		slots.append(slot)
		var state:=CampaignState.new()
		SaveInfo.write(slot,24.0+i,"gipath","gz1g","Selection fixture %d"%i)
		state.save(SaveInfo.path(slot))
		var shot:=Image.create(32,32,false,Image.FORMAT_RGBA8);shot.fill(Color.DARK_SLATE_GRAY)
		SaveInfo.write_shot_image(slot,shot)
		panel.saves.append(SaveInfo.read(slot))
	panel._select(0);panel._select(2,true)
	await capture("save-selection.png")
	panel._delete()
	await capture("save-selection-confirm.png")
	panel._box._answer(true)
	for i in 4:
		for ext:String in ["sav","info.sav","shot.png"]:
			check(FileAccess.file_exists(SaveInfo.path(slots[i],ext))==(i==3),"bulk delete removes selected %s and preserves unselected fixture"%ext)
	# The unsaved first row is never a disk deletion target.
	var fresh:=SaveInfo.make_fresh(24.0,"gipath","gz1g",null)
	panel.save_mode=true;panel.saves.assign([fresh,SaveInfo.read(slots[3])])
	panel._select(0);panel._select(1,true);panel._delete()
	check(panel._box.message!=RemakeText.t("Delete %d selected saves?")%2,"fresh row is excluded from deletion count")
	panel._box._answer(true)
	check(panel.saves.size()>0 and panel.saves[0].fresh,"deleting saved rows preserves the new-save entry")
	for slot:String in slots:SaveInfo.delete(slot)
	panel.queue_free()
	for i in 6:await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

func capture(filename:String)->void:
	if DisplayServer.get_name()=="headless":return
	for i in 3:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://"+filename)==OK,"save selection layout captured")
