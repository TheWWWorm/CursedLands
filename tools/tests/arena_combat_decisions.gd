extends "arena_combat_effects.gd"
## Observable Autochess choices; campaign AI retains the original scoring and
## friendly-fire gates. Real spell execution checks that admitting area magic
## does not remove its ally protection.
func _ready()->void:
	var native:=hash(GameData.db.tables)
	setup([16,0],[0,0])
	var caster:=own[0];var ally:=own[1];var enemy:=enemies[0]
	caster.pos=Vector2(24,32);ally.pos=Vector2(30,32);enemy.pos=Vector2(31,32);enemies[1].pos=Vector2(32,33)
	caster.remove_meta("flying");caster.proto.altitude=0.0
	var ai:=battle.world.ai
	var wall:Dictionary=ai.options(caster).a.filter(func(o):return o.type==3)[0]
	check(ai._area_safe(caster,wall,enemy),"Autochess area spell accepts an ally-protected melee cluster")
	var choice:=ai.choose(caster,Array(enemies))
	check(not choice.is_empty() and choice.opt.slot==wall.slot,"harpy chooses its wall while an ally screens it")
	var hp:=ally.hp;var enemy_hp:=enemy.hp
	var spell:=Spells.parse(wall.slot).duplicate(true);spell.effect=100.0;spell.radius=3.0
	Spells._area_hit(battle.world,caster,spell,enemy.pos)
	check(ally.hp==hp and enemy.hp<enemy_hp,"admitted area damage still protects the allied frontline")
	battle.world.remove_meta("expedition_spell_safety")
	check(not ai._area_safe(caster,wall,enemy),"campaign keeps original ally safety distance")
	battle.world.set_meta("expedition_spell_safety",true)
	setup([3],[0,0])
	caster=own[0];ai=battle.world.ai
	var bolt:Dictionary=ai.options(caster).a[0]
	caster.pos=Vector2(24,32);enemies[0].pos=caster.pos+Vector2(2,0);enemies[1].pos=caster.pos+Vector2(minf(8.0,float(bolt.range)-0.5),0)
	enemies[1].hp=1.0
	choice=ai.choose(caster,Array(enemies))
	check(not choice.is_empty() and choice.t==enemies[1],"caster finishes a wounded enemy already within range")
	caster.command({"type":"cast","spell":bolt.slot,"target":enemies[0],"range":bolt.range,"ai":true})
	choice=ai.choose(caster,Array(enemies))
	check(not choice.is_empty() and choice.t==enemies[1],"finishable target can outweigh current-target preference")
	enemies[1].pos=caster.pos+Vector2(40,0)
	choice=ai.choose(caster,Array(enemies))
	check(not choice.is_empty() and choice.t==enemies[0],"caster keeps nearby combat instead of chasing a distant wounded target")
	caster.order={};enemies[1].pos=caster.pos+Vector2(8,0);caster.stats.trials_budget=false
	choice=ai.choose(caster,Array(enemies))
	check(not choice.is_empty() and choice.t==enemies[0],"campaign preserves original distance-weighted choice")
	setup([13],[0])
	caster=own[0];ai=battle.world.ai
	caster.buffs["regression_no_cast"]={"until":INF,"no_cast":true}
	choice=ai.choose(caster,Array(enemies))
	check(not choice.is_empty() and choice.opt.type==0,"blocked hybrid caster chooses its available weapon")
	caster.buffs.erase("regression_no_cast")
	choice=ai.choose(caster,Array(enemies))
	check(not choice.is_empty(),"caster can choose again after cast restriction ends")
	check(hash(GameData.db.tables)==native,"combat decisions preserve campaign source data")
	print("ARENA_COMBAT_DECISIONS ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
