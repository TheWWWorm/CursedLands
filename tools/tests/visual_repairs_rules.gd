extends Node
var checks:=0
var failures:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func translated(value:String)->void:
	if value.is_empty():return
	var pair:Array=RemakeText.TEXTS.get(value,[])
	check(pair.size()==2 and not pair.has(""),"RU/DE: "+value)
func _ready()->void:
	for key:String in GameData.REMAKE_OPTIONS:
		for label:String in GameData.REMAKE_OPTIONS[key]:translated(label)
	for label:String in GfxPresets.NAMES:translated(label)
	for pair:Array in OptionsPanel.PAD_ACTIONS.values():
		for label:String in pair:translated(label)
	for rule:Array in ModSchema.RULES.values():
		translated(rule[0])
		for label:String in rule[1]:translated(label)
	var proto:=GameData.db.find("monster_prototypes","Human Mercenary Kania Paladin")
	var kit:=CampaignState.merc_kit({},proto)
	var enchanted:=0
	for raw:String in kit.armors:
		if not "[" in raw:continue
		enchanted+=1
		var fixed:=Items.canonical_equipment(raw)
		check("|" in fixed and not "[" in fixed,"native enchanted kit is parsed")
		check(not Items.info(raw).mat.is_empty(),"native kit retains its steel material")
		check(".st." in str(Items.look(raw)),"inventory armor uses a real steel texture")
		check(Items.title(raw)==Items.title(fixed) and not "{" in Items.title(raw) and not "uniqueingos" in Items.title(raw).to_lower(),"armor uses authored localized title")
		check(not Items.spell_of(raw).is_empty(),"armor retains the authored spell")
		check(Items.canonical_equipment(raw+"@12.5~7")==fixed+"@12.5~7","old save keeps wear and charge exactly")
		check(Items.durability(raw+"@12.5~7")==Items.durability(fixed+"@12.5~7"),"saved armor stats use the same material")
		check(Items.canonical_equipment(fixed)==fixed,"canonical item is stable")
	check(enchanted==2,"Brissen has two authored enchanted armor pieces")
	for raw in ["unknown.steel[strength{ic}]","uniqueingos plate.unknown[strength{ic}]","uniqueingos plate.steel[unknown{ic}]","material.steel[2]","uniqueingos plate.steel"]:
		check(Items.canonical_equipment(raw)==raw,"preserve unsupported/plain spec: "+raw)
	print("VISUAL_REPAIRS_RULES ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
