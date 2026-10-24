extends Node
## Make rendering checkpoints from an explicit test save, with original maps.
func _ready():
	var seed:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed-save="):seed=arg.trim_prefix("--seed-save=")
	if seed.is_empty() or GameData.campaign_id!=CampaignProfile.ASTRAL:
		printerr("Requires Lost in Astral and --seed-save=/absolute/test.sav");get_tree().quit(2);return
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.load_from(seed)
	if s.state==null:get_tree().quit(2);return
	s.state.world_time=12.0
	for zone in ["gz1h","gz2h","bz2h","bz5h","gz1d1"]:
		await s.enter_zone(zone,1,false)
		if s.world==null or s.zone_id!=zone or s.save_game("descriptor-"+zone)!=OK:
			printerr("FAIL rendering fixture ",zone);get_tree().quit(1);return
		print("SAVED descriptor-",zone)
	g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	TexUpscale.shutdown();get_tree().quit()
