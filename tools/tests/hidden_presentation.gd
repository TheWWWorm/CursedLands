extends Node
## Actual replica rig, animation clocks, snapshots and observation boundaries.
var checks := 0
var failures := 0

class GroundWorld extends GameWorld:
	func ground_at(_x:float,_y:float)->float:
		return 3.0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func sleep_unit(w:GameWorld,u:GameUnit)->void:
	u.anim_watched=false
	u.fogged=true
	u.hide()
	u._presentation_observed_until=0.0
	u.set_process(true)
	w._presentation_clock+=0.016
	w._presentation_frame=Engine.get_process_frames()
	u._process(0.016)
	check(u._presentation_sleeping,"hidden unheard replica sleeps")
	check(not u.is_processing() and not u.model.is_processing(),"frame callbacks are suspended together")

func _ready()->void:
	var w:=GroundWorld.new()
	w.authority=false
	add_child(w)
	w.set_process(false) # the fixture advances the scheduler explicitly
	var u:=GameUnit.new()
	check(u.setup(w,{"prototype":"zone1 JunEvil","template":"unmocu","nid":666666,"player":6}),"actual Terror rig loads")
	w.add_child(u)
	w.set_unit(u.uid,u)
	u.pos=Vector2(200,200)
	u.net_view.got(u.pos,true,u.facing)
	u._sync_transform(0.0)
	var sound:=GameSound.new()
	var previous:=GameSound.instance
	sound._world=w
	sound.mixer=SoundMixer.new()
	sound.mixer.listener=Vector3.ZERO
	GameSound.instance=sound
	sleep_unit(w,u)
	for i in 2*GameWorld.HIDDEN_PRESENTATION_BUCKETS:w._step_hidden_presentations(GameWorld.HIDDEN_PRESENTATION_SLICE)
	check(u._game_clock>0.0 and w._presentation_clock-u._game_clock<=GameWorld.HIDDEN_PRESENTATION_STEP+0.001,"sleep retains bounded animation updates")
	u.anim_watched=true
	check(not u._presentation_sleeping and u.is_processing() and u.model.is_processing(),"inspection wakes both callbacks immediately")
	check(is_equal_approx(u._game_clock,w._presentation_clock),"wake accounts for elapsed time once")
	check(u.global_position==Vector3(200,3,-200),"wake restores current ground placement")
	sleep_unit(w,u)
	w._presentation_clock+=0.08
	u.pos=Vector2(230,210)
	u.facing=1.2
	u.show()
	check(not u._presentation_sleeping,"visibility wakes in the same frame")
	check(u.global_position==Vector3(230,3,-210),"hidden teleport is placed before first visible frame")
	check(is_equal_approx(u._game_clock,w._presentation_clock),"show retains elapsed animation time")
	# Wake/re-sleep before an old queue entry is visited must not duplicate work.
	for i in 8:
		sleep_unit(w,u)
		u.wake_presentation()
	sleep_unit(w,u)
	for i in 2*GameWorld.HIDDEN_PRESENTATION_BUCKETS:w._step_hidden_presentations(GameWorld.HIDDEN_PRESENTATION_SLICE)
	check(w._hidden_pending==1,"obsolete wake generations leave exactly one queue entry")
	# Active figures can process before the world (priority -1). Entering
	# sleep must not count this frame twice when the world advances later.
	u.anim_watched=true
	var before_early_sleep:=u._game_clock
	u.anim_watched=false
	w._presentation_frame=Engine.get_process_frames()-1
	u._process(0.016)
	w._step_hidden_presentations(0.016)
	u.anim_watched=true
	check(is_equal_approx(u._game_clock,before_early_sleep+0.016),"actor-before-world sleep counts its first frame once")
	sleep_unit(w,u)
	# A new action receives only time after its packet, not the previous clip's debt.
	w._presentation_clock+=0.07
	var packet:=u.snapshot()
	packet[4]="attack"
	packet[14]=10
	u.apply_snapshot(packet)
	check(u._presentation_sleeping,"fogged replica stays asleep while receiving its new action")
	check(is_equal_approx(u._presentation_stamp,w._presentation_clock),"old animation debt consumed before snapshot")
	check(u.model.player.current_animation_position<0.001,"new action begins at its own start")
	w._presentation_clock+=0.04
	u.anim_watched=true
	check(is_equal_approx(u._game_clock,w._presentation_clock),"new action wake consumes only its new interval")
	check(u.model.player.current_animation_position<0.1,"old clip debt never advances the new action")
	sleep_unit(w,u)
	var fx:=ParticleFx.new()
	var emitter:=FxEmitter.new()
	var point:=fx.carrier_point(emitter,u)
	check(not u._presentation_sleeping and point==ParticleFx.ei(u.global_position),"particle carrier query wakes and reads current placement")
	check(not u._can_sleep_presentation(),"observed effect carrier stays active across ticks")
	fx.free()
	sleep_unit(w,u)
	sound.mixer.listener=Vector3(u.pos.x,u.pos.y,2)
	var voices:=UnitSounds.new(sound.mixer,w)
	voices.tick()
	check(not u._presentation_sleeping,"listener reaching hidden actor wakes before sound sampling")
	sound.mixer.listener=Vector3.ZERO
	sleep_unit(w,u)
	w.authority=true
	w._step_hidden_presentations(0.0)
	check(not u._presentation_sleeping,"authority transition restores normal actor callbacks")
	check(not u._can_sleep_presentation(),"authoritative actors never enter presentation sleep")
	w.authority=false
	sleep_unit(w,u)
	var before_pause:=u._game_clock
	var pending_time:=w._presentation_clock-u._presentation_stamp
	u.process_mode=Node.PROCESS_MODE_DISABLED
	for i in 2*GameWorld.HIDDEN_PRESENTATION_BUCKETS:w._step_hidden_presentations(GameWorld.HIDDEN_PRESENTATION_SLICE)
	check(is_equal_approx(u._game_clock,before_pause),"disabled actor is not advanced by its active world")
	u.process_mode=Node.PROCESS_MODE_INHERIT
	u.anim_watched=true
	check(is_equal_approx(u._game_clock,before_pause+pending_time),"resume consumes only the pending active interval")
	# An independently disabled model must not receive its cycle callback.
	u.model._cycle_pos=123.0
	u.model.process_mode=Node.PROCESS_MODE_DISABLED
	sleep_unit(w,u)
	for i in GameWorld.HIDDEN_PRESENTATION_BUCKETS:w._step_hidden_presentations(GameWorld.HIDDEN_PRESENTATION_SLICE)
	check(is_equal_approx(u.model._cycle_pos,123.0),"model callback respects its own process mode")
	u.model.process_mode=Node.PROCESS_MODE_INHERIT
	u.anim_watched=true
	sleep_unit(w,u)
	u.world=null
	check(not u._presentation_sleeping and u.is_processing() and u.model.is_processing(),"world reassignment restores actor and model callbacks")
	u.world=w
	# Current movement-speed packets let hidden figures keep time without
	# placing their model or applying wounds until an observer needs them.
	u._remote_move_speed=true
	var before_hidden_transform:=u.transform
	u.pos=Vector2(270,260)
	u.net_view.got(u.pos,true,u.facing)
	u._wounds_dirty=true
	sleep_unit(w,u)
	for i in GameWorld.HIDDEN_PRESENTATION_BUCKETS:w._step_hidden_presentations(GameWorld.HIDDEN_PRESENTATION_SLICE)
	check(u.transform==before_hidden_transform,"hidden remote-speed figure defers placement")
	check(u._wounds_dirty,"hidden wounds remain pending")
	u.anim_watched=true
	check(u.global_position==Vector3(270,3,-260),"observation places the deferred figure immediately")
	check(not u._wounds_dirty,"observation applies pending wounds")
	sleep_unit(w,u)
	u.free()
	w._step_hidden_presentations(10.0)
	check(w._hidden_pending==0,"freed actors are removed during bounded catch-up")
	GameSound.instance=previous
	sound.mixer.free()
	sound.free()
	w.free()
	print("HIDDEN_PRESENTATION checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
