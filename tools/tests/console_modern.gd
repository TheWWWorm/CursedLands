extends Node
## Exercise the real editor and live campaign; completion must never execute.
var checks:=0
var failures:=[]
var s:Session
var g:Game
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func command(line:String)->PackedStringArray:return ConsoleCommands.execute(s,line)
func key(code:Key,ctrl:bool=false):
	var e:=InputEventKey.new();e.keycode=code;e.pressed=true;e.ctrl_pressed=ctrl
	DeveloperConsole._input(e)
func completion(text:String,caret:int,name:String)->Dictionary:
	for row:Dictionary in ConsoleCatalog.candidates(text,caret,s):
		if row.text==name:return row
	return {}
func _ready():
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.resolution=maxi(1,GameData.resolutions().find(Vector2i(800,600)))
	GameData._apply_window()
	s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	var u:GameUnit=s.party_units(0)[0];var c:=DeveloperConsole
	c.run("help heal");check(not c.unlocked and "\n".join(c.lines).contains("heal"),"help is discoverable before unlock")
	c.run("thingamabob")
	check(command("status").size()==4,"status supplies build, clocks and authority")
	check(command("party")[0].contains(u.display_name),"party uses display names")
	check(command("inspect hero").size()==2,"inspect supplies live state")
	check(ConsoleCommands.execute(s,"inspect selected",0,[u.uid]).size()==2,"selected IDs resolve on host")
	check(ConsoleCommands.execute(s,"inspect selected",0,["bad",{},null]).size()==1,"invalid selection is bounded and rejected")
	u.take_damage(1.0,null);u.mana=0
	check(u.hp<u.max_hp and u.mana==0,"healing test begins with real damage")
	command("heal hero");check(is_equal_approx(u.hp,u.max_hp) and u.mana==u.max_mana,"heal restores actual body parts and stamina")
	command("god on");check(u.god_mode(),"god alias enables the qualified basic mode")
	command("god off");check(not u.god_mode(),"god alias disables mode")
	command("time 12 freeze");check(s.world.vm.time_fixed and s.state.world_time==12,"freeze uses scene clock")
	command("time 19 run");check(not s.world.vm.time_fixed and s.state.world_time==19,"resume uses scene clock")
	for invalid:String in ["time 24","time -1","time 1e100","time 12 nonsense","god 2","god on extra","teleport -1 2","teleport 1e100 2","teleport 1 2 party","teleport 1 2 missing","heal missing","travel missing","travel gz1g -1","travel gz1g 1.5"]:
		var pos:=u.pos;var hp:=u.hp
		check(not command(invalid).is_empty() and u.pos==pos and u.hp==hp and s.state.world_time==19 and not u.god_mode(),"invalid shorthand leaves state unchanged: "+invalid)
	var p:=s.world.nav.nearest_walkable_for(u,u.pos+Vector2(3,0),3,u.move_class())
	command("teleport %.5f %.5f hero"%[p.x,p.y])
	check(u.pos.distance_to(p)<0.1 and u.path.is_empty(),"teleport moves the live unit and clears its route")
	check(u._occ_cell==s.world.nav.cell(u.pos),"teleport re-registers navigation occupancy")
	check(ConsoleTools.zone_rows(s,"gz1g").size()==1,"zone search filters installed campaign maps")
	for line:String in ["heal hero","god on","time 8 freeze","teleport 0 0","travel gz1g"]:
		var pos:=u.pos
		var result:=ConsoleCommands.execute(s,line,1)
		check(result==PackedStringArray([RemakeText.t("Only the host can change the campaign through the console.")]) and u.pos==pos and not u.god_mode() and s.state.world_time==19,"guest denied: "+line)
	s.loading_game=true;check(command("god on").size()==1 and not u.god_mode(),"loading guard applies to new commands");s.loading_game=false
	s.state.set_var(0,"console_probe",42)
	var row:=completion("he",2,"heal");check(not row.is_empty() and row.insert=="heal ","root completion inserts command and argument space")
	row=completion("give 0 mo 7",9,"money");check(not row.is_empty() and "give 0 mo 7".substr(row.end)==" 7","completion preserves suffix arguments")
	row=completion("getvar 0 console_",17,"console_probe");check(not row.is_empty() and row.help.contains("42"),"variable completion has live values")
	row=completion('@GSSetVar(0,"console_")',20,"console_probe");check(not row.is_empty() and row.start==13,"quoted variable completion preserves quotes")
	row=completion("#HP(GetObj)",10,"GetObjectByName");check(not row.is_empty() and row.insert=="GetObjectByName()","nested read function completion")
	check(completion("#GSSet",6,"GSSetVar").is_empty(),"read completion does not suggest mutation")
	check(completion("@HP(GSSet",9,"GSSetVar").is_empty(),"nested completion does not suggest mutation")
	check(not completion("@God",4,"GodMode").is_empty(),"root write completion")
	check(not completion("travel gz1",10,"gz1g").is_empty(),"travel completion resolves installed maps")
	c.visible=true;c.input.grab_focus();await get_tree().process_frame
	c._set_input("god o");c._complete(true)
	check(c.suggestions.visible,"editor shows contextual suggestions")
	key(KEY_TAB);check(c.input.text in ["god off","god on"] and not u.god_mode(),"Tab inserts without executing")
	c._set_input("god on");key(KEY_ENTER);check(u.god_mode(),"Enter explicitly executes")
	c.run("god off")
	c._set_input("unfinished draft");c._recall(-1);check(c.input.text=="god on","Up recalls command history")
	c._recall(1);check(c.input.text=="unfinished draft","Down restores unsent draft")
	var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://console/history.json"))
	check(saved is Array and saved[-1]=="god on","history saved to isolated user profile")
	c._set_input("god");key(KEY_R,true);check(c.suggestions.visible and not c._candidates.is_empty(),"Ctrl+R filters command history")
	key(KEY_ESCAPE);check(not c.suggestions.visible and c.visible,"Escape dismisses suggestions first")
	c._set_input("");c.input.insert_text_at_caret("god on\ngive 0 money 5");await get_tree().process_frame
	check(not c.input.text.contains("\n") and not u.god_mode(),"pasting multiline text never executes")
	c.run("clear");c.append("[url=https://example.invalid]plain[/url]");c.append("needle");c.append("haystack")
	check(c.output.get_parsed_text().contains("[url="),"untrusted output is literal text")
	key(KEY_F,true);c.search.text="needle";c._render_output()
	check(c.output.get_parsed_text().strip_edges()=="needle","find filters existing output")
	key(KEY_ESCAPE);check(c.output.get_parsed_text().contains("haystack"),"closing find restores output")
	c.run("log output.txt");check(FileAccess.get_file_as_string("user://console/output.txt").contains("haystack"),"log exports plain output")
	c.run("report bug.txt");var report:=FileAccess.get_file_as_string("user://console/bug.txt")
	check(report.contains("gz1g") and report.contains("haystack") and report.contains("FPS"),"report combines live authority diagnostics and local output")
	for name:String in ["../escape.txt","/tmp/escape.txt","settings.json","history.json","C:\\bad.txt"]:check(c._path(name).is_empty(),"console file confinement: "+name)
	c._resize_text(1);check(c.font_size==17,"font sizing changes console preference")
	c._resize_text(-1)
	if DisplayServer.get_name()!="headless":
		for language:String in ["en","ru","de"]:
			RemakeText.lang=language;c._refresh_labels();c.run("clear");c.run("party");c.run("help teleport")
			c._set_input("@GSSetVar(0,\"console_probe\",42)");c.run("console f")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://modern-"+language+".png")
		get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(640,480);c._set_input("teleport 100 100 he");c.input.grab_focus();c._complete(true)
		for i in 6:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://modern-narrow-de.png")
		check(get_viewport().get_visible_rect().size.x==640 and c.panel.size.x<=640 and c.panel.size.y<=get_viewport().get_visible_rect().size.y+1,"German console fits narrow viewport")
	c._close();RemakeText.lang="en"
	command('setvar 0 "console space" 5');check(command('getvar 0 "console space"')==PackedStringArray(["5.0"]),"quoted variable names execute after completion")
	var old_world:=s.world.get_instance_id();command("travel gz1g 1")
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline and (s.loading_game or not s.world or s.world.get_instance_id()==old_world):await get_tree().process_frame
	check(s.world and s.world.get_instance_id()!=old_world and s.zone_id=="gz1g" and not s.loading_game,"travel goes through the real zone transition")
	check(s.state.get_var(0,"console_probe")==42,"travel preserves campaign variables")
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	FileAccess.open("user://console_modern.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CONSOLE_MODERN ",checks," checks ",failures.size()," failures")
	UnitWounds.shutdown();TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
