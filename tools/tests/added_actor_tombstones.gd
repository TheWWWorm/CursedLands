extends "story_coop_traps_net.gd"
## Generic extra-mob identity regression using the authored replacement queen.
## Death/loot/save is deliberately held before the next VM poll. This proves
## the save boundary without claiming a player combat/input reproduction.
const QUEEN := 1000027
const QUEST := "q.gz5g.q22g"

func original_dead(u: GameUnit) -> bool:
	var inst := ScriptVM.Instance.new(); inst.locals.subject=u
	return bool(host.world.vm._call("IsDead",[[ScriptParser.N_VAR,"subject"]],inst))

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	host=branch(false); check(host.host(29951,2)==OK,"open tombstone host")
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.set_physics_process(false)
	await host.enter_zone("gz5g",1,false); freeze(host)
	host.world.vm.briefings._rewards("Dr20"); ticks(24)
	var leader: GameUnit=host.party_units(0)[0]
	host.world.vm._use_lever(leader,4523); ticks(30); await frames(3); ticks(6)
	var queen: GameUnit=host.world.units.get(QUEEN)
	check(queen!=null and not queen.dead,"original poisoning creates living extra-mob queen")
	if queen==null: await finish(); return
	check(host.state.get_var(0,QUEST+".1")==1 and host.state.get_var(0,QUEST+".2")==2,"only replacement queen death gate remains pending")
	check(host.save_game("queen-living")==OK,"save living extra-mob control")
	queen.die(leader); host.take_loot(leader,queen)
	check(host.world.looted.get(QUEEN)==queen and original_dead(queen),"death and loot retain the live VM identity")
	check(host.state.get_var(0,QUEST+".1")==1,"save boundary precedes next original death predicate poll")
	check(host.save_game("queen-dead-looted")==OK,"save pending gate with looted added actor")
	var saved:=CampaignState.read_data(SaveInfo.path("queen-dead-looted"))
	check(saved.zones.gz5g.looted.has(QUEEN) and saved.zones.gz5g.removed.has(QUEEN),"writer records removed and looted extra-mob identity")
	for mode: String in ["current","legacy-carried","legacy-units"]:
		var data: Dictionary=saved.duplicate(true)
		if mode!="current": data.zones.gz5g.removed.erase(QUEEN)
		if mode=="legacy-units": data.zones.gz5g.erase("carried")
		FileAccess.open(SaveInfo.path(mode),FileAccess.WRITE).store_var(data,false)
		check(host.load_game(mode),"load "+mode+" looted extra actor")
		freeze(host)
		var tombstone: GameUnit=host.world.looted.get(QUEEN)
		check(tombstone!=null and tombstone.dead and tombstone.hp<=0.0,"retain dead tombstone, "+mode)
		check(not host.world.units.has(QUEEN) and (tombstone==null or not tombstone.is_inside_tree()),"never publish looted extra actor, "+mode)
		check(tombstone!=null and host.world.vm.globals.ScrabMotherP==tombstone and original_dead(tombstone),"restore original IsDead reference, "+mode)
		ticks(12)
		check(host.state.get_var(0,QUEST)==2 and host.state.get_var(0,QUEST+".1")==2,"original pending gate completes after reload, "+mode)
		check(host.save_game(mode+"-again")==OK and host.load_game(mode+"-again"),"second save/reload "+mode)
		freeze(host)
		check(host.world.looted.has(QUEEN) and host.state.get_var(0,QUEST)==2,"second reload keeps dead identity and completion, "+mode)
	check(host.load_game("queen-living"),"reload originally living extra actor")
	freeze(host); queen=host.world.units.get(QUEEN)
	check(queen!=null and not queen.dead and not host.world.looted.has(QUEEN),"living extra actor remains living")
	if queen: host.world.remove_unit(queen)
	check(host.save_game("queen-removed-alive")==OK and host.load_game("queen-removed-alive"),"save/reload intentionally removed living extra actor")
	freeze(host); ticks(12)
	check(not host.world.units.has(QUEEN) and not host.world.looted.has(QUEEN),"removed living actor never becomes a dead tombstone")
	check(not original_dead(null) and host.state.get_var(0,QUEST+".1")==1,"missing living actor cannot satisfy IsDead or queen objective")
	print("ADDED_ACTOR_TOMBSTONES ",checks," checks ",failures," failures")
	await finish()
