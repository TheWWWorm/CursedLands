class_name WikiKnowledge
extends RefCounted
## Read-only relationships from authored databases and object records. No VM,
## world, random stock generator, saves or gameplay objects are constructed.
var links := {}
var pins := {}
var subtitles := {}
var _seen := {}
var _catalog_ref: WeakRef
var catalog: RefCounted:
	get: return _catalog_ref.get_ref()

const LABELS := {
	"biography":"Character biography", "people":"Inhabitants", "person":"Related characters",
	"region":"Locations", "model":"In-game models",
	"carried":"Carried by", "equipped":"Equipped by", "cast":"Used by",
	"material":"What uses it", "stock":"Potential trader stock", "location":"Found in",
	"inhabitant":"Creatures and people", "item_location":"Recorded on this map",
	"reward":"Rewarded by", "required":"Needed for", "reward_item":"Reward items",
	"required_item":"Required items", "quest":"Quests", "exit":"Connected locations"
}

func add(from: String, relation: String, to: String, detail := "", variant := "") -> void:
	if not catalog.entries.has(from) or not catalog.entries.has(to) or from==to: return
	var identity := JSON.stringify([from,relation,to,detail,variant])
	if _seen.has(identity): return
	_seen[identity]=true
	links.get_or_add(from,[]).append({"relation":relation,"key":to,"detail":detail,"variant":variant})

func item_key(spec: String) -> String:
	var id := String(Items.parse_stack(spec.to_lower())[0])
	if id.begins_with("rune:"): return "rune/"+id.trim_prefix("rune:").uri_encode()
	if id.begins_with("spell:"): return "spell/"+id.trim_prefix("spell:").get_slice("{",0).uri_encode()
	return WikiCatalog.item_key(id)

func build(source: RefCounted) -> void:
	_catalog_ref=weakref(source)
	# Shop records follow the installed campaign, regardless of a live co-op session.
	var previous_network := Shops.network
	Shops.network = false
	for entry: Dictionary in catalog.entries.values():
		subtitles[entry.key]=RemakeText.t(entry.category)
		if entry.kind=="item":
			subtitles[entry.key]=RemakeText.t(WikiCatalog.ITEM_TYPES.get(WikiCatalog.item_subcategory(entry.value),"Other items"))
			for id: String in catalog.variants_for(entry.key):
				if id.begins_with("bp:"): continue
				var info := Items.info(id)
				if not info.mat.is_empty(): add(WikiCatalog.item_key(Items.material_unit(info.material)),"material",entry.key)
		elif entry.kind=="creature":
			var row := GameData.db.find("monster_prototypes",entry.value)
			subtitles[entry.key]+=" · "+RemakeText.t("Health")+" "+WikiCatalog.num(row.get("hp",0))
			for field: String in ["wears","items"]:
				for spec: String in row.get(field,[]): add(item_key(spec),"equipped" if field=="wears" else "carried",entry.key)
			for field: String in ["weapon","second_weapon"]:
				if row.get(field,""): add(item_key(row[field]),"equipped",entry.key)
			for spec: String in row.get("spells",[]): add("spell/"+spec.replace(" ","").to_lower().get_slice("{",0).uri_encode(),"cast",entry.key)
	for zone: Dictionary in catalog._campaign.zones.values():
		var key := "map/"+String(zone.id).uri_encode()
		if not catalog.entries.has(key): continue
		var island := WikiWorldText.text("allod "+String(zone.get("allod",""))).get_slice("\n",0)
		var purpose := RemakeText.t("Camp") if zone.get("type", "")=="brief" else RemakeText.t("Exploration")
		subtitles[key]=RemakeText.t("Maps")+" · "+purpose+(" · "+island if island else "")
		var dimensions: Vector2i=zone.get("size",Vector2i.ZERO)
		for exit_record: Dictionary in zone.get("exits",{}).values():
			var pending := [String(exit_record.get("to",""))]
			var visited := {String(zone.id):true}
			while not pending.is_empty():
				var dest := String(pending.pop_front())
				if visited.has(dest):continue
				visited[dest]=true
				var destination := "map/"+dest.uri_encode()
				if catalog.entries.has(destination):
					add(key,"exit",destination)
					if exit_record.has("deploy"):_pin(key,destination,exit_record.deploy.get_center(),dimensions,"exit")
					continue
				for edge: Dictionary in catalog._campaign.zone(dest).get("exits",{}).values():pending.append(String(edge.get("to","")))
		var mob_name := String(zone.get("mob",""))
		if mob_name.is_empty(): continue
		var mob: EIMob = catalog.map_records(mob_name)
		for object: Dictionary in mob.objects:
			if object.kind!="UNIT": continue
			var creature := "creature/"+String(object.get("prototype","")).to_lower().uri_encode()
			if not catalog.entries.has(creature): continue
			add(creature,"location",key)
			add(key,"inhabitant",creature)
			var p: Vector3=object.get("position",Vector3.ZERO)
			_pin(key,creature,Vector2(p.x,p.y),dimensions,"inhabitant")
			for field: String in ["quest_items","quick_items"]:
				for spec: String in object.get(field,[]):
					var item := item_key(spec)
					add(item,"item_location",key,catalog.entries[creature].title)
					add(item,"carried",creature)
		# Topics name both the actual trader and the authored shop record.
		# A topic reference proves possible availability, never current stock.
		var pattern := RegEx.create_from_string('(?i)b\\.([a-z0-9_]+)\\.constr_?([1-5])')
		var script_text := RegEx.create_from_string("(?s)/\\*.*?\\*/|//[^\\n]*").sub(mob.script_text,"",true)
		for found: RegExMatch in pattern.search_all(script_text):
			var shop := found.get_string(2).to_int()
			var trader := ""
			for object: Dictionary in mob.objects:
				if String(object.get("name","")).to_lower()==found.get_string(1).to_lower():
					trader=GameUnit.unit_title(String(object.get("prototype","")).to_lower())
			var lists := Shops.lists(shop,{})
			for table: String in ["weapons","armors","quick_items","materials","spell_prototypes","spell_modifiers"]:
				if table.begins_with("spell") and not Shops.sells_spells(shop): continue
				if not table.begins_with("spell") and not Shops.sells_items(shop): continue
				for row: Dictionary in lists[table]:
					var target := ""
					if table=="spell_prototypes": target="spell/"+String(row.code).to_lower().uri_encode()
					elif table=="spell_modifiers": target="rune/"+String(row.code).to_lower().uri_encode()
					else:
						if table!="materials" and not Items.has_blueprint(table,row): continue
						target=WikiCatalog.item_key(Items.material_unit(String(row.name).to_lower()) if table=="materials" else String(row.name).to_lower())
					add(target,"stock",key,trader)
	for quest: String in catalog._quest_zones:
		var key := "quest/"+quest.uri_encode()
		for zone: String in catalog._quest_zones[quest]:
			var map_key := "map/"+zone.uri_encode()
			add(key,"location",map_key)
			add(map_key,"quest",key)
			if catalog.entries.has(map_key): subtitles[key]=RemakeText.t("Quests")+" · "+catalog.entries[map_key].title
			for p: Vector2 in catalog._campaign.quest_areas.get(quest,PackedVector2Array()):
				_pin(map_key,key,p,catalog._campaign.zone(zone).get("size",Vector2i.ZERO),"quest")
	# Side-quest reward/requirement lists have an unambiguous quest owner.
	for quest: Dictionary in SideQuests.all():
		var key := "quest/"+String(quest.id).uri_encode()
		var row := SideQuests.briefing_row(quest.id+"_3")
		for field: String in ["give_items","take_items"]:
			for spec: String in row.get(field,[]) if row.get(field) is Array else []:
				var item := item_key(spec)
				add(item,"reward" if field=="give_items" else "required",key)
				add(key,"reward_item" if field=="give_items" else "required_item",item)

	Shops.network = previous_network

