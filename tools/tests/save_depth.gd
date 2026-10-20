extends Node
## Prepared edge states, actual original map and full Session save/load in an isolated profile.
var out := "user://"
var scenario := "cast"
var s: Session
var game: Game
var result := {"checks":[],"before":{},"after":{}}
func check(ok: bool,label: String) -> void:
	result.checks.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)
func stop() -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	game.rig.set_process(false)
func hero() -> GameUnit:
	return s.party_units(0).filter(func(u:GameUnit):return u.has_meta("hero") and not u.get_meta("hero").has("merc"))[0]
func timers() -> Spells.WorldTimers:
	return s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
func drain(n:=200) -> void:
	for i in n:
		s.world._logic_step+=1; s.world.time+=GameUnit.TICK
		if timers(): timers()._tick(GameUnit.TICK,true)
func candidates() -> Array:
	return s.world.units.values().filter(func(u:GameUnit):return not u.dead and not u.has_meta("hero") and u.controller<0)
func animal(u:GameUnit) -> Dictionary:
	return {"uid":u.uid,"name":u.info.get("name",""),"proto":u.info.get("prototype",""),"stage":u.get_meta("tame_stage",0),"peace":u.get_meta("peace",[]),"faction":u.faction,"controller":u.controller,"hostile":s.world.is_enemy(u,hero()),"pet":CampaignState.is_pet(u),"original_faction":u.get_meta("tame_original_faction",-1),"tamer_faction":u.get_meta("tame_faction",-1)}
