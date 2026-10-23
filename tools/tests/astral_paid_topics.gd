extends "astral_fortune.gd"
## Exercise the shipped paid-rumour scripts through the actual topic/close
## path. Wallets change after the original offer poll and after the list opens.
## The raw original script provides the reference when its wallet is current.
const ZONE16_EDITIONS := {
	"aba195909addc8771cdb25ceb04d709a62243341291dd843dfc6393d603ba4d7":"1.00",
	"09ca5c96dec5f87d6bf06e80b8178b4a54cae88a1e70a1c40be3938143c2b082":"1.01",
	"580852c8b985be8fe86402a253f4672cc9e6a9c82bb5587a420a6beea47759c1":"1.02",
}

func paid_market(zone: String, name: String, n: int, cash: int, adapt := true) -> Dictionary:
	market()
	var vm := vm_for(zone, zone, adapt)
	s.state.money = cash
	var npc := actor(ScriptVM.name_id(name), Vector2(40, 40))
	npc.info.name = name
	var script := ("Skelet#%d" % (n-1)) if zone == "bz5h" else ("Spletnica#%d" % (n-8))
	# Set only the authored non-wallet prerequisites, including previous quest.
	for condition: Array in vm.ast.scripts[script].blocks[0].conds.slice(1):
		s.state.set_var(0, condition[2][0][2][1][1], condition[2][1][1])
	start(vm, script)
	start(vm, ("BuySkeletMain#2#%d#0"%(n-1)) if zone=="bz5h" else ("BuySpletnicaMain#2#%d#0"%(n-8)))
	return {"vm":vm, "npc":npc, "script":script}

func original_outcomes() -> void:
	for zone: String in ["bz5h","bz11g"]:
		var gipat := zone=="bz11g"
		var price := 500 if gipat else 50
		for n in (range(9,14) if gipat else range(2,7)):
			for cash in [0,price-1,price,price+1]:
				var outcomes := []
				for adapt in [false,true]:
					var row := paid_market(zone,"Spletnica" if gipat else "skelet",n,cash,adapt)
					var vm: ProbeVM = row.vm
					var entries := vm.briefings.available_for(row.npc,0)
					check(entries.size()==1,"native reference has one authored response")
					if entries.size()!=1: continue
					var key := "b.%s.%s"%entries[0]
					vm.briefings.topic(0,key,row.npc.uid)
					vm.briefings.complete(0,vm.briefings.active,true)
					step(vm,20)
					outcomes.append(result())
				check(outcomes.size()==2 and outcomes[0]==outcomes[1],"%s %d wallet %d: original script price, journal, unlocks and inventory match"%[zone,n,cash])

