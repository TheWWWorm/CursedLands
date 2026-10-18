extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	var g:=Game.new();g._sun=DirectionalLight3D.new();g.add_child(g._sun)
	g.world=GameWorld.new();g.add_child(g.world)
	g.direct=DirectControl.new();g.direct.game=g;g.add_child(g.direct)
	for mode in [1,2,3]:
		GameData.options.control_mode=mode
		for choice in [0,1,2]:
			GameData.options.selection_glow=choice
			check(g.selection_glow_enabled()==(choice!=1 if mode==1 else choice==2 and mode==2),"selection glow view/setting "+str([mode,choice]))
	g.sun_aim_mode=1;GameData.options.q_shadows=0
	var direction:=Vector3(0.5,-0.7,0.3).normalized()
	g._aim_sun(direction,true);var held:=g._sun.basis
	for i in 60:g._aim_sun(direction.rotated(Vector3.UP,deg_to_rad(i*.025)),false)
	check(g._sun.basis==held,"low shadows keep a stationary texel grid during slow sun motion")
	g._aim_sun(direction.rotated(Vector3.UP,deg_to_rad(25)),false)
	check(g._sun.basis!=held and g.sun_reaim_reason=="cap","low shadow drift remains bounded")
	GameData.options.q_shadows=2
	g._aim_sun(direction,false);held=g._sun.basis
	g._aim_sun(direction.rotated(Vector3.UP,0.01),false)
	check(g._sun.basis!=held,"higher quality keeps continuous sunlight")
	g.free()
	var run:=ArenaRun.new();run.auto_save=false;run.begin(3);run._recruit(5,0,0).deployed=true
	var battle:=ArenaPveMatch.new();battle.run=run;add_child(battle);battle._world_parent=self;battle.prepare();battle.set_process(false);battle.set_physics_process(false)
	var unit:GameUnit=battle.world.unit_rows()[0];battle.formation_motion.settle(battle.world)
	var fx:=ParticleFx.of(battle.world);fx.set_process(false)
	var centre: Vector3 = ParticleFx.ei(unit.global_position)+EIFigureGeometry.of(unit.model).centre
	var mouth:=fx.unit_point(unit,0)
	check(mouth.distance_to(centre)>0.15,"toad emission is at the mouth instead of body centre")
	var previous:=mouth-ParticleFx.ei(unit.global_position)
	unit.facing+=PI;unit.resync_drawn()
	mouth=fx.unit_point(unit,0)
	var rotated:=mouth-ParticleFx.ei(unit.global_position)
	check(Vector2(previous.x,previous.y).dot(Vector2(rotated.x,rotated.y))<0,"mouth emission follows the facing direction")
	var dummy:={"proto":{"light_radius":0.0}}
	fx._missile("acid_ray",mouth,null,mouth+Vector3(6,0,0),1.0,dummy)
	var missile:Dictionary=fx.missiles.back();fx._missile_tick(missile)
	check(absf(missile.pos.z-mouth.z)<0.01,"acid leaves low mouth without jumping to waist height")
	battle.queue_free();await get_tree().process_frame
	print("CAMPAIGN_PRESENTATION_FEEDBACK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
