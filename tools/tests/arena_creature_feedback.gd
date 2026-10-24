extends Node
## Scaled Trials sockets, elemental charge-up, and Horror's hovering death rig.
var checks := 0
var failures: Array[String] = []
var serial := 800000
var world: GameWorld

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ", message)

func fighter(id: String) -> GameUnit:
	serial += 1
	var actor := GameUnit.new()
	check(actor.setup(world,{"prototype":id,"nid":serial,"player":1}),"loads "+id)
	world.add_child(actor); world.set_unit(actor.uid,actor)
	actor.pos=Vector2(32,32); actor.resync_drawn()
	ArenaPveMatch._fit_figure(actor)
	actor.model.set_process(false)
	actor.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return actor

func _ready() -> void:
	world=GameWorld.new(); world.process_mode=Node.PROCESS_MODE_DISABLED
	world.zone={"type":"arena"}; add_child(world)
	var fx:=ParticleFx.of(world); fx.set_process(false)
	for id: String in ["DragonBrownM16","DragonGreenM12","DragonBlueM14","ToadM1","BatDarkM12","AncientCurseM25"]:
		var actor:=fighter(id)
		var clip:=actor._cast_clip()
		actor.model.play(clip,0,true)
		var release:=float(maxi(1,GameUnit._clip_hit_frame(actor.model.template,clip)))/EIAnim.FPS
		actor.model.player.seek(release,true); actor.model.flush_pending_pose()
		var body:=fx.unit_point(actor,0)
		for spell: String in ["fireball","lightning","acid_ray"]:
			fx.cast_fx({"uid":actor.uid,"spell":spell,"secs":1.0})
			var charge: ParticleFx.Effect=fx.effects.back()
			check(charge.e.wp.distance_to(fx.cast_point(actor))<0.001,id+" "+spell+" charge-up shares the animated source")
			actor.model.player.seek(0,true); actor.model.flush_pending_pose()
			charge.e.update_pre()
			check(charge.e.wp.distance_to(fx.cast_point(actor))<0.001,id+" "+spell+" charge-up follows animation")
			actor.model.player.seek(release,true); actor.model.flush_pending_pose()
		check(body.distance_to(fx.unit_point(actor,0))<0.001,id+" incoming effects retain their body anchor")
		if id.begins_with("Dragon"):
			check(fx.cast_point(actor).distance_to(body)>0.8,id+" fitted snout remains outside its body")
			fx.spell_cast({"a":actor.uid,"spell":"fireball","x":38.0,"y":32.0})
			check(fx._pending_fireballs.back().pos.distance_to(fx.cast_point(actor))<0.001,id+" released fireball starts at the same fitted mouth")
		world.erase_unit(actor.uid); actor.free()
	var battle:=ArenaPveMatch.new(); battle.drives_clock=false; add_child(battle)
	battle.set_process(false); battle.set_physics_process(false); battle.world=world
	var horror:=fighter("AncientCurseM25")
	horror.hp=0; horror.die()
	var position_before:=horror.pos
	var body_before:=ArenaOnlineGame.exact_body(horror)
	battle.phase=ArenaMatch.Phase.PAUSED
	var initial:=horror.model.position.y
	var floating_center := ArenaPveMatch._corpse_bounds(horror).get_center().y
	var living_basis := horror.model.basis
	battle._process(0.5)
	check(horror.model.position.y==initial,"paused combat holds the corpse's fall")
	battle.phase=ArenaMatch.Phase.FIGHT
	for i in 20:
		horror._anim_acc+=GameUnit.TICK; horror.anim_flush()
		battle._update_corpse_falls(GameUnit.TICK)
	check(ArenaPveMatch._corpse_bounds(horror).get_center().y<floating_center-0.5,"Horror falls out of its authored hovering death cycle")
	check(absf(ArenaPveMatch._corpse_clearance(horror))<0.001,"Horror's visible corpse touches the ground")
	check(horror.is_frozen(),"landed Horror holds its final death pose")
	check(absf(horror.model.basis.y.normalized().dot(living_basis.y.normalized())) < 0.001,"landed Horror lies flat instead of freezing upright")
	check(horror.pos==position_before and ArenaOnlineGame.exact_body(horror)==body_before,"presentation fall preserves authoritative placement and health")
	battle.phase=ArenaMatch.Phase.FINISHED; battle._process(1.0)
	check(absf(ArenaPveMatch._corpse_clearance(horror))<0.001,"finished combat keeps the corpse on the snow")
	# Late/full board records already freeze their final pose. Scouting must
	# ground them immediately, independently of the board's display offset.
	var snap:=horror.snapshot()
	var corpse:=fighter("AncientCurseM25"); corpse.apply_snapshot(snap,true)
	var living_transform := corpse.model.transform
	world.position=Vector3(64,3,-64)
	battle._update_corpse_falls(0)
	check(absf(ArenaPveMatch._corpse_clearance(corpse))<0.001,"quiet scouted corpse grounds immediately on an offset board")
	var online:=ArenaOnlineMatch.new(); add_child(online); online.set_process(false); online.world=world
	corpse.model.transform=living_transform
	online.phase=ArenaMatch.Phase.FINISHED; online._process(0)
	check(absf(ArenaPveMatch._corpse_clearance(corpse))<0.001,"online replica dispatch grounds a finished scouted corpse")
	corpse.revive(); battle._update_corpse_falls(0); online._update_corpse_falls(0)
	check(is_zero_approx(corpse.model.position.y) and not corpse.is_frozen(),"revival restores the figure's living transform and playback")
	check(corpse.model.transform.is_equal_approx(living_transform),"revival restores the living orientation as well as height")
	world.erase_unit(corpse.uid); corpse.free()
	online.world=null; online.queue_free()
	battle.world=null; battle.queue_free(); world.queue_free(); await get_tree().process_frame
	print("ARENA_CREATURE_FEEDBACK ",checks," checks; failures=",JSON.stringify(failures))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
