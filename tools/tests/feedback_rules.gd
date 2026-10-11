extends Node
class HeardSound extends GameSound:
	var calls: Array[String] = []
	func ui(path: String) -> void: calls.append(path)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for key: String in GameData.REMAKE_OPTIONS:
		for text: String in GameData.REMAKE_OPTIONS[key]:
			check(RemakeText.TEXTS.has(text),"RU/DE translation for "+key+": "+text.left(45))
	for rule: Array in ModSchema.RULES.values():
		check(RemakeText.TEXTS.has(rule[0]),"translated rule "+rule[0])
		for choice: String in rule[1]: check(RemakeText.TEXTS.has(choice),"translated choice "+choice)
	var s:=Session.new(); add_child(s)
	var game:=Game.new(); game.session=s; s.game=game
	var sound:=HeardSound.new(); game.sound=sound
	s._rpc_clock(true,false,0)
	check(sound.calls.is_empty(),"unchanged initial clock is silent")
	s._rpc_clock(true,true,0)
	check(get_tree().paused and sound.calls.size()==1,"host pause sounds once on paused client")
	s._rpc_clock(true,true,0)
	check(sound.calls.size()==1,"duplicate pause is silent")
	s._rpc_clock(true,false,0)
	check(not get_tree().paused and sound.calls.size()==2,"resume sounds once")
	var w:=GameWorld.new(); w.session=s
	var u:=GameUnit.new(); u.world=w
	s.mod_config={"rules":{"armor_formula":0}}; GameData.options.armor_formula=1
	check(Combat.armor_minimum(u,100)==0,"host original armour overrides client preference")
	s.mod_config.rules.armor_formula=1; GameData.options.armor_formula=0
	check(Combat.armor_minimum(u,100)==20,"host optional armour overrides client preference")
	check(ModStore.new_game_defaults().rules.armor_formula==0,"new games use original armour by default")
	check(GameData.options.has("gfx_rain_puddles"),"puddles participate in saved graphics settings")
	u.free(); w.free(); sound.free(); game.free(); s.free()
	print("FEEDBACK_RULES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
