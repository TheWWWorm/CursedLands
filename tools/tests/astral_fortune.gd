extends "story_coop_predicates.gd"
## Original LiA market scripts, real paid briefings, and persisted cross-map flags.
## Controlled script inputs: this is archive parity, not a native EXE run.
const Fortunes := preload("res://src/game/script/story_astral_fortunes.gd")

func market(adapt := true) -> ProbeVM:
	fixture()
	s.is_host=true;s.online=true;s.my_index=0;s.players={1:{"index":0},2:{"index":1}}
	s.coop=CoopProgress.new();s.coop.session=s;s.add_child(s.coop)
	s.coop.joiners={"guest":{"idx":1,"purse":{"money":500,"items":[]}}}
	s.state.money=500
	return vm_for("bz5h","bz5h",adapt)

func buy(vm: ProbeVM, n: int, player: int) -> void:
	var topic:="b.skelet.skelet_fq%d"%n
	vm.briefings.play_named("skelet_fq%d"%n,topic,player,null,true)
	vm.briefings.complete(player,topic)

func result() -> Dictionary:
	return {"vars":s.state.vars.duplicate(),"money":s.state.money,
		"guest":s.coop.purse_entry(1).purse.duplicate(true),"quests":s.state.quests.duplicate(true),"items":s.state.items.duplicate()}

func normal_parity() -> void:
	for n in range(2,7):
		var outcomes:=[]
		for adapt in [false,true]:
			var vm:=market(adapt)
			s.state.set_var(0,"b.skelet.skelet_fq%d"%n,1)
			start(vm,"BuySkeletMain#2#%d#0"%(n-1))
			buy(vm,n,0);step(vm,20)
			outcomes.append(result())
		check(outcomes[0]==outcomes[1],"fortune %d: settled flags, price, quests and bag match unadapted original scripts"%n)

func completion_race() -> void:
	for player in [0,1]:
		for n in range(2,7):
			var vm:=market()
			var topic:="b.skelet.skelet_fq%d"%n
			var flag:="b.skelet.fq%d"%n
			s.state.set_var(0,topic,1);s.state.set_var(0,"b.NSheriff.buy_1",2)
			start(vm,"BuySkeletMain#2#%d#0"%(n-1))
			buy(vm,n,player)
			check(s.coop.owner_money(player)==450 and s.coop.owner_money(1-player)==500,"fortune %d: original 50 gold charged to speaker %d only"%[n,player])
			start(vm,"BuyNSheriffMain#1");step(vm,5)
			check(s.state.get_var(0,flag)==2,"fortune %d: player %d completion survives catalogue refresh before next poll"%[n,player])
			var before:=result()
			vm.briefings.complete(player,topic);Fortunes.recover(vm);Fortunes.recover(vm)
			check(result()==before,"fortune %d: duplicate close/recovery cannot charge, grant or reset again"%n)

func gates_and_saves() -> void:
	var vm:=market()
	# Exercise the real offer prerequisites rather than unlocking every topic.
	s.state.set_var(0,"b.skelet.skelet_about",2);s.state.set_var(0,"q.gz1h.q4h",2)
	s.state.set_var(0,"b.NSheriff.buy_1",2)
	start(vm,"BuyNSheriffMain#1");step(vm,5)
	check(s.state.get_var(0,"b.skelet.skelet_fq2")==1,"original prerequisite offers the torch fortune")
	check(s.state.get_var(0,"b.skelet.skelet_fq3")!=1,"later fortune still requires the previous original quest")
	vm=market();s.state.money=49
	s.state.set_var(0,"b.skelet.skelet_about",2);s.state.set_var(0,"q.gz1h.q4h",2)
	start(vm,"Skelet#1")
	check(s.state.get_var(0,"b.skelet.skelet_fq2")!=1 and s.state.get_var(0,"b.skelet.skelet_fq2f")==1,"original insufficient-money branch stays in effect")
	for n in range(2,7):
		for source in [0,1,3]:
			vm=market();s.state.set_var(0,"b.skelet.skelet_fq%d"%n,source)
			Fortunes.recover(vm)
			check(s.state.get_var(0,"b.skelet.fq%d"%n)==0,"fortune %d: unavailable/offered/hidden state %d cannot unlock"%[n,source])
		vm=market();s.state.set_var(0,"b.skelet.skelet_fq%d"%n,2)
		FileAccess.open("user://pending-fortune.sav",FileAccess.WRITE).store_var(s.state.to_dict())
		s.state=CampaignState.load_from("user://pending-fortune.sav")
		vm=vm_for("gz1h","zone1")
		Fortunes.recover(vm)
		check(s.state.get_var(0,"b.skelet.fq%d"%n)==2,"fortune %d: saved completed conversation survives leaving the market before poll"%n)
		check(s.state.get_var(0,"z.gz1d1")==0 and s.state.get_var(0,"q.gz1h.fq2")==0,"recovery does not open the entrance or complete the torch quest itself")

