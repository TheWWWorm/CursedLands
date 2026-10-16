class_name WikiPlan
extends RefCounted
## Portable, versioned plans. No save data or executable content in a link.
const LIMIT := 32
const MAX_LINK := 24000
const SLOTS := ["weapon1","weapon2","weapon3","weapon4","quick1","quick2","quick3","quick4","helm","plate","leggins","shirt","pants","gloves","boots","spell1","spell2","spell3","spell4","spell5","spell6","spell7","spell8"]

static func slot_type(slot: String) -> String:
	return slot.rstrip("12345678")

static func entry_type(row: Dictionary, catalog: WikiCatalog) -> String:
	if not catalog.entries.has(row.key):return ""
	if row.key.begins_with("spell/"):return "spell"
	var kind := Items.kind(row.variant)
	return Items.slot(row.variant).replace("leggings","leggins") if kind in ["weapon","armor"] else "quick" if kind=="quick" else ""

static func auto_slot(plan: Dictionary,row: Dictionary,catalog: WikiCatalog) -> void:
	row.slot=""
	for slot: String in SLOTS:
		if slot_type(slot)==entry_type(row,catalog) and not plan.entries.any(func(other):return other.get("slot","")==slot):row.slot=slot;return

static func assign_slot(plan: Dictionary,index: int,slot: String,catalog: WikiCatalog) -> bool:
	if index<0 or index>=plan.entries.size():return false
	if slot and (not slot in SLOTS or slot_type(slot)!=entry_type(plan.entries[index],catalog)):return false
	if slot:
		for other: Dictionary in plan.entries:
			if other.get("slot","")==slot:other.slot=""
	plan.entries[index].slot=slot
	return true

static func blank(campaign: String) -> Dictionary:
	return {"v":1,"campaign":campaign,"strength":25,"dexterity":25,"intelligence":25,"experience":50000,"skills":{},"entries":[]}

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("v") != 1 or not value.get("campaign","") in [CampaignProfile.ORIGINAL,CampaignProfile.ASTRAL]: return {}
	var out := blank(value.campaign)
	for field: String in ["strength","dexterity","intelligence","experience"]:
		var n: Variant = value.get(field,out[field])
		if not (n is int or n is float) or not is_finite(float(n)) or n < (0 if field=="experience" else 1) or n > (1000000000 if field=="experience" else 100): return {}
		out[field]=int(n)
	if not value.get("skills") is Dictionary or not value.get("entries") is Array: return {}
	for skill: String in Skills.LIST:
		var n: Variant = value.get("skills",{}).get(skill,0)
		if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>100: return {}
		out.skills[skill]=int(n)
	if value.get("entries",[]).size()>LIMIT: return {}
	for entry: Variant in value.get("entries",[]):
		if not entry is Dictionary: return {}
		var row := {"key":"","variant":"","spell":"","runes":[],"count":1}
		for field: String in ["key","variant","spell"]:
			if not entry.get(field,"") is String or String(entry.get(field,"")).length()>512: return {}
			row[field]=entry.get(field,"")
		if not row.key.begins_with("item/") and not row.key.begins_with("spell/"): return {}
		if not entry.get("runes",[]) is Array or entry.get("runes",[]).size()>Spells.MAX_MODS: return {}
		for rune: Variant in entry.get("runes",[]):
			if not rune is String or rune.length()>32: return {}
			row.runes.append(rune)
		if row.spell.is_empty() and not row.runes.is_empty():return {}
		var count: Variant=entry.get("count",1)
		if not (count is int or count is float) or count<1 or count>99 or not is_finite(float(count)): return {}
		row.count=int(count)
		if entry.has("slot"):
			if not entry.slot is String or (entry.slot and not entry.slot in SLOTS):return {}
			row.slot=entry.slot
			if row.slot and out.entries.any(func(other):return other.get("slot","")==row.slot):return {}
		out.entries.append(row)
	if JSON.stringify(out).to_utf8_buffer().size()>MAX_LINK*3/4:return {}
	return out

static func encode(plan: Dictionary) -> String:
	var clean := validate(plan)
	if clean.is_empty(): return ""
	return Marshalls.raw_to_base64(JSON.stringify(clean).to_utf8_buffer()).replace("+","-").replace("/","_").rstrip("=")

static func decode(text: String) -> Dictionary:
	if "#build=" in text: text=text.get_slice("#build=",1)
	if text.is_empty() or text.length()>MAX_LINK or RegEx.create_from_string("[^A-Za-z0-9_-]").search(text): return {}
	text=text.replace("-","+").replace("_","/")
	while text.length()%4: text+="="
	var parser := JSON.new()
	if parser.parse(Marshalls.base64_to_raw(text).get_string_from_utf8()) != OK: return {}
	return validate(parser.data)

static func url(plan: Dictionary, language: String) -> String:
	return "https://cursedlands.wwworm.com/wiki/?lang="+language+"&campaign="+plan.campaign+"&page=mechanics%2Fplanning#build="+encode(plan)

static func spell(row: Dictionary) -> String:
	return row.spell+("{"+";".join(row.runes)+"}" if row.runes.size() else "")

static func totals(plan: Dictionary, catalog: WikiCatalog) -> Dictionary:
	var result := {"weight":0.0,"value":0,"construction":0,"materials":{},"rows":[],"training":0,
		"health":Skills.base_pool(plan.experience,plan.strength),"stamina":Skills.base_pool(plan.experience,plan.dexterity,"MP"),"capacity":plan.strength*12}
	for skill: String in Skills.LIST: result.training+=Skills.span_cost(0,plan.skills.get(skill,0))
	for row: Dictionary in plan.entries:
		var data := {"title":RemakeText.t("Page unavailable"),"valid":false,"ready":false,"key":row.key,"count":row.count}
		if not catalog.entries.has(row.key): result.rows.append(data); continue
		if row.get("slot","") and slot_type(row.slot)!=entry_type(row,catalog):result.rows.append(data);continue
		data.title=catalog.entries[row.key].title
		var magic := spell(row)
		if magic and catalog.add_variant(magic).is_empty(): result.rows.append(data); continue
		if row.key.begins_with("item/"):
			var choices := catalog.variants_for(row.key)
			if not row.variant in choices or row.variant.begins_with("bp:"): result.rows.append(data); continue
			var id: String=row.variant
			if magic:
				id=catalog.construct_item(row.key,row.variant,magic)
				if id.is_empty(): result.rows.append(data); continue
			data.title=catalog.display_item_title(id)
			data.ready=true
			result.weight+=Items.weight(id)*row.count
			result.value+=Items.price(id)*row.count
			if catalog.craftable(row.key):
				result.construction+=int(Items.price(id)*Items.COEF[Items.Deal.CONSTR])*row.count
				var info := Items.info(id)
				var mat := Items.material_unit(info.material)
				var key := WikiCatalog.item_key(mat)
				if catalog.entries.has(key):
					if not result.materials.has(key): result.materials[key]={"title":catalog.entries[key].title,"count":0}
					result.materials[key].count+=Items.components("bp:"+String(info.base))*row.count
		else:
			if magic.is_empty() or magic.get_slice("{",0)!=catalog.entries[row.key].value.get_slice("{",0): result.rows.append(data); continue
			var parsed := Spells.parse(magic)
			data.title=WikiCatalog.spell_title(magic)
			data.ready=Skills.knowledge({"int":plan.intelligence,"skills":plan.skills},parsed.subtype)>=parsed.complex and result.stamina>=parsed.mana
			result.value+=int(parsed.price)*row.count
		data.valid=true
		result.rows.append(data)
	return result
