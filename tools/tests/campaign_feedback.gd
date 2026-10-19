extends "single_player_rules.gd"
var session:Session
var game:Game
func frames(count:=4) -> void:
	for i in count:await get_tree().process_frame
func hold() -> void:
	session.set_physics_process(false);session.world.set_physics_process(false)
	session.world.vm.instances.clear();session.world.vm.briefings._check=INF
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	# Exhausting the whole party is a defeat, even when a companion dies last.
	for online in [false,true]:
		var s:=ProbeSession.new();var w:=GameWorld.new();var lh:=LocalHost.new()
		s.local_host=lh;lh.session=s;s.world=w;w.session=s;s.online=online
		var main:=hero(w,1);var merc:=hero(w,2,true)
		main.dead=true
		check(not s.check_party_defeat(),"living companion can revive the hero")
		merc.dead=true
		check(s.check_party_defeat()==not online,"last companion triggers solo defeat only")
		check(s.events.any(func(e):return e.t=="game_over")==not online,"defeat offers load prompt")
		w.units={};main.free();merc.free();w.free();lh.free();s.free()
	session=Session.new();add_child(session);game=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	session._enter_zone("gz15h",1,false);hold()
	for speed in [0,1]:
		for paused in [false,true]:
			game.set_speed(speed+1);get_tree().paused=paused
			var slot:="feedback-clock-%d-%s"%[speed,paused]
			check(session.save_game(slot)==OK,"save clock state "+slot)
			var state:=CampaignState.load_from(SaveInfo.path(slot))
			check(state.play_clock=={"speed":speed,"paused":paused},"save contains exact clock "+slot)
			get_tree().paused=false;game.speed=1-speed;Engine.time_scale=1
			check(session.load_game(slot),"load clock state "+slot);hold()
			check(get_tree().paused==paused and game.speed==speed and is_equal_approx(Engine.time_scale,55.0/27.0 if speed else 1.0),"clock restored "+slot)
	get_tree().paused=false;game.speed=1;Engine.time_scale=55.0/27.0
	game.hud._pause_before=false;get_tree().paused=true
	check(session.saved_play_clock()=={"speed":1,"paused":false},"menu pause is excluded from save")
	game.hud._pause_before=null;get_tree().paused=false
	session.restore_play_clock({})
	check(game.speed==0 and not get_tree().paused,"old saves default to normal unpaused play")
	check(session.suslanger_revisit_options("gz15h_gz16h").is_empty(),"no return shortcut before desert reached")
	for id in ["gz15h","gz16h","gz17h"]:
		session.state.set_var(0,"z."+id,2)
		await session.enter_zone(id,1,false);hold()
		session.state.set_var(0,"feedback."+id,7)
	session.state.current_party="";session.state.del_var(0,"i.nocamp")
	session.world.zone.erase("cage")
	var options:=session.suslanger_revisit_options("gz17h_bz14h")
	check(options.map(func(o):return o.zone)==["gz15h","gz16h"],"completed canyon and cave offered from desert")
	for id in ["gz15h","gz16h"]:
		session.leave_zone("gz17h_bz14h",1)
		session._travel(id,1);await frames(8);hold()
		check(session.zone_id==id,"travel reaches "+id)
		check(session.state.get_var(0,"feedback."+id)==7,"revisit retains quest state "+id)
		check(session.suslanger_revisit_options("gz15h_gz16h").any(func(o):return o.zone=="gz17h"),"old map offers route back to desert")
		session.leave_zone("gz15h_gz16h",1);session._travel("gz17h",1);await frames(8);hold()
		check(session.zone_id=="gz17h","return reaches desert")
	session.state.current_party="HeroAlone"
	check(session.suslanger_revisit_options("gz17h_bz14h").is_empty(),"story party cannot bypass its sequence")
	game.queue_free();session.queue_free();await frames();Engine.time_scale=1;get_tree().paused=false
	print("CAMPAIGN_FEEDBACK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
