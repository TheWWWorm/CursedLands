extends Node
class PoseGame extends Game:
	var issued: Dictionary
	func issue(cmd:Dictionary)->void: issued=cmd
class PoseHUD extends GameHUD:
	func _rebuild_party()->void: pass
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready()->void:
	GameData.options.merge({"volume_sfx":0,"volume_stream":0,"auto_graphics":0},true)
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false);w.zone={"type":"game"}
	var a:=w.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(5,5,0)})
	a.set_process(false);a.set_physics_process(false);a.controller=0;a._perceive_next=INF;a.ai_next=INF
	a.restore_gait(0);a._anim_lock=0;a.action="idle";a.max_mana=10000;a.mana=10000;a.stats.int=25.0;a.facing=0
	a.command({"type":"cast","spell":"healing{}","target":a})
	var casted:=false;var standing:=false
	for i in 120:
		w.time+=GameUnit.TICK;a._tick(GameUnit.TICK);a._draw_step(GameUnit.TICK);a.anim_flush();a.model.player.advance(GameUnit.TICK);a.model._process(0)
		if a.stance==GameUnit.STANCE_NONE:standing=true
		if a.action.begins_with("cast"):casted=true;break
	check(casted and a.stance==GameUnit.STANCE_KNEEL and not standing,"prone tactical caster rises to kneeling before casting")
	var replica_world:=GameWorld.new();add_child(replica_world);replica_world.authority=false;replica_world.set_process(false);replica_world.set_physics_process(false)
	var replica:=replica_world.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(1,1,0)})
	replica.set_process(false);replica.set_physics_process(false)
	a.facing=1.37;a.action="idle"
	var snapshot:=a.snapshot();replica.apply_snapshot(snapshot,true)
	check(replica.transform.origin.is_equal_approx(EISpace.pos(a.pos.x,a.pos.y,0)) and replica.transform.basis.is_equal_approx(Basis(Vector3.UP,replica.facing+GameUnit.MODEL_YAW_OFFSET)),"quiet snapshot immediately places saved facing and position")
	for gait in [2,0,1,2,0]:
		a.order={};a.orders.clear();a.action="idle";a._anim_lock=0;a.set_gait(gait);a._update_pose()
		var clip:=a.model._current
		print("TRANSITION ",gait," ",clip," at ",a.model.player.current_animation_position)
		check(a.model.player.current_animation_position<0.01,"posture transition starts at its first frame")
		for tick in 50:a.model.player.advance(GameUnit.TICK);a.model._process(0)
	# The actual HUD command must tolerate old packets already in flight.
	# They used to reverse a predicted cross clip into the destination pose.
	var session:=Session.new();session.is_host=false;session.world=replica_world
	var game:=PoseGame.new();game.session=session;game.world=replica_world;game.selected.assign([replica])
	var hud:=PoseHUD.new();hud.game=game
	for gait in [0,1,2]:
		a.restore_gait(2 if gait!=2 else 0);a.action="idle"
		var old:=a.snapshot();replica.apply_snapshot(old,true)
		var head:=replica.model.find_child("hd",true,false) as Node3D
		var before:=head.global_position.y
		hud.set_move_mode(["crawl","sneak","walk"][gait])
		check(game.issued.get("gait")==gait,"HUD sends requested posture to authority")
		replica.apply_snapshot(old);replica._update_pose()
		for frame in 5:replica.model.player.advance(1.0/60);replica.model._process(0)
		check(absf(head.global_position.y-before)<0.08,"in-flight old snapshot cannot flash the requested end pose")
		a.set_gait(gait);replica.apply_snapshot(a.snapshot());replica._update_pose()
		check(replica.model._current.begins_with("ucross") and absf(head.global_position.y-before)<0.08,"accepted posture starts its cross from the displayed pose")
		for frame in 150:replica.model.player.advance(1.0/60);replica.model._process(0)
		check(replica.model.pose_state==a.model.pose_state or replica.gait()==gait,"accepted posture completes")
	hud.free();game.free();session.world=null;session.free()
	w.queue_free();replica_world.queue_free()
	for i in 8:await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
