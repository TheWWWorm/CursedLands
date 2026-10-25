extends Node
## F2 edits only the selected save's display metadata in Load and Save screens.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr('FAIL ',label)
func key(panel: LoadPanel, code: Key, unicode := 0) -> void:
	var e := InputEventKey.new();e.pressed=true;e.keycode=code;e.unicode=unicode
	panel._unhandled_key_input(e)
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with('--texts='):
			GameData.texts=EIResArchive.open_path(arg.trim_prefix('--texts='))
			EIText.code_page=EIText.detect_code_page(GameData.texts)
			RemakeText.lang=RemakeText.detect(GameData.texts)
	var slot := 'rename_fixture'
	var state := CampaignState.new()
	check(state.save(SaveInfo.path(slot))==OK,'fixture saved')
	SaveInfo.write(slot,27.5,'gipath','gz1g','Before')
	var shot:=Image.create(32,32,false,Image.FORMAT_RGBA8);shot.fill(Color.DARK_SLATE_GRAY)
	SaveInfo.write_shot_image(slot,shot)
	var saved:=FileAccess.get_file_as_bytes(SaveInfo.path(slot))
	var image:=FileAccess.get_file_as_bytes(SaveInfo.path(slot,'shot.png'))
	var info:=SaveInfo.read(slot);var date:=info.time
	if DisplayServer.get_name()=='headless':get_viewport().size=Vector2i(1280,720)
	for i in 6:await get_tree().process_frame
	var window_size:=Vector2i(1024,768) if OS.get_cmdline_user_args().has('--small-window') else Vector2i(1280,720)
	GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(window_size)
	GameData._apply_window()
	get_window().size=window_size
	for i in 3:await get_tree().process_frame
	check(get_window().size==window_size,'rename uses the requested test window size')
	var panel:=LoadPanel.new();add_child(panel);panel.visible=true;panel.saves.assign([info]);panel._select(0)
	key(panel,KEY_F2)
	check(panel.get('_renaming')==true,'F2 starts editing an existing selected save')
	if panel.get('_renaming')!=true:
		print('SAVE_RENAME ',checks,' checks ',failures,' failures')
		get_tree().quit(1);return
	key(panel,KEY_ESCAPE)
	var activated:=[0,0]
	panel.load_requested.connect(func(_slot:String):activated[0]+=1)
	panel.save_requested.connect(func(_slot:String,_name:String,_frame:Image):activated[1]+=1)
	for save:bool in [false,true]:
		panel.save_mode=save
		for name:String in ['Camp','Лес','Höhle']:
			key(panel,KEY_F2)
			check(panel._renaming and panel._editable(),'F2 enters rename in both screens')
			for c:String in name:
				key(panel,KEY_NONE,c.unicode_at(0))
			check(panel._edit==name,'Unicode typing replaces the selected name')
			await capture('save-rename-edit-'+str(save)+'-'+name+'.png')
			key(panel,KEY_ENTER)
			check(SaveInfo.read(slot).name==name,'Enter persists the display name')
			check(not panel._renaming and panel.visible and activated==[0,0],'Enter renames without loading or overwriting')
			check(info.time==date and SaveInfo.read(slot).time==date,'original save date retained')
			check(FileAccess.get_file_as_bytes(SaveInfo.path(slot))==saved,'saved world is byte-identical')
			check(FileAccess.get_file_as_bytes(SaveInfo.path(slot,'shot.png'))==image,'preview is byte-identical')
			key(panel,KEY_F2);key(panel,KEY_NONE,'X'.unicode_at(0));key(panel,KEY_ESCAPE)
			check(not panel._renaming and panel.visible and SaveInfo.read(slot).name==name,'Escape cancels without closing the screen')
	key(panel,KEY_F2);key(panel,KEY_BACKSPACE);key(panel,KEY_ENTER)
	check(SaveInfo.read(slot).name.is_empty(),'empty rename restores the localized default name')
	check(info.rename_to('x'.repeat(61))==ERR_INVALID_PARAMETER,'reject overlong names')
	check(info.rename_to('bad\nname')==ERR_INVALID_PARAMETER,'reject multiline names')
	var other:=SaveInfo.new();other.slot='other';panel.saves.append(other);panel._select(0);panel._select(1,true)
	key(panel,KEY_F2);check(not panel._renaming,'multiple selection cannot rename an arbitrary slot')
	panel.saves.assign([info]);panel._select(0)
	key(panel,KEY_F2);key(panel,KEY_NONE,'Z'.unicode_at(0));panel._select(0)
	check(not panel._renaming and SaveInfo.read(slot).name.is_empty(),'selection cancels a pending edit')
	for special:String in ['quick','autosave','saveq','savea','saveb']:
		var protected:=SaveInfo.new();protected.slot=special
		panel.saves.assign([protected]);panel._select(0);key(panel,KEY_F2)
		check(not panel._renaming and protected.rename_to('changed')==ERR_UNAVAILABLE,'protected slot keeps its name: '+special)
	var fresh:=SaveInfo.make_fresh(0,'gipath','gz1g',null);panel.saves.assign([fresh]);panel._select(0);key(panel,KEY_F2)
	check(not panel._renaming and fresh.rename_to('new')==ERR_UNAVAILABLE,'new unsaved entry is not a rename target')
	# Existing Save mode can replace a damaged manual save and name that
	# replacement. F2 must not make the damaged save itself a rename target.
	var damaged:=SaveInfo.new();damaged.slot='damaged_manual';damaged.error=true
	panel.saves.assign([damaged]);panel.save_mode=true;panel._select(0)
	check(panel._editable(),'damaged manual save retains replacement-name editing')
	key(panel,KEY_F2);check(not panel._renaming,'damaged save cannot be renamed in place')
	# A failed sidecar creation keeps the existing metadata and edit intact.
	panel.saves.assign([info]);panel._select(0);key(panel,KEY_F2);key(panel,KEY_NONE,'Y'.unicode_at(0))
	DirAccess.make_dir_recursive_absolute(SaveInfo.path(slot,'info.sav.rename'))
	key(panel,KEY_ENTER)
	check(panel._renaming and is_instance_valid(panel._box),'storage failure remains editable and shows an error')
	check(SaveInfo.read(slot).name.is_empty(),'failed rename preserves original metadata')
	await capture('save-rename-error.png')
	panel._box._answer(true);DirAccess.remove_absolute(SaveInfo.path(slot,'info.sav.rename'))
	key(panel,KEY_ENTER);check(SaveInfo.read(slot).name=='Y','retry succeeds after storage recovers')
	SaveInfo.delete(slot);panel.queue_free()
	for i in 6:await get_tree().process_frame
	print('SAVE_RENAME ',checks,' checks ',failures,' failures')
	get_tree().quit(1 if failures else 0)
func capture(filename:String)->void:
	if DisplayServer.get_name()=='headless':return
	for i in 3:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png('user://'+filename)==OK,'rename layout captured')
