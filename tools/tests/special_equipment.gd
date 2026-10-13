extends Node
## Unique equipment survives sale/buyback and old generated material variants.
const SPECIALS := {
	"unique sword":"steel", "unique spear":"mithrill", "uniqueingos plate":"steel",
	"uniqueingos helm":"steel", "uniquegipathadagan helm":"iron", "uniquegipathadagan plate":"adamantium",
}
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	var s:=Session.new();add_child(s);s.set_physics_process(false)
	s.state=CampaignState.new();s.world=GameWorld.new();add_child(s.world)
	s.world.set_physics_process(false);s.world.set_process(false);s.world.zone={"type":"brief"}
	var old_sold:={"weapons":[],"armors":[]}
	for base:String in SPECIALS:
		var original:=base+"."+String(SPECIALS[base])
		var info:=Items.info(original)
		old_sold[info.table].append(base)
		check(not Items.can_deconstruct(original),base+" is authored fixed equipment")
		for mat:Dictionary in Items.materials_for("bp:"+base):
			var id:=base+"."+String(mat.name).to_lower()+"|litnwall{it}"
			var saved:=id+"@12.5~7"
			var look:=Items.look(saved)
			check(GameData.redress.has("unhuma"+String(look.get("layer",""))+".mmp"),id+" resolves an authored skin")
			check(not "unique" in Items.title(saved).to_lower() and not "{" in Items.title(saved),id+" retains a localized title and enchantment name")
			check(Items.flavor(saved)==Items.flavor(original),id+" retains the authored description")
			check(Items.info(saved).material==String(mat.name).to_lower() and Items.wear(saved)==12.5 and Items.spent(saved)==7, id+" display repair preserves saved instance state")
			check(Items.damage(saved)==Items.damage(id) and Items.spell_of(saved)=="litnwall{it}",id+" retains stats and spell")
			var repaired:=Items.with_wear(saved,0)
			s.state.items=[saved];s.state.money=100000000
			s.state.shops[3]={"restock":false,"goods":{},"sold":{}}
			check(s._trade_apply({"shop":3,"sell":[saved]}),id+" sells")
			check(s.shop_count(repaired,{"shop":3})==1 and s.state.shops[3].sold.is_empty(),id+" sale keeps exact buyback without teaching random copies")
			check(s._trade_apply({"shop":3,"buy":[repaired]}) and s.state.items==[repaired],id+" buys back with magic and charge intact")
	# Existing learned prototypes must not generate more invalid variants.
	for shop in [1,3,4,5]:
		var lists:=Shops.lists(shop,old_sold)
		for base:String in SPECIALS:
			var table:String=Items.info(base+"."+String(SPECIALS[base])).table
			check(not lists[table].any(func(row):return String(row.name).to_lower()==base),"legacy sold history does not generate "+base)
		for seed_value in 6:
			var rng:=RandomNumberGenerator.new();rng.seed=seed_value
			var goods:=Shops.generate(shop,old_sold,{"*":100},rng)
			check(not goods.keys().any(func(id):return "unique" in String(id)),"restock excludes fixed equipment and its blueprints")
	var ordinary:="stone axe.rock"
	s.state.items=[ordinary];s.state.money=100000;s.state.shops[1]=Shops.blank()
	check(s._trade_apply({"shop":1,"sell":[ordinary]}) and s.state.shops[1].sold.get("weapons",[]).has("stone axe"),"ordinary craftable equipment still teaches its prototype")
	check(GameData.redress.has("unhuma"+String(Items.look(ordinary).layer)+".mmp"),"ordinary skin selection is unchanged")
	for table in ["weapons","armors"]:
		for row:Dictionary in GameData.db.table(table):
			if not String(row.name).to_lower().begins_with("unique"): continue
			for mat:Dictionary in Items.materials_for("bp:"+String(row.name).to_lower()):
				check(not "unique" in Items.title(String(row.name).to_lower()+"."+String(mat.name).to_lower()).to_lower(),"fixed NPC equipment never exposes its internal prototype name")
	print("SPECIAL_EQUIPMENT ",checks," checks ",failures," failures")
	s.world.queue_free();s.queue_free()
	for i in 4:await get_tree().process_frame
	get_tree().quit(int(failures>0))
