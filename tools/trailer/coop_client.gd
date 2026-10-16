extends Node
## Real ENet guest for the co-op recording. Sends an ordinary move command.
var session: Session
var game: Game
var coordination := ""

func until(predicate: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+180000
	while not predicate.call():
		if Time.get_ticks_msec()>deadline:get_tree().quit(2);return false
		await get_tree().process_frame
	return true

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--coordination="):coordination=arg.trim_prefix("--coordination=")
	GameData.options.merge({"autosave":0,"auto_graphics":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.player_name="Mira"
	CoopProgress.bring_slot=CoopProgress.NEW
	session=Session.new();session.name="Session";get_tree().current_scene.add_child(session)
	game=Game.new();game.name="Game";game.session=session;session.game=game;get_tree().current_scene.add_child(game)
	get_tree().current_scene.game=game;get_tree().current_scene.session=session
	if not await until(func():return FileAccess.file_exists(coordination+"/ready")):return
	var port:=FileAccess.get_file_as_string(coordination+"/ready").to_int()
	if session.join("127.0.0.1",port)!=OK:get_tree().quit(2);return
	if not await until(func():return session.world!=null and not session.loading_game and not session._remote_loading and not session.party_units(session.my_index).is_empty()):return
	FileAccess.open(coordination+"/loaded",FileAccess.WRITE).store_string("loaded")
	if not await until(func():return FileAccess.file_exists(coordination+"/go")):return
	var hero: GameUnit=session.party_units(session.my_index)[0]
	var to:=session.world.nav.nearest_walkable(hero.pos+Vector2(7,0))
	var cmd:={"t":"move","units":[hero.uid],"x":to.x,"y":to.y,"run":false}
	session.submit(cmd)
	var proof:=FileAccess.open(coordination+"/command",FileAccess.WRITE)
	proof.store_string(JSON.stringify({"index":session.my_index,"hero":hero.uid,"command":cmd}))
	proof.close()
	await until(func():return FileAccess.file_exists(coordination+"/done"))
	get_tree().quit()
