extends Node
## Replays one original-game checkpoint in the remake. The checkpoint
## (--checkpoint=path.json, made by tools/parity/checkpoints.py from two
## original saves) names the zone, the GS vars read from the original's save
## before the step, and the steps. This harness loads those vars, enters the
## zone, performs the steps through the normal UI/command routes and prints
## the GS vars after zone entry and after the steps. It never sees the
## original's result; checkpoints.py compares.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(s: Session, n: int) -> void:
	for i in n:
		if not s.loading_game and is_instance_valid(s.world): s.world._tick(GameUnit.TICK)

func freeze(s: Session) -> void:
	s.set_physics_process(false)
	if is_instance_valid(s.world):
		s.world.set_process(false)
		s.world.set_physics_process(false)

## Inspect every nested argument before evaluating a probe: a pure outer
## comparison must not hide GSSetVar/GiveItem/etc. Random also changes the
## supplied draw stream, so it is never an observation.
func read_only_expression(expr: Array) -> bool:
	if expr[0] != ScriptParser.N_CALL: return true
	if not ScriptVM.PURE_CALLS.has(expr[1]) or expr[1] == "Random": return false
	for arg: Array in expr[2]:
		if not read_only_expression(arg): return false
	return true

## The same explicit console operation recorded in the original. This is a
## test-only parser path, not an extension of the player's console whitelist.
func expression(s: Session, text: String, read_only := false) -> Variant:
	var p := ScriptParser.new()
	p._tokenize(text)
	var expr := p._expr()
	check(p.errors.is_empty() and p._i == p._t.size(), "parse recorded operation " + text)
	if not p.errors.is_empty() or p._i != p._t.size(): return null
	if read_only:
		var allowed := read_only_expression(expr)
		check(allowed, "read-only observation " + text)
		if not allowed: return null
	var vm := s.world.vm
	var unknown_before := vm.unknown_calls.duplicate()
	var result = vm._eval(expr, ScriptVM.Instance.new())
	# Unknown functions only emit engine warnings. Their return value can be
	# null even when a caller ignores it, so syntax/output checks cannot catch
	# an unsupported or misspelled recorded action. Check counts as well as
	# names, including a second call to an already unknown function.
	check(vm.unknown_calls == unknown_before, "recorded operation resolves " + text)
	return result

func observations(s: Session, probes: Dictionary) -> Dictionary:
	var out := {"money": s.state.money}
	for key: String in probes:
		if key.to_lower() == "money":
			check(false, "money is a reserved observation")
			continue
		out[key] = expression(s, String(probes[key]), true)
	return out

func snapshot(s: Session) -> Dictionary:
	var out := {}
	for k: String in s.state.vars:
		if k.begins_with("0:"):
			out[k.substr(2)] = float(s.state.vars[k])
	out["gtime"] = s.state.get_var(0, "gtime")
	return out

func unit_named(s: Session, name: String) -> GameUnit:
	# The VM resolves authored aliases as well as deployed party identities.
	# Map NPC metadata does not always store its script name in info.name.
	return s.world.vm._by_name(name)


## Talk to `who` and pick the topic whose var is `topic`: the click opens the
## list, the pick stages the walk, Space skips it, the phrases are clicked
## through to the end.
func talk(s: Session, g: Game, who: String, topic: String) -> void:
	var npc := unit_named(s, who)
	check(not s.party_units(0).is_empty(), "party exists for dialogue")
	if s.party_units(0).is_empty(): return
	var hero: GameUnit = s.party_units(0)[0]
	check(npc != null, "%s is in %s" % [who, s.zone_id])
	if npc == null: return
	g.issue({"t": "interact", "units": [hero.uid], "target": npc.uid})
	ticks(s, 2)
	var d: DialogPanel = g.hud._dialog
	var opts: Array = d._topics.get("options", [])
	var vars: Array = opts.map(func(o): return String(o["var"]).to_lower())
	var k := vars.find(topic.to_lower())
	check(d._mode == DialogPanel.TOPICS and k >= 0, "%s offers %s (%s)" % [who, topic, str(vars)])
	if k < 0: return
	d._on_topic(k)
	ticks(s, 2)
	var space := InputEventKey.new(); space.keycode = KEY_SPACE; space.pressed = true
	d._unhandled_input(space)
	ticks(s, 2)
	d._finish()
	var n := 0
	while (d.visible or not s.world.vm.briefings.active.is_empty()) and n < 600:
		ticks(s, 1); n += 1
	check(not d.visible, "the conversation with %s ends" % who)

## Order the first hero to use lever / object `nid` (its MOB id) as a click
## does, and run until the hero has used it.
func use(s: Session, g: Game, nid: int) -> void:
	check(not s.party_units(0).is_empty(), "party exists for lever use")
	if s.party_units(0).is_empty(): return
	var hero: GameUnit = s.party_units(0)[0]
	check(s.world.levers.has(nid), "lever %d is in %s" % [nid, s.zone_id])
	if not s.world.levers.has(nid): return
	var state := int(s.world.levers[nid].state)
	g.issue({"t": "use_lever", "units": [hero.uid], "target": nid})
	var n := 0
	while int(s.world.levers[nid].state) == state and n < 1200:
		ticks(s, 1); n += 1
		if n % 20 == 0: await get_tree().process_frame
	check(int(s.world.levers[nid].state) != state, "lever %d changes state (%d)" % [nid, state])
	await settle(s, g, 2.2)

