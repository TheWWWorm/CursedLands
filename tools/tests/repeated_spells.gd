extends Node
var checks := 0
var failures := 0
var rows: Array = []
var w: GameWorld
var c: GameUnit
var t: GameUnit

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	rows.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)

func actor(id: int) -> GameUnit:
	var u:=GameUnit.new()
	check(u.setup(w,{"prototype":"Human Hero","nid":id,"player":0}),"original human actor loads")
	w.add_child(u);w.set_unit(u.uid,u)
	u.mana=10000.0;u.facing=0.0
	return u

func cast(spell: String) -> void:
	c.mana=10000.0;c._anim_lock=0.0;c.facing=0.0
	c.order={"type":"cast","spell":spell,"target":t,"point":t.pos}
	c._do_cast(GameUnit.TICK)
	var timers:=w.get_node_or_null("SpellTimers") as Spells.WorldTimers
	check(timers!=null and timers.pending.size()==1,"cast queues exactly one effect: "+spell)
	if not timers:return
	for i in 300:
		if timers.pending.is_empty():break
		w._logic_step+=1;w.time+=GameUnit.TICK
		timers._tick(GameUnit.TICK,true)
	check(timers.pending.is_empty(),"cast completes: "+spell)

func _ready() -> void:
	w=GameWorld.new();w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	c=actor(900001);t=actor(900002)
	c.pos=Vector2(1,1);t.pos=Vector2(2,1)
	var normal_hp:=t.max_hp
	for spell in ["weak","slow","strength"]:
		for round in 3:
			cast(spell)
			check(t.buffs.has(spell) and t.effect_ticks(spell)>0,"effect applies on cast %d: %s"%[round+1,spell])
			if spell=="weak":check(t.max_hp<normal_hp,"weakness reduces maximum HP on cast %d"%[round+1])
			var duration:=int(Spells.parse(spell).duration)
			for i in 3:t._tick_effects()
			cast(spell)
			check(t.effect_ticks(spell)==duration,"recast refreshes the active effect: "+spell)
			for i in duration:t._tick_effects()
			check(not t.buffs.has(spell),"effect expires before next cast: "+spell)
			check(is_equal_approx(t.max_hp,normal_hp),"base HP restored after effect: "+spell)
	for round in 3:
		t.hp=normal_hp*0.4
		var before:=t.hp
		cast("healing")
		check(t.hp>before,"healing works on cast %d"%[round+1])
	w.free()
	var f:=FileAccess.open("user://repeated-spells.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"  "));f.close()
	print("REPEATED_SPELLS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
