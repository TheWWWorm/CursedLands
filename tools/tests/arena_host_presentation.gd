extends Node
## Rendered-process authority must remain visual-free even at Ultra.
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL ",message)
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"net_lan":0,"net_upnp":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	for i in 24: await get_tree().process_frame
	var authority := ArenaOnlineGame.new(); add_child(authority)
	authority.begin(7319,{0:"Host"}); authority.set_process(false)
	for player in 9:
		var battle := authority.encounter(player)
		check(not battle.world.presentation,"authority world has no presentation")
		check(not battle.world.is_visible_in_tree(),"authority world is hidden")
		check(not is_instance_valid(battle.world.terrain.contact),"navigation scenery creates no contact materials")
		check(battle.world.terrain._ground_surface == null,"no visual field allocated for authority terrain")
		check(battle.world.nav != null,"navigation remains available")
	authority.run._recruit(0,0,1); authority.run.arrange(); authority._prepare()
	check(not authority.home.world.is_visible_in_tree(),"formation refresh retains hidden authority")
	authority.start_round()
	for player in 9: check(not authority.encounter(player).world.is_visible_in_tree(),"combat retains hidden authority")
	authority.advance_clock(0.55)
	check(authority.home.world.time > 0,"hidden authority still simulates")
	authority.queue_free()
	for i in 4: await get_tree().process_frame
	print("ARENA_HOST_PRESENTATION ",checks," checks; failures=",failures)
	TexUpscale.shutdown(); get_tree().quit(int(failures>0))
