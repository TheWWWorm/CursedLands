extends "local_host_campaign.gd"
## A village save carries a masked field speed through the real solo worker.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	var seed := Session.new(); add_child(seed)
	seed.local_host.worker = true; seed.local_host.single_player = true
	var seed_game := Game.new(); seed_game.session = seed; seed.game = seed_game; add_child(seed_game)
	seed.state.ensure_hero(0,"Human Hero")
	seed._enter_zone("bz14h",1,false)
	seed.restore_play_clock({"speed":0,"field_speed":1,"paused":false})
	check(seed.save_game("worker-village-seed") == OK,"village fixture saved")
	seed_game.queue_free(); seed.queue_free()
	for i in 8: await get_tree().process_frame
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session = s; s.game = g; get_parent().add_child(g)
	check(await s.local_host.start(0,1,true) == OK,"solo authority starts")
	var answer := await s.local_host.request("load",{"slot":"worker-village-seed"})
	check(answer.get("ok",false),"worker loads village")
	check(await until(func():return s.world != null and not s._remote_loading and s.field_speed == 1,30),"owner receives remembered field speed")
	check(g.speed == 0 and Engine.time_scale == 1.0,"village remains at 1x")
	g.set_speed(2)
	check(g.speed == 0 and s.field_speed == 1,"village input keeps the field preference")
	answer = await s.local_host.request("save",{"slot":"worker-village-roundtrip"})
	check(answer.get("ok",false),"worker saves village")
	var state := CampaignState.load_from(SaveInfo.path("worker-village-roundtrip"))
	check(state != null and state.play_clock == {"speed":0,"paused":false,"field_speed":1},"worker and owner retain masked speed in save")
	s.restore_play_clock({})
	answer = await s.local_host.request("load",{"slot":"worker-village-roundtrip"})
	check(answer.get("ok",false),"worker reloads village")
	check(await until(func():return not s._remote_loading and s.field_speed == 1,30),"reload restores remembered 2x")
	check(g.speed == 0 and Engine.time_scale == 1.0,"reloaded village stays normal")
	await s.local_host.stop()
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("LOCAL_HOST_ZONE_SPEED ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
