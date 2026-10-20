extends "save_depth.gd"
## Save before/after real lasting effects, then reload in the same process.
func summary_marker() -> String: return "LOAD_SPELL_BOUNDARY"
func probe_cast() -> void:
	var h:=hero();var at:=h.pos+Vector2(3,0)
	check(s.save_game("before-wall")==OK,"checkpoint before casting saves")
	Spells.cast_unit(s.world,h,"litnwall",null,at)
	check(Spells.save_lasting(s.world).any(func(r):return r.get("spell","")=="litnwall"),"real lightning wall is active")
	check(not s._replay_state().spells.is_empty(),"wall visuals are tracked")
	check(s.save_game("with-wall")==OK,"checkpoint with wall saves")
	check(s.load_game("before-wall"),"earlier checkpoint reloads without restart");stop()
	check(Spells.save_lasting(s.world).is_empty(),"earlier checkpoint contains no later wall logic")
	check(s._replay_state().spells.is_empty(),"earlier checkpoint contains no later wall replay")
	check(s.load_game("with-wall"),"later checkpoint reloads");stop()
	check(not Spells.save_lasting(s.world).is_empty(),"saved wall resumes its own logic")
	check(not s._replay_state().spells.is_empty(),"saved wall resumes its own visuals")
	check(s.load_game("before-wall"),"earlier checkpoint can be loaded again");stop()
	check(Spells.save_lasting(s.world).is_empty() and s._replay_state().spells.is_empty(),"repeated load replaces wall state")
