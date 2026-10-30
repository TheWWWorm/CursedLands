extends "enchanted_equipment_net.gd"
## Recruitment followed by real guest unequip commands, without a zone reload.
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"show_tutorial":0},true)
	var h:=branch("Host",true);host=h.s;hg=h.g
	var c:=branch("Guest",false);client=c.s;cg=c.g
	var port:=29949 if GameData.campaign_id==CampaignProfile.ASTRAL else 29948
	check(host.host(port,2)==OK,"recruitment authority opens")
	CoopProgress.bring_slot="";GameData.player_name="Recruitment Guest"
	check(client.join("127.0.0.1",port)==OK,"recruitment guest connects")
	check(await until(func():return host.players.size()==2 and client.my_index==1),"recruitment handshake completes")
	if failures: await finish();return
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero")
	var zone:="gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g"
	await host.enter_zone(zone,1,false);freeze(host)
	check(await until(func():return client.world!=null and client.zone_id==zone and not client._remote_loading and not client._zone_holding,90),"guest enters recruitment fixture")
	if failures: await finish();return
	freeze(client)
	# Keep authority network/state batching running while simulation is frozen.
	host.set_physics_process(true)
	# LiA merc2 is Kel, the story companion the host always controls
	# (Session._story_companion), so a guest-owned LiA recruit uses merc10.
	var n:=10 if GameData.campaign_id==CampaignProfile.ASTRAL else 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--recruit="):n=int(arg.trim_prefix("--recruit="))
	var rec:=host._find_merc_record(n)
	if GameData.campaign_id==CampaignProfile.ASTRAL:
		# The base-game fallback intentionally scans basecam/bz2g. LiA
		# recruits are authored in its own chapter maps.
		rec={}
		for map in ["bz1h","bz2h","bz3h","bz4h","bz5h","bz6h","bz7h"]:
			var bytes := GameData.read_file("maps/%s.mob"%map)
			if not rec.is_empty() or bytes.is_empty(): continue
			var mob := EIMob.load_bytes(bytes)
			for row: Dictionary in mob.objects:
				if row.get("kind")=="UNIT" and String(row.get("name","")).to_lower()=="merc%d"%n:
					rec=row; break
	check(not host._story_companion(n),"fixture recruit is guest-assignable")
	check(not rec.is_empty(),"campaign supplies original recruit record")
	if failures: await finish();return
	print("RECRUIT_RECORD ",rec.name," ",rec.prototype)
	var at:Vector2=host.party_units(1)[0].pos+Vector2(2,0)
	rec=rec.duplicate(true);rec.nid=host.world.new_uid();rec.position=Vector3(at.x,at.y,0)
	var npc:=host.world.spawn_unit(rec);host.announce_unit(npc)
	host.merc_changed(n,true,1)
	check(await until(func():return client.world.units.has(npc.uid) and client.world.units[npc.uid].has_meta("hero")),"new recruitment reaches guest on the existing actor")
	var replica:GameUnit=client.world.units[npc.uid]
	check(is_same(replica.get_meta("hero"),client.state.mercs[n]),"new recruit links to current replicated roster")
	host.world.zone.type="brief";client.world.zone.type="brief"
	cg.selected.assign([replica]);cg.hud._inventory.open(false)
	var camp:=cg.hud._inventory._camp
	var kit:Array=host.state.mercs[n].armors.duplicate()+host.state.mercs[n].weapons.duplicate()
	check(not kit.is_empty(),"recruited actor carries its original equipment")
	for item:String in kit:
		client.submit({"t":"unequip","unit":npc.uid,"item":item})
		check(await until(func():return not item in replica.get_meta("hero").armors and not item in replica.get_meta("hero").weapons,3),"guest slot clears after removing "+item)
		check(item in client.state.items,"removed item reaches the guest bag")
	camp._process(0)
	check(replica.info.armors.is_empty() and replica.info.weapons.is_empty(),"world appearance has no removed gear")
	check(range(7).all(func(i):return camp._content.get("armor%d"%i,["?"])[0]==""),"camp shows empty armour slots")
	check(range(4).all(func(i):return camp._content.get("top%d"%i,["?"])[0]==""),"camp shows empty weapon slots")
	check(is_same(replica.get_meta("hero"),client.state.mercs[n]),"subsequent inventory states keep the recruited record linked")
	print("RECRUITED_EQUIPMENT_NET ", JSON.stringify({"checks":checks,"failures":failures}))
	await finish()
