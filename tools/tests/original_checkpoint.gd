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
	for i in n: s.world._tick(GameUnit.TICK)

func snapshot(s: Session) -> Dictionary:
	var out := {}
	for k: String in s.state.vars:
		if k.begins_with("0:"):
			out[k.substr(2)] = float(s.state.vars[k])
	out["gtime"] = s.state.get_var(0, "gtime")
	return out

func unit_named(s: Session, name: String) -> GameUnit:
	for u: GameUnit in s.world.unit_rows():
		if String(u.info.get("name", "")).to_lower() == name.to_lower(): return u
	return null

## Talk to `who` and pick the topic whose var is `topic`: the click opens the
## list, the pick stages the walk, Space skips it, the phrases are clicked
## through to the end.
func talk(s: Session, g: Game, who: String, topic: String) -> void:
	var npc := unit_named(s, who)
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
	var hero: GameUnit = s.party_units(0)[0]
	check(s.world.levers.has(nid), "lever %d is in %s" % [nid, s.zone_id])
	if not s.world.levers.has(nid): return
	var state := int(s.world.levers[nid].state)
	g.issue({"t": "use_lever", "units": [hero.uid], "target": nid})
	var n := 0
	while hero.has_meta("interact") and n < 1200:
		ticks(s, 1); n += 1
		if n % 20 == 0: await get_tree().process_frame
	check(int(s.world.levers[nid].state) != state, "lever %d changes state (%d)" % [nid, state])
	await settle(s, g, 2.2)

## Let the zone run for `seconds` of game time, playing any conversation that
## starts (the original's arrival talks) through to its end, as the recording
## did in the original.
func settle(s: Session, g: Game, seconds: float) -> void:
	var d: DialogPanel = g.hud._dialog
	var n := int(seconds / GameUnit.TICK)
	for i in n:
		ticks(s, 1)
		if d.visible and d._mode != DialogPanel.TOPICS:
			d._finish()
		elif not s.world.vm.briefings._pending_dialog.is_empty():
			s.world.vm.briefings.skip_staging(0)
		if i % 20 == 0:
			await get_tree().process_frame


func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="): path = arg.trim_prefix("--checkpoint=")
	var cp = JSON.parse_string(FileAccess.get_file_as_string(path)) if path else null
	check(cp is Dictionary, "read checkpoint %s" % path)
	if not cp is Dictionary:
		get_tree().quit(2); return
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	for k: String in cp.vars_before:
		s.state.set_var(0, k, float(cp.vars_before[k]))
	await s.enter_zone(String(cp.zone), 1, false)
	await settle(s, g, float(cp.get("settle", 2.2)))
	var entry := snapshot(s)
	for step: Dictionary in cp.steps:
		if step.has("talk"):
			await talk(s, g, String(step.talk), String(step.topic))
		elif step.has("use"):
			await use(s, g, int(step.use))
		else:
			check(false, "unknown step %s" % JSON.stringify(step))
	ticks(s, 20)
	print("CHECKPOINT_RESULT ", JSON.stringify({"entry": entry, "after": snapshot(s), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures == 0 else 1)