func exclusions() -> void:
	for zone: String in ["bz5h","bz11g"]:
		var gipat := zone=="bz11g"
		var name := "Spletnica" if gipat else "skelet"
		var n := 9 if gipat else 2
		var row := paid_market(zone,name,n,0)
		var vm: ProbeVM = row.vm
		var raw_entries := Briefings.pending_for(s.state,row.npc,1)
		s.state.campaign_id=CampaignProfile.ORIGINAL
		check(vm.briefings.available_for(row.npc,1)==raw_entries,"base campaign keeps authored topics untouched")
		s.state.campaign_id=CampaignProfile.ASTRAL
		for stage in [1,2,3]:
			s.state.set_var(0,"b.shava.fq9" if gipat else "b.skelet.fq2",stage)
			# b.skelet.fq2=1 is also a separate generic GS topic under the
			# native topic-list rules; it must not be filtered as a paid offer.
			var entries := vm.briefings.available_for(row.npc,1)
			check(not entries.any(func(e):return String(e[1]).trim_suffix("f")==("fq9" if gipat else "skelet_fq2")),"a stale offer cannot sell already advanced rumour "+str(stage))
			var before := result()
			vm.briefings.topic(1,"b.Spletnica.fq9" if gipat else "b.skelet.skelet_fq2",row.npc.uid)
			check(vm.briefings.active.is_empty() and result()==before,"stale selection cannot charge or play a completed rumour")
		row=paid_market(zone,name,n,0);vm=row.vm
		var prerequisite := "q.gz9g.fq8" if gipat else "q.gz1h.q4h"
		s.state.set_var(0,prerequisite,1)
		check(vm.briefings.available_for(row.npc,1).is_empty(),"a stale offer cannot bypass original previous-quest gate")
		# Modify the actual original AST before recognition, as mod loading does.
		for change: String in ["price","side_effect","prerequisite"]:
			row=paid_market(zone,name,n,0,false);vm=row.vm
			var offer: Dictionary = vm.ast.scripts[row.script]
			if change=="price":offer.blocks[0].conds[0][2][0][2][1][1]+=1
			elif change=="side_effect":offer.blocks[0].body.append([ScriptParser.S_CALL,"Nop",[]])
			else:offer.blocks[0].conds[1][2][1][1]=1.0
			Fortunes.apply(vm.ast,zone)
			check(vm.briefings.available_for(row.npc,1)==Briefings.pending_for(s.state,row.npc,1),"modified "+change+" retains original mod topic decision")
		row=paid_market(zone,name,n,0,false);vm=row.vm
		vm.ast.scripts["BuySpletnicaMain#2#1#0" if gipat else "BuySkeletMain#2#1#0"].blocks[0].body.pop_back()
		Fortunes.apply(vm.ast,zone)
		s.state.set_var(0,"b.Spletnica.fq9" if gipat else "b.skelet.skelet_fq2",2)
		Fortunes.recover(vm)
		check(s.state.get_var(0,"b.shava.fq9" if gipat else "b.skelet.fq2")==0,"modified completion bridge retains its own effects")
	for n in range(9,14):
		var row := paid_market("bz11g","Spletnica",n,500)
		s.state.set_var(0,"b.Spletnica.fq%d"%n,2)
		FileAccess.open("user://pending-gipat-rumour.sav",FileAccess.WRITE).store_var(s.state.to_dict())
		s.state=CampaignState.load_from("user://pending-gipat-rumour.sav")
		Fortunes.recover(row.vm)
		check(s.state.get_var(0,"b.shava.fq%d"%n)==2,"saved Gipat completion resumes its original durable bridge")

func gipat_downstream() -> void:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(GameData.read_file("maps/zone16.mob"))
	var edition: String = ZONE16_EDITIONS.get(hash.finish().hex_encode(),"")
	check(not edition.is_empty(),"downstream fixture is a verified CD, 1.01 or 1.02 map")
	if edition.is_empty(): return
	for row: Array in [["gz11g","zone11","VCheck#6#1",9,"zone11_fq9"],
		["gz16g","zone16","VCheck#3#1",10,"zone16_fq10"],
		["gz7g","zone7","VCheck#5#1",11,"zone7_fq11"],
		["gz16g","zone16","VCheck#4#1",12,"zone16_fq12"]]:
		fixture()
		var reference := vm_for(row[0],row[1],false)
		var current := vm_for(row[0],row[1])
		check(current.ast.has_meta(AstralPatches.META) if row[1]=="zone16" else true,"official zone16 correction is recognized")
		if row[3]==10:
			var lever := Node3D.new();allocations.append(lever)
			lever.set_meta("ei",{"nid":4955,"position":Vector3.ZERO});s.world.objects[4955]=lever
			s.world.levers[4955]={"state":0,"enabled":false}
		for bought in [0,1,2,3]:
			for stage in [0,1,2,3]:
				s.state.set_var(0,"b.shava.fq%d"%row[3],bought);s.state.set_var(0,row[4],stage)
				for lever_state in ([0,1] if row[3]==10 else [0]):
					if row[3]==10:s.world.levers[4955].state=lever_state
					var outputs := []
					for vm: ProbeVM in [reference,current]:
						outputs.append(vm.ast.scripts[row[2]].blocks[0].conds.all(func(c):return bool(vm._eval(c,ScriptVM.Instance.new()))))
					var ready: bool = stage==0
					# 1.01 uses the actual lever state for fq10; 1.02 allows
					# fq12 setup again after purchase regardless of its old flag.
					if row[3]==10 and edition!="1.00":ready=lever_state==0
					if row[3]==12 and edition=="1.02":ready=true
					var expected: bool = bought==2 and ready
					var patched_ready: bool = lever_state==0 if row[3]==10 else (true if row[3]==12 else stage==0)
					check(outputs==[expected,bought==2 and patched_ready],"%s %s: native and built-in 1.02 gates, purchase=%d flag=%d lever=%d"%[row[2],edition,bought,stage,lever_state])
	# The fifth rumour describes an existing crypt; the original does not
	# require buying the information before opening it. Do not add that gate.
	fixture()
	var vm := vm_for("gz11d1","zone11dun1")
	check(not str(vm.ast.scripts["Crypt#4"]).contains("b.shava.fq13"),"crypt reward retains original exploration without paid hint")

