extends "coop_story.gd"
const Refund := preload("res://src/game/training_refund.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func zero(h: Dictionary) -> bool:
	return Array(h.get("perks",[])).is_empty() and Skills.LIST.all(func(sk):return Skills.level(h,sk)==0)
func guest(s: Session) -> Dictionary:
	return s.party_units(1)[0].get_meta("hero")
func settled() -> void:
	for i in 12:await get_tree().process_frame
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	var a:=branch("Host",true);host=a.s;hg=a.g
	var b:=branch("Guest",false);client=b.s;cg=b.g
	cg.get_viewport().render_target_update_mode=SubViewport.UPDATE_ALWAYS
	require(host.host(29912,2)==OK)
	GameData.player_name="Training Guest";require(client.join("127.0.0.1",29912)==OK)
	require(await until(func():return host.players.size()==2))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Training Guest")
	var h: Dictionary=host.state.heroes[1][0]
	h.exp=10000.0;h.exp_total=200271.0;h.skills={"melee":25,"science":10};h.perks=["sword1","bs1"];h.erase(Refund.KEY)
	var expected:=float(h.exp)+Refund.amount(h)
	await host.enter_zone("bz2g",1,false);host.world.set_physics_process(false);host.world.vm.instances.clear()
	require(await until(func():return client.zone_id=="bz2g" and not client.loading_game and not client._remote_loading))
	var owner: GameUnit=host.party_units(0)[0]
	var uid: int=host.party_units(1)[0].uid
	var untouched: Dictionary=owner.get_meta("hero").duplicate(true)
	client.submit({"t":"refund_training","unit":owner.uid});await settled()
	check(owner.get_meta("hero").exp==untouched.exp and owner.get_meta("hero").perks==untouched.perks,"guest cannot refund the host's character")
	var panel:=cg.hud._inventory
	panel.open(false);panel._camp.set_mode("spells")
	await settled()
	if DisplayServer.get_name()!="headless":
		var rows: Array=panel._camp._skill_rows.filter(func(r):return r[3]=="refund")
		check(rows.size()==1 and not rows[0][1].is_empty(),"guest's older character has an enabled reset button")
		if not rows.is_empty():
			panel._camp._hover_desc=rows[0][2];panel._camp.queue_redraw()
		await settled()
		check(cg.get_viewport().get_texture().get_image().save_png("user://training-before.png")==OK,"guest reset tooltip captured")
		if not rows.is_empty():panel._camp.construct.emit(rows[0][1])
	else:client.submit({"t":"refund_training","unit":uid})
	check(await until(func():return zero(guest(host)) and zero(guest(client))),"guest UI/ENet reset reaches authority and presentation")
	check(guest(host).exp==expected and guest(client).exp==expected,"refund amount agrees on both peers")
	client.submit({"t":"perk","unit":uid,"perk":"sword1"})
	check(await until(func():return Perks.has(guest(client),"sword1")),"guest learns first ability through authority")
	var second:=Perks.cost("bs1",guest(client))
	client.submit({"t":"perk","unit":uid,"perk":"bs1"})
	check(await until(func():return Perks.has(guest(client),"bs1")),"guest learns discounted second ability")
	check(guest(host).exp==expected-Perks.cost("sword1")-second and guest(host).exp==guest(client).exp,"displayed marginal price equals the host's charge")
	client.submit({"t":"refund_training","unit":uid});client.submit({"t":"refund_training","unit":uid})
	check(await until(func():return zero(guest(client))),"two queued reset clicks return to zero")
	await settled()
	check(guest(host).exp==expected and guest(client).exp==expected,"duplicate request cannot pay twice")
	host.state.shops[2]={"restock":false,"goods":{"rune:e1":3},"sold":{}}
	host.open_shop(2)
	check(await until(func():return int(client.state.shops.get(2,{}).get("goods",{}).get("rune:ic",0))==20 and int(client.state.shops.get(2,{}).get("goods",{}).get("rune:it",0))==20),"new infusion stock reaches the co-op guest")
	check(client.state.shops[2].goods["rune:e1"]==3,"guest receives preserved older shop stock")
	if DisplayServer.get_name()!="headless":
		panel.refresh();await settled()
		check(cg.get_viewport().get_texture().get_image().save_png("user://training-after.png")==OK,"zero-allocation screen captured")
	panel.hide()
	check(host.save_game("coop_training")==OK,"co-op training saves")
	check(await host.load_game_shown("coop_training"),"co-op training reloads")
	host.world.set_physics_process(false)
	require(await until(func():return not client.loading_game and not client._remote_loading))
	check(zero(guest(host)) and zero(guest(client)) and guest(client).exp==expected,"guest reset remains correct across network reload")
	host.online=false;client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for root: Node in branches:root.queue_free()
	await settled()
	print("TRAINING_COOP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
