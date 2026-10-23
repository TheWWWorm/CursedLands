extends "base_campaign_ingos_support.gd"
## Prepared completed detective introduction: Trapper offers T43. The
## guardian, captive elder, escort and ranger outcomes are all earned here.

func _ready() -> void: run.call_deferred()

func run() -> void:
	ingos()
	await accept("bz8k","b.Trapper.T43","q.gz11k.q45ak")
	await enter("gz11k")
	start(["VCheck#0#20","VCheck#0#32","VCheck#0#264","VTriger#0#66","VCheck#0#88","VCheck#0#89","VCheck#0#97","VCheck#0#123","VCheck#0#124","VCheck#0#128","VCheck#0#129","VTriger#0#203"])
	teleport(Vector2(122,347)); ticks(8)
	check(value("q.gz11k.q45ak.7") == 2 and value("q.gz11k.q45ak.8") == 1,"actual laborer camp approach discovers the optional release objective")
	use(3712); ticks(8)
	check(value("q.gz11k.q45ak.8") == 2,"ordinary laborer fence use completes the optional rescue")
	check(int(s.world.levers[3711].state) == 1,"laborer release opens the second linked fence")
	for id in [3851,3852,3853]:
		var laborer: GameUnit = s.world.units.get(id)
		if check(laborer != null and not laborer.dead,"released original laborer remains alive before evacuation: "+str(id)):
			teleport(Vector2(110,373),laborer); ticks(8)
			check(not s.world.units.has(id),"freed laborer exits through the authored evacuation point: "+str(id))
	teleport(Vector2(147,252)); near_object(3617)
	use(3617,false)
	check(value("q.gz11k.q45ak") == 1,"cage rescue stays pending without its original key")
	if not await loot_original("zone11.mob",39):
		await finish("BASE_CAMPAIGN_INGOS_DRYADS","Stopped at guardian key"); return
	use(3617)
	check(not has_item(39),"actual cage unlock consumes the shaman's key")
	near_object(3596)
	check(value("q.gz11k.q45ak") == 1,"freed cage still requires the outer fence")
	use(3595); near_object(3596); ticks(8)
	check(int(s.world.levers[3594].state) == 1,"guardian rescue opens both linked outer fences")
	done("q.gz11k.q45ak","cage, fence and actual freed-guardian contact finish rescue")
	check(has_item(11) and value("q.gz11k.q45k") == 1,"guardian rescue grants the idol and accepts the dryad visit")
	teleport(Vector2(295,90)); ticks(8)
	done("q.gz11k.q45k","actual dryad-camp arrival finishes the introduction")
	gate("bz9k",true,"guardian invitation opens the original dryad camp")
	if not await leave("bz9k"):
		await finish("BASE_CAMPAIGN_INGOS_DRYADS","Stopped at dryad village passage"); return
	await complete("b.bz9k.Yc45")
	check(value("q.gz13k.q46k") == 1 and not has_item(11),"actual dryad introduction consumes the idol and accepts elder rescue")
	await enter("gz13k")
	start(["VCheck#0#63","VTriger#0#52","VCheck#0#89","VCheck#0#108","VCheck#0#9","VCheck#0#299"])
	near_object(2703); near_object(4216); use(4216,false)
	check(value("q.gz13k.q46k") == 1,"elder prison remains locked before looting its key")
	if not await loot_original("zone13.mob",32):
		await finish("BASE_CAMPAIGN_INGOS_DRYADS","Stopped at elder key"); return
	use(4216); ticks(8)
	done("q.gz13k.q46k","normal keyed prison use completes elder release")
	check(value("q.gz13k.q46bk") == 1 and not has_item(32),"release consumes the key and starts the living escort")
	await roundtrip("base_ingos_elder_released",["q.gz13k.q46k","q.gz13k.q46bk","b.YCF.Yc46"])
	var before := accounting()
	# An escort casualty has no player killer, so combat experience cannot
	# obscure whether the failed quest itself granted a reward.
	s.world.units[4215].die(null); ticks(8)
	check(value("q.gz13k.q46bk") == 3 and value("b.YCF.Yc47") == 0,"dead elder fails the escort without its success topic")
	check(s.state.heroes[0][0].get("exp_total",0) == before.experience,"failed elder escort grants no quest experience")
	check(await s.load_game_shown("base_ingos_elder_released"),"restore living elder before continuing the escort")
	freeze(); ticks(8)
	var elder: GameUnit = s.world.units.get(4215)
	check(elder != null and not elder.dead and value("q.gz13k.q46bk") == 1,"saved checkpoint restores a living pending escort")
	if elder != null:
		teleport(Vector2(142,311),elder); ticks(8)
		done("q.gz13k.q46bk","living elder reaches an authored evacuation boundary")
		check(not s.world.units.has(4215) and value("b.YCF.Yc47") == 1,"successful escort removes the elder and offers YCF's gratitude")
	await enter("bz9k"); await complete("b.YCF.Yc46")
	check(value("q.gz12k.q47ak") == 1,"actual elder-release hand-in accepts the ranger quest")
	await enter("gz12k")
	start(["VCheck#0#21","VTriger#0#213","VCheck#0#42","VCheck#0#49"])
	teleport(Vector2(116,83)); near_object(6304)
	kill([6304]); ticks(8)
	check(value("q.gz12k.q47ak") == 1 and not has_item(65),"dead ranger still requires ordinary proof-item loot")
	loot(6304); ticks(8)
	done("q.gz12k.q47ak","ordinary ranger proof loot completes the ranger quest")
	await enter("bz9k"); await complete("b.YCF.Yc47_2"); await complete("b.YCF.Yc47")
	check(not has_item(65) and value("amerc_9") == 1,"actual ranger hand-in consumes proof and earned dryad gratitude unlocks the companion")
	await roundtrip("base_ingos_dryads_done",["q.gz11k.q45ak","q.gz11k.q45k","q.gz13k.q46k","q.gz13k.q46bk","q.gz12k.q47ak","b.YCF.Yc47","amerc_9"])
	stable("dryad rescue and ranger chain")
	await finish("BASE_CAMPAIGN_INGOS_DRYADS","Prepared Trapper T43 offer from completed detective inquiry. Actual q45ak keyed cage/fence/contact plus optional laborer-fence rescue and all three living evacuations, q45 camp arrival and travel, Yc45 acceptance, q46 keyed prison release, q46bk living escort plus saved dead-elder failure branch, Yc46 acceptance, q47ak killed-and-looted ranger and normal proof/gratitude hand-ins. No measured objective or reward assigned; selected original roots, teleport/combat acceleration, save/load and duplicate checks; not native runtime parity.")
