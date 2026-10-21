extends Node
## Native observations cover effect registration. Real casts below separately
## cover figure replacement, recasting, expiry and serialized client state.
var checks := 0
var failures := 0
var rows := []
var w: GameWorld

func check(ok: bool, label: String) -> void:
	checks += 1
	rows.append({"ok":ok,"label":label})
	if not ok:failures += 1;printerr("FAIL ",label)

func actor(world: GameWorld, id: int, proto: String) -> GameUnit:
	return world.spawn_unit({"prototype":proto,"nid":id,"player":0,"complexion":Vector3(.5,.5,.5),
		"position":Vector3(float(id%10),1,0),"logic":[{"logic_model":0}]})

func cast(caster: GameUnit, target: GameUnit, spell: String) -> void:
	caster.mana=10000.0;caster._anim_lock=0.0;caster.facing=0.0
	caster.order={"type":"cast","spell":spell,"target":target,"point":target.pos}
	caster._do_cast(GameUnit.TICK)
	var timers:=w.get_node_or_null("SpellTimers") as Spells.WorldTimers
	check(timers!=null and timers.pending.size()==1,"ordinary cast schedules one effect: "+spell)
	if timers==null:return
	for i in 300:
		if timers.pending.is_empty():break
		w._logic_step+=1;w.time+=GameUnit.TICK;timers._tick(GameUnit.TICK,true)
	check(timers.pending.is_empty(),"ordinary cast delivers effect: "+spell)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0,"auto_graphics":0},true)
	w=GameWorld.new();w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	var replica_world:=GameWorld.new();replica_world.authority=false
	replica_world.process_mode=Node.PROCESS_MODE_DISABLED;add_child(replica_world)
	var caster:=actor(w,920001,"Human Hero")
	var target:=actor(w,920002,"Human Hero")
	var document: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/fixtures/original_size_effects.json"))
	var campaign: String="lost_in_astral" if GameData.campaign_id==CampaignProfile.ASTRAL else "original"
	var reference: Dictionary=document.campaigns[campaign]
	for row: Dictionary in reference.rows:
		var code:=String(row.spell)
		# Controlled duration/power inputs match the captured native record;
		# the actual authored values are restored before the ordinary casts.
		var authored:=Spells.parse(code)
		var p:=authored.duplicate(true);p.duration=int(row.ticks);p.effect=15.0
		Spells._cache[code]=p
		target.buffs.clear();target.refresh_max_hp()
		Spells.cast_unit(w,caster,code,target if row.has_target else null,target.pos)
		Spells._cache[code]=authored
		var expected: Array=row.records
		var label: String="%s / ticks=%s / target=%s"%[code,row.ticks,row.has_target]
		check(target.buffs.size()==expected.size(),"native effect registration: "+label)
		if not expected.is_empty():
			check(target.buffs.has(code),"native effect type: "+label)
			check(target.effect_ticks(code)==int(expected[0].ticks),"native effect duration: "+label)
		else:check(target.buffs.is_empty(),"no target receives no effect: "+label)
	var rat_rows:=GameData.db.table("monster_prototypes").filter(func(p):return "rat" in String(p.name).to_lower())
	check(not rat_rows.is_empty(),"authored creature prototype available")
	if rat_rows.is_empty():get_tree().quit(2);return
	var rat:=actor(w,920003,String(rat_rows[0].name))
	for unit: GameUnit in [target,rat]:
		unit.buffs.clear();unit.refresh_max_hp()
		var base:=unit.figure_complexion()
		var stored: Vector3=unit.info.complexion
		var base_hp:=unit.max_hp
		var replica:=actor(replica_world,unit.uid,String(unit.info.prototype))
		for spell: String in ["enlarge","shrink"]:
			var expected: Vector3=base+Vector3.ONE*(.4 if spell=="enlarge" else -.4)
			cast(caster,unit,spell)
			check(unit.buffs.has(spell),"authored size effect registers: "+spell)
			check(unit.figure_complexion().is_equal_approx(expected),"size effect changes all three figure axes: "+spell)
			check((unit.model.get_meta("complexion") as Vector3).is_equal_approx(expected),"live figure uses changed build: "+spell)
			check(unit.info.complexion==stored and is_equal_approx(unit.max_hp,base_hp),"size effect preserves base build and HP: "+spell)
			replica.apply_snapshot(unit.snapshot(),true)
			check(replica.buffs.has(spell) and replica.figure_complexion().is_equal_approx(expected),"serialized client state includes size effect: "+spell)
			check((replica.model.get_meta("complexion") as Vector3).is_equal_approx(expected),"client figure refreshes after size snapshot: "+spell)
			var duration:=int(Spells.parse(spell).duration)
			for i in mini(3,duration-1):unit._tick_effects()
			cast(caster,unit,spell)
			check(unit.effect_ticks(spell)==duration,"recast refreshes original duration: "+spell)
			check(unit.figure_complexion().is_equal_approx(expected),"recast does not compound body size: "+spell)
			for i in duration:unit._tick_effects()
			check(not unit.buffs.has(spell) and unit.figure_complexion().is_equal_approx(base),"expiry restores original figure build: "+spell)
			replica.apply_snapshot(unit.snapshot(),true)
			check(replica.buffs.is_empty() and replica.figure_complexion().is_equal_approx(base),"expiry restores client build: "+spell)
			check(unit.info.complexion==stored,"saved base build remains unchanged: "+spell)
		Spells.cast_unit(w,caster,"enlarge",unit,unit.pos)
		Spells.cast_unit(w,caster,"shrink",unit,unit.pos)
		check(unit.buffs.has("enlarge") and unit.buffs.has("shrink") and unit.figure_complexion().is_equal_approx(base),"opposite size effects coexist and cancel their visual offset")
		unit.buffs.clear();unit.refresh_max_hp()
	FileAccess.open("user://size-spells.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":campaign,"reference":reference.sha256,"checks":checks,"failures":failures,"rows":rows},"\t"))
	w.queue_free();replica_world.queue_free()
	for i in 8:await get_tree().process_frame
	print("SIZE_SPELLS ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
