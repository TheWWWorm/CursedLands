extends Node
var checks:=0
var failures:=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _ready():
	var c:=WikiCatalog.new();c.rebuild()
	for base:String in c._fixed:
		var id:String=c._fixed[base]
		var expected:=WikiCatalog.authored_name(id)
		if expected.is_empty():continue
		check(c.entries[WikiCatalog.item_key(base)].title==expected,"fixed article retains finished item name: "+base)
		check(c.display_item_title(id)==expected,"fixed variant retains finished item name: "+base)
	if GameData.campaign_id==CampaignProfile.ASTRAL:
		var expected:=Items.title("spiked mace.bronze")
		check(c.entries[WikiCatalog.item_key("spiked mace")].title==expected,"reported club has same name in inventory and wiki")
		check(c.page(WikiCatalog.item_key("spiked mace")).html.contains(WikiCatalog.esc(expected)),"article heading uses original finished club name")
	FileAccess.open("user://wiki_item_names.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("WIKI_ITEM_NAMES ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if failures else 0)
