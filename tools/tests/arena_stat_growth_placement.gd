extends Node
## Promotion never weakens a recruit, replica boards inspect Trials spells,
## armor names its exceptions instead of a range, and the deployment ring
## agrees with ArenaRun.deploy (2026-10-28 autochess feedback).
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	ArenaExpansion.mount()
	var native := hash(GameData.db.tables)
	growth()
	await replica_spells()
	armor_lines()
	await placement()
	check(hash(GameData.db.tables) == native, "campaign database remains immutable")
	print("ARENA_STAT_GROWTH_PLACEMENT ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


## Every displayed statistic and spell grows (or holds) with each star.
func growth() -> void:
	for family: int in ArenaRules.active_families(true):
		var rows := ArenaUnitInfo.rank_values(family, 0)
		for star in [1, 2]:
			var low: Dictionary = rows[star - 1]
			var high: Dictionary = rows[star]
			for key in ["max_hp", "attack", "defense", "min", "max", "actions"]:
				check(float(high[key]) >= float(low[key]), "%s does not fall at star %d of family %d" % [key, star + 1, family])
			for type in 7:
				check(high.armor[type] >= low.armor[type], "armor %d does not fall at star %d of family %d" % [type, star + 1, family])
			for index in high.spells.size():
				# Curse's smallest native hit is fixed; its cast rate grows instead.
				var grows: bool = float(high.spells[index].damage) > float(low.spells[index].damage) \
					or (is_equal_approx(float(high.spells[index].damage), float(low.spells[index].damage)) and float(high.actions) > float(low.actions))
				check(grows, "spell %s grows at star %d of family %d" % [high.spells[index].code, star + 1, family])


## The reported two-star shaman: a board mirrored from the combat worker kept
## the native prototype, so inspection showed campaign spell power (21/21/0.8).
func replica_spells() -> void:
	var run := ArenaRun.new(); run.auto_save = false; run.begin(7191); run.army.clear()
	var shaman := run._recruit(13, 1, 9); run.arrange()
	var authority := ArenaPveMatch.new(); authority.run = run; authority.rendered = false; authority.drives_clock = false
	add_child(authority); authority.set_process(false); authority.set_physics_process(false); authority._world_parent = self
	authority.prepare()
	var actor: GameUnit = null
	for unit: GameUnit in authority.world.unit_rows():
		if int(unit.get_meta("arena_placement", {}).get("run_uid", -1)) == int(shaman.uid): actor = unit
	check(actor != null, "authority deploys the shaman")
	var record := authority._unit_record(actor)
	record.online_body = ArenaOnlineGame.exact_body(actor)
	record.placement = actor.get_meta("arena_placement", {}).duplicate(true)
	var replica := ArenaOnlineMatch.new(); replica.run = run; replica.rendered = false
	add_child(replica); replica._world_parent = self; replica.set_process(false); replica.set_physics_process(false)
	replica.apply_board({"generation":"growth:1","serial":1,"full":true,"phase":ArenaMatch.Phase.DEPLOY,"time":0.0,"winner":-1,
		"damage":authority.damage.duplicate(),"records":[record],"army":authority.round_army.duplicate(true)})
	var mirrored: GameUnit = replica.world.units[int(record.nid)]
	check(Array(mirrored.proto.spells) == Array(actor.proto.spells), "replica casts the authority's Trials spells")
	RemakeText.lang = "en"
	var shown := ArenaUnitInfo.summary(mirrored.info.prototype, mirrored, -1, 0, run.army)
	var arrow := RemakeText.t(WikiCatalog.spell_title("arrow"))
	check(shown.contains(arrow + " (24.5/[b]45.5[/b]/101.5)"), "replica fire arrow shows the two-star value: " + shown)
	check(not shown.contains("[b]21[/b]"), "replica no longer shows native spell power")
	replica.queue_free(); authority.queue_free(); await get_tree().process_frame


## Trolls resist piercing: the physical line names that type, not "9–16".
func armor_lines() -> void:
	var rows := ArenaUnitInfo.rank_values(14, 1)
	check(roundi(rows[1].armor[0]) != roundi(rows[1].armor[1]), "fixture troll has unequal physical armor")
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		var text := ArenaUnitInfo.summary(ArenaRules.prototype(14, 1), null, 14, 1)
		var physical := ""
		var elemental := ""
		for line in text.split("\n"):
			if line.begins_with(RemakeText.t("Physical armor")): physical = line
			if line.begins_with(RemakeText.t("Elemental armor")): elemental = line
		check(not physical.contains("–") and not elemental.contains("–"), "armor lines contain no ranges: " + language)
		var exception := RemakeText.t(WikiCatalog.DAMAGE_TYPES[0])
		check(physical.contains("[b]%d[/b]" % roundi(rows[1].armor[1])) and physical.contains(" · " + exception + " "), "troll armor names its exception: " + physical)
		check(physical.contains("[b]%d[/b]" % roundi(rows[1].armor[0])), "exception shows its own rank values: " + physical)
	RemakeText.lang = "en"


## A valid ring is a valid deploy, and near misses snap beside the neighbour.
func placement() -> void:
	var run := ArenaRun.new(); run.auto_save = false; run.begin(7191); run.army.clear()
	var still := run._recruit(2, 0, 1)
	var moving := run._recruit(2, 0, 1)
	still.deployed = true; still.point = [25.0, 30.0]
	moving.deployed = true; moving.point = [25.0, 40.0]
	var battle := ArenaPveMatch.new(); battle.run = run; battle.rendered = false; battle.drives_clock = false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent = self
	battle.prepare()
	battle.selected_run_uid = int(moving.uid)
	var near := Vector2(25.0, 32.0)
	check(battle.placement_error(near) == RemakeText.t("Leave more space between creatures."), "ring rejects a spot ArenaRun.deploy rejects")
	var mismatches := 0
	for x in range(41):
		for y in range(49):
			var point := Vector2(20.0 + x * 0.25, 20.0 + y * 0.5)
			if battle.placement_error(point).is_empty() and not run.spacing_error(int(moving.uid), point).is_empty(): mismatches += 1
	check(mismatches == 0, "no blue ring where deployment is refused (%d)" % mismatches)
	var snapped := battle.placement_point(near)
	check(snapped.is_finite() and snapped.distance_to(near) <= 1.5 + 0.001, "near miss snaps within reach")
	check(snapped.distance_to(Vector2(25.0, 30.0)) >= ArenaRun.DEPLOY_SPACING, "snapped spot keeps saved spacing")
	check(run.deploy(int(moving.uid), snapped).is_empty(), "snapped spot deploys")
	check(battle.placement_point(Vector2(60.0, 30.0)) == Vector2.INF, "enemy half never snaps into the deployment zone")
	battle.queue_free(); await get_tree().process_frame