func _pin(map_key: String, target: String, p: Vector2, dimensions: Vector2i, kind: String) -> void:
	if dimensions.x<=0 or dimensions.y<=0 or not catalog.entries.has(target): return
	var x := p.x/(32.0*dimensions.x)
	var y := 1.0-p.y/(32.0*dimensions.y)
	if x<0 or x>1 or y<0 or y>1: return
	pins.get_or_add(map_key,[]).append({"key":target,"title":catalog.entries[target].title,"x":x,"y":y,"kind":kind})

func groups(key: String) -> Array:
	var out := []
	for relation: String in LABELS:
		var rows := []
		for edge: Dictionary in links.get(key,[]):
			if edge.relation!=relation: continue
			rows.append({"key":edge.key,"title":catalog.entries[edge.key].title,"detail":edge.detail,"variant":edge.variant})
		if rows.is_empty(): continue
		rows.sort_custom(func(a,b): return String(a.title).naturalnocasecmp_to(b.title)<0)
		out.append({"id":relation,"title":RemakeText.t(LABELS[relation]),"rows":rows})
	return out

func html(key: String) -> String:
	var out := ""
	for group: Dictionary in groups(key):
		# These sections already have dedicated, richer article content.
		if group.id in ["material","quest","exit"]: continue
		out+=WikiCatalog.heading(group.title)
		if group.id=="stock": out+=WikiCatalog.paragraph(RemakeText.t("This trader can generate this stock. Selection, materials and availability vary; this is not a live shop inventory."))
		if group.id in ["equipped","carried","item_location"]: out+=WikiCatalog.paragraph(RemakeText.t("Authored equipment and carried items are references, not guaranteed drops. Scripts and quest state can change availability."))
		if group.id=="location": out+=WikiCatalog.paragraph(RemakeText.t("These locations come from original records. Scripts may move or hide a character."))
		var rows := []
		if group.id in ["biography", "people", "person", "region", "model"]:
			for row: Dictionary in group.rows: rows.append([WikiCatalog.link(row.key,row.title)])
			out += WikiCatalog.table_html([RemakeText.t("Related page")],rows)
			continue
		for row: Dictionary in group.rows: rows.append([WikiCatalog.link(row.key,row.title),WikiCatalog.esc(row.detail)])
		out+=WikiCatalog.table_html([RemakeText.t("Related page"),RemakeText.t("Details")],rows)
	return out
