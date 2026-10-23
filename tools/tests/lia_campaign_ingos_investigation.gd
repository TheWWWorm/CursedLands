extends "lia_campaign_support.gd"
## Starts with the separately earned Grey ritual return (q5k). Actual offers
## then connect the factory, forest, materials, investigation and mine key.

func _ready() -> void: run.call_deferred()

func run() -> void:
	boot(); chapter("Gipat","Hero3","Hero","merc2g")
	# Previous ritual checkpoint: Grey207 gave the invitation and SverAlc,
	# accepted q6k, and offered His210/Trapper207a. These are not outcomes
	# tested here; lia_campaign_mid_ingos earns them through the full scene.
	s.state.set_var(0,"q.gz23k.q6k",1)
	s.state.set_var(0,"b.His.brief_210",1)
	s.state.set_var(0,"b.Trapper.brief_207a",1)
	s.state.add_item("SverAlc")
	await enter("gz21k")
	await enter("bz21k"); await complete("b.Trapper.brief_207a"); await complete("b.His.brief_210")
	check(value("q.gz22k.q8k") == 1 and value("q.gz21k.q9k") == 1,"actual ritual follow-ups start forest and magic-item quests")
	await magic_items()
	await factory()
	await forest_and_materials()
	await investigation()
	await finish("LIA_CAMPAIGN_INGOS_INVESTIGATION","Prepared earned Grey ritual-return checkpoint; normal offers and actions complete q6k factory approach, q7k explosive sabotage, q8k forest clearance, q9k magic items, q10k supplies, q11k four looted elemental corpses, q12k arrow, q13k sighting and q14k note handoff. Actual shared-topic gates lead to q15k mine key and q16k missing-person offers. Negative item/last-target/hand-in conditions, saves and ordinary village travel. God mode, teleport and combat kills; no native-executable claim.")

func magic_items() -> void:
	await enter("gz21k"); start(["VCheck#4#1"]); ticks(25)
	teleport(Vector2(459,318.5)); kill([1009002,1009003])
	check(value("q.gz21k.q9k.2") == 1,"last magic-item guardian prevents the collection objective")
	kill([1009004]); use(1009001)
	check(value("q.gz21k.q9k") == 2 and s.state.quest_items.has("magicitems") and value("b.His.brief_211") == 1,"actual guarded container completes magic-item recovery")
	await enter("bz21k"); await complete("b.His.brief_211")
	check(not s.state.quest_items.has("magicitems"),"His hand-in consumes the recovered magic items")

func factory() -> void:
	await enter("gz23k"); start(["VCheck#1#1"]); ticks(25)
	gate("bz23k",false,"factory village remains closed before the accepted approach quest")
	teleport(Vector2(216,8))
	check(value("q.gz23k.q6k") == 1,"factory arrival area cannot skip its original gate control")
	use(4285); teleport(Vector2(216,8))
	check(value("q.gz23k.q6k") == 2 and value("b.Grey.brief_208") == 1,"gate use and actual approach complete factory arrival")
	gate("bz23k",true,"completed approach opens the factory village")
	if not await leave("bz23k"): return
	await complete("b.Grey.brief_208")
	await enter("bz21k"); await complete("b.Trader.brief_208b")
	check(value("q.gz23k.q7k") == 1,"actual Grey and Trader dialogue chain offers sabotage")
	await enter("gz23k"); start(["VCheck#2#1"]); ticks(25)
	teleport(Vector2(264,81)); use(1007002,false)
	check(value("q.gz23k.q7k") == 1,"planting point rejects use before collecting the actual explosive")
	use(1007001)
	check(s.state.quest_items.has("caboom"),"normal explosive pickup grants the planting prerequisite")
	use(1007002)
	check(not s.state.quest_items.has("caboom") and value("q.gz23k.q7k") == 1,"planting consumes the explosive without skipping its fuse")
	await roundtrip("campaign_factory_fuse",["q.gz23k.q7k","q.gz23k.q7k.3"])
	ticks(300)
	check(value("q.gz23k.q7k") == 2 and value("b.Grey.brief_209") == 1 and value("b.Haburu.fq15") == 1,"actual explosion completes sabotage and unlocks both main hand-in and fortune chain")
	check(not s.world.objects.has(4217) and not s.world.objects.has(1007002),"authored explosion removes its blocking structure and planting object")
	stable("factory explosion")
	await enter("bz23k"); await complete("b.Grey.brief_209")

