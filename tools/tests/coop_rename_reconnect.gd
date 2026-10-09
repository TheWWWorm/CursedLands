extends Node
## Actual menu keyboard editing -> MainMenu join -> ENet hello/bring ->
## original Game inventory preview, normal leave, reconnect and host reload.
## Only the entrypoint argv/bootstrap and process-wide asset teardown are
## suppressed on the two nested frontends sharing this disposable process.
const Menu = preload("res://src/ui/main_menu.gd")
class Frontend:
	extends "res://src/main.gd"
	func _ready() -> void: pass
	func _exit_tree() -> void: pass

class ViewportRoot:
	extends SubViewport
	var frontend: Node
	func back_to_menu() -> void: await frontend.back_to_menu()

var host_app: Frontend
var guest_app: Frontend
var host: Session
var guest: Session
var roots: Array[SubViewport]=[]
var outer_scene: Node
var checks:=0
var failures:=0
var rows:=[]
var rendered:=false
var original_bytes:=PackedByteArray()
var fingerprint:={}
var purse:={}
var old_slot:=-1
var old_uid:=-1
var merged_slot:=""
var original_host:={}
const PORT:=29947

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)

func until(test: Callable,seconds:=60.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await get_tree().process_frame
	return bool(test.call())

func branch(name_: String) -> Frontend:
	var view:=ViewportRoot.new(); view.name=name_; view.size=Vector2i(1024,768)
	view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	get_tree().root.add_child(view); roots.append(view)
	var app:=Frontend.new(); app.name="Frontend"; view.add_child(app); view.frontend=app
	var api:=SceneMultiplayer.new(); api.root_path=app.get_path(); get_tree().set_multiplayer(api,app.get_path())
	return app

func menu_of(app: Frontend):
	for c in app.get_children():
		if c.get_script()==Menu: return c
	return null

func open_menu(app: Frontend) -> void:
	var menu:=Menu.new(); menu.start_game.connect(app.start_game); app.add_child(menu)

func key(panel: Node,code: Key,unicode:=0) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.unicode=unicode; e.pressed=true
	panel._unhandled_key_input(e)

func focus_row(panel: NetworkPanel,id: String) -> void:
	panel._sel=-1; panel._focus=""
	for row: Dictionary in panel._rows():
		key(panel,KEY_DOWN)
		if String(row.id)==id: return

func type_field(panel: NetworkPanel,id: String,text: String) -> void:
	focus_row(panel,id)
	for i in 280: key(panel,KEY_BACKSPACE)
	for c in text: key(panel,KEY_NONE,c.unicode_at(0))

func join_from_menu(name_: String,slot: String) -> bool:
	var menu=menu_of(guest_app)
	if menu==null: return false
	var panel: NetworkPanel=menu._net
	check(panel!=null,"original network panel is available")
	if panel==null: return false
	panel.open(); panel.show_page(NetworkPanel.JOIN_COOP)
	type_field(panel,"name",name_); type_field(panel,"addr","127.0.0.1:%d"%PORT)
	focus_row(panel,"bring")
	var limit:=panel._bring_choices().size()+1
	for i in limit:
		if CoopProgress.bring_slot==slot: break
		key(panel,KEY_RIGHT)
	check(panel.player_name==name_ and CoopProgress.bring_slot==slot,"keyboard menu selects "+name_+" and the requested brought character")
	if rendered: await capture(guest_app,"menu-"+name_.to_lower())
	focus_row(panel,"addr"); key(panel,KEY_ENTER)
	check(await until(func():return guest_app.session!=null and guest_app.game!=null and not guest_app.session.loading_game \
		and not guest_app.session._remote_loading and not guest_app.session._zone_holding and guest_app.session._pool_epoch==host._load_serial),"menu join loads actual ENet world for "+name_)
	guest=guest_app.session
	if guest==null: return false
	freeze(guest); CampaignState.watch=host.coop._on_var
	return true

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.set_process(false) # hold clock/cursor/selection while inspecting either peer's model
	if s.world.vm: s.world.vm.instances.clear()
	s.game.rig.set_process(false); s.game.hud._tutorial.close(); s.game.hud._dialog.hide()

func identity(hero: Dictionary) -> Dictionary:
	var out:={}
	for k in ["prototype","str","dex","int","skills","exp","exp_total","weapons","armors","quick","spells","perks"]:
		out[k]=hero.get(k)
	return out.duplicate(true)

func capture(app: Frontend,label: String) -> void:
	var view:=app.get_viewport() as SubViewport
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("user://rename-"+label+".png")
	view.render_target_update_mode=SubViewport.UPDATE_DISABLED

func presented(app: Frontend,name_: String,label: String) -> void:
	var s: Session=app.session; var idx:=guest.my_index
	var units:=s.party_units(idx)
	check(units.size()==1,label+" has one owned brought hero")
	if units.is_empty(): return
	var u: GameUnit=units[0]
	var entry:=PlayerNames.of(app.game)
	check(entry.active() and entry.entries().any(func(e):return e[0]==u and e[1]==name_),label+" overhead uses the current player name")
	check(u.display_name==name_ and String((u.get_meta("hero") as Dictionary).get("name",""))==name_,label+" live hero and character record share the current name")
	app.game.selected=[u]; app.game.rig.focus(u.global_position)
	app.game.rig.camera.make_current()
	if rendered: await capture(app,label+"-overhead")
	var e:=InputEventKey.new(); e.keycode=KEY_B; e.physical_keycode=KEY_B; e.pressed=true
	app.game._unhandled_input(e)
	var panel: InventoryPanel=app.game.hud._inventory
	check(panel.visible and panel._camp.visible and panel._camp._unit==u and panel._camp._unit.display_name==name_,label+" normal inventory key opens the current character preview")
	# refresh() queues the previous fallback labels for deletion.
	await get_tree().process_frame
	await get_tree().process_frame
	var text:=""
	for c in panel._hero_box.get_children():
		if c is Label: text+=(c as Label).text
	check(text.begins_with(name_+"\n"),label+" character-preview backing label starts with current name")
	if rendered: await capture(app,label+"-preview")
	rows.append({"phase":label,"player":name_,"slot":idx,"unit":u.uid,"deployment":u.info.get("name"),"display_name":u.display_name,"hero_name":u.get_meta("hero").get("name"),"hero":identity(u.get_meta("hero")),"preview_label":text})
	key(panel,KEY_ESCAPE)

func leave_from_menu(label: String) -> String:
	var saved:=guest.coop.last_merged
	var count:=host.players.size()
	guest.game.hud._on_signpost("exit"); key(guest.game.hud._quit_box,KEY_ENTER)
	check(await until(func():return host.players.size()==count-1 and guest_app.session==null and menu_of(guest_app)!=null),"normal confirmed Exit disconnects "+label)
	return saved

func current_identity(label: String,expected_uid: int) -> void:
	check(guest.my_index==old_slot,label+" keeps the original slot")
	check(host.party_units(guest.my_index)[0].uid==expected_uid,label+" keeps the live hero identity")
	check(identity(host.state.heroes[guest.my_index][0])==fingerprint and host.coop.purse_entry(guest.my_index).purse==purse,label+" retains earned stats, equipment, spells and private items")
	check(host.state.heroes.size()==2 and host.coop.joiners.size()==1,label+" has one guest roster and one tally")

func copy_progress(source: String,destination: String,kind: String) -> bool:
	var st:=CampaignState.load_from(SaveInfo.path(source))
	if st==null: return false
	var e: Dictionary=host.coop.joiners.ally
	if kind=="unrelated":
		st.coop={}
	else:
		# The latest host tally is fixture input; transmission still uses the
		# actual saved character, client_hello and sanitizing bring RPC.
		st.coop.applied={String(e.sid):{"seq":int(e.seq)}}
		if kind=="stale": st.coop.applied[e.sid].seq=maxi(0,int(e.seq)-1)
		if kind=="future": st.coop.applied[e.sid].seq=int(e.seq)+1
		if kind=="invalid": st.coop.applied[e.sid].seq="not-a-sequence"
	return st.save(SaveInfo.path(destination))==OK

func rejected_identity(kind: String,source: String,active:=false) -> void:
	var original_app:=guest_app
	var original_guest:=guest
	var slot:="rename_"+kind
	var unchanged: Dictionary=host.coop.joiners.ally
	var tally_sid:=String(unchanged.sid)
	var roster: Array=host.state.heroes[old_slot].duplicate(true)
	var bag: Dictionary=unchanged.purse.duplicate(true)
	var uid:=-1
	for u: GameUnit in host.world.units.values():
		if u.controller==old_slot or int(u.get_meta("orphan_of",-1))==old_slot:
			if u.has_meta("hero") and not u.get_meta("hero").has("merc"): uid=u.uid
	check(copy_progress(source,slot,kind),kind+" prepares a disposable brought-character control")
	if kind=="ambiguous":
		var duplicate: Dictionary=unchanged.duplicate(true)
		duplicate.idx=80; duplicate.name="Duplicate Fixture"; duplicate.active=false; duplicate.pid=0
		host.coop.joiners.duplicate_fixture=duplicate
	if active:
		guest_app=branch("RenameActiveCopy"); open_menu(guest_app)
	get_tree().current_scene=guest_app.get_parent()
	if await join_from_menu("T"+kind,slot):
		check(guest.my_index!=old_slot,kind+" cannot take the original character slot")
		check(host.state.heroes[old_slot]==roster and host.coop.joiners.ally.sid==tally_sid and host.coop.joiners.ally.purse==bag,kind+" preserves the original roster, tally and private purse")
		var kept: GameUnit=host.world.units.get(uid)
		check(kept!=null and (kept.controller==old_slot if active else int(kept.get_meta("orphan_of",-1))==old_slot),kind+" preserves the original live actor and ownership")
		check(identity(host.state.heroes[guest.my_index][0])==fingerprint,kind+" remains a separately imported character even with matching stats/items")
		rows.append({"case":kind,"original_slot":old_slot,"new_slot":guest.my_index,"original_uid":uid,"sid":tally_sid,"active_original":active,"keys":host.coop.joiners.keys()})
		await leave_from_menu("control "+kind)
	if kind=="ambiguous": host.coop.joiners.erase("duplicate_fixture") # exact injected fixture entry only
	if active:
		guest_app.get_parent().queue_free(); roots.erase(guest_app.get_parent())
		guest_app=original_app; guest=original_guest
		get_tree().current_scene=guest_app.get_parent()

func _ready() -> void:
	await get_tree().process_frame
	process_mode=Node.PROCESS_MODE_ALWAYS; rendered=DisplayServer.get_name()!="headless"; outer_scene=get_tree().current_scene
	# This tests original UI and identities; optional renderer effects would
	# obscure two-view CPU software-renderer captures without adding coverage.
	for option: String in GameData.options:
		if option.begins_with("gfx_"): GameData.options[option]=0
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0,"coop_share_loot":0,"coop_player_names":1,
		"gfx_ambient_wildlife":0,"gfx_ambient_particles":0,"gfx_weather_mist":0,"gfx_clouds":0},true)
	var origin:=CoopProgress.fresh_state()
	var hero:=CoopProgress.main_hero(origin); hero.str=31.0; hero.dex=43.0; hero.int=59.0
	origin.money=222; origin.items=["rune:e1"]; origin.visited[origin.current_zone]=true
	check(origin.save(SaveInfo.path("rename_origin"))==OK,"create disposable brought-character origin")
	original_bytes=FileAccess.get_file_as_bytes(SaveInfo.path("rename_origin"))
	host_app=branch("RenameHost"); host=Session.new(); host_app.add_child(host)
	GameData.player_name="Rename Host"; check(host.host(PORT,4)==OK,"open real ENet authority")
	host_app.start_game(host); host.state=CoopProgress.fresh_state(); host.state.money=9000; host.state.items=[]
	host.set_physics_process(false)
	await host.enter_zone(origin.current_zone,1,false); freeze(host)
	original_host=identity(host.state.heroes[0][0])
	guest_app=branch("RenameGuest"); get_tree().current_scene=guest_app.get_parent(); open_menu(guest_app)
	if not await join_from_menu("Ann","rename_origin"): await finish(); return
	old_slot=guest.my_index; old_uid=host.party_units(old_slot)[0].uid
	check(old_slot==1 and host.coop.joiners.has("ann"),"Ann receives the first guest slot and imported tally")
	await presented(host_app,"Ann","ann-host"); await presented(guest_app,"Ann","ann-guest")
	# Prepared earned-state sent through normal save/package RPC; no rename,
	# rebind, spawn, hero relink or incoming-hello internals are called here.
	host.state.heroes[old_slot][0].str+=2.0
	host.coop.with_purse(old_slot,func():host.state.money+=137;host.state.items.append("rune:e2"))
	fingerprint=identity(host.state.heroes[old_slot][0]); purse=host.coop.purse_entry(old_slot).purse.duplicate(true)
	var prior:=guest.coop.merged_count
	check(host.save_game("rename_ann")==OK,"normal host save packages the earned character")
	check(await until(func():return guest.coop.merged_count>prior and not guest.coop.last_merged.is_empty()),"Ann receives the normal brought-progress save")
	merged_slot=guest.coop.last_merged
	var merged:=CampaignState.load_from(SaveInfo.path(merged_slot))
	check(merged!=null and identity(CoopProgress.main_hero(merged))==fingerprint and CoopProgress.main_bag(merged)==purse,"returned save retains earned stats and private items")
	await leave_from_menu("Ann")
	if not await join_from_menu("Alice",merged_slot): await finish(); return
	var renamed_slot:=guest.my_index
	check(guest.my_index==old_slot,"renamed brought character reclaims its existing slot")
	check(host.party_units(guest.my_index)[0].uid==old_uid,"renamed reconnect reclaims the same live hero")
	check(identity(host.state.heroes[guest.my_index][0])==fingerprint and host.coop.purse_entry(guest.my_index).purse==purse,"renamed reconnect preserves earned stats and private items")
	check(host.state.heroes.size()==2,"renamed reconnect adds no duplicate guest character")
	await presented(host_app,"Alice","alice-host"); await presented(guest_app,"Alice","alice-guest")
	check(await host.load_game_shown("rename_ann"),"host reloads the pre-rename save through the normal load operation"); freeze(host)
	check(await until(func():return guest.zone_id==host.zone_id and guest._pool_epoch==host._load_serial and not guest.loading_game and not guest._remote_loading),"guest receives host reload")
	freeze(guest); CampaignState.watch=host.coop._on_var
	check(identity(host.state.heroes[guest.my_index][0])==fingerprint and host.coop.purse_entry(guest.my_index).purse==purse,"reload retains earned stats and private items")
	await presented(host_app,"Alice","reload-host"); await presented(guest_app,"Alice","reload-guest")
	check(host.coop.joiners.size()==1 and host.coop.joiners.has("alice"),"pre-rename host reload retains only the current tally alias")
	if guest.my_index==old_slot and host.coop.joiners.size()==1:
		var current_uid: int=host.party_units(old_slot)[0].uid
		merged_slot=await leave_from_menu("Alice after host reload")
		if not await join_from_menu("Ally",merged_slot): await finish(); return
		current_identity("second rename",current_uid)
		await presented(host_app,"Ally","ally-host"); await presented(guest_app,"Ally","ally-guest")
		merged_slot=await leave_from_menu("Ally")
		if not await join_from_menu("Ally",merged_slot): await finish(); return
		current_identity("same-name reconnect after two renames",current_uid)
		await presented(host_app,"Ally","repeat-host"); await presented(guest_app,"Ally","repeat-guest")
		check(await until(func():return not guest.coop.last_merged.is_empty()),"reconnected character receives current progress")
		merged_slot=guest.coop.last_merged
		await rejected_identity("active",merged_slot,true)
		merged_slot=await leave_from_menu("Ally before inactive controls")
		for kind in ["unrelated","ambiguous","stale","future","invalid"]:
			await rejected_identity(kind,merged_slot)
	check(identity(host.state.heroes[0][0])==original_host,"guest rename leaves host protagonist unchanged")
	check(FileAccess.get_file_as_bytes(SaveInfo.path("rename_origin"))==original_bytes,"original imported save stays byte-identical")
	rows.append({"case":"identity","original_slot":old_slot,"rejoined_slot":renamed_slot,"original_uid":old_uid,"hero_slots_after_controls":host.state.heroes.keys(),"joiner_keys_after_controls":host.coop.joiners.keys(),"expected_hero":fingerprint,"expected_purse":purse,"merged_slot":merged_slot})
	await finish()

func finish() -> void:
	get_tree().current_scene=outer_scene
	for app: Frontend in [guest_app,host_app]:
		if app and is_instance_valid(app.session):
			app.session.online=false
			if app.session.multiplayer.multiplayer_peer: app.session.multiplayer.multiplayer_peer.close()
	for view in roots: view.queue_free()
	for i in 5: await get_tree().process_frame
	CoopProgress.bring_slot=""
	var file:=FileAccess.open("user://rename-receipt.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"campaign":GameData.campaign_id,"checks":checks,"failures":failures,"rows":rows},"\t"));file.close()
	print("COOP_RENAME_RECONNECT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
