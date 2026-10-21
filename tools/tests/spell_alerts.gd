extends Node
## Dispatch comparisons use x86-generated observations. The fixture does not
## inject expected AI state and does not claim a complete original playthrough.
class ObservedAI:
	extends UnitAI
	var notifications: Array = []
	func on_attacked(u: GameUnit, by: GameUnit) -> void:
		notifications.append([u, by])
		super.on_attacked(u, by)

var checks := 0
var failures := 0
var observations := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0}, true)
	var w := GameWorld.new()
	w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w)
	w.ai = ObservedAI.new(w)
	var ai: ObservedAI = w.ai
	var prototypes := GameData.db.table("monster_prototypes").filter(func(p: Dictionary):
		return String(p.name).to_lower().begins_with("rat") or " rat" in String(p.name).to_lower())
	check(not prototypes.is_empty(), "authored rat prototype exists")
	if prototypes.is_empty(): get_tree().quit(2); return
	var target := w.spawn_unit({"prototype":prototypes[0].name,"nid":910001,"player":1,"position":Vector3(20,20,0),
		"logic":[{"logic_model":0,"aggression":0,"help_radius":7.0}]})
	var caster := w.spawn_unit({"prototype":"Human Hero","nid":910002,"player":0,"position":Vector3(30,20,0)})
	caster.controller = 0
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/fixtures/original_spell_alerts.json"))
	var campaign := "lost_in_astral" if GameData.campaign_id == CampaignProfile.ASTRAL else "original"
	var ref: Dictionary = document.campaigns[campaign]
	var spell_rows := GameData.db.table("spell_prototypes")
	for row: Dictionary in ref.rows:
		if int(row.index) >= spell_rows.size(): continue
		var code := String(spell_rows[int(row.index)].code).to_lower()
		# These have their own damage, taming, relocation or area-suspicion
		# paths. The native branch captured here runs after their dispatch.
		if Spells.DAMAGE_SCHOOLS.has(code) or code in ["charm","teleport","fireworks","vision_fog"]: continue
		if String(row.situation) == "object": continue
		target.buffs.clear(); target.refresh_max_hp()
		for key: StringName in target.get_meta_list(): target.remove_meta(key)
		for key: StringName in caster.get_meta_list(): caster.remove_meta(key)
		target.order.clear(); target.orders.clear(); target.target = null
		w.set_relation(1,0,{"enemy":2,"neutral":1,"friend":0,"point":2,"no_caster":2}[row.situation])
		w.time += 12.0 * GameUnit.TICK
		ai.notifications.clear(); ai._help.clear()
		var before := target.hp
		if row.situation == "no_caster":
			Spells.cast_from(w, code, caster.pos, target, target.pos)
		else:
			Spells.cast_unit(w, caster, code, null if row.situation == "point" else target, target.pos)
		var count := ai.notifications.filter(func(n):return n[0] == target and n[1] == caster).size()
		var hates := ai._hates(target,caster.faction)
		var label := "%s / %s"%[code,row.situation]
		check(count == row.notifications.size(), "original dispatch AI notification: "+label)
		check(hates == bool(row.hates_caster), "original dispatch individual hostility: "+label)
		# Weakness changes the maximum as well as current HP; compare wound
		# damage instead of assuming equal HP for every non-damaging spell.
		check(not target.dead and target.action != "hit", "spell provocation does not invent a damaging hit: "+label)
		observations.append({"spell":code,"index":row.index,"situation":row.situation,"notifications":count,
			"hates_caster":hates,"original_notifications":row.notifications.size(),"original_hates_caster":row.hates_caster,
			"before_hp":before,"after_hp":target.hp})
		if row.situation=="enemy" and code in Spells.PROVOKING_EFFECTS:
			# The captured switch tests target kind only. A retained creature
			# corpse reaches that same branch; do not invent an alive-only gate.
			target.dead=true;target.remove_meta("hate");ai.notifications.clear()
			Spells.cast_unit(w,caster,code,target,target.pos)
			check(ai.notifications.size()==row.notifications.size(),"native creature gate also notifies for retained corpse: "+code)
			check(ai._hates(target,caster.faction)==bool(row.hates_caster),"native creature gate retains corpse hostility write: "+code)
			check(target.dead,"spell notification does not revive corpse: "+code)
			target.dead=false
	FileAccess.open("user://spell-alerts.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":campaign,"reference":ref.sha256,
		"rat":prototypes[0].name,"checks":checks,"failures":failures,"rows":observations},"\t"))
	w.queue_free()
	for i in 8: await get_tree().process_frame
	print("SPELL_ALERTS ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
