extends Node
## Original multiplayer: the process owner keeps character zero across maps.
## Run with original base-game data and a disposable user profile.
var checks := 0
var failures := 0
var session: Session
var game: Game

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL LOCAL_HOST_LMP ", label)
	return value

func until(predicate: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func finish() -> void:
	if session and session.local_host.frontend:
		await session.local_host.stop()
	if session:
		check(not session.local_host._process_alive(), "authority exits")
	print("LOCAL_HOST_LMP ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,
		"net_directory":0,"autosave":0,"auto_graphics":0}, true)
	if not check(LmpMode.available() and GameData.use_lmp_database(true), "base-game LMP data exists"):
		await finish(); return
	var faces := MpCharacter.faces()
	if not check(not faces[0].is_empty(), "authored character prototypes exist"):
		await finish(); return
	var character := MpCharacter.create(String(faces[0][0]))
	character.heroes[0].name = "OwnerTest"
	MpCharacter.finish(character, "", "", "")
	if not check(MpCharacter.save_file("1.mp", character), "test character saved"):
		await finish(); return
	MpCharacter.select("1.mp")
	GameData.use_lmp_database(false)
	session = Session.new()
	get_parent().add_child(session)
	game = Game.new()
	game.session = session; session.game = game
	get_parent().add_child(game)
	if not check(await session.local_host.start(29929, 2) == OK, "owner starts"):
		await finish(); return
	check(session.my_index == 0 and session.players.size() == 1, "one real owner")
	var quests := LmpMode.quests_of(session.campaign, "bz1mpg")
	if not check(not quests.is_empty(), "authored quests exist"):
		await finish(); return
	var quest := String(quests[0])
	var answer := await session.local_host.request("lmp", {"base":"bz1mpg", "quest":quest})
	if not check(answer.get("ok", false), "authority accepts selected character"):
		await finish(); return
	if not check(await until(func(): return session.zone_id == "bz1mpg" and session.world != null and not session._remote_loading), "owner receives base"):
		await finish(); return
	check(not session.world.authority and not game.my_units().is_empty(), "owner controls a replicated party")
	check(session.lmp_generation > 0 and String(session.lmp.get("quest", "")) == quest, "quest and generation synchronized")
	var hero: GameUnit = game.my_units()[0]
	# Villages permit walk/run, but deliberately refuse crawl/kneel. Use a
	# permitted gait to prove that the owner's command reaches the worker.
	var gait := 3 if hero.gait() != 3 else 2
	session.submit({"t":"gait", "units":[hero.uid], "gait":gait})
	check(await until(func(): return hero.gait() == gait, 5), "owner command reaches authority")
	session.submit({"t":"gait", "units":[hero.uid], "gait":0})
	await get_tree().create_timer(0.4).timeout
	check(hero.gait() == gait, "base refuses crawling without losing permitted gait")
	var before := session.lmp_generation
	session.submit({"t":"travel", "zone":quest, "entrance":1})
	if not check(await until(func(): return session.zone_id == quest and not session._remote_loading, 45), "owner receives quest after travel"):
		await finish(); return
	check(session.lmp_generation > before, "quest advances generation")
	check(not game.my_units().is_empty() and session.my_index == 0, "quest preserves owner party")
	hero = game.my_units()[0]
	session.submit({"t":"gait", "units":[hero.uid], "gait":0})
	check(await until(func(): return hero.gait() == 0, 5), "field permits crawling through authority")
	session.submit({"t":"gait", "units":[hero.uid], "gait":2})
	check(await until(func(): return hero.gait() == 2, 5), "field returns to walking through authority")
	before = session.lmp_generation
	session.submit({"t":"travel", "zone":"bz1mpg", "entrance":1})
	if not check(await until(func(): return session.zone_id == "bz1mpg" and not session._remote_loading, 45), "owner returns to base"):
		await finish(); return
	check(session.lmp_generation > before, "return advances generation")
	hero = game.my_units()[0]
	gait = 3 if hero.gait() != 3 else 2
	session.submit({"t":"gait", "units":[hero.uid], "gait":gait})
	check(await until(func(): return hero.gait() == gait, 5), "commands work after return")
	session.submit({"t":"gait", "units":[hero.uid], "gait":1})
	await get_tree().create_timer(0.4).timeout
	check(hero.gait() == gait, "return to base restores the posture restriction")
	check(MpCharacter.load_file("1.mp").heroes[0].name == "OwnerTest", "local character persists")
	await finish()
