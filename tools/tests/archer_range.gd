extends "third_person_kbm.gd"
## Original item records and models on Ingos terrain. Prepared hostile orders
## exercise the AI attack/approach and native release animation, without RNG
## perception deciding whether a particular stationary target has been noticed.
var rows := []

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	_database_cases()
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz11k",1,false);await prepare()
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	var archer:=s.world.spawn_unit({"prototype":"Human Kania Police A10","need_import":0,"player":1})
	archer.set_process(false);archer.set_physics_process(false);archer._perceive_next=INF;archer.ai_next=INF
	var start:=hero.pos;var axis:=Vector2.RIGHT;var found:=false
	for ring in 60:
		for angle in 16:
			archer.pos=start+Vector2.from_angle(angle*TAU/16)*ring
			s.world.nav.track_unit(archer)
			for direction in 8:
				axis=Vector2.from_angle(direction*TAU/8)
				var end:=archer.pos+axis*21.0
				if s.world.nav.direct_line(archer,end) and s.world.terrain_ray(archer.pos,s.world.ground_at(archer.pos.x,archer.pos.y)+1.5,end,s.world.ground_at(end.x,end.y)+1.5)>.99:
					found=true;break
			if found:break
		if found:break
	check(found,"original Ingos terrain supplies a clear 21m firing lane")
	start=archer.pos
	if found:
		for prototype:String in ["Human Kania Police A10","Human Kania Ranger F9","Human Kania Gang A9","Human Mercenary Kania Archer"]:
			s.world.remove_unit(archer)
			archer=s.world.spawn_unit({"prototype":prototype,"need_import":0,"player":1,"position":Vector3(start.x,start.y,0)})
			archer.set_process(false);archer.set_physics_process(false);archer._perceive_next=INF;archer.ai_next=INF
			var distance:=15.0 if "long bow" in String(archer.info.weapons[0]) else 11.0
			for moving:bool in [false,true]:
				mode=prototype+" moving="+str(moving)
				_place(archer,start,axis,distance)
				hero._moving=moving;hero.facing=axis.angle()+PI*.5
				var motion:=axis.orthogonal() if moving else Vector2.ZERO
				var result:=_release(archer,120,motion)
				check(result.shot,"noticed target receives a real arrow at bow range")
				check(archer.pos.distance_to(start)<.001,"archer fires without walking into the old 8m/melee range")
				rows.append({"prototype":prototype,"moving":moving,"distance":distance,"advance":archer.pos.distance_to(start),"shot":result.shot,"ticks":result.ticks})
				if moving:
					var second:=_release(archer,180,motion)
					check(second.shot and archer.pos.distance_to(start)<.001,"cooldown and repeated shots do not pull the archer toward an in-range moving target")
			mode=prototype+" out of range"
			_place(archer,start,axis,float(archer.stats.reach)+4.0)
			var result:=_release(archer,400)
			check(result.shot and archer.pos.distance_to(start)>2.0,"out-of-range target is approached before shooting")
			check(archer.pos.distance_to(hero.pos)>float(archer.stats.reach)-1.0,"approach stops at bow range, not next to the target")
		mode="equipment and saved state"
		archer.set_equipment(PackedStringArray(),PackedStringArray(["long crossbow.steel"]))
		check(archer.stats.ranged and archer.stats.reach==20.0,"NPC weapon change refreshes crossbow range")
		archer.set_equipment(PackedStringArray(),PackedStringArray(["short sword.steel"]))
		check(not archer.stats.ranged and archer.stats.reach<3.0,"switching to a sword restores melee combat")
		archer.set_equipment(PackedStringArray(),PackedStringArray())
		check(not archer.stats.ranged,"empty weapon slots do not retain bow combat")
		archer.set_equipment(PackedStringArray(),PackedStringArray(["long bow.steel"]))
		var record:=s._unit_record(archer);record.nid=s.world.new_uid()
		var client:=s._spawn_record(record)
		check(client!=null and client.stats.ranged and client.stats.reach==16.0,"late-join unit retains authoritative equipment range")
		if client:s.world.remove_unit(client)
		# Legacy campaign saves store body/position, not derived runtime_stats.
		var legacy:=CampaignState.new()
		legacy.zones.test={"dead":[],"removed":[],"units":{archer.uid:[start.x,start.y,archer.hp,archer.faction,false]},"levers":{}}
		legacy.restore_zone("test",s.world)
		check(archer.stats.ranged and archer.stats.reach==16.0,"legacy zone restore preserves equipment-derived combat")
		var h:Dictionary=hero.get_meta("hero")
		for entry:Array in [["short bow.steel",12.0],["long bow.steel",16.0],["long crossbow.steel",20.0]]:
			h.weapons=[entry[0]];Combat.hero_stats(hero,h)
			check(hero.stats.ranged and hero.stats.reach==entry[1],"party archers use the same authored weapon range: "+entry[0])
	g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown()
	print("ARCHER_RANGE ",JSON.stringify({"checks":checks,"failures":failures,"rows":rows}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _database_cases() -> void:
	mode="original databases"
	var archers:=0;var natural:=0
	for proto:Dictionary in GameData.db.table("monster_prototypes"):
		var weapons:=CampaignState.proto_weapons(proto)
		var item:=Items.info(weapons[0]) if not weapons.is_empty() else {}
		var equipped:bool=int(proto.get("weapon_type_id",-1))==8 and not item.is_empty() and item.table=="weapons" and int(item.row.get("type_id",-1)) in [5,6]
		var innate:=int(proto.get("weapon_type_id",-1)) in [5,6]
		if not equipped and not innate:continue
		var u:=GameUnit.new();u.proto=proto;u.race=GameData.db.find("race_models",proto.base_race);u.info={"weapons":weapons};u._init_stats()
		if equipped:
			archers+=1
			check(u.stats.ranged and u.stats.reach==float(item.row.range),"bow/crossbow prototype uses its item range: "+String(proto.name))
		else:
			natural+=1
			check(u.stats.ranged and u.stats.reach==float(proto.attack_range),"natural ranged creature keeps its authored range: "+String(proto.name))
		u.free()
	check(archers>=25 and natural>=30,"database coverage includes Ingos, Suslanger and innate ranged creatures")

func _place(archer:GameUnit,start:Vector2,axis:Vector2,distance:float) -> void:
	archer.pos=start;archer.facing=axis.angle();hero.pos=start+axis*distance;hero._moving=false
	archer.order={};archer.orders.clear();archer.path=PackedVector2Array();archer._goal=Vector2.INF
	archer._pending_hit={};archer._attack_cd=0;archer._anim_lock=0;archer.action="idle";archer.alert=true
	archer._pose_snap=true;archer._update_pose();archer._anim_lock=0
	for u:GameUnit in [archer,hero]:s.world.nav.track_unit(u);u._sync_transform(0)
	s.world.ai._attack(archer,hero)

func _release(archer:GameUnit,limit:int,motion:=Vector2.ZERO) -> Dictionary:
	var target_start:=hero.pos
	for tick in limit:
		if motion!=Vector2.ZERO:
			hero.pos=target_start+motion*sin(float(tick)*.09)*.6
			s.world.nav.track_unit(hero);hero._sync_transform(0)
		s.world.time+=GameUnit.TICK;archer._tick(GameUnit.TICK);archer._sync_transform(0)
		for child in s.world.get_children():
			if child is Projectile and child.source==archer:
				child.free();return {"shot":true,"ticks":tick+1}
	return {"shot":false,"ticks":limit}
