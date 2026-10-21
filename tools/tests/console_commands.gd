extends Node
var checks:=0
var failures:=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _ready():
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	var console:=DeveloperConsole
	console.run("give 0 money 123")
	check(not console.unlocked and s.state.money==0,"unlock required")
	console.run("thingamabob")
	check(console.unlocked,"original unlock command")
	console.run("give 0 money 123")
	check(s.state.money==123,"money command reaches authority")
	var hero:GameUnit=s.party_units(0)[0]
	var exp:=float(hero.get_meta("hero").get("exp",0))
	console.run("give 0 exp 100")
	check(float(hero.get_meta("hero").get("exp",0))>exp,"experience command updates actual character")
	console.run("setvar 0 console_probe 7")
	check(s.state.get_var(0,"console_probe")==7,"setvar updates campaign state")
	console.run("getvar 0 console_probe")
	check(console.lines[-1]=="7.0" or console.lines[-1]=="7","getvar prints value")
	console.run("#Add(GSGetVar(0,\"console_probe\"),3)")
	check(console.lines[-1] in ["10","10.0"],"nested original numeric expression")
	console.run("$\"console probe\"")
	check(console.lines[-1]=="console probe","original string output")
	console.run("#HP(GetObjectByName(\"hero\"))")
	check(console.lines[-1].is_valid_float() and is_equal_approx(float(console.lines[-1]),hero.hp),"object expression resolves live hero")
	console.run("@GiveMoney(0,5)")
	check(s.state.money==128,"script money builtin uses existing VM")
	console.run("@GSSetVar(0,\"console_probe\",9)")
	check(s.state.get_var(0,"console_probe")==9,"script variable builtin")
	console.run("@BlockUnit(GetObjectByName(\"hero\"),1)")
	check(hero.blocked,"supported unit command")
	console.run("@BlockUnit(GetObjectByName(\"hero\"),0)")
	check(not hero.blocked,"unit command reversible")
	var item:=String(GameData.db.table("weapons")[0].name)+".bronze"
	var count:=s.state.items.size()
	console.run('@GiveItem(0,"'+item+'")')
	check(s.state.items.size()>count,"item command uses campaign inventory")
	for invalid:String in ["#GSSetVar(0,\"console_probe\",99)","@GSSetVar(0,\"console_probe\")","@GiveMoney(0,\"oops\")","#HP(1)","#Unknown()","#Add(1,2) garbage","@SetCP(GetObjectByName(\"missing\"),1,2,3)","give 0 money -1","loadvars {\"console_probe\":999,\"bad\":\"text\"}"]:
		var before:=s.state.money
		ConsoleCommands.execute(s,invalid)
		check(s.state.money==before and s.state.get_var(0,"console_probe")==9,"invalid command does not mutate: "+invalid)
	for invalid:String in ["#Div(1,0)","#1e100",'@GSSetVar(0,"console_probe",Mul(1e30,1e30))','@GSSetVar(0,"console_probe",1e100)','$"unterminated','#'+"Not(".repeat(100)+"1"+")".repeat(100)]:
		var result:=ConsoleCommands.execute(s,invalid)
		check(result==PackedStringArray([RemakeText.t(ConsoleCommands.ERROR)]) and s.state.get_var(0,"console_probe")==9,"invalid arithmetic/syntax rejected: "+invalid)
	ConsoleCommands.execute(s,"give 0 money 999",1)
	check(s.state.money==128,"guest slot cannot mutate host")
	s.loading_game=true;ConsoleCommands.execute(s,"give 0 money 999");s.loading_game=false
	check(s.state.money==128,"loading blocks console changes")
	console.run("listvar 0 probe.txt")
	check(FileAccess.file_exists("user://console/probe.txt"),"original-style variable dump written")
	console.run("setvar 0 console_probe 20");console.run("loadvar 0 probe.txt")
	check(s.state.get_var(0,"console_probe")==9,"variable dump import restores values")
	FileAccess.open("user://console/commands.txt",FileAccess.WRITE).store_string("setvar 0 console_batch 42\n@GiveMoney(0,2)\n")
	console.run("exec commands.txt")
	check(s.state.get_var(0,"console_batch")==42 and s.state.money==130,"command file executes in order")
	FileAccess.open("user://console/recursive.txt",FileAccess.WRITE).store_string("exec recursive.txt\n")
	console.run("exec recursive.txt")
	check(console._exec_depth==0,"recursive exec terminates")
	console.run("loadvar 0 ../settings.cfg")
	check(s.state.get_var(0,"console_probe")==9,"file imports stay inside console directory")
	for language:String in ["en","ru","de"]:
		RemakeText.lang=language;console.lines.clear();console.run("help")
		for row:Array in console.HELP:
			check(language=="en" or RemakeText.t(row[1])!=row[1],language+" help translated: "+row[0])
		if DisplayServer.get_name()!="headless":
			console.visible=true;console.run("console f");await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://console-"+language+".png")
	for place:String in ["t","b","c","l","r","f"]:
		console.run("console "+place);check(console.placement==place,"console position "+place)
	console.visible=true
	check(g.hud.blocks_input() and g.hud.blocks_camera(),"console owns gameplay and camera input")
	console.visible=false
	check(not g.hud.blocks_camera(),"closing console restores gameplay input")
	s.state.store_zone("gz1g",s.world)
	s.state.save("user://console-save.eis")
	var restored:=CampaignState.load_from("user://console-save.eis")
	check(restored.money==130 and restored.get_var(0,"console_batch")==42,"console changes survive normal save/load")
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	FileAccess.open("user://console_commands.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CONSOLE_COMMANDS ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
