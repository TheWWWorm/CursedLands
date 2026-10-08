extends "spell_requirements_coop.gd"
## Real co-op command routing from the field/radial UI, with native spell data.
func press(action: String) -> void:
	PadInput._press(action);PadInput._release(action)
func pick_spell(pad: PadField, slot := 0) -> void:
	pad._page.actions=0
	pad.open_wheel("actions","actions")
	pad.wheel.selected=slot
	pad._confirm()
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":1,"pad_glyphs":1},true)
	var a:=branch("Host",true);host=a.s;hg=a.g
	var b:=branch("Guest",false);client=b.s;cg=b.g
	cg.get_viewport().render_target_update_mode=SubViewport.UPDATE_ALWAYS
	require(host.host(29929,2)==OK);GameData.player_name="Controller Guest"
	require(client.join("127.0.0.1",29929)==OK)
	require(await until(func():return host.players.size()==2 and client.my_index==1))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Controller Guest")
	var h: Dictionary=host.state.heroes[1][0]
	h.skills={"astral":100};h.int=25.0;h.exp_total=200271.0;h.spells=[SPELL,"strength{}"];h.perks=[]
	var field := "gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g"
	await host.enter_zone(field,1,false);freeze()
	var ready := await until(func():return loaded(field),60)
	print("PAD_JOIN ",ready," players=",host.players," online=",host.online,"/",client.online," zone=",client.zone_id," loading=",host.loading_game,"/",client.loading_game)
	require(ready)
	var guest: GameUnit=host.party_units(1)[0]
	var owner: GameUnit=host.party_units(0)[0]
	guest.blocked=false;guest.order={};guest.orders.clear();guest._anim_lock=0
	owner.pos=guest.pos+Vector2(1,0)
	host._send_snapshot_records([guest.snapshot(),owner.snapshot()],host.world.time)
	await frames()
	var view: GameUnit=client.party_units(1)[0]
	var ally: GameUnit=client.party_units(0)[0]
	cg.selected.assign([view]);cg.rig.release()
	PadInput._set_active("pad");PadInput.field=cg.get_node("PadField")
	hg.get_node("PadField").set_process(false);hg.direct.set_process(false)
	PadInput.action.disconnect(hg.get_node("PadField")._on_action)
	await frames()
	var pad:=cg.get_node("PadField") as PadField
	cg.direct._neutral=false
	pick_spell(pad)
	check(pad.target_unit()==view,"healing defaults to self in third person")
	await frames()
	check(pad.target_unit()==view,"shoulder frame updates preserve friendly target")
	check(pad.hints().any(func(e):return e[1]==RemakeText.t("Cast on self")),"self-cast shortcut is visible")
	press("context");await frames()
	check(guest.orders.size()==1 and guest.orders[0].target==guest,"X heals self through real guest authority command")
	guest.orders.clear();guest.order={}
	pick_spell(pad)
	press("right")
	check(pad.target_unit()==ally,"D-pad can select co-op partner for healing")
	await frames()
	check(pad.target_unit()==ally,"manual ally target is not immediately replaced by self")
	press("interact");await frames()
	check(guest.orders.size()==1 and guest.orders[0].target==owner,"A casts on selected ally rather than interacting")
	check(cg.selected==[view],"casting at ally keeps guest caster selected")
	guest.orders.clear();guest.order={}
	pick_spell(pad)
	press("right")
	cg.direct._neutral=false;cg.direct.pad_action("system","down");cg.direct.pad_action("system","up");await frames()
	check(guest.orders.size()==1 and guest.orders[0].target==owner,"RT honors explicit ally target instead of crosshair")
	guest.orders.clear();guest.order={}
	pick_spell(pad,1)
	check(pad.friendly_spell() and pad.target_unit()==view,"strength buff also defaults to self")
	press("context");await frames()
	check(guest.orders.size()==1 and guest.orders[0].spell=="strength{}" and guest.orders[0].target==guest,"X self-buff reaches authority")
	guest.orders.clear();guest.order={}
	# Choose an actual enemy; its context ring must offer six equally spaced parts.
	var enemy: GameUnit
	for u: GameUnit in client.world.units.values():
		if not u.dead and u.controller<0 and client.world.is_enemy(view,u):enemy=u;break
	require(enemy!=null)
	pad.target={"unit":enemy};pad.cursor_mode=true;pad.open_ring();pad.cursor_mode=false
	check(pad.wheel.entries.size()==6,"body-part ring dedicates all six sectors to aimed strikes")
	var angles: Array=[]
	for i in 6:angles.append(pad.wheel.angle_of(i))
	angles.sort()
	check(angles==[0.0,60.0,120.0,180.0,240.0,300.0],"all body parts have equal selection sectors")
	var seen: Array=[]
	for i in 6:
		press("right");seen.append(pad.wheel.current().id[1])
	check(seen.size()==6 and seen.all(func(i):return seen.count(i)==1),"D-pad reaches every part exactly once")
	pad.wheel.selected=0
	pad.wheel.flick(Vector2.from_angle(deg_to_rad(-59)))
	check(pad.wheel.selected==0,"small boundary jitter keeps selected head")
	pad.wheel.flick(Vector2.from_angle(deg_to_rad(-45)))
	check(pad.wheel.current().id==["aim",2],"deliberate move selects next body part")
	if DisplayServer.get_name()!="headless":
		await frames();await RenderingServer.frame_post_draw
		check(cg.get_viewport().get_texture().get_image().save_png("user://gamepad-body-parts.png")==OK,"body-part wheel captured")
	press("interact");await frames()
	check(guest.orders.size()==1 and guest.orders[0].get("aim",-1)==2,"chosen body part reaches co-op attack order")
	guest.orders.clear();guest.order={}
	GameData.options.control_mode=1;await frames()
	pick_spell(pad);press("context");await frames()
	check(guest.orders.size()==1 and guest.orders[0].target==guest,"same self-cast shortcut works in classic gamepad mode")
	PadInput.release_all();PadInput.active="kbm"
	host.online=false;client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for node in branches:node.queue_free()
	await frames()
	print("GAMEPAD_COOP_TARGETS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
