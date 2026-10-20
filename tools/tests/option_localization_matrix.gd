extends Node
## Every declared remake option label/help and dynamic choice, plus formatting
## contracts for the translation catalogue. Layout is covered by rendered tests.
var checks := 0
var failures: Array[String] = []
var format_pattern := RegEx.new()
const TECHNICAL_CHOICES := ["SMAA","MSAA 4×","MSAA 4× + SMAA","TAA","FSR 2",
	"Xbox","PlayStation","Nintendo","Steam Deck"]

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)

func formats(text: String) -> Array:
	# Ignore escaped literal percent signs, then retain argument order/types.
	return format_pattern.search_all(text.replace("%%","")).map(func(m): return m.get_string())

func translated(key: String, origin: String) -> void:
	var row: Array=RemakeText.TEXTS.get(key,WikiLoreData.DATA.texts.get(key,[]))
	check(row.size()==2,origin+" declares Russian and German: "+key)
	for i in 2:
		var lang: String=["ru","de"][i]
		check(row.size()>i and row[i] is String and not String(row[i]).strip_edges().is_empty(),
			origin+" has nonempty "+lang+": "+key)
		if row.size()<=i: continue
		RemakeText.lang=lang
		check(RemakeText.t(key)==String(row[i]),origin+" resolves dynamically in "+lang+": "+key)

func _ready() -> void:
	# A literal "20% faster" is not a %f argument. No catalogue callsite
	# uses printf's space flag. "%ds" is valid ("%d" plus a seconds suffix).
	format_pattern.compile("%[-+0#]*[0-9]*(?:\\.[0-9]+)?[sdifxXoc]")
	var language := RemakeText.lang
	var alpha := RegEx.new(); alpha.compile("[A-Za-z]")
	for id: String in GameData.REMAKE_OPTIONS:
		var row: Array=GameData.REMAKE_OPTIONS[id]
		check(row.size()==2 and not String(row[0]).is_empty() and not String(row[1]).is_empty(),id+" has label and help")
		for key: String in row: translated(key,"option "+id)
	for id: String in GameData.DISPLAY_CHOICES:
		for key: String in GameData.DISPLAY_CHOICES[id]:
			if alpha.search(key)==null or key in TECHNICAL_CHOICES: continue
			translated(key,"choice "+id)
	for key: String in RemakeText.TEXTS:
		var row: Array=RemakeText.TEXTS[key]
		check(row.size()==2,"translation entry has both languages: "+key)
		for i in mini(2,row.size()):
			check(not String(row[i]).strip_edges().is_empty(),"nonempty translation: "+key)
			check(formats(key)==formats(String(row[i])),"format arguments preserve order and type: "+key+" / "+["ru","de"][i])
	RemakeText.lang=language
	print("OPTION_LOCALIZATION_MATRIX ",JSON.stringify({"checks":checks,"failures":failures,
		"options":GameData.REMAKE_OPTIONS.size(),"choice_groups":GameData.DISPLAY_CHOICES.size(),
		"translation_keys":RemakeText.TEXTS.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