func forest_and_materials() -> void:
	await enter("gz22k"); start(["VCheck#0#1"]); ticks(25)
	gate("bz22k",false,"far-forest village is gated before its clearance")
	teleport(Vector2(106,332)); kill(range(1008001,1008008))
	check(value("q.gz22k.q8k") == 1,"one remaining forest enemy keeps the village gate closed")
	kill([1008008])
	check(value("q.gz22k.q8k") == 2 and value("b.Gerald.brief_212") == 1,"last forest enemy completes clearance and offers Gerald")
	gate("bz22k",true,"forest clearance opens its actual village passage")
	if not await leave("bz22k"): return
	await complete("b.Gerald.brief_212"); await complete("b.Gerald.brief_214")
	check(value("q.gz23k.q10k") == 1,"actual Gerald chain starts supplies retrieval")
	await enter("gz23k"); start(["VCheck#3#1"]); ticks(25)
	teleport(Vector2(84,189.5)); kill(range(1010002,1010007))
	check(value("q.gz23k.q10k") == 1,"supplies guards alone cannot grant the uncollected cargo")
	use(1010001)
	check(value("q.gz23k.q10k") == 2 and s.state.quest_items.has("capitalitems"),"normal cargo pickup completes supplies retrieval")
	await enter("bz22k"); await complete("b.Gerald.brief_215"); await complete("b.MThief.brief_217")
	check(value("q.gz22k.q11k") == 1 and s.state.quest_items.has("kkey06"),"actual cargo hand-in unlocks materials quest and supplies its key")
	await enter("gz22k"); start(["VCheck#1#1","Lever#0#1"]); ticks(25)
	use(5634); kill(range(1011001,1011005))
	check(value("q.gz22k.q11k") == 1,"dead elementals must actually be looted before materials are granted")
	for id: int in [1011001,1011002,1011003]: loot(id)
	check(value("q.gz22k.q11k") == 1,"one unlooted elemental keeps materials collection pending")
	await roundtrip("campaign_materials_last_body",["q.gz22k.q11k","q.gz22k.q11k.2"],["kkey06"])
	loot(1011004)
	check(value("q.gz22k.q11k") == 2 and s.state.quest_items.has("elemmat"),"fourth ordinary corpse loot completes materials collection")
	await enter("bz22k"); start(["VCheck#0#2"])
	await complete("b.KMage.brief_219")
	check(value("b.KMage.brief_221") == 0,"first materials hand-in alone cannot offer the mage follow-up")
	await complete("b.MThief.brief_220")
	check(value("b.KMage.brief_221") == 1,"both actual materials hand-ins offer the mage follow-up")
	await complete("b.KMage.brief_221")
	await enter("bz21k"); start(["VCheck#0#11"])
	check(value("b.His.brief_222") == 1,"mage and previously earned magic-item hand-ins unlock the successful investigation branch")
	await complete("b.His.brief_222"); await complete("b.Huber.brief_224")
	check(value("q.gz22k.q12k") == 1,"actual successful branch accepts arrow investigation")

