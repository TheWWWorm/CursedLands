extends Node
## Uses owned CD/official-patch data, never embeds expansion scripts.
## Optional --unpatched-lia-root=... checks both editions in the same run.
const Compat := preload("res://src/game/script/story_compat.gd")
const Traps := preload("res://src/game/script/story_coop_traps.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ",label)

func parse_file(path: String) -> ScriptParser:
	var data := FileAccess.get_file_as_bytes(path.path_join("maps/zone13.mob"))
	check(not data.is_empty(),"owned zone13 data exists")
	var ast := ScriptParser.parse(EIMob.load_bytes(data).script_text)
	check(ast.errors.is_empty(),"owned zone13 script parses")
	return ast

func admitted(ast: ScriptParser, family: int) -> bool:
	return ast.scripts.has("Trap#%d#1"%family+Traps.WATCH)

func inspect_root(path: String) -> void:
	var ast := parse_file(path)
	AstralPatches.apply_script(ast,"gz13g")
	var original := ast.scripts.duplicate(true)
	Compat.apply(ast,CampaignProfile.ASTRAL,"gz13g")
	for i in 2:
		check(admitted(ast,i),"official trap family %d admits co-op"%i)
		for name: String in ["Trap#%d#1"%i,"Trap#%d#2"%i,"Trap#%d#3"%i,"VCheck#0#1"]:
			check(ast.scripts[name] == original[name],"adapter retains authored body: "+name)
	var once := JSON.stringify(ast.scripts,"",true,true)
	Compat.apply(ast,CampaignProfile.ASTRAL,"gz13g")
	check(JSON.stringify(ast.scripts,"",true,true) == once,"applying compatibility twice is idempotent")
	for family in 2:
		var changed := parse_file(path)
		changed.scripts["Trap#%d#3"%family].blocks[0].body[2][2][1][1] = 1.0
		Compat.apply(changed,CampaignProfile.ASTRAL,"gz13g")
		check(not admitted(changed,family),"custom trap damage stays unadapted")
		check(admitted(changed,1-family),"independent unmodified trap still admitted")
	var retimed := parse_file(path)
	var edits := 0
	for statement: Array in retimed.scripts["VCheck#0#1"].blocks[0].body:
		if statement[0] == ScriptParser.S_CALL and statement[1] == "Sleep":
			statement[2][0][1] += 1.0; edits += 1
	check(edits > 0,"custom caller timing fixture changes an actual delay")
	Compat.apply(retimed,CampaignProfile.ASTRAL,"gz13g")
	check(not admitted(retimed,0) and not admitted(retimed,1),"custom caller timing rejects both families")
	var other_zone := parse_file(path)
	Compat.apply(other_zone,CampaignProfile.ASTRAL,"gz14g")
	check(not admitted(other_zone,0) and not admitted(other_zone,1),"same script in another zone is not adapted")
	var other_campaign := parse_file(path)
	Compat.apply(other_campaign,CampaignProfile.ORIGINAL,"gz13g")
	check(not admitted(other_campaign,0) and not admitted(other_campaign,1),"base campaign is not adapted")

func _ready() -> void:
	check(GameData.campaign_id == CampaignProfile.ASTRAL,"requires owned LiA data")
	inspect_root(GameData.root)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--unpatched-lia-root="):
			inspect_root(arg.trim_prefix("--unpatched-lia-root="))
	print("ASTRAL_OFFICIAL_PATCH_GUARDS ",checks," checks ",failures," failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
