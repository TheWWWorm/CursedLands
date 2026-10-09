extends Node
## Original Ingos scripts and actors, controlled 55-ms authority ticks.
## No script edits, fabricated animation clips, or scenery placement changes.
var checks := 0
var failures := 0
var rows := {}
const SEATS := {420812:"uspecial13",137765:"uspecial15",506671:"uspecial13"}

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)

func step(world: GameWorld) -> void:
	world._tick(GameUnit.TICK)
	for u: GameUnit in world.unit_rows():
		u._draw_step(0.0)
		if u.model and u.model.player:
			u.model.player.advance(GameUnit.TICK)
			u.model._process(GameUnit.TICK)

func _ready() -> void:
	seed(104031)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_websocket":0,
		"net_lan":0,"net_directory":0,"auto_graphics":0,"unit_fog":1},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.use_lmp_database(true)
	var character := MpCharacter.create(String(MpCharacter.faces()[0][0]))
	character.heroes[0].name="Seated pose probe"
	MpCharacter.finish(character,"","","")
	MpCharacter.save_file("1.mp",character); MpCharacter.select("1.mp")
	var session := Session.new(); add_child(session)
	var game := Game.new(); game.session=session; session.game=game; add_child(game)
	check(session.host(31061,2)==OK,"original multiplayer authority opens")
	check(session.new_lmp_game("bz2mpg"),"authored Ingos multiplayer base loads")
	session.set_physics_process(false); game.set_process(false)
	game.get_node("UnitFog").set_process(false); game.rig.set_process(false)
	var world:=session.world; world.set_process(false); world.set_physics_process(false)
	check(world.zone.mpr=="bz8k" and world.zone.mob=="bz8k-lmp" and world.zone.type=="brief","original Ingos base identity")
	for id: int in SEATS:
		var u: GameUnit=world.units.get(id)
		check(u!=null and u.controller<0 and u.model.template=="unhuma","authored seated NPC "+str(id))
		rows[str(id)]={"name":u.info.name,"position":str(u.pos),"initial_position":u.pos,
			"clip":SEATS[id],"started":false,"idle_frames":0,"idle_ready_frames":0,"starts":0,
			"restart_failures":0,"last_serial":-1,"events":[]}
	var other_idle := 0
	for frame in 600:
		step(world)
		for id: int in SEATS:
			var u: GameUnit=world.units[id]; var row: Dictionary=rows[str(id)]
			if u.action=="anim:"+String(SEATS[id]):
				row.started=true
				if u._action_serial!=row.last_serial:
					row.starts+=1
					if not u.model.player.is_playing() or u.model.player.current_animation_position>GameUnit.TICK+0.00001:
						row.restart_failures+=1
			if row.started and u.action=="idle": row.idle_frames+=1
			if row.started and u.is_idle(): row.idle_ready_frames+=1
			if u._action_serial!=row.last_serial:
				row.events.append({"frame":frame,"time":world.time,"action":u.action,"clip":u.model._current,
					"serial":u._action_serial,"lock":u._anim_lock,"playing":u.model.player.is_playing(),
					"animation_position":u.model.player.current_animation_position})
			row.last_serial=u._action_serial
		var other: GameUnit=world.units[960939]
		if frame>10 and other.action=="idle": other_idle+=1
	for id: int in SEATS:
		var u: GameUnit=world.units[id]; var row: Dictionary=rows[str(id)]
		check(row.starts>=3,"authored script repeats seated clip "+str(id))
		check(row.idle_frames==0,"no standing idle inserted between seated repeats "+str(id))
		check(row.idle_ready_frames>0,"seated hold preserves command completion/readiness "+str(id))
		check(row.restart_failures==0,"each new seated event restarts its one-shot "+str(id))
		check(u.pos==row.initial_position,"authored seat placement unchanged "+str(id))
		row.erase("initial_position")
	check(other_idle>0,"unrelated PoorMan uspecial20 retains ordinary one-shot idle completion")
	# Stop further script injection only after the unchanged authored run.
	# Existing commands finish normally; ordinary orders must release each hold.
	world.vm.instances.clear()
	for id: int in SEATS: (world.units[id] as GameUnit).command({"type":"wait","t":0.2})
	for frame in 240: step(world)
	for id: int in SEATS:
		var u: GameUnit=world.units[id]
		check(u.action=="idle" and u.is_idle() and u._story_clip.is_empty(),"ordinary wait replaces seated pose "+str(id))
	var report:={"checks":checks,"failures":failures,"zone":world.zone,"frames":600,"tick":GameUnit.TICK,
		"seats":rows,"other_one_shot_idle_frames":other_idle,
		"scope":"Authored authority/script and animation timeline regression, headless. Final interruption controls stop script injection after the unchanged33-second sequence. Not rendered or network acceptance."}
	FileAccess.open("user://lmp-seated-pose.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	var peer:=session.multiplayer.multiplayer_peer
	session.online=false; session.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new(); peer.close()
	game.free(); session.free(); TexUpscale.shutdown(); UnitWounds.shutdown()
	print("LMP_SEATED_POSE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
