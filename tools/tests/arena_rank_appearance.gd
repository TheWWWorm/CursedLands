extends Node
## Native palette compatibility, immutable combat data, promotions and replicas.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := ArenaRun.new(); run.auto_save = false; run.begin(7191)
	var restore := ArenaRun.new(); restore.auto_save = false
	run.army.clear()
	for family in ArenaRules.ACTIVE_FAMILIES:
		var previous_native_level := -1
		for rank in 3:
			var id := ArenaRules.prototype(family, rank)
			var base := ArenaAppearance.info(id)
			var shown := ArenaAppearance.info(id, family, rank)
			var proto := GameData.db.find("monster_prototypes", id)
			var own_race := GameData.db.find("race_models", proto.base_race)
			var race := GameData.db.find("race_models", shown.get("look_race", proto.base_race))
			if shown.has("look_race"):
				check(not race.is_empty() and race.mask != own_race.mask, "rank figure is another original rig %d:%d" % [family, rank])
				for key in ["speeds", "anim_speeds", "attack_distance", "head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]:
					check(race.get(key) == own_race.get(key), "rank figure keeps %s %d:%d" % [key, family, rank])
				check(rig({"prototype": id, "look_race": shown.look_race}) == rig({"prototype": id}), "rank figure has the same parts and clip lengths %d:%d" % [family, rank])
			var textures: Array[String] = []
			for compatible: Dictionary in GameData.db.tables.race_models:
				if compatible.mask == race.mask:
					for texture: String in compatible.textures: textures.append(texture.to_lower())
			check(shown.prototype == id and shown.keys().all(func(key): return key in ["prototype", "texture", "look_race"]), "appearance changes only native texture or rig %d:%d" % [family, rank])
			if shown.has("texture"):
				check(shown.texture in textures, "palette belongs to original rig %d:%d" % [family, rank])
				check(GameData.textures.has(shown.texture + ".mmp"), "native palette exists %d:%d" % [family, rank])
			if not ArenaAppearance.RANK_PALETTES.has(family) and not ArenaAppearance.RANK_RACES.has(family): check(shown == base, "single-palette recruit remains native %d:%d" % [family, rank])
			check(ArenaAppearance.info(id, -1, rank) == base, "creeps keep native appearance %d:%d" % [family, rank])
			check(ArenaAppearance.info(id, (family+1)%ArenaRules.FAMILIES.size(), rank) == base, "mismatched family cannot recolour creep %d:%d" % [family, rank])
			check(ArenaPortraits.texture(id, family, rank) != null, "rank portrait exists %d:%d" % [family, rank])
			var named := ArenaAppearance.name_prototype(id, family, rank)
			var named_proto := GameData.db.find("monster_prototypes", named)
			check(not named_proto.is_empty(), "original localized variant exists " + named)
			check(int(named_proto.base_level) >= previous_native_level, "original variant strength never decreases %d:%d" % [family,rank])
			previous_native_level = int(named_proto.base_level)
			for language in ["en", "ru", "de"]:
				RemakeText.lang = language
				var title := ArenaRules.title(id, family, rank)
				check(not title.is_empty() and not title.to_lower().contains(named), "readable localized variant %d:%d:%s" % [family, rank, language])
				check(language == "en" or RemakeText.TEXTS.has(GameUnit.unit_title(named)), "variant title has RU/DE coverage %d:%d:%s" % [family, rank, language])
			RemakeText.lang = "en"
			run.army.clear()
			run._recruit(family, rank, int(ArenaRules.FAMILIES[family].cost) * int(pow(3,rank)))
			run.arrange()
			var saved := run.snapshot()
			check(restore.restore(saved) and restore.snapshot() == saved, "original canonical save identity round-trips %d:%d" % [family,rank])
	for family: int in ArenaAppearance.RANK_RACES:
		check(not ArenaAppearance.same(ArenaAppearance.info(ArenaRules.prototype(family,0),family,0), ArenaAppearance.info(ArenaRules.prototype(family,2),family,2)), "three stars have a distinct native rig %d" % family)
	for family: int in ArenaAppearance.RANK_PALETTES:
		check(ArenaAppearance.RANK_PALETTES[family][0] != ArenaAppearance.RANK_PALETTES[family][2], "three stars have a distinct native palette %d" % family)
		check(ArenaPortraits.texture(ArenaRules.prototype(family,0),family,0) != ArenaPortraits.texture(ArenaRules.prototype(family,2),family,2), "three-star portrait has its own resource %d" % family)
	# Dragons share a canonical prototype. Rank-only promotion must rebuild its
	# palette locally and over the full-board snapshot without changing its body.
	run.begin(7191); run.army.clear()
	var dragon := run._recruit(23, 0, 5); run.arrange()
	var match_state := ArenaPveMatch.new(); match_state.run = run; match_state.rendered = false; match_state.drives_clock = false
	add_child(match_state); match_state.set_process(false); match_state.set_physics_process(false); match_state._world_parent = self
	match_state.prepare()
	var first := owned(match_state, int(dragon.uid))
	var first_record := record(match_state, first)
	var radius := first.figure_radius
	var kit: Array = Array(first.proto.spells).map(func(spell): return Spells.parse(spell).code)
	check(first.info.get("texture") == "dragon00", "one-star deployed dragon is green")
	dragon.rank = 2; dragon.investment = 45
	match_state.prepare()
	var promoted := owned(match_state, int(dragon.uid))
	check(promoted != first and promoted.info.get("texture") == "dragon02", "rank-only promotion replaces stale green figure")
	check(promoted.figure_radius == radius and Array(promoted.proto.spells).map(func(spell): return Spells.parse(spell).code) == kit, "palette promotion preserves native collision and spell kit")
	var retained := promoted
	match_state.prepare()
	check(owned(match_state, int(dragon.uid)) == retained, "unchanged appearance retains animated actor")
	var replica := ArenaOnlineMatch.new(); replica.run = run; replica.rendered = false
	add_child(replica); replica._world_parent = self; replica.set_process(false); replica.set_physics_process(false)
	var frame := {"generation":"rank-test:1","serial":1,"full":true,"phase":ArenaMatch.Phase.DEPLOY,"time":0.0,"winner":-1,"damage":match_state.damage.duplicate(),"records":[first_record],"army":match_state.round_army.duplicate(true)}
	replica.apply_board(frame)
	var old_replica: GameUnit = replica.world.units[int(first_record.nid)]
	check(old_replica.info.get("texture") == "dragon00", "full-board replica receives green dragon")
	var upgraded := record(match_state, promoted); upgraded.nid = first_record.nid
	frame.records = [upgraded]; frame.serial = 2
	replica.apply_board(frame)
	var new_replica: GameUnit = replica.world.units[int(first_record.nid)]
	check(new_replica != old_replica and new_replica.info.get("texture") == "dragon02", "same-id full-board promotion replaces stale replica palette")
	frame.serial = 3; replica.apply_board(frame)
	check(replica.world.units[int(first_record.nid)] == new_replica, "unchanged full-board refresh retains replica actor")
	check(ArenaPveMatch._replica_key({"id":dragon.prototype,"rank":0,"family":23}) != ArenaPveMatch._replica_key({"id":dragon.prototype,"rank":2,"family":23}), "replica adoption distinguishes same-prototype star ranks")
	check(hash(GameData.db.tables) == native, "campaign database remains immutable")
	replica.queue_free(); match_state.queue_free(); await get_tree().process_frame
	print("ARENA_RANK_APPEARANCE ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func owned(battle: ArenaPveMatch, uid: int) -> GameUnit:
	for unit: GameUnit in battle.world.unit_rows():
		if unit.get_meta("arena_placement", {}).get("run_uid", -1) == uid: return unit
	return null

func record(battle: ArenaPveMatch, unit: GameUnit) -> Dictionary:
	var result := battle._unit_record(unit)
	result.online_body = ArenaOnlineGame.exact_body(unit)
	result.placement = unit.get_meta("arena_placement", {}).duplicate(true)
	return result


## Part names and every clip's length of a built figure.
func rig(record: Dictionary) -> Dictionary:
	var model := EIUnitModel.create(record, true)
	var out := {"parts": model.find_children("*", "MeshInstance3D", true, false).map(func(mesh): return String(mesh.get_parent().name))}
	out.parts.sort()
	if model.player:
		for clip in model.player.get_animation_list(): out[clip] = snappedf(model.player.get_animation(clip).length, 0.001)
	model.free()
	return out
