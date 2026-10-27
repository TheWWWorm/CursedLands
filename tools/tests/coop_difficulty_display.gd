extends "coop_trade.gd"
## The effective network rule and its caption agree, regardless of solo preferences.
func _ready() -> void:
	GameData.options.merge({"difficulty":1,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0}, true)
	TutorialPanel.auto_show = false
	host = peer("DifficultyHost", true); client = peer("DifficultyGuest", false)
	check(host.host(30149,2) == OK and client.join("127.0.0.1",30149) == OK, "real co-op peers connect")
	check(await until(func(): return host.players.size() == 2), "co-op admits the guest")
	if failures: get_tree().quit(1); return
	for s: Session in [host,client]:
		ModStore.attach(s)
		s.mod_config.rules.difficulty = 1
		check(GameData.option("difficulty") == 0, "network effective difficulty ignores saved Easy")
		check(not ModStore.editable("difficulty", s).is_empty(), "network difficulty remains locked")
		var panel := OptionsPanel.new()
		panel._values.difficulty = panel._preference("difficulty")
		for language in ["en","ru","de"]:
			RemakeText.lang = language
			check(panel._switch_text({"name":"difficulty"}) == panel._t("string difficulty_hard", "Normal"), "network caption matches combat " + language)
		panel.free()
		var w := GameWorld.new(); w.session = s
		var combat := Combat.new(w)
		var enemy := GameUnit.new(); enemy.uid = 42
		GameData.difficulty = 1
		for key in ["Attack","Defence","Absorption"]:
			check(combat.difficulty(enemy,key) == 1.0, "network combat already uses full " + key)
		enemy.free(); w.free()
		check(s.mod_config.rules.difficulty == 1 and GameData.options.difficulty == 1, "effective rule preserves solo preference and saved configuration")
		ModStore.detach(s)
	check(GameData.option("difficulty") == 1, "leaving co-op restores solo Easy preference")
	host.online = false; client.online = false
	client.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for root: Node in roots: root.queue_free()
	for i in 8: await get_tree().process_frame
	print("COOP_DIFFICULTY_DISPLAY ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
