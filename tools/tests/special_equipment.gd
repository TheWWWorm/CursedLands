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
	var old_sold:={"weapons":[],"armors":[],"quick_items":[]}
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
	# Special quick items obey the same fixed-item rule as story equipment.
	for base:String in ["wand 5","wand 6"]:
		old_sold.quick_items.append(base)
		var bp:="bp:"+base
		var mat:=String(Items.materials_for(bp)[0].name).to_lower()
		var item:=base+"."+mat+"|weak{t2;fe}@7"
		check(not Items.valid_blueprint(bp) and not Items.can_deconstruct(item),base+" has no authored recipe")
		s.state.items=[item];s.state.money=100000000;s.state.shops[3]={"restock":false,"goods":{},"sold":{}}
		check(s._trade_apply({"shop":3,"sell":[item]}) and s.state.shops[3].sold.is_empty(),base+" sale does not teach a recipe")
		check(s._trade_apply({"shop":3,"buy":[Items.with_wear(item,0)]}),base+" exact sold item remains buyable")
		s.state.shops[3].goods[bp]=3;s.state.items=[bp,"material."+mat]
		check(not s.shop_stock({"shop":3}).has(bp) and s.shop_count(bp,{"shop":3})==0,"old saved stock hides "+bp)
		var before:=s.state.items.duplicate();var money:=s.state.money
		check(not s._trade_apply({"shop":3,"buy":[bp]}) and not s._trade_apply({"shop":3,"sell":[bp]}),"stale commands cannot trade "+bp)
		s._construct({"shop":3,"bp":bp,"mat":mat})
		check(s.state.items==before and s.state.money==money,"an old owned recipe cannot construct a special item or consume ingredients")
	# Existing learned prototypes must not generate more invalid variants.
	for shop in [1,3,4,5]:
		var lists:=Shops.lists(shop,old_sold)
		for base:String in SPECIALS:
			var table:String=Items.info(base+"."+String(SPECIALS[base])).table
			check(not lists[table].any(func(row):return String(row.name).to_lower()==base),"legacy sold history does not generate "+base)
		check(not lists.quick_items.any(func(row):return String(row.name).to_lower() in ["wand 5","wand 6"]),"legacy special-wand sale history cannot teach blueprints")
		for seed_value in 6:
			var rng:=RandomNumberGenerator.new();rng.seed=seed_value
			var goods:=Shops.generate(shop,old_sold,{"*":100},rng)
			check(not goods.keys().any(func(id):return "unique" in String(id)),"restock excludes fixed equipment and its blueprints")
			check(not goods.has("bp:wand 5") and not goods.has("bp:wand 6"),"restock excludes Dragon Horn and Goblin Doll recipes")
	check(Shops.generate(1,{}, {},RandomNumberGenerator.new()).has("bp:wand 1"),"ordinary wand blueprints remain available")
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
