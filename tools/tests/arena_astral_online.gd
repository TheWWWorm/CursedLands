extends "arena_online_lobby.gd"
const MODE_ERROR := "Choose the same autochess mode. LiA autochess requires matching Lost in Astral data on every player."
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "mount native expansion")
	for ws in [false, true]:
		var port := 29824 if ws else 29823
		var addr := ("ws://" if ws else "") + "127.0.0.1:" + str(port)
		GameData.arena_character = "lia_hero:wrapped"
		var host := ArenaOnlineSession.new(); host.expansion = true; add_child(host)
		check(host.host(port, ws) == OK, "expansion host opens")
		check(host.lan_info().expansion, "LAN advertises expansion mode")
		var wrong := ArenaOnlineSession.new(); add_child(wrong)
		check(wrong.join(addr) == OK, "standard client tries connection")
		check(await wait_for(func(): return not wrong.status.is_empty()), "mode mismatch rejected")
		check(wrong.status == RemakeText.t(MODE_ERROR) and host.members.size() == 1, "mode rejection reserves no seat")
		wrong.close(); wrong.queue_free()
		wrong = ArenaOnlineSession.new(); wrong.expansion = true; add_child(wrong)
		check(wrong.join(addr) == OK, "different-content client connects transport")
		wrong._expansion_hash = "different-installation"
		check(await wait_for(func(): return not wrong.status.is_empty()), "content mismatch rejected")
		check(wrong.status == RemakeText.t(MODE_ERROR) and host.members.size() == 1, "content rejection reserves no seat")
		wrong.close(); wrong.queue_free()
		GameData.arena_character = "hero:jun"
		var guest := ArenaOnlineSession.new(); guest.expansion = true; add_child(guest)
		check(guest.join(addr) == OK, "compatible client connects")
		check(await wait_for(func(): return guest.my_seat == 1), "compatible client gets seat")
		guest.request("ready")
		check(await wait_for(func(): return host.members.values().all(func(m): return m.ready)), "expansion client can ready")
		check(host.start_game(7191).is_empty(), "expansion game starts")
		host.game.set_process(false)
		check(await wait_for(func(): return guest.started), "expansion snapshot arrives")
		check(guest.view.expansion and guest.view.rivals.all(func(r): return r.expansion), "every replica company has expansion pool")
		check(guest.view.pool_left().size() == 37, "replica shared pool includes eight new families")
		check(guest.view.commander == "hero:jun" and host.game.run.commander == "lia_hero:wrapped", "LiA choices remain with their owners")
		check(range(2, ArenaTournamentRun.PLAYER_COUNT).all(func(seat): return ArenaCommanders.character(host.game.run.company(seat).commander) not in ["hero", "lia_hero"]), "NPC selection excludes both chosen characters across skins")
		check(host.game.run.rivals.any(func(r): return r.commander == "lia_merc2"), "NPCs include LiA companions")
		guest.close(); host.close(); guest.queue_free(); host.queue_free(); await frames()
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		check(language == "en" or RemakeText.t(MODE_ERROR) != MODE_ERROR, "localized mode mismatch " + language)
	print("ARENA_ASTRAL_ONLINE checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