func wallet_cases() -> void:
	for zone: String in ["bz5h", "bz11g"]:
		var name := "skelet" if zone == "bz5h" else "Spletnica"
		var price := 50 if zone == "bz5h" else 500
		for n in (range(2,7) if zone == "bz5h" else range(9,14)):
			var id := "skelet_fq%d" % n if zone == "bz5h" else "fq%d" % n
			check(-int(GameData.db.find("briefings",id).get("money",0)) == price, id+": price agrees with shipped reward record")
			for player in [0,1]:
				# Host selected branch; buyer balance at list opening and click.
				for scenario: Array in [[0,price,price], [price,price-1,price-1], [0,0,price], [price,price,price-1]]:
					var row := paid_market(zone,name,n,scenario[0])
					var vm: ProbeVM = row.vm
					if player == 0: s.state.money = scenario[1]
					else: s.coop.joiners.guest.purse.money = scenario[1]
					var entries := vm.briefings.available_for(row.npc,player)
					check(entries.size()==1, id+": one original offer remains visible")
					if entries.size()!=1: continue
					var key := "b.%s.%s" % entries[0]
					check(key.to_lower().ends_with(id if scenario[1]>=price else id+"f"),id+": list uses player %d current wallet %s" % [player,str(scenario)])
					if player == 0: s.state.money = scenario[2]
					else: s.coop.joiners.guest.purse.money = scenario[2]
					var other := s.coop.owner_money(1-player)
					s.coop.with_purse(player,vm.briefings.topic.bind(player,key,row.npc.uid))
					var accepted: bool = scenario[2]>=price
					check(vm.briefings.active.to_lower().ends_with(id if accepted else id+"f"),id+": click reevaluates buyer %d balance"%player)
					var completion := vm.briefings.active
					check(not completion.is_empty(),id+": selected original conversation starts")
					s.coop.with_purse(player,vm.briefings.complete.bind(player,completion,true))
					check(s.coop.owner_money(player)==scenario[2]-(price if accepted else 0),id+": correct first-attempt debit")
					check(s.coop.owner_money(1-player)==other,id+": other purse unchanged")
					step(vm,4)
					var flag := ("b.skelet.fq%d" if zone=="bz5h" else "b.shava.fq%d")%n
					check(s.state.get_var(0,flag)==(2 if accepted else 0),id+": only paid success unlocks the original downstream flag")

func refresh_race() -> void:
	for player in [0,1]:
		for n in range(9,14):
			var row := paid_market("bz11g","Spletnica",n,500)
			var vm: ProbeVM = row.vm
			var key := "b.Spletnica.fq%d"%n
			vm.briefings.play_named("fq%d"%n,key,player,null,true)
			vm.briefings.complete(player,key)
			start(vm,"BuyMain#1");step(vm,4)
			check(s.state.get_var(0,"b.shava.fq%d"%n)==2,"Gipat rumour %d: player %d paid completion survives refresh"%[n,player])
			var before := result()
			vm.briefings.complete(player,key);Fortunes.recover(vm)
			check(result()==before,"Gipat rumour %d: duplicate completion is harmless"%n)

func _ready() -> void:
	GameData.options.coop_share_loot=0
	wallet_cases();refresh_race();original_outcomes();exclusions();gipat_downstream()
	for instance:ProbeVM in vms:instance.briefings=null;instance.instances.clear();instance.globals.clear();instance.seen.clear();instance.actions.clear()
	vms.clear()
	for node:Node in allocations:
		if node is GameWorld:node.units={};node.looted.clear();node.objects.clear();node.vm=null
	for node:Node in allocations:node.free()
	print("ASTRAL_PAID_TOPICS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
