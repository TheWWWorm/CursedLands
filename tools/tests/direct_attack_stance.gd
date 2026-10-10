extends Node
## Real original hero clips, authoritative commands, and ordinary unit ticks.
## Empty floor/no enemies isolates repeated swing cadence from pathfinding.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"volume_sfx":0,"volume_stream":0,"auto_graphics":0},true)
	var w := GameWorld.new(); add_child(w)
	w.set_process(false); w.set_physics_process(false); w.zone = {"type":"game"}
	var a := GameUnit.new()
	check(a.setup(w,{"nid":1,"prototype":"Human Hero","position":Vector3(5,5,0)}),"original hero model and animation database load")
	w.add_child(a); w.set_unit(1,a); a.controller=0
	a.set_process(false); a.set_physics_process(false)
	a._perceive_next=INF; a.ai_next=INF; a.facing=0.0
	var s := Session.new(); s.world=w; s.state=CampaignState.new()
	s.apply_command({"t":"direct_control","leader":a.uid},0)
	# Use the actual command key, as DirectControl sends it.
	check(a.direct_controlled,"authority enables direct control")
	var starts: Array = []; var neutral_frames := 0; var cross_frames := 0
	var previous_hit := false; var first := false
	for tick in 600:
		if tick % 4 == 0:
			s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3.RIGHT},0)
		w.time += GameUnit.TICK
		a.tick(GameUnit.TICK)
		a._draw_step(GameUnit.TICK)
		a.model.player.advance(GameUnit.TICK)
		var hit := a._pending_hit.has("direction")
		if hit and not previous_hit:
			starts.append({"time":w.time,"cooldown":a._attack_cd,"lock":a._anim_lock,"clip":a.model._current})
			first=true
		if first and not a.alert: neutral_frames += 1
		if first and a.model.pose_state==EIUnitModel.ST_NEUTRAL: cross_frames += 1
		previous_hit=hit
	check(starts.size() >= 5,"repeated authoritative requests produce at least five real swings")
	check(neutral_frames == 0,"direct control keeps combat readiness between swings")
	check(cross_frames == 0,"real model does not return to neutral between swings")
	for i in range(1,starts.size()):
		var gap := float(starts[i].time)-float(starts[i-1].time)
		check(gap+0.0001 >= float(starts[i-1].cooldown),"swing %d respects weapon and animation cooldown"%i)
		check(gap <= float(starts[i-1].cooldown)+GameUnit.TICK*6.1,"swing %d adds no repeated stance delay"%i)
	check(int(a.snapshot()[6]) & (1<<8) != 0,"ready stance is replicated to clients")
	a.order={}; a.orders.clear(); a._pending_hit={}; a.action="idle"; a._anim_lock=0.0
	s.apply_command({"t":"direct_control","leader":-1},0)
	a._draw_step(GameUnit.TICK)
	check(not a.direct_controlled and not a.alert,"leaving direct control restores ordinary relaxed idle")
	a.alert=true; a.orders=[{"type":"attack"}]; a._draw_step(GameUnit.TICK)
	check(a.alert,"ordinary queued attack retains readiness")
	a.orders.clear(); a._draw_step(GameUnit.TICK)
	check(not a.alert,"ordinary idle still relaxes")
	FileAccess.open("user://direct-attack-stance.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"starts":starts,"neutral_frames":neutral_frames,"neutral_pose_frames":cross_frames},"\t"))
	s.world=null; s.free(); w.free()
	print("DIRECT_ATTACK_STANCE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
