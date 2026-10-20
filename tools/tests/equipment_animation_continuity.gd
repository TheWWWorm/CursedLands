extends Node
## Original loaded rigs: redress/reshape, dialogue, locomotion and dead bodies.
## Verifies the actual mixer, clock and pose, not a duplicate animation model.
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func frames(n:=3) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0},true)
	var world := GameWorld.new(); add_child(world)
	world.set_process(false); world.set_physics_process(false)
	var unit := world.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(1,1,0),
		"complexion":Vector3(0,.5,.8),"armors":PackedStringArray(),"weapons":PackedStringArray()})
	check(unit!=null and unit.model.player!=null,"original hero rig loads")
	if unit==null: get_tree().quit(1); return
	unit.set_process(false); unit.set_physics_process(false)
	var animation_rng := RandomNumberGenerator.new(); animation_rng.seed=20261020
	unit.model.animation_rng=animation_rng
	var gear := PackedStringArray(["battle axe.adamantium"])
	var armor := PackedStringArray(["hadagan high2 plate.adamantium"])
	check(Items.info(gear[0]).table=="weapons" and Items.info(gear[0]).row.type=="axe","equipment fixture resolves to a real original axe")
	check(Items.info(armor[0]).table=="armors","armor fixture resolves to original equipment")
	for action in ["idle","walk","run","attack","hit","cast","dialogue"]:
		unit.action=action if action!="dialogue" else "idle"
		unit.model.end_dialogue()
		if action=="dialogue": unit.model.begin_dialogue(true,1)
		elif action=="cast": unit.model.act("cast")
		else: unit.model.act(action,1,0.0)
		unit.model.player.advance(.17)
		var player := unit.model.player
		var clip := unit.model._current
		var at := player.current_animation_position
		var old_pose := unit.model.pose_state
		var random_state := animation_rng.state
		unit.set_equipment(armor,gear)
		check(unit.model.animation_rng==animation_rng and animation_rng.state==random_state,action+" redress preserves the seeded animation stream")
		check(unit.model.player==player,action+" redress retains the animation player")
		check(unit.model._current==clip and is_equal_approx(unit.model.player.current_animation_position,at),action+" redress retains clip and time")
		check(unit.model.pose_state==old_pose,action+" redress retains posture")
		check(unit.model.weapon_type=="axe",action+" new equipment is actually applied: "+unit.model.weapon_type)
		if action=="dialogue":
			check(unit.model._dialogue_active and unit.model._dialogue_clip==clip,"redress preserves the speaking special")
		var model := unit.model
		unit.set_equipment(armor,gear)
		check(unit.model==model and unit.model.player==player,action+" unchanged equipment does not rebuild the rig")
		unit.set_equipment(PackedStringArray(),PackedStringArray())
		check(unit.model._current==clip and unit.model.player==player,action+" removing equipment preserves animation")
	# A changed body build may require a new height-dependent animation
	# library, but must not force an idle action or restart the clip.
	unit.model.end_dialogue(); unit.action="run"; unit.model.act("run",1,0.0)
	unit.model.player.advance(.2)
	var before := unit.model.player.current_animation_position
	var clip := unit.model._current
	unit.info.complexion=Vector3(.1,.6,.7)
	unit.set_equipment(PackedStringArray(),PackedStringArray())
	check(unit.model._current==clip and is_equal_approx(unit.model.player.current_animation_position,before),"stat-driven complexion rebuild retains clip and phase")
	unit.dead=true; unit.action="death"; unit.model.act("death",1,0.0)
	unit.model.player.advance(unit.model.player.current_animation_length); unit.model.player.pause()
	before=unit.model.player.current_animation_position; clip=unit.model._current
	unit.set_equipment(PackedStringArray(),gear)
	check(unit.model._current==clip and is_equal_approx(unit.model.player.current_animation_position,before),"redressing a corpse retains the death pose")
	check(not unit.model.player.is_playing(),"redressing a corpse does not restart death")
	world.free(); await frames()
	print("EQUIPMENT_ANIMATION_CONTINUITY ",JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
