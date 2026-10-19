extends Node
## Authored bridge positions/facings plus neutral-hostility replication.
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var s:=Session.new();add_child(s);s.state.ensure_hero(0,"Human Hero")
	var game:=Game.new();game.session=s;s.game=game;add_child(game)
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_physics_process(false);s.world.set_process(false);s.world.vm.instances.clear()
	var w:=s.world
	var hero:GameUnit=s.party_units(0)[0]
	var left:GameUnit=w.units[1901];var right:GameUnit=w.units[1913]
	hero.pos=left.pos+Vector2(0,1);hero._sync_transform(0);w.nav.track_unit(hero)
	for u:GameUnit in [left,right,hero]:
		u.set_process(false);u.set_physics_process(false);u.remove_meta("noticed");u.remove_meta("seen_corpses");u.remove_meta("suspect");u.remove_meta("perceived")
	check(not w.ai.can_notice(right,left,float(right.stats.sight)) and not w.ai.can_notice(right,hero,float(right.stats.sight)),"authored right bridge goblin cannot see fatal blow behind it")
	w.ai._help.clear();left.take_damage(left.max_hp*10,hero)
	check(left.dead,"backstab victim dies")
	check(not w.ai._help.any(func(e):return e[0]==right),"fatal unseen blow cannot send a help call")
	check(not right.get_meta("noticed",{}).has(hero.get_instance_id()) and not right.has_meta("suspect"),"unseeing bridge goblin remains unaware")
	left.revive();left.hp=left.max_hp;right.remove_meta("noticed");right.remove_meta("seen_corpses");right.remove_meta("suspect")
	w.ai._help.clear();left.take_damage(.6,hero)
	check(not left.dead and w.ai._help.any(func(e):return e[0]==right),"surviving hit still calls for help")
	# Witnesses, as distinct from recipients of a shouted warning.
	right.facing=(left.pos-right.pos).angle();right.remove_meta("noticed");right.remove_meta("seen_corpses");right.remove_meta("perceived")
	w.ai._help.clear();left.take_damage(left.max_hp*10,hero)
	check(right.get_meta("noticed",{}).has(hero.get_instance_id()),"visible murder still alerts the witnessing goblin")
	var neutral_record:={"prototype":"PigF0","nid":900001,"player":2,"position":Vector3(20,20,0)}
	var animal:=w.spawn_unit(neutral_record);animal.faction=2
	w.set_relation(2,hero.faction,1)
	check(not w.is_enemy(animal,hero),"neutral marker begins non-hostile")
	animal.take_damage(.6,hero)
	check(w.is_enemy(animal,hero),"attacked neutral becomes individually hostile")
	var replica:=GameWorld.new();add_child(replica);replica.authority=false;replica.set_process(false);replica.set_physics_process(false)
	var remote:=replica.spawn_unit(neutral_record);var peer:=replica.spawn_unit({"nid":900002,"prototype":"Human Hero","position":Vector3(20,21,0)})
	peer.faction=hero.faction;replica.set_relation(2,peer.faction,1)
	var row:Array=NetSnapshot.unpack(NetSnapshot.pack([animal.snapshot()]))[0]
	remote.apply_snapshot(row,true)
	check(replica.is_enemy(remote,peer),"compressed snapshot changes replica minimap hostility without changing faction")
	animal.remove_meta("hate");remote.apply_snapshot(animal.snapshot())
	check(not replica.is_enemy(remote,peer),"later snapshot clears individual hostility")
	row.resize(18);remote.apply_snapshot(row)
	check(remote.faction==animal.faction,"legacy snapshots still apply")
	# A neutral witness becomes hostile even when it was never damaged.
	hero.pos=Vector2(20,22);hero._sync_transform(0);w.nav.track_unit(hero)
	var victim:=w.spawn_unit({"prototype":"PigF0","nid":900003,"player":2,"position":Vector3(20,21,0)})
	animal.facing=PI/2.0;animal.remove_meta("perceived");animal.remove_meta("noticed")
	w.nav.track_unit(animal);w.nav.track_unit(victim)
	check(w.ai.can_notice(animal,victim,float(animal.stats.sight)),"neutral pig can see the nearby victim")
	victim.take_damage(victim.max_hp*10,hero)
	check(w.is_enemy(animal,hero),"neutral pig witnessing a kill becomes hostile without being hit")
	remote.apply_snapshot(NetSnapshot.unpack(NetSnapshot.pack([animal.snapshot()]))[0])
	check(replica.is_enemy(remote,peer),"witness hostility also reaches the replica")
	replica.queue_free();game.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	print("CREATURE_ALERTS ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
