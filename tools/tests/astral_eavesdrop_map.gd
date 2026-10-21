extends "coop_story.gd"
## Shipped Portal map, spawned quest actors and real terrain/AI perception.
## Compare the adapted host/guest predicate with the unadapted original
## script under equivalent protagonist inputs. This is not an EXE replay.
const Q := "q.gz1h.q12h"
const Compat := preload("res://src/game/script/story_compat.gd")
var checks := 0
var failures: Array[String] = []
var observations: Array = []
var authored_areas := {}

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func evaluate(ast: ScriptParser, script: String) -> bool:
	var vm := host.world.vm
	vm.ast=ast;vm.instances.clear()
	# Successful original bodies delete their one-shot area. Each side of
	# the comparison starts with the same authored map/area state.
	vm.areas=authored_areas.duplicate(true)
	for suffix in [".1",".2",".3",".4"]:host.state.set_var(0,Q+suffix,0)
	host.state.set_var(0,Q,1)
	vm._refresh_heroes()
	vm.spawn(script,[null])
	var inst: ScriptVM.Instance=vm.instances.back()
	vm._run(inst)
	return inst.killed

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	var h := branch("EavesdropHost",true);host=h.s;hg=h.g
	var c := branch("EavesdropGuest",false);client=c.s;cg=c.g
	require(host.host(29987,2)==OK and client.join("127.0.0.1",29987)==OK)
	require(await until(func():return host.players.size()==2))
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero")
	# This late quest follows the prison escape. A new campaign's q02h=0
	# would start the unrelated escape and temporarily reuse area number 4.
	for key in ["q.gz1h.q01h","q.gz1h.q02h","q.gz1h.q1h"]:host.state.set_var(0,key,2)
	host.state.set_var(0,"b.merc2.brief_5",3)
	host.set_physics_process(false)
	await host.enter_zone("gz1h",1,false)
	require(await until(func():return client.world!=null and client.zone_id=="gz1h" and not client._remote_loading))
	var w := host.world
	w.set_process(false);w.set_physics_process(false)
	var vm := w.vm
	vm.instances.clear();vm.briefings._check=INF
	var heroes: Array[GameUnit]=[host.party_units(0)[0],host.party_units(1)[0]]
	for u: GameUnit in heroes:u.pos=Vector2(300,200)
	host.state.set_var(0,Q,1)
	vm.spawn("VCheck#5#1",[null])
	for i in 25:vm.tick(GameUnit.TICK)
	check(w.units.has(1012004) and w.units.has(1012005) and w.units.has(1012001),"original quest startup loads both speakers and captive")
	if not w.units.has(1012005):await finish();return
	var speaker: GameUnit=w.units[1012005]
	var original := ScriptParser.parse(w.mob.script_text)
	var adapted := ScriptParser.parse(w.mob.script_text)
	Compat.apply(adapted,CampaignProfile.ASTRAL,"gz1h")
	authored_areas=vm.areas.duplicate(true)
	check(vm.areas.get(3)==[Vector3(158,73,5)] and vm.areas.get(4)==[Vector3(153,66,3.5)],"quest startup creates the original discovery/listening circles")
	var speakers := []
	for id in [1012004,1012005]:
		var u: GameUnit=w.units[id]
		speakers.append({"uid":id,"name":u.info.get("name",""),"prototype":u.proto.get("name",""),"pos":[u.pos.x,u.pos.y],"facing":u.facing,"sight":u.stats.get("sight",0)})
	var usable := {"discovery":0,"listening":0}
	for hour in [12.0,23.0]:
		host.state.world_time=hour
		for stance in [0,1,2]:
			for u: GameUnit in heroes:u.stance=stance
			for row: Array in [["VCheck#5#2",Vector2(158,73),5.0,"discovery"],["VCheck#5#3",Vector2(153,66),3.5,"listening"]]:
				for dy in range(-6,7,2):
					for dx in range(-6,7,2):
						var p: Vector2=row[1]+Vector2(dx,dy)
						heroes[0].pos=p;heroes[1].pos=Vector2(300,200)
						var seen := vm._sees_has([speaker],heroes[0])
						var reference := evaluate(original,row[0])
						var label := "%s hour=%s stance=%d point=%s"%[row[3],hour,stance,p]
						check(evaluate(adapted,row[0])==reference,label+": host matches original script")
						var walkable := w.nav.is_walkable(p)
						if reference and walkable:usable[row[3]]+=1
						heroes[1].pos=p;heroes[0].pos=Vector2(300,200)
						check(evaluate(adapted,row[0])==reference,label+": guest matches original protagonist")
						if reference:
							heroes[1].hidden=true
							check(not evaluate(adapted,row[0]),label+": hidden guest cannot complete the objective")
							heroes[1].hidden=false
						observations.append({"stage":row[3],"hour":hour,"stance":stance,"point":[p.x,p.y],"walkable":walkable,"noticed":seen,"fires":reference})
			await get_tree().process_frame
	check(usable.discovery>0,"at least one walkable map approach discovers the house unseen")
	check(usable.listening>0,"at least one walkable listening position advances the original objective")
	# Prove a real successful guest gate publishes its original objectives.
	var successful: Array=observations.filter(func(o):return o.stage=="listening" and o.fires and o.walkable)
	if not successful.is_empty():
		var o: Dictionary=successful[0]
		host.state.world_time=o.hour;heroes[1].stance=o.stance
		heroes[1].pos=Vector2(o.point[0],o.point[1]);heroes[0].pos=Vector2(300,200)
		check(evaluate(adapted,"VCheck#5#3"),"guest actually completes listening on original map geometry")
		host.sync_state()
		check(await until(func():return client.state.get_var(0,Q+".2")==2 and client.state.get_var(0,Q+".4")==1),"listening and rescue objectives replicate to guest")
		check(not hg.hud._dialog.visible and not cg.hud._dialog.visible,"original trigger does not open a dialogue window")
	FileAccess.open("user://astral_eavesdrop_map.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"areas":authored_areas,"speakers":speakers,"usable":usable,"observations":observations},"\t"))
	await finish()

func finish() -> void:
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in branches:root.queue_free()
	for i in 10:await get_tree().process_frame
	print("ASTRAL_EAVESDROP_MAP ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

func _process(_dt: float) -> void:pass