## Teleport only to skip walking. Availability, deliberate exit click,
## confirmation and transfer all use the ordinary campaign routes.
func leave(s: Session, g: Game, id: int, destination: String) -> void:
	var ex: Dictionary = s.world.zone.get("exits", {}).get(id, {})
	check(ex.has("remove"), "recorded exit exists")
	if not ex.has("remove"): return
	var center: Vector2 = ex.remove.get_center()
	check(s.open_exit_at(center, 0) == id, "recorded return exit is usable")
	if s.open_exit_at(center, 0) != id: return
	for hero: GameUnit in s.party_units(0):
		hero.pos = center
		hero.resync_drawn()
	s._arm_exit(0, center, true, id)
	s._check_exits()
	check(MessageBox.is_up(g.hud._leave_box), "ordinary exit offers confirmation")
	s.apply_command({"t":"leave_exit", "exit":id}, 0)
	for i in 1800:
		await get_tree().process_frame
		if s.zone_id == destination and not s.loading_game: break
	check(s.zone_id == destination and not s.loading_game, "confirmed exit reaches " + destination)
	freeze(s)

## Let the zone run for `seconds` of game time, playing any conversation that
## starts (the original's arrival talks) through to its end, as the recording
## did in the original.
func settle(s: Session, g: Game, seconds: float) -> void:
	var d: DialogPanel = g.hud._dialog
	var n := int(seconds / GameUnit.TICK)
	for i in n:
		# Scripted LeaveToZone/redeployment yields while its map loads.
		# Loading time must not consume the recorded simulation wait.
		while s.loading_game: await get_tree().process_frame
		freeze(s)
		ticks(s, 1)
		if d.visible and d._mode != DialogPanel.TOPICS:
			d._finish()
		elif not s.world.vm.briefings._pending_dialog.is_empty():
			s.world.vm.briefings.skip_staging(0)
		if i % 20 == 0:
			await get_tree().process_frame


func perform(s: Session, g: Game, step: Dictionary) -> void:
	if step.has("talk"):
		await talk(s, g, String(step.talk), String(step.topic))
	elif step.has("use"):
		await use(s, g, int(step.use))
	elif step.has("script"):
		expression(s, String(step.script))
	elif step.has("wait"):
		await settle(s, g, float(step.wait))
	elif step.has("leave"):
		await leave(s, g, int(step.leave), String(step.destination))
	elif step.has("reload"):
		check(s.save_game("checkpoint-reload") == OK, "checkpoint saves before replay continuation")
		check(await s.load_game_shown("checkpoint-reload"), "checkpoint reloads before replay continuation")
		freeze(s)
	else:
		check(false, "unknown step %s" % JSON.stringify(step))


func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_exit":0},true)
	TutorialPanel.auto_show = false
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="): path = arg.trim_prefix("--checkpoint=")
	var cp = JSON.parse_string(FileAccess.get_file_as_string(path)) if path else null
	check(cp is Dictionary, "read checkpoint %s" % path)
	if not cp is Dictionary:
		get_tree().quit(2); return
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.set_physics_process(false)
	check(s.state.campaign_id == (CampaignProfile.ASTRAL if cp.get("campaign", "original") == "lost_in_astral" else CampaignProfile.ORIGINAL), "correct campaign data loaded")
	s.state.ensure_hero(0, s._hero_proto(0))
	var fixture: Dictionary = cp.get("fixture", {})
	# Archived parties are needed by chapter transfers and Kel's revival;
	# establish their before-state before the destination's Start script runs.
	for name: String in fixture.get("parties", {}):
		s.state.create_party(name)
		for row: Dictionary in fixture.parties[name]:
			s.state.add_party_unit(name, String(row.name), String(row.prototype))
	if fixture.has("active_party"):
		s.state.set_current_party(String(fixture.active_party))
	if fixture.has("party"):
		var name: String = fixture.get("party_name", "Checkpoint")
		s.state.create_party(name)
		for row: Dictionary in fixture.party:
			s.state.add_party_unit(name, String(row.name), String(row.prototype))
		s.state.set_current_party(name)
	for item: String in fixture.get("quest_items", []):
		s.state.quest_items[Session._quest_item_key(item)] = true
	if fixture.has("money"): s.state.money = int(fixture.money)
	for k: String in cp.vars_before:
		s.state.set_var(0, k, float(cp.vars_before[k]))
	await s.enter_zone(String(cp.zone), 1, false)
	freeze(s)
	# enter_zone restores the campaign clock from GS gtime. Apply an explicit
	# recorded clock fixture after that restore, before any setup operations.
	if fixture.has("world_time"): s.state.world_time = float(fixture.world_time)
	for command: String in fixture.get("setup", []): expression(s, command)
	for step: Dictionary in fixture.get("setup_steps", []): await perform(s, g, step)
	await settle(s, g, float(cp.get("settle", 2.2)))
	var entry := snapshot(s)
	var probes: Dictionary = cp.get("probes", {})
	var observed_entry := observations(s, probes)
	check(s.save_game("checkpoint-before") == OK, "retain rerunnable remake before save")
	for step: Dictionary in cp.steps: await perform(s, g, step)
	await settle(s, g, float(cp.get("after_settle", 2.0)))
	var observed_after := observations(s, probes)
	check(s.save_game("checkpoint-after") == OK, "retain rerunnable remake after save")
	print("CHECKPOINT_RESULT ", JSON.stringify({"entry": entry, "after": snapshot(s), "zone": s.zone_id,
		"observations_entry": observed_entry, "observations_after": observed_after, "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures == 0 else 1)