func _ready() -> void: _run.call_deferred()
func summary_marker() -> String: return "SAVE_DEPTH"
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--case="):scenario=arg.trim_prefix("--case=")
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"confine_mouse":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s=Session.new();add_child(s);s.set_physics_process(false)
	game=Game.new();game.session=s;s.game=game;add_child(game)
	s.state.ensure_hero(0,"Human Hero");s._enter_zone("gz1h" if scenario=="alarm" else "gz1g",1,false);stop()
	s.world.vm.instances.clear()
	match scenario:
		"cast": probe_cast()
		"taming": probe_taming()
		"pet": probe_pet()
		"boundaries": probe_boundaries()
		"pet_travel": probe_pet_travel()
	result.scenario=scenario;result.campaign=GameData.campaign_id
	FileAccess.open(out.path_join("deep-save.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	game.queue_free();s.queue_free()
	for i in 10: await get_tree().process_frame
	TexUpscale.shutdown(); print(summary_marker()," ",JSON.stringify({
		"scenario":scenario,"checks":result.checks.size(),"failures":result.checks.filter(func(c):return not c.ok).size()}))
	get_tree().quit(1 if result.checks.any(func(c): return not c.ok) else 0)

func probe_cast() -> void:
	var h:=hero();h.hp=h.max_hp*0.4;h.mana=h.max_mana;h.facing=0.0
	var hp_before:=h.hp;var mana_before:=h.mana
	h.order={"type":"cast","spell":"healing","target":h,"point":h.pos};h._do_cast(GameUnit.TICK)
	check(timers()!=null and timers().pending.size()==1,"normal cast schedules a delayed effect")
	check(h.mana<mana_before and h.hp==hp_before,"mana is paid before the healing effect")
	if not timers():return
	result.before={"hp":h.hp,"mana":h.mana,"original_mana":mana_before,"delay":timers().pending[0].left,"action":h.action,"lock":h._anim_lock,"lasting":Spells.save_lasting(s.world)}
	check(s.save_game("deep-cast")==OK,"save during cast succeeds")
	drain();check(h.hp>hp_before,"control: continuing without load delivers healing")
	result.control_hp=h.hp
	check(s.load_game("deep-cast"),"load during cast succeeds");stop();h=hero()
	result.after={"hp":h.hp,"mana":h.mana,"pending":timers().pending.size() if timers() else 0,"action":h.action,"lock":h._anim_lock}
	check(is_equal_approx(h.mana,float(result.before.mana)),"already paid mana survives load")
	check(timers()!=null and timers().pending.size()>0,"pending paid cast survives load")
	drain();result.after.drain_hp=h.hp
	check(h.hp>hp_before,"loaded paid cast eventually delivers healing")

func probe_taming() -> void:
	var h:=hero();var npcs:=candidates();check(npcs.size()>=3,"actual map has three untamed NPCs")
	if npcs.size()<3:return
	var ids:=[];var rows:=[]
	for stage in range(1,4):
		var n:GameUnit=npcs[stage-1];ids.append(n.uid)
		for i in stage: check(Spells.tame(s.world,h,n,1000000.0),"production charm transition %d/%d succeeds"%[i+1,stage])
		rows.append(animal(n))
	result.before=rows
	check(s.save_game("deep-taming")==OK,"save all three taming stages")
	check(s.load_game("deep-taming"),"reload all three taming stages");stop();h=hero()
	var a:GameUnit=s.world.units.get(ids[0]);var b:GameUnit=s.world.units.get(ids[1]);var pets:=s.world.units.values().filter(CampaignState.is_pet)
	result.after={"stage1":animal(a),"stage2":animal(b),"pets":pets.map(animal)}
	check(int(a.get_meta("tame_stage",0))==1,"partial charm stage 1 survives")
	check(not s.world.is_enemy(a,h),"charmed stage-1 creature remains peaceful")
	check(int(b.get_meta("tame_stage",0))==2,"partial charm stage 2 survives")
	check(b.faction==h.faction,"stage-2 faction survives as a control")
	check(int(b.get_meta("tame_original_faction",-1))==int(rows[1].original_faction) and int(b.get_meta("tame_faction",-1))==int(rows[1].tamer_faction),"original and tamer faction history survive reload")
	check(a.get_meta("peace",[])==rows[0].peace and b.get_meta("peace",[])==rows[1].peace,"allowed-hostility masks survive all partial stages")
	check(not Spells.tame(s.world,h,b,0.0) and int(b.get_meta("tame_stage",0))==2,"failed charm retains the intermediate stage")
	check(Spells.tame(s.world,h,b,1000000.0) and CampaignState.is_pet(b),"one more success completes stage-2 taming after load")
	check(pets.size()==1 and int(pets[0].get_meta("tame_stage",0))==3,"fully tamed pet survives as a control")

func probe_pet() -> void:
	var h:=hero();var p:GameUnit=candidates()[0]
	for i in 3: check(Spells.tame(s.world,h,p,1000000.0),"production charm reaches pet stage %d"%[i+1])
	s.world.vm.globals["AuditPet"]=p
	var arrow:=Projectile.launch(s.world,h,p,true);arrow.roll={"hit":true,"backstab":false}
	result.before={"pet":animal(p),"vm_ref":s.world.vm._ser(p),"spell_ref":Spells._caster_ref(p),"shots":Spells.save_lasting(s.world)}
	check(s.save_game("deep-pet")==OK,"save with a pet-referencing shot and VM value")
	check(s.load_game("deep-pet"),"reload pet references");stop()
	var pets:=s.world.units.values().filter(CampaignState.is_pet)
	check(pets.size()==1,"exactly one fully tamed pet restored")
	if pets.is_empty():return
	p=pets[0]
	var ref=s.world.vm.globals.get("AuditPet")
	var shots:=s.world.get_children().filter(func(c):return c is Projectile)
	result.after={"pet":animal(p),"vm_is_pet":ref==p,"vm_null":ref==null,"shot_count":shots.size(),"shots":Spells.save_lasting(s.world)}
	check(ref==p,"saved VM object reference resolves to restored pet")
	check(shots.size()==1 and shots[0].target==p,"saved targeted arrow resolves to restored pet")

func reset_actions(u: GameUnit) -> void:
	u._anim_lock=0.0;u._attack_cd=0.0;u.order={};u.orders.clear();u._pending_hit={}

func reload(slot: String) -> void:
	check(s.save_game(slot)==OK,"save boundary "+slot)
	check(s.load_game(slot),"load boundary "+slot);stop()

func probe_boundaries() -> void:
	var h:=hero();reset_actions(h);h.hp=h.max_hp*.3;h.mana=h.max_mana
	var hp:=h.hp;var mana:=h.mana
	h.command({"type":"cast","spell":"healing","target":h,"point":h.pos})
	reload("before-payment");h=hero()
	check(is_equal_approx(h.hp,hp) and is_equal_approx(h.mana,mana),"uncommitted cast costs nothing across save/load")
	check(Spells.save_lasting(s.world).is_empty(),"uncommitted cast does not manufacture a paid delivery")
	h.order={"type":"cast","spell":"healing","target":h,"point":h.pos};h._do_cast(GameUnit.TICK)
	var delay:=float(timers().pending[0].left);var paid:=h.mana;var lock:=h._anim_lock
	reload("after-payment");h=hero()
	check(is_equal_approx(h._anim_lock,lock),"committed cast recovery survives reload")
	check(is_equal_approx(float(timers().pending[0].left),delay),"remaining cast delay survives reload")
	drain(roundi(delay/GameUnit.TICK)-1)
	check(is_equal_approx(h.hp,hp),"cast does not deliver one tick early")
	reload("effect-boundary");h=hero()
	check(is_equal_approx(float(timers().pending[0].left),GameUnit.TICK),"exact last logic tick survives reload")
	drain(1)
	check(h.hp>hp and is_equal_approx(h.mana,paid),"last tick delivers healing without another mana charge")
	check(not Spells.save_lasting(s.world).any(func(r):return r.k=="cast"),"delivered cast is removed before the next save")
	h.hp=hp;reload("after-delivery");h=hero();drain(80)
	check(is_equal_approx(h.hp,hp),"post-delivery reload cannot heal twice")
	reset_actions(h);h.mana=h.max_mana
	h.order={"type":"cast","spell":"healing","target":h,"point":h.pos};h._do_cast(GameUnit.TICK)
	h.hp=0.0;h.lie_dead();reload("dead-caster");h=hero();hp=h.hp;drain(80)
	check(h.dead and is_equal_approx(h.hp,hp),"a dead caster's pending heal does not revive it")
	# Removed actors must not resolve through a fresh actor with the same UID.
	check(s.load_game("before-payment"),"restore living boundary fixture");stop();h=hero()
	var n:GameUnit=candidates()[0]
	Spells.cast_after(s.world,n,"healing",h,h.pos,GameUnit.TICK)
	s.world.remove_unit(n);reload("removed-caster");h=hero();hp=h.hp;drain(2)
	check(is_equal_approx(h.hp,hp),"removed caster cancels delivery after reload")
	n=candidates()[0]
	Spells.cast_after(s.world,h,"healing",n,n.pos,GameUnit.TICK)
	s.world.remove_unit(n);reload("removed-target");h=hero();hp=h.hp;drain(2)
	check(is_equal_approx(h.hp,hp),"removed target does not redirect healing to the caster")
	n=candidates()[0];var nid:=n.uid
	Spells.cast_after(s.world,h,"healing",n,n.pos,GameUnit.TICK)
	n.hp=0.0;n.lie_dead();reload("dead-target");drain(2)
	check(s.world.units[nid].dead,"pending healing never revives a dead target")

func probe_pet_travel() -> void:
	var h:=hero();var animals:=candidates().slice(0,3)
	var keys:=[]
	for n:GameUnit in animals:
		for i in 3:check(Spells.tame(s.world,h,n,1000000.0),"tame travelling pet")
		keys.append(Spells._caster_ref(n))
	check(keys[0]!=keys[1] and keys[1]!=keys[2],"multiple pets have distinct persistent identities")
	s.world.vm.globals.AuditPets=animals
	var target:GameUnit=animals[1];var source:GameUnit=animals[0]
	var arrow:=Projectile.launch(s.world,source,target,true);arrow.roll={"hit":true,"backstab":false}
	reload("pet-travel-start")
	check(s.world.vm.globals.AuditPets[0]==Spells._caster_of(s.world,keys[0]),"nested VM pet references survive save/load")
	s._enter_zone("gz1h",1,false);stop()
	check(keys.all(func(k):return Spells._caster_of(s.world,k)!=null),"all pet identities survive zone travel")
	s._enter_zone("gz1g",1,false);stop()
	check(s.world.vm.globals.AuditPets[1]==Spells._caster_of(s.world,keys[1]),"revisited-zone VM binds the returning pet")
	var shots:=s.world.get_children().filter(func(c):return c is Projectile)
	check(shots.size()==1 and shots[0].source==Spells._caster_of(s.world,keys[0]) and shots[0].target==Spells._caster_of(s.world,keys[1]),"pet caster and target rebind after leaving and revisiting a zone")
	var dead_pet:=Spells._caster_of(s.world,keys[0]);dead_pet.hp=0.0;dead_pet.lie_dead()
	reload("dead-pet")
	dead_pet=Spells._caster_of(s.world,keys[0])
	check(dead_pet!=null and dead_pet.dead and s.world.vm.globals.AuditPets[0]==dead_pet,"dead travelling pet retains its corpse identity in the VM")
	check(s.world.units.values().filter(CampaignState.is_pet).size()==2,"dead pet is not redeployed as a living duplicate")
	s.world.remove_looted(dead_pet);reload("looted-pet")
	dead_pet=Spells._caster_of(s.world,keys[0])
	check(dead_pet!=null and dead_pet.dead and s.world.looted.get(dead_pet.uid)==dead_pet and s.world.vm.globals.AuditPets[0]==dead_pet,"looted pet retains a stable VM tombstone without respawning")
	var removed:=Spells._caster_of(s.world,keys[1]);s.world.remove_unit(removed)
	reload("removed-pet")
	check(Spells._caster_of(s.world,keys[1])==null,"removed pet key cannot bind a different deployed actor")
	check(Spells._caster_of(s.world,keys[2])!=null,"removing one pet retains another pet's identity")
