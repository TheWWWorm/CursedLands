extends Node
var s:Session
var g:Game
var checks:=0
var failures:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr('FAIL ',label)
	else:print('PASS ',label)
func until(test:Callable,seconds:=20.0)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await get_tree().process_frame
	return bool(test.call())
func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()
func run()->void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({'autosave':0,'show_tutorial':0,'auto_graphics':0,'control_mode':3,'net_lan':0,'net_upnp':0,'net_directory':0,'confine_mouse':0},true)
	# Build a disposable ordinary checkpoint before any casts.
	var state:=CampaignState.new();state.ensure_hero(0,'Human Hero');state.current_zone='gz1g'
	var h:Dictionary=state.heroes[0][0];h.spells=['litnwall{}'];h.skills={'elemental':100,'fire':100,'astral':100};h.int=40;h.exp=100000
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(state.save(SaveInfo.path('quick'))==OK,'checkpoint before wall saves')
	s=Session.new();get_parent().add_child(s);g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,'real solo simulation worker starts')
	if failures:await finish();return
	check(await s.load_game_shown('quick'),'ordinary solo load succeeds')
	check(await until(func():return s.world!=null and not s.loading_game and not s._remote_loading),'frontend receives completed world')
	if failures:await finish();return
	g.hud._tutorial.close();g.hud._menu.hide();g.hud._esc_open=false;get_tree().paused=false
	var u:GameUnit=s.party_units(0)[0]
	var at:=u.pos+Vector2(2,0)
	s.submit({'t':'cast','unit':u.uid,'spell':'litnwall{}','x':at.x,'y':at.y})
	check(await until(func():return is_instance_valid(s.world) and ParticleFx.of(s.world).bolts.size()>0,12),'authority cast reaches frontend lightning geometry')
	if failures:await finish();return
	var old_world: WeakRef = weakref(s.world);var old_bolt: WeakRef = weakref(ParticleFx.of(s.world).bolts[0].node)
	var serial:=s._load_serial
	# The field F9 action delegates to this same load_game_shown quick slot.
	g._key_action('quickload')
	check(await until(func():return s._load_serial>serial and s.world!=old_world.get_ref() and not s.loading_game and not s._remote_loading),'F9 replaces the solo frontend world')
	for i in 20:await get_tree().process_frame
	check(old_world.get_ref()==null,'retired world is freed after quickload')
	check(old_bolt.get_ref()==null,'retired lightning geometry is freed after quickload')
	check(ParticleFx.of(s.world).bolts.is_empty(),'earlier quicksave has no later lightning geometry')
	await finish()
func finish()->void:
	# Quiesce input before stopping the separate authority, just as the real
	# return-to-menu path does. Otherwise its final steering tick targets a
	# disconnected peer and turns a successful load check into teardown noise.
	if is_instance_valid(g):
		g.set_process(false);g.set_physics_process(false);g.set_process_unhandled_input(false)
		if is_instance_valid(g.direct):
			g.direct.set_process(false);g.direct._control_id=-2;g.direct._move_id=-1
		var pad:=g.get_node_or_null('PadField')
		if pad:pad.set_process(false);pad.set_physics_process(false)
	if is_instance_valid(s):s.set_process(false);s.set_physics_process(false)
	if is_instance_valid(s):await s.local_host.stop()
	if is_instance_valid(g):g.queue_free()
	if is_instance_valid(s):s.queue_free()
	for i in 10:await get_tree().process_frame
	TexUpscale.shutdown()
	FileAccess.open('user://solo-wall-quickload.json',FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures}))
	print('SOLO_WALL_QUICKLOAD ',checks,' checks ',failures)
	get_tree().quit(1 if failures else 0)
