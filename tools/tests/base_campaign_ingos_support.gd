extends "base_campaign_support.gd"
## Base Ingos checkpoints keep original map objects and predicates. Only
## walking/combat are accelerated; all objective effects come from handlers.

func ingos() -> void:
	boot(); chapter("Ingos","Human Hero","Hero","")

func near_object(id: int) -> void:
	var unit: GameUnit = s.world.units.get(id)
	if unit != null:
		teleport(unit.pos+Vector2(1,0)); return
	var obj: Node3D = s.world.objects.get(id)
	if not check(obj != null,"original object exists for approach: "+str(id)): return
	var p: Vector3 = obj.get_meta("ei").position
	teleport(Vector2(p.x,p.y)+Vector2(1,0))

func item_name(number: int) -> String:
	for row: Dictionary in GameData.db.table("quest_items"):
		if int(row.get("script_id",0)) == number: return String(row.name).to_lower()
	check(false,"original quest-item record exists: "+str(number))
	return ""

func has_item(number: int) -> bool:
	return s.state.quest_items.has(item_name(number))

func loot_original(map_file: String, number: int) -> bool:
	return loot_key(map_file,item_name(number))

func steal_original(id: int) -> void:
	var target: GameUnit = s.world.units.get(id)
	if not check(target != null and not target.dead,"original living theft target exists: "+str(id)): return
	teleport(target.pos+Vector2(1,0))
	var thief := hero()
	thief.stats.dex = 999.0 # Skill acceleration, never inventory/outcome setup.
	s.apply_command({"t":"steal","unit":thief.uid,"target":id},0)
	vm()._check_interactions()
	for i in 320:
		thief.tick(GameUnit.TICK); vm()._check_interactions()
		if not thief.has_meta("interact") and thief.orders.is_empty() and thief.order.is_empty(): break
	check(not thief.has_meta("interact"),"ordinary theft reaches its use-animation completion")
	ticks(8)

func done(quest: String, label: String) -> void:
	check(value(quest) == 2,label)
	check(s.state.quests.get(quest.get_slice(".",2),0) == 2,"completed objective is recorded in the journal: "+quest)

func calm() -> void:
	for i in 800:
		if s.world.dialog_movers.is_empty(): break
		s.world._tick(GameUnit.TICK)
		if i%40 == 0: await frames(1)
	check(s.world.dialog_movers.is_empty(),"normal dialogue return walks finish")
