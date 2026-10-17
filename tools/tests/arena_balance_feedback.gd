extends Node
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	var native:=hash(GameData.db.tables)
	var run:=ArenaRun.new();run.auto_save=false
	for challenge in 3:
		run.begin(1515,0,challenge)
		check(run.preparation_left==[60,45,30][challenge],"preparation time follows chosen difficulty")
		var saved:=run.snapshot();saved.version=8;saved.preparation_left=45.0
		var restored:=ArenaRun.new();restored.auto_save=false
		check(restored.restore(JSON.parse_string(JSON.stringify(saved))) and restored.preparation_left==45.0,"old active countdown is preserved")
		check(restored.restore(JSON.parse_string(JSON.stringify(restored.snapshot()))) and restored.preparation_left==45.0,"migrated countdown remains readable after saving again")
	check(ArenaRules.recruit_pool(5).has(10) and not ArenaRules.recruit_pool(5).has(7),"spiders become available before trolls")
	check(run.offer_cost({"family":7})==7 and run.offer_cost({"family":9})==10,"troll and ogre costs require meaningful investment")
	check(run.offer_cost({"family":10,"rank":1})==9,"early spider evolution costs three copies")
	check(ArenaRules.enemies(24,1515,2).size()>ArenaRules.enemies(24,1515,1).size(),"Champion brings additional native caster support")
	# Preserve old owned creatures and actual paid investment through schema 8.
	run.begin(1515);run.gold=100
	run.shop[0]={"family":7,"rank":0,"locked":false};run.buy(0)
	var saved:=run.snapshot();saved.version=8;saved.preparation_left=45.0;saved.army[0].investment=4
	var restored:=ArenaRun.new();restored.auto_save=false
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))) and restored.army[0].investment==4,"old army retains its original purchase value")
	var gold:=restored.gold;restored.sell(restored.army[0].uid)
	check(restored.gold==gold+4,"old one-star sale cannot mint new higher recruit price")
	var battle:=ArenaPveMatch.new();battle.rendered=false;battle.run=run
	add_child(battle);battle.set_process(false);battle._world_parent=self
	run.army[0].deployed=true;run.army[0].point=[25.0,32.0];run.wave=25;battle.prepare()
	var world:=battle.world
	var caster:=world.unit_rows().filter(func(u):return u.faction==1)[0] as GameUnit
	var ally:=battle._spawn({"id":"trollbluef9","team":0,"point":Vector2(26,32)})
	var enemy:=battle._spawn({"id":"trollbluef9","team":1,"point":Vector2(27,32)})
	var spell:=Spells.parse("acid_fog").duplicate(true);spell.effect=5000.0;spell.radius=12.0
	var ally_hp:=ally.hp;var enemy_hp:=enemy.hp
	Spells._area_hit(world,caster,spell,Vector2(26,32))
	check(ally.hp==ally_hp and enemy.hp<enemy_hp,"acid fog damages the enemy and preserves an ally inside the same area")
	check(not Spells.damage_target_allowed(world,enemy,enemy,0),"both expedition teams receive the same friendly-fire protection")
	check(Spells.passes_filter(world,caster,ally,1),"friendly buff filters still admit allies")
	world.remove_meta("expedition_spell_safety")
	Spells._area_hit(world,caster,spell,Vector2(26,32))
	check(ally.hp<ally_hp,"campaign damage retains original unfiltered friendly fire")
	check(hash(GameData.db.tables)==native,"prices and encounter rules never alter campaign prototype data")
	battle.queue_free()
	for i in 5: await get_tree().process_frame
	print("ARENA_BALANCE_FEEDBACK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
