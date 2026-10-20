extends "coop_progress_travel.gd"
## Completed original quests continue changing their objectives. Replay the
## actual GSSetVarMax instructions, then cross the island boundary and merge
## a resumable save. Divergent/absent guests keep their existing protection.

class QuietSession extends Session:
	func broadcast(_event: Dictionary) -> void: pass
	func sync_state() -> void: pass

func _ready() -> void:
	s = QuietSession.new(); s.state = CoopProgress.fresh_state()
	s.state.heroes[1] = s.state.heroes[0].duplicate(true)
	s.campaign = CampaignMap.load_from(GameData.texts)
	s.coop = QuietProgress.new(); s.coop.session = s
	s.online=true; s.multiplayer_game=true
	var ast := ScriptParser.parse(EIMob.load_bytes(GameData.read_file("maps/zone10.mob")).script_text)
	var instructions := []
	for script: Dictionary in ast.scripts.values():
		for block: Dictionary in script.blocks:
			for stmt: Array in block.body:
				if stmt[0]==ScriptParser.S_CALL and stmt[1]=="GSSetVarMax" and stmt[2].size()==3 \
						and stmt[2][1][0]==ScriptParser.N_STR and stmt[2][1][1] in ["q.gz10g.q36ag.11","q.gz10g.q36ag.12"]:
					instructions.append(stmt)
	check(instructions.size()>=3,"original portal script defines post-completion objective transitions")
	var e := entry(); e.vars={"q.gz10g.q36ag":2.0,"q.gz10g.q36ag.11":1.0}
	s.state.set_var(0,"q.gz10g.q36ag",2); s.state.set_var(0,"q.gz10g.q36ag.11",1)
	s.coop.joiners={"guest":e}; s.coop._zone="gz10g"; s.zone_id="gz10g"
	CampaignState.watch=s.coop._on_var
	var vm := ScriptVM.new(); vm.session=s
	for stmt: Array in instructions:
		vm._call(stmt[1],stmt[2],ScriptVM.Instance.new())
	check(e.clean and e.in_sync and e.present,"shared completed quest retains continuity through all original objective writes")
	check(e.vars.get("q.gz10g.q36ag.11")==2 and e.vars.get("q.gz10g.q36ag.12")==2,"completed quest objectives still reach the shared save")
	# Terminal objective reset is also an authored transition, not new loot.
	s.state.set_var(0,"q.gz10g.q36ag.12",0)
	check(e.clean and e.vars.get("q.gz10g.q36ag.12")==0,"aligned reset does not strand the guest")
	s.state.day=104; s.state.world_time=20.25; s.zone_id="gz11k"
	s.coop.zone_entered("gz11k")
	check(e.in_sync and e.clean,"island departure follows the same shared story")
	var own := CoopProgress.fresh_state(); own.day=50; own.current_zone="bz3g"
	CoopProgress.merge(own,s.coop.package(e))
	check(own.current_zone=="gz11k" and own.day==104 and own.world_time==20.25,"returned location and campaign day advance together")
	check(own.money==222,"advancing the story retains personal money")
	for field: String in ["in_sync","clean","present"]:
		var guarded := entry(); guarded.vars={"q.gz10g.q36ag":2.0,"q.gz10g.q36ag.11":1.0}; guarded[field]=false
		s.coop._credit_var(guarded,"q.gz10g.q36ag.11",1,2)
		check(guarded.vars["q.gz10g.q36ag.11"]==1 and not guarded.clean,"divergent completed quest remains protected without "+field)
	var mismatch := entry(); mismatch.vars={"q.gz10g.q36ag":2.0,"q.gz10g.q36ag.11":3.0}
	s.coop._credit_var(mismatch,"q.gz10g.q36ag.11",1,2)
	check(mismatch.vars["q.gz10g.q36ag.11"]==3 and not mismatch.clean,"a genuinely different objective is never silently overwritten")
	CampaignState.watch=Callable(); s.coop.free(); s.free()
	print("COOP_PROGRESS_CLEANUP ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
