extends "third_person_kbm.gd"
## Original item records and models on Ingos terrain. Prepared hostile orders
## exercise the AI attack/approach and native release animation. Explicit
## An ordinary NPC and a noticed hostile exercise the original retention rule.
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
		_combat_cases(archer,start,axis)
	g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown()
	print("ARCHER_RANGE ",JSON.stringify({"checks":checks,"failures":failures,"rows":rows}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _database_cases() -> void:
	mode="original databases"
	var equipped_count:=0;var natural:=0;var spell_count:=0
	var ai:=UnitAI.new(null)
	for proto:Dictionary in GameData.db.table("monster_prototypes"):
		var weapons:=CampaignState.proto_weapons(proto)
		var item:=Items.info(weapons[0]) if not weapons.is_empty() else {}
		var equipped:bool=int(proto.get("weapon_type_id",-1))==8 and not item.is_empty() and item.table=="weapons"
		var u:=GameUnit.new();u.proto=proto;u.race=GameData.db.find("race_models",proto.base_race);u.info={"weapons":weapons};u._init_stats()
		if equipped:
			equipped_count+=1
			var ranged:=int(item.row.get("type_id",-1)) in [5,6]
			check(u.stats.range==float(item.row.range) and u.stats.ranged==ranged and (not ranged or u.stats.reach==float(item.row.range)),"equipped prototype uses its item range: "+String(proto.name))
		elif int(proto.get("weapon_type_id",-1))!=8:
			natural+=1
			check(u.stats.range==float(proto.attack_range) and u.stats.ranged==(float(proto.attack_range)>3.0),"natural attack keeps its authored range: "+String(proto.name))
		var only16:=int(proto.get("weapon_type_id",-1))==16
		var spells:=ai._spell_options(u,only16)
		for opt:Dictionary in spells[0]+spells[1]:
			spell_count+=1
			var expected:=float(proto.attack_range) if only16 else float(Spells.parse(opt.slot).range)
			check(opt.range==expected,"spell option uses authored range: "+String(proto.name)+" / "+String(opt.slot))
		u.free()
	check(equipped_count>=100 and natural>=30 and spell_count>=20,"database coverage includes melee, bows, crossbows, natural attacks and spell options")
	rows.append({"equipped_prototypes":equipped_count,"natural_prototypes":natural,"spell_options":spell_count})

func _combat_cases(u:GameUnit,start:Vector2,axis:Vector2) -> void:
	var melee_types:={}
	var h:Dictionary=hero.get_meta("hero")
	for weapon:Dictionary in GameData.db.table("weapons"):
		var id:=String(weapon.name).to_lower()+".steel"
		if Items.info(id).is_empty():continue
		var ranged:=int(weapon.type_id) in [5,6]
		mode="all weapon records / "+id
		u.set_equipment(PackedStringArray(),PackedStringArray([id]))
		h.weapons=[id];Combat.hero_stats(hero,h)
		check(u.stats.range==float(weapon.range) and hero.stats.range==float(weapon.range) and u.stats.ranged==ranged and hero.stats.ranged==ranged,"NPC and party share the authored weapon range")
		if ranged or melee_types.has(weapon.type_id):continue
		melee_types[weapon.type_id]=true
		var reach:=u.melee_reach(hero)
		_place(u,start,axis,reach-.05)
		var hit:=_begin_melee(u,120)
		check(hit and u.pos.distance_to(start)<.001,"in-range melee begins without advancing")
		_place(u,start,axis,reach+3.0)
		hit=_begin_melee(u,350)
		check(hit and u.pos.distance_to(start)>2.0 and u.pos.distance_to(hero.pos)<=reach+.01,"out-of-range melee approaches its body-and-weapon reach")
	check(melee_types.size()>=5,"all authored melee weapon categories exercise actual attack orders")
	# Original AI caster prototypes: ordinary spells use their parsed range;
	# natural spell attacks (weapon type 16) use the creature's authored range.
	for only16:bool in [false,true]:
		var chosen:={};var option:={}
		for proto:Dictionary in GameData.db.table("monster_prototypes"):
			if (int(proto.get("weapon_type_id",-1))==16)!=only16:continue
			var probe:=GameUnit.new();probe.proto=proto
			var opts:=s.world.ai._spell_options(probe,only16);probe.free()
			for opt:Dictionary in opts[0]:
				if opt.type<=3 and float(opt.range)>2 and float(opt.range)<=20:
					chosen=proto;option=opt;break
			if not chosen.is_empty():break
		check(not chosen.is_empty(),"original caster available, natural="+str(only16))
		if chosen.is_empty():continue
		var caster:=s.world.spawn_unit({"prototype":chosen.name,"need_import":0,"player":1,"position":Vector3(start.x,start.y,0)})
		caster.set_process(false);caster.set_physics_process(false)
		mode="spell range / "+String(chosen.name)+" / "+String(option.slot)
		for outside:bool in [false,true]:
			_place(caster,start,axis,float(option.range)+(3.0 if outside else -.1))
			caster.mana=100000
			caster.order={"type":"cast","spell":option.slot,"target":hero,"range":option.range,"ai":true}
			for tick in 400:
				caster._do_cast(GameUnit.TICK)
				if caster.action.begins_with("cast") or caster.order.is_empty():break
			check(caster.action.begins_with("cast") and caster.pos.distance_to(hero.pos)<=float(option.range)+.01,"spell begins within its authored range, outside="+str(outside))
			check(caster.pos.distance_to(start)>2 if outside else caster.pos.distance_to(start)<.001,"spell approaches only when out of range")
		rows.append({"caster":chosen.name,"spell":option.slot,"range":option.range,"natural_spell_attack":only16})
		s.world.remove_unit(caster)
	for spell:String in ["arrow{}","litnwall{e2;e1;d1;m1;m1;m1;m1;m1}"]:
		var reach:=float(Spells.parse(spell).range)
		mode="party spell / "+spell
		for outside:bool in [false,true]:
			hero.pos=start;hero.facing=axis.angle();hero.action="idle";hero.path=PackedVector2Array();hero.mana=100000
			u.pos=start+axis*(reach+(3.0 if outside else -.1))
			for unit:GameUnit in [hero,u]:s.world.nav.track_unit(unit);unit._sync_transform(0)
			# A party order on a unit goes on only while the party has noticed
			# it (54dd70); the hero has seen this target.
			var known:Dictionary=hero.get_meta("noticed",{});known[u.get_instance_id()]=u;hero.set_meta("noticed",known)
			hero.order={"type":"cast","spell":spell,"target":u}
			for tick in 400:
				hero._do_cast(GameUnit.TICK)
				if hero.action.begins_with("cast") or hero.order.is_empty():break
			check(hero.action.begins_with("cast") and hero.pos.distance_to(u.pos)<=reach+.01,"party target/point spell begins within parsed range, outside="+str(outside))
			check(hero.pos.distance_to(start)>2 if outside else hero.pos.distance_to(start)<.001,"party spell approaches only when out of range")

func _begin_melee(u:GameUnit,limit:int) -> bool:
	for tick in limit:
		s.world.time+=GameUnit.TICK;u._tick(GameUnit.TICK)
		if not u._pending_hit.is_empty():return true
	return false

func _place(archer:GameUnit,start:Vector2,axis:Vector2,distance:float) -> void:
	archer.pos=start;archer.facing=axis.angle();hero.pos=start+axis*distance;hero._moving=false
	archer.order={};archer.orders.clear();archer.path=PackedVector2Array();archer._goal=Vector2.INF
	archer._pending_hit={};archer._attack_cd=0;archer._anim_lock=0;archer.action="idle";archer.alert=true
	archer._pose_snap=true;archer._update_pose();archer._anim_lock=0
	for u:GameUnit in [archer,hero]:s.world.nav.track_unit(u);u._sync_transform(0)
	# Attack rechoice must retain an already noticed hostile for an ordinary
	# NPC too; a scripted Aggression override would hide retention regressions.
	s.world.set_relation(archer.faction,hero.faction,2)
	archer.set_meta("noticed",{hero.get_instance_id():hero})
	archer.remove_meta("perceived")
	check(s.world.is_enemy(archer,hero) and s.world.ai.enemies(archer).has(hero),"range fixture retains its explicitly noticed hostile")
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