func downstream_gates() -> void:
	# The permanent flags feed several unrelated originals: the torch,
	# midday basket, dead man, nocturnal undead and the three cave levers.
	for row:Array in [["gz1h","zone1","Raja#0",2,"q.gz1h.fq2"],
		["gz1h","zone1","DeadMan#1",4,"deadman"],
		["gz2h","zone2","BigBasket#1#1",3,"q.gz2h.fq3"],
		["gz2h","zone2","Undead#1#1",5,"q.gz2h.fq5"],
		["gz4h","zone4","VLever1#0#0",6,"q.gz4h.fq6"]]:
		fixture()
		var reference:=vm_for(row[0],row[1],false)
		var current:=vm_for(row[0],row[1])
		for topic in [0,1,2,3]:
			for stage in [0,2]:
				for hour in [12.0,12.01,12.4,22.0,22.01]:
					s.state.set_var(0,"b.skelet.fq%d"%row[3],topic)
					s.state.set_var(0,row[4],stage);s.state.world_time=hour
					var actual:=[]
					for vm:ProbeVM in [reference,current]:
						var inst:=ScriptVM.Instance.new();inst.locals.this=null
						actual.append(vm.ast.scripts[row[2]].blocks[0].conds.all(func(c):return bool(vm._eval(c,inst))))
					var expected:bool=topic==2 and stage==0
					if row[3]==3:expected=expected and hour>12.0 and hour<12.4
					if row[3]==5:expected=expected and hour>22.0
					check(actual==[expected,expected],"%s: native gate topic=%d stage=%d hour=%.2f"%[row[2],topic,stage,hour])

func boundaries() -> void:
	var vm:=market(false)
	var original:=vm.ast.scripts.duplicate(true)
	Fortunes.apply(vm.ast,"bz5h")
	check(vm.ast.has_meta(&"astral_fortunes") and vm.ast.scripts==original,"recognition leaves original script bodies and saved instruction offsets intact")
	Fortunes.apply(vm.ast,"bz5h")
	check(vm.ast.scripts==original,"recognition is idempotent")
	vm=market(false)
	vm.ast.scripts["BuySkeletMain#2#1#0"].blocks[0].body.pop_back()
	Fortunes.apply(vm.ast,"bz5h");s.state.set_var(0,"b.skelet.skelet_fq2",2);Fortunes.recover(vm)
	check(not vm.ast.has_meta(&"astral_fortunes") and s.state.get_var(0,"b.skelet.fq2")==0,"modified market scripts retain their own completion semantics")
	vm=market();s.state.campaign_id=CampaignProfile.ORIGINAL
	s.state.set_var(0,"b.skelet.skelet_fq2",2);Fortunes.recover(vm)
	check(s.state.get_var(0,"b.skelet.fq2")==0,"base campaign cannot receive the LiA repair")

func _ready() -> void:
	GameData.options.coop_share_loot=0
	normal_parity();completion_race();gates_and_saves();downstream_gates();boundaries()
	for instance:ProbeVM in vms:instance.briefings=null;instance.instances.clear();instance.globals.clear();instance.seen.clear();instance.actions.clear()
	vms.clear()
	for n:Node in allocations:
		if n is GameWorld:n.units={};n.looted.clear();n.objects.clear();n.vm=null
	for n:Node in allocations:n.free()
	print("ASTRAL_FORTUNE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
