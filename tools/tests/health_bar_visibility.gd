extends Node
## Prepared combat relationships in a loaded original map. Snapshot round trips
## cover client presentation; this is not a two-process network acceptance run.
var checks := []
var s: Session
var g: Game
var bars: EnemyBars
var hero: GameUnit
var foe: GameUnit

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)

func wanted(u: GameUnit) -> bool:
	return bars.entries().any(func(row): return row[0] == u and row[1] > 0.0)

func reset() -> void:
	for u: GameUnit in [hero,foe]:
		u.order={};u.orders.clear();u._pending_hit={};u.target=null;u.action="idle";u.hp=u.max_hp
	foe.dead=false;foe.hidden=false;foe.visible=true
	g.direct._fire=false

func frames(n:=2) -> void:
	for i in n:await get_tree().process_frame

func aim_foe() -> bool:
	foe._sync_transform(0);hero._sync_transform(0)
	var cam:=g.rig.camera
	cam.global_position=foe.global_position+Vector3(3,2,3)
	cam.look_at(foe.global_position+Vector3.UP*foe.figure_half_z)
	cam.reset_physics_interpolation();await frames()
	for i in 5:
		g._pick_key=[]
		if g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==foe:return true
		var at:=Vector2.INF
		for r:Rect2i in foe.screen_rects(cam).slice(1):
			var p:=Vector2(r.position)+Vector2(r.size)*0.5
			if g.pick_unit(p,hero)==foe:at=p;break
		if at==Vector2.INF:return false
		cam.look_at(cam.global_position+cam.project_ray_normal(at)*10)
		cam.reset_physics_interpolation();await frames()
	return false

func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"autosave":0,"auto_graphics":0,"control_mode":2,"enemy_hp_bars":2,
		"show_tutorial":0,"confine_mouse":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	PadInput.active="kbm"
	s=Session.new();add_child(s);s.set_physics_process(false)
	g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");s._enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.rig.set_process(false);g.direct.set_process(false);g.direct.pointer=true
	hero=s.party_units(0)[0]
	foe=s.world.units.values().filter(func(u): return u.controller<0 and not u.dead and u.model!=null)[0]
	foe.pos=hero.pos+Vector2(2,0);foe.faction=4;foe.controller=-1;hero.faction=0
	s.world.set_relation(0,4,2);s.world.set_relation(4,0,2)
	g.selected.assign([hero]);bars=EnemyBars.of(g);bars.set_process(false);reset()
	check(not wanted(hero) and not wanted(foe),"third-person full-health character and idle enemy have no bar")
	hero.hp*=0.5;foe.hp*=0.5
	check(wanted(hero) and wanted(foe),"hurt character and enemy show their bars")
	reset();hero.attack(foe)
	check(wanted(foe),"issued attack shows full-health target before its first simulation tick")
	reset();hero.order={"type":"attack","target":foe}
	check(wanted(foe) and not wanted(hero),"active attack keeps healthy enemy bar without showing healthy hero bar")
	foe.hp*=0.5;bars._step(0.3);foe.hp=foe.max_hp;bars._step(0.3)
	check(wanted(foe) and bars._alpha.get(foe.uid,0.0)==1.0,"healing to full during combat keeps the enemy bar")
	reset();foe.order={"type":"attack","target":hero}
	check(wanted(foe),"enemy attacking the party shows its bar before taking damage")
	var snap:=foe.snapshot();foe.order={};foe.target=hero;foe.alert=true
	check(not wanted(foe),"stale target and combat stance alone do not show an idle full-health enemy")
	hero._pending_hit={"target":foe};hero.order={"type":"move"}
	check(wanted(foe),"committed attack keeps target bar after a movement order")
	reset();hero.order={"type":"cast","target":foe,"spell":"arrow"}
	check(wanted(foe),"hostile spell target keeps full-health bar")
	hero.mana=hero.max_mana;hero.facing=0;hero.order={"type":"cast","target":foe,"spell":"healing","point":foe.pos}
	hero._do_cast(GameUnit.TICK)
	check(hero.order.is_empty() and hero.action.begins_with("cast") and wanted(foe),"paid cast keeps its healthy target visible after its order is consumed")
	s.world.time=hero._cast_bar_until+GameUnit.TICK
	check(not wanted(foe),"finished cast does not leave a permanent healthy-target bar")
	reset();g.rig.release();g.rig._window_focused=true;g.direct.pointer=false
	var aimed:=await aim_foe()
	check(aimed and g.direct.usable(),"direct-view fixture aims at an actual enemy silhouette")
	check(not wanted(foe),"merely aiming at a healthy idle enemy keeps its bar hidden")
	g.direct._fire=true
	check(wanted(foe),"direct attack input shows healthy enemy under the crosshair")
	g.direct._fire=false;hero.action="attack"
	check(wanted(foe),"committed direct swing keeps full-health target bar after button release")
	hero.action="idle";g.direct.pointer=true
	reset();s.world.authority=false;foe.apply_snapshot(snap,true)
	check(wanted(foe),"client snapshot retains enemy-to-party combat relationship")
	foe.apply_snapshot(snap.slice(0,15),true)
	check(not wanted(foe),"older snapshot clears missing combat relationship safely")
	s.world.authority=true;foe.hp=foe.max_hp*0.75
	var hurt:=foe.snapshot();s.world.authority=false;foe.apply_snapshot(hurt,true)
	check(wanted(foe),"damaged remote enemy still shows its bar")
	s.world.authority=true;foe.hp=foe.max_hp
	var healed:=foe.snapshot();s.world.authority=false;foe.apply_snapshot(healed,true)
	check(not wanted(foe),"fully healed remote enemy hides its bar after combat ends")
	s.world.authority=true;reset();hero.order={"type":"attack","target":foe};foe.hidden=true
	check(not wanted(foe),"combat never exposes a hidden enemy")
	foe.hidden=false;foe.dead=true
	check(not wanted(foe),"dead target loses its bar")
	reset();GameData.options.control_mode=3;hero.hp*=0.5
	check(not wanted(hero),"first-person camera still hides its own overhead bar")
	GameData.options.control_mode=0;reset()
	check(not wanted(foe),"Always input mode also hides full-health idle enemies")
	hero.order={"type":"attack","target":foe}
	check(wanted(foe),"classic view retains full-health combat target bar")
	reset();bars._step(0.3)
	check(bars._alpha.get(foe.uid,0.0)==0.0,"ending combat fades out the healthy enemy bar")
	var report:={"checks":checks,"failures":checks.filter(func(c):return not c.ok).size(),"campaign":GameData.campaign_id}
	FileAccess.open("user://health-bar-visibility.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	TexUpscale.shutdown();print("HEALTH_BAR_VISIBILITY ",checks.size()," checks ",report.failures," failures")
	get_tree().quit(0 if report.failures==0 else 1)
