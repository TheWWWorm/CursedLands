extends Node
## Compare against byte-qualified original EXE captures, then exercise the
## console's real damage, movement, persistence and typed-command boundaries.
var checks := 0
var failures := 0
var s: Session
var u: GameUnit

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

func command(line: String) -> PackedStringArray:
	return ConsoleCommands.execute(s,line)

func original_cases() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/fixtures/original_god_mode.json"))
	var ref: Dictionary = document.campaigns["lost_in_astral" if GameData.campaign_id==CampaignProfile.ASTRAL else "original"]
	for row: Dictionary in ref.setter:
		command("@GodMode(%d,%d)"%[row.owner,row.mode])
		check(int(s.state.god_modes.get(0,0))==int(row.stored),"original dispatcher stores only the named existing player's mode")
	for row: Dictionary in ref.movement:
		command("@GodMode(0,%d)"%row.mode)
		for part: UnitBodyPart in u.parts:part.cur=part.max
		u.stats.load=0.0;u.stats.max_load=100.0
		if int(row.refusal)==1:
			for part: UnitBodyPart in u.parts:
				if part.type==3:part.cur=part.max*0.1
		elif int(row.refusal)==2:u.stats.load=101.0
		u.mana=float(row.mana);u.max_mana=150.0
		check(u.run_refusal()==int(row.refusal),"real body/load produces the native refusal input")
		check(not u.cannot_run()==bool(row.can_run),"running admission matches original: "+str(row))
		# Compare an already-running tick independently of the admission gate,
		# exactly as captured. Disable recovery and all unrelated pending orders.
		u.action="run";u.order={};u.orders.clear();u._pending_hit.clear();u._regen_t=0.0;u._anim_lock=0.0
		u._tick(GameUnit.TICK)
		check(absf(u.mana-float(row.after_running_tick))<0.00001,"running stamina matches original: "+str(row))
	for part: UnitBodyPart in u.parts:part.cur=part.max
	for row: Dictionary in ref.damage:
		u.controller=0 if row.owned else -1
		command("@GodMode(0,%d)"%row.mode)
		u.heal(u.max_hp)
		var before := u.hp
		u._anim_lock=1.0
		u.take_damage(1.0,null)
		check((u.hp<before)==bool(row.accepts_damage),"native damage acceptance for owned=%s mode=%s"%[row.owned,row.mode])
	u.controller=0

func additional_commands() -> void:
	var hero := 'GetUnitOfPlayer(0,0)'
	var native_id := float(PackedFloat32Array([u.uid])[0])
	check(float(command("#GetObjectID("+hero+")")[0])==native_id,"query obtains the actual player record with native float32 ID storage")
	check(float(command("#GetObjectID(GetLeader(0))")[0])==native_id,"leader query resolves live party with native float32 ID storage")
	check(float(command("#DistanceUnitUnit("+hero+","+hero+")")[0])==0.0,"distance query composes object arguments")
	check(float(command("#DistanceUnitPoint("+hero+",GetX("+hero+"),GetY("+hero+"))")[0])==0.0,"distance query composes coordinate arguments")
	for name: String in ["GetFutureX","GetFutureY","IsUnitBlocked","WasLooted"]:
		check(command("#"+name+"("+hero+")")[0].is_valid_float(),"typed original query: "+name)
	for row: Array in [["Lie",0],["Crawl",1],["Stand",2]]:
		command("@"+row[0]+"("+hero+")")
		check(u.stance==([GameUnit.STANCE_CRAWL,GameUnit.STANCE_KNEEL,GameUnit.STANCE_NONE][row[1]]),"original posture command "+row[0])
	command("@FixWorldTime(12)")
	check(s.world.vm.time_fixed and s.state.world_time==12.0,"freeze clock at chosen hour")
	command("@RunWorldTime(19)")
	check(not s.world.vm.time_fixed and s.state.world_time==19.0,"resume clock at chosen hour")
	check(command("#HaveItem(0,\"missing-console-item\")")==PackedStringArray(["0.0"]),"missing quest item query returns zero")
	check(command("#IsInArea(987654,0,0)")==PackedStringArray(["0.0"]),"missing area query returns false")
	check(command("#GetDiplomacy(0,0)")[0].is_valid_float(),"diplomacy query is available")
	check(command("#GetMercsNumber(0)")[0].is_valid_float(),"party count query is available")
	var found := false
	for id in s.world.levers:
		if not s.world.objects.has(id):continue
		found=true
		var object := "GetObject(%d)"%int(id)
		command("@EnableLever("+object+",1)")
		check(s.world.levers[id].enabled,"console enables actual map mechanism")
		command("@EnableLever("+object+",0)")
		check(not s.world.levers[id].enabled,"console disables actual map mechanism")
		command("@SwitchLeverStateEx("+object+",1,0)")
		check(float(command("#GetLeverState("+object+")")[0])==1.0,"console changes and queries actual mechanism state")
		command("@SwitchLeverState("+object+",0)")
		check(float(command("#GetLeverState("+object+")")[0])==0.0,"original timed switch restores actual mechanism state")
		break
	check(found,"loaded original map supplies a lever fixture")

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"free_run":0,"stamina_regen":0},true)
	s=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	var zone := "gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g"
	await s.enter_zone(zone,1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	u=s.party_units(0)[0]
	original_cases()
	command("@GodMode(0,1)")
	var hp := u.hp
	var mp := u.mana
	command("@GodMode(0,0)");command("@GodMode(0,1)")
	check(u.hp==hp and u.mana==mp,"toggling does not heal wounds or refill stamina")
	check(u._spell_cost({"mana":10.0})>0.0,"GodMode retains original spell costs")
	for line: String in ["@GodMode(0,2)","@GodMode(0,-1)","@GodMode(0,0.5)","@GodMode(0.5,1)","#GodMode(0,0)","@EnableLever(1,1)"]:
		check(command(line)==PackedStringArray([RemakeText.t(ConsoleCommands.ERROR)]) and u.god_mode(),"unsupported argument/query cannot mutate: "+line)
	ConsoleCommands.execute(s,"@GodMode(0,0)",1)
	check(u.god_mode(),"guest cannot disable the host's mode")
	command("@GodMode(0,0)")
	check(not u.god_mode() and s.state.god_modes.is_empty(),"disable removes the saved cheat flag")
	additional_commands()
	command("@GodMode(0,1)")
	check(s.state.save("user://console-mode.sav")==OK,"mode can be saved")
	var restored := CampaignState.load_from("user://console-mode.sav")
	check(restored!=null and restored.god_modes.get(0,0)==1,"mode survives campaign save/load")
	var old := s.state.to_dict();old.erase("god_modes")
	FileAccess.open("user://console-legacy.sav",FileAccess.WRITE).store_var(old)
	check(CampaignState.load_from("user://console-legacy.sav").god_modes.is_empty(),"legacy saves keep GodMode off")
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	print("CONSOLE_GOD_MODE ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
