extends Node
## Recovery keeps local purchases and discards only incomplete combat outcomes.
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func _ready() -> void:
	var league:=ArenaTournamentRun.new();league.auto_save=false;league.live_boards=true;league.begin(7319)
	league._recruit(24,0,1);league.arrange()
	var stage:=Node3D.new();add_child(stage)
	var home:=ArenaPveMatch.new();home.run=league;home.rendered=false
	add_child(home);home.set_process(false);home.set_physics_process(false);home._world_parent=stage;home.prepare()
	var boards:=ArenaSoloBattles.new();boards.worker_failed=true;boards.run=league
	boards.home=home;boards.parent_stage=stage;boards.rendered=false
	add_child(boards);boards.set_process(false);boards.synchronize()
	check(boards.request_start(),"prepare round for fallback")
	# A transport failure can occur between adopting two of the nine boards.
	home.external_combat=true;home.is_host=false;home.world.authority=false
	boards._inline_fallback()
	check(boards.starting and not home.external_combat and home.is_host and home.world.authority,"partial replica returns to ordinary authority")
	for index in 20:
		if not boards.starting:break
		boards._prepare_start_frame()
	check(league.stage=="fight" and not boards.starting,"inline fallback starts the same round")
	league.gold=100;league.shop[0]={"family":27,"rank":0,"locked":false}
	check(league.buy(0).is_empty(),"purchase during battle")
	var army:=league.army.duplicate(true);var gold:=league.gold;var health:=league.lives
	boards.external_active=true
	boards._lost("fixture")
	check(league.stage=="prepare" and league.board_results.is_empty() and league._human_result.is_empty(),"failed round discards partial outcomes")
	check(league.army==army and league.gold==gold and league.lives==health,"failure preserves purchases, gold and health")
	check(home.is_host and home.world.authority and not home.external_combat,"retry owns fresh local units")
	league.stage="result";boards.external_active=true
	boards._lost("fixture")
	check(league.stage=="result","late disconnect cannot undo settled results")
	boards.queue_free();home.queue_free();stage.queue_free()
	await get_tree().process_frame;await get_tree().process_frame
	print("ARENA_SOLO_RECOVERY ",checks," checks; failures=",JSON.stringify(failures))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