func investigation() -> void:
	await enter("gz22k"); start(["VCheck#2#1"]); ticks(25)
	teleport(Vector2(83,184))
	var carrier: GameUnit = s.world.units.get(1012001)
	if not check(carrier != null,"original arrow carrier exists"): return
	teleport(carrier.pos+Vector2(3,0))
	check(value("q.gz22k.q12k.3") == 1 and value("q.gz22k.q12k") == 1,"finding the actual arrow carrier does not grant its item")
	if not loot_key("zone22.mob","darrow"): return
	check(value("q.gz22k.q12k") == 2 and value("b.Huber.brief_225") == 1,"ordinary arrow loot completes the investigation and offers Huber")
	await enter("bz21k"); await complete("b.Huber.brief_225")
	check(value("b.MThief.brief_228") == 1,"actual arrow hand-in offers the spy quest")
	await enter("bz22k"); await complete("b.MThief.brief_228")
	if not await wait_zone("gz22k"): return
	# Earlier fixtures select only their quest roots, so restore this original
	# waiting root when the real conversation returns to that cached map.
	start(["VCheck#3#1"]); ticks(30)
	gate("bz22k",false,"active spy outing closes the village passage")
	check(value("q.gz22k.q13k") == 1,"spy quest remains pending before actually seeing the target")
	var watcher: GameUnit = s.world.units.get(1013001)
	var target: GameUnit = s.world.units.get(1013002)
	if not check(watcher != null and target != null,"original spy and lookout actors were spawned"): return
	await roundtrip("campaign_spy_before_sighting",["q.gz22k.q13k","z.bz22k"])
	watcher = s.world.units.get(1013001)
	# An actual sightline in front of the lookout exercises the failure
	# branch; reload the pending checkpoint before taking the hidden route.
	var observer := hero()
	observer.command({"type":"wait","t":0.0})
	observer.pos = watcher.pos+Vector2.from_angle(watcher.facing)*3.0
	observer.resync_drawn(); ticks(3)
	check(value("q.gz22k.q13k") == 3 and value("b.MThief.brief_230") == 0,"actual lookout detection fails the spy quest without a success hand-in")
	check(await s.load_game_shown("campaign_spy_before_sighting"),"reload pending spy checkpoint before its detected failure")
	freeze(); ticks(12)
	check(value("q.gz22k.q13k") == 1,"pending spy save restores the unfailed quest")
	observer = hero(); target = s.world.units.get(1013002)
	# Position/orientation are accelerated; the original UnitSee predicate
	# obtains its own noticed list and decides whether the target is seen.
	observer.command({"type":"wait","t":0.0})
	observer.pos = target.pos+Vector2(3,0)
	observer.facing = (target.pos-observer.pos).angle(); observer.resync_drawn()
	# Native perception refreshes candidates every 8–11 logic ticks, then
	# the authored success scene waits another 30 ticks before its reward.
	ticks(50)
	check(value("q.gz22k.q13k") == 2 and value("b.MThief.brief_230") == 1,"actual unnoticed sighting completes the spy quest")
	ticks(65)
	gate("bz22k",true,"spy scene departure reopens the actual village passage")
	if not await leave("bz22k"): return
	await complete("b.MThief.brief_230")
	await enter("bz23k"); await complete("b.Grey.brief_231")
	check(value("b.Huber.brief_232") == 1,"actual spy follow-up unlocks Huber's next discussion")
	await enter("bz21k"); await complete("b.Huber.brief_232"); await complete("b.KMage.brief_233")
	check(value("b.MThief.brief_238") == 1 and value("b.Trapper.brief_234") == 1,"actual mage discussion offers both the note and missing-person branches")
	await complete("b.Trapper.brief_234")
	check(value("b.Grey.brief_237") == 1,"actual Trapper follow-up offers the missing-person quest")
	await enter("bz23k"); await complete("b.Grey.brief_237")
	check(value("q.gz21k.q16k") == 1,"actual Grey offer accepts the separately tested missing-person quest")
	await enter("bz22k"); await complete("b.MThief.brief_238")
	check(value("q.gz22k.q14k") == 1 and s.state.quest_items.has("knote01"),"actual note offer supplies its item and accepted quest")
	await enter("gz22k"); start(["VCheck#4#1"]); ticks(25)
	teleport(Vector2(261,372)); use(1014001)
	check(value("q.gz22k.q14k") == 2 and not s.state.quest_items.has("knote01") and value("b.MThief.brief_239a") == 1,"normal note delivery consumes its item and offers the mine-key handoff")
	await enter("bz22k"); await complete("b.MThief.brief_239a")
	check(value("b.Guard.brief_239") == 1,"actual note hand-in unlocks the Guard's mine offer")
	await roundtrip("campaign_ingos_mine_offer",["q.gz22k.q13k","q.gz22k.q14k","q.gz21k.q16k","b.Guard.brief_239"])
