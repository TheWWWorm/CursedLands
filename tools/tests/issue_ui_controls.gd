extends Node
## Real control handlers and original item/quest data. List fixtures replace
## inventory ownership only; no game commands or purchase results are mocked.
class CampFixture extends CampView:
	var goods: Array = []
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _draw() -> void: pass
	func bag_items() -> Array: return goods
	func shop_items() -> Array: return goods
	func bag_count(_id: String) -> int: return 1
	func shop_left(_id: String) -> int: return 1
	func tutorial_visible() -> bool: return false
class CharacterFixture extends MpCharPanel:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _draw() -> void: pass
	func _layout() -> void: pass
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func mouse(panel: Control, point: Vector2, button: MouseButton, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = point; e.button_index = button; e.pressed = true; e.shift_pressed = shift
	panel._gui_input(e)
func _ready() -> void:
	await get_tree().process_frame
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"pad_enabled":0},true)
	var camp := CampFixture.new(); camp.size=Vector2(800,600); add_child(camp)
	camp.mode="itemtrade"
	for i in 40: camp.goods.append("battle axe.adamantium")
	mouse(camp,Vector2(754,550),MOUSE_BUTTON_LEFT,true)
	check(camp.scroll==33,"Shift-right goes to the last bag page")
	mouse(camp,Vector2(38,550),MOUSE_BUTTON_LEFT,true)
	check(camp.scroll==0,"Shift-left goes to the first bag page")
	mouse(camp,Vector2(754,50),MOUSE_BUTTON_LEFT,true)
	check(camp.shop_scroll==33,"Shift-right goes to the last shop page")
	mouse(camp,Vector2(38,50),MOUSE_BUTTON_LEFT,true)
	check(camp.shop_scroll==0,"Shift-left goes to the first shop page")
	mouse(camp,Vector2(100,550),MOUSE_BUTTON_WHEEL_DOWN)
	check(camp.scroll==1 and camp.shop_scroll==0,"wheel changes only the hovered bag")
	mouse(camp,Vector2(100,550),MOUSE_BUTTON_WHEEL_RIGHT,true)
	check(camp.scroll==33,"Shift-wheel shares the bag endpoint behavior")
	mouse(camp,Vector2(100,550),MOUSE_BUTTON_WHEEL_LEFT,true)
	check(camp.scroll==0,"horizontal wheel returns to the first item")
	var u := GameUnit.new()
	var h := {"perks":[]}
	for i in 24: h.perks.append("fixture_"+String.chr(65+i)+"1")
	u.set_meta("hero",h); camp._unit=u; camp.mode="spells"
	mouse(camp,Vector2(240,360),MOUSE_BUTTON_WHEEL_DOWN)
	check(camp._perk_scroll==1,"wheel scrolls known abilities")
	camp._scroll_list("known",1,true)
	check(camp._perk_scroll==14,"Shift endpoint uses the complete known-ability list")
	camp._scroll_list("known",-1,true)
	check(camp._perk_scroll==0,"known abilities return to the beginning")
	camp.touch_scroll(Vector2(240,360),Vector2(0,-10))
	check(camp._perk_scroll==1 and camp._avail_scroll==0,"vertical touch gesture uses the hovered known-ability list")
	camp.mode="itemtrade"; camp._content={"shop0":["battle axe.adamantium","shop"]}
	var tip := camp._get_tooltip(Vector2(100,50))
	check(tip==Items.title("battle axe.adamantium"),"shop hover contains the item name without a duplicate bare price")
	camp.selected_id="battle axe.adamantium"; camp.selected_where="shop"
	camp._process_selection(.04)
	check(float(camp._selection_alpha.shop0)>0.0 and float(camp._selection_alpha.shop0)<1.0,"selection border fades in")
	camp._process_selection(.2); camp.selected_id=""; camp._process_selection(.04)
	check(float(camp._selection_alpha.shop0)>0.0 and float(camp._selection_alpha.shop0)<1.0,"selection border fades out")
	camp._unit=null; u.free(); camp.free()
	var chars := CharacterFixture.new(); add_child(chars); chars.size=Vector2(800,600); chars.show()
	chars.state=MpCharPanel.CREATE
	for i in 30: chars.faces[0].append(str(i)); chars.faces[1].append(str(i))
	for i in 20: chars.voices[0].append(str(i))
	# Interface800 maps physical coordinates through its actual viewport.
	for row in [[0,50.0],[1,550.0]]:
		mouse(chars,chars.r8(Rect2(100,row[1],1,1)).position,MOUSE_BUTTON_WHEEL_DOWN)
		check(chars.face_top[row[0]]==1,"wheel scrolls the hovered face row "+str(row[0]))
		mouse(chars,chars.r8(Rect2(755,row[1],1,1)).position,MOUSE_BUTTON_LEFT,true)
		check(chars.face_top[row[0]]==23,"Shift reaches the last face in row "+str(row[0]))
		mouse(chars,chars.r8(Rect2(35,row[1],1,1)).position,MOUSE_BUTTON_LEFT,true)
		check(chars.face_top[row[0]]==0,"Shift returns to the first face in row "+str(row[0]))
	mouse(chars,chars.r8(Rect2(70,340,1,1)).position,MOUSE_BUTTON_WHEEL_DOWN)
	check(chars.voice_top==1 and chars.face_top==[0,0],"voice wheel does not scroll the face rows")
	chars.free()
	var repeat := preload("res://src/ui/scroll_repeat.gd").new()
	repeat.begin("bag",1)
	check(repeat.advance(.39)==0,"holding an arrow waits before repeating")
	check(repeat.advance(.02)==1,"held arrow begins repeating after its delay")
	var slow := 0
	for i in 5: slow+=repeat.advance(.1)
	for i in 15: repeat.advance(.1)
	var fast := 0
	for i in 5: fast+=repeat.advance(.1)
	check(fast>slow,"held scrolling accelerates")
	repeat.stop(); check(repeat.advance(4)==0,"released arrow cannot keep scrolling")
	for fixed in [1,2,3]:
		GameData.options.cursor_size=fixed
		check(GameCursor.size_px()==[32,48,64][fixed-1],"explicit cursor size "+str(fixed))
	GameData.options.cursor_size=0
	var state := CampaignState.new()
	for q: Dictionary in SideQuests.all():
		state.vars.clear(); state.side_quests={q.id:"active"}
		var entries := JournalPanel.quest_entries(state)
		check(entries.active==[q.id] and entries.done.is_empty(),q.id+" appears without a campaign quest variable")
		check(not JournalPanel._parse(q.id).text.is_empty(),q.id+" has the original quest description")
		state.set_var(0,"q."+q.id+"."+q.id,1)
		check(JournalPanel.quest_entries(state).active==[q.id],q.id+" is not duplicated by campaign flags")
		state.side_quests[q.id]="done"
		check(JournalPanel.quest_entries(state).done==[q.id],q.id+" completion appears in the journal")
		state.side_quests.erase(q.id); state.set_var(0,"q."+q.id+"."+q.id,0)
		check(JournalPanel.quest_entries(state).active.is_empty(),q.id+" cancellation removes the active entry")
	for language in ["en","ru","de"]:
		RemakeText.lang=language
		for name in ["cursor_size","show_player_status","item_icon_fit"]:
			for key: String in GameData.REMAKE_OPTIONS[name]:
				check(not RemakeText.t(key).is_empty() and (language=="en" or RemakeText.t(key)!=key),language+" translated "+name)
		for key: String in GameData.DISPLAY_CHOICES.cursor_size:
			check(RemakeText.TEXTS.has(key) or language=="en",language+" cursor choice is registered: "+key)
	print("ISSUE_UI_CONTROLS ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
