extends Node
## Real ENet progress return followed by an independent offline Session.
## Prepared casts, pet ownership and projectiles in the original opening map.
var host: Session
var client: Session
var branches: Array[Node] = []
var branch_count := 0
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func until(predicate: Callable, seconds := 90.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func branch(guest: bool) -> Session:
	var root: Node = SubViewport.new() if guest else Node.new()
	if root is SubViewport:
		root.size = Vector2i(1280,720); root.own_world_3d = true
		root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	branch_count += 1; root.name = "TrapBranch"+str(branch_count); add_child(root); branches.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path()
	get_tree().set_multiplayer(api,root.get_path())
	var s := Session.new(); s.name = "Session"; root.add_child(s)
	var g := Game.new(); g.session = s; s.game = g; root.add_child(g)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.rig.set_process(false); s.game.hud._tutorial.close(); s.game.hud._dialog.visible = false

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz1g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func ticks(count: int) -> void:
	for i in count:
		host.world.time += ScriptVM.POLL; host.world.vm.tick(ScriptVM.POLL)

func visitor() -> GameUnit:
	for u: GameUnit in host.party_units(1):
		if not u.get_meta("hero",{}).has("merc"): return u
	return null

func sync_visitor(u: GameUnit) -> bool:
	var deadline := Time.get_ticks_msec()+5000; var next := 0
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= next:
			next = Time.get_ticks_msec()+50; host._send_snapshot_records([u.snapshot()],host.world.time)
		await get_tree().process_frame
		var replica: GameUnit = client.world.units.get(u.uid)
		if replica and replica.dead == u.dead and replica.pos.distance_to(u.pos) < .03: return true
	return false

func connect_guest() -> bool:
	client = branch(true); GameData.player_name = "Boundary Guest"
	check(client.join("127.0.0.1",29933) == OK,"connect guest")
	var ready := await until(loaded)
	check(ready,"guest receives live throne room")
	if ready: freeze(client)
	return ready

var out := "user://"
var evidence := {}
func stop_branches() -> void:
	for s:Session in [client,host]:
		if is_instance_valid(s):
			var peer:=s.multiplayer.multiplayer_peer
			s.online=false;s.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
			if peer:peer.close()
	for root:Node in branches:root.queue_free()
	branches.clear();await frames(10);host=null;client=null
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"confine_mouse":0},true)
	var origin:=CoopProgress.fresh_state();origin.heroes[0][0].name="Depth Guest"
	check(origin.save(SaveInfo.path("depth-origin"))==OK,"disposable guest origin saves")
	host=branch(false);host.state=CoopProgress.fresh_state();host.state.heroes[0][0].name="Depth Host"
	host.set_physics_process(false);GameData.player_name="Depth Host"
	check(host.host(29953,2)==OK,"real ENet host opens")
	client=branch(true);CoopProgress.bring_slot="depth-origin";GameData.player_name="Depth Guest"
	check(client.join("127.0.0.1",29953)==OK,"guest imports its campaign over ENet")
	check(await until(func():return host.coop.joiners.has("depth guest") and host.players.size()==2 and client.my_index==1),"host receives imported guest")
	if failures:done.call_deferred();return
	CampaignState.watch=host.coop._on_var
	await host.enter_zone("gz1g",1,false);freeze(host)
	check(await until(loaded),"guest loads original opening map")
	if failures:done.call_deferred();return
	freeze(client)
	var entry:Dictionary=host.coop.joiners["depth guest"]
	check(entry.in_sync and entry.clean and entry.present,"guest eligible for full checkpoint return")
	if failures:done.call_deferred();return
	host.world.vm.instances.clear()
	var guest:=visitor()
	var npcs:=host.world.units.values().filter(func(u:GameUnit):return not u.has_meta("hero") and not u.dead)
	var attacker:GameUnit=npcs[0];var target:GameUnit=npcs[1]
	var shot:=Projectile.launch(host.world,attacker,guest,true);shot.roll={"hit":true,"backstab":false}
	var control:=Projectile.launch(host.world,attacker,target,true);control.roll={"hit":true,"backstab":false}
	var lead:GameUnit=host.party_units(0)[0]
	# Deliberately equal display names cannot transfer a host actor's identity.
	lead.get_meta("hero").name=guest.get_meta("hero").name
	var own:=Projectile.launch(host.world,guest,target,true);own.roll={"hit":true,"backstab":false}
	var absent:=Projectile.launch(host.world,attacker,lead,true);absent.roll={"hit":true,"backstab":false}
	var host_shot:=Projectile.launch(host.world,lead,target,true);host_shot.roll={"hit":true,"backstab":false}
	var pet:GameUnit=npcs[2]
	for i in 3: check(Spells.tame(host.world,guest,pet,1000000.0),"guest completes pet taming")
	var pet_key:=Spells._caster_ref(pet)
	var pet_in:=Projectile.launch(host.world,attacker,pet,true);pet_in.roll={"hit":true,"backstab":false}
	var pet_out:=Projectile.launch(host.world,pet,target,true);pet_out.roll={"hit":true,"backstab":false}
	var foreign_pet:GameUnit=npcs[3]
	for i in 3: check(Spells.tame(host.world,lead,foreign_pet,1000000.0),"host completes separate pet taming")
	var foreign_key:=Spells._caster_ref(foreign_pet)
	var foreign_shot:=Projectile.launch(host.world,attacker,foreign_pet,true);foreign_shot.roll={"hit":true,"backstab":false}
	guest.hp=guest.max_hp*.3;guest.mana=guest.max_mana;guest.facing=.654321
	lead.hp=lead.max_hp*.3;lead.mana=lead.max_mana
	for caster:GameUnit in [guest,lead]:
		caster._anim_lock=0.0;caster._attack_cd=0.0
		caster.order={"type":"cast","spell":"healing","target":caster,"point":caster.pos};caster._do_cast(GameUnit.TICK)
	var paid:=guest.mana;var hp:=guest.hp;var facing:=guest.facing
	evidence.before={"guest":Spells._caster_ref(guest),"guest_uid":guest.uid,"shots":Spells.save_lasting(host.world)}
	check(evidence.before.shots.size()==10,"eight targeted shots and two paid casts present before return")
	var before:=client.coop.merged_count
	host.coop.send_all();var seq:=int(entry.seq)
	check(await until(func():
		if client.coop.merged_count<=before or client.coop.last_merged.is_empty():return false
		var received:=CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
		return received!=null and int(received.coop.get("applied",{}).get(entry.sid,{}).get("seq",-1))>=seq
	),"progress RPC writes guest continuation checkpoint")
	if failures:done.call_deferred();return
	var returned:=CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
	evidence.returned_shots=returned.zones.gz1g.get("lasting",[])
	check(evidence.returned_shots.size()==10,"all effect records reach the returned save")
	check(returned.save(SaveInfo.path("depth-return"))==OK,"copy returned save to isolated solo slot")
	await stop_branches();CoopProgress.bring_slot=""
	host=branch(false);host.set_physics_process(false)
	check(host.load_game("depth-return"),"independent offline Session loads returned save");freeze(host)
	var solo:GameUnit=host.party_units(0)[0]
	var restored:=host.world.get_children().filter(func(c):return c is Projectile)
	evidence.after={"solo_ref":Spells._caster_ref(solo),"shots":Spells.save_lasting(host.world),"count":restored.size()}
	check(restored.any(func(p):return p.target!=null and not p.target.has_meta("hero")),"control: NPC-targeted shot survives return")
	check(restored.any(func(p):return p.target==solo),"guest-targeted shot follows recipient into solo save")
	var restored_pet:=Spells._caster_of(host.world,pet_key)
	check(restored_pet!=null and restored_pet.controller==0,"guest-owned pet follows recipient into solo")
	check(Spells._caster_of(host.world,foreign_key)==null,"host-owned pet remains absent from recipient's party")
	check(restored.size()==6,"missing host targets and foreign pet targets are discarded")
	check(restored.filter(func(p):return p.target==solo).size()==1,"same-name host target is never redirected to the guest")
	check(restored.any(func(p):return p.source==solo),"guest-as-source rebinds to solo controller zero")
	check(restored.any(func(p):return p.source==null and p.target!=solo),"host-fired strike retains damage without assigning its source to guest")
	check(restored.any(func(p):return p.target==restored_pet) and restored.any(func(p):return p.source==restored_pet),"pet effect references preserve both source and target")
	check(is_equal_approx(solo.mana,paid) and is_equal_approx(solo.facing,facing),"guest paid mana and facing survive continuation")
	check(solo._cast_bar_target!=null and solo._cast_bar_target.get_ref()==solo,"body action references project with pending effects")
	var timers:=host.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	check(timers!=null and timers.pending.size()==1,"only the returning guest's paid cast resumes")
	if timers:
		for i in 100:
			host.world._logic_step+=1;timers._tick(GameUnit.TICK,true)
	check(solo.hp>hp and is_equal_approx(solo.mana,paid),"returning paid cast heals once without repaying")
	solo.hp=hp
	if timers: timers._tick(100.0)
	check(is_equal_approx(solo.hp,hp),"guest return does not duplicate delivery")
	done.call_deferred()
func done() -> void:
	evidence.checks=checks;evidence.failures=failures
	FileAccess.open(out.path_join("coop-effect-return.json"),FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	await stop_branches();TexUpscale.shutdown()
	print("AUDIT_COOP_EFFECT_RETURN ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
