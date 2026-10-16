class_name WikiLibrary
extends RefCounted
## Local, named recipe snapshots. Separate from campaign saves and game inventory.
const PATH := "user://wiki-creations.json"
const LIMIT := 100

static func read(path: String=PATH) -> Dictionary:
	if not FileAccess.file_exists(path):return {"records":[],"error":""}
	var file := FileAccess.open(path,FileAccess.READ)
	if not file:return {"records":[],"error":"Local storage is unavailable. Copy a link to keep your creation."}
	if file.get_length()>2000000:return {"records":[],"error":"Saved creations cannot be read. Existing data was left untouched."}
	var json := JSON.new()
	if json.parse(file.get_as_text())!=OK:return {"records":[],"error":"Saved creations cannot be read. Existing data was left untouched."}
	var value: Variant=json.data
	if not value is Dictionary or value.get("v")!=1 or not value.get("records") is Array or value.records.size()>LIMIT:return {"records":[],"error":"Saved creations cannot be read. Existing data was left untouched."}
	var records := [];var ids := {}
	for record: Variant in value.records:
		var clean := _clean(record)
		if clean.is_empty() or ids.has(clean.id):return {"records":[],"error":"Saved creations cannot be read. Existing data was left untouched."}
		ids[clean.id]=true;records.append(clean)
	records.sort_custom(func(a,b):return a.updated>b.updated)
	return {"records":records,"error":""}

static func _clean(record: Variant) -> Dictionary:
	if not record is Dictionary or not record.get("id") is String or not RegEx.create_from_string("^[a-zA-Z0-9_-]{1,80}$").search(record.id):return {}
	if not record.get("type","") in ["item","spell","character"] or not record.get("name") is String or record.name.strip_edges().is_empty() or record.name.length()>120:return {}
	if not (record.get("updated") is int or record.get("updated") is float) or not is_finite(float(record.updated)) or record.updated<0:return {}
	var plan := WikiPlan.validate(record.get("plan"))
	if plan.is_empty():return {}
	if record.type!="character":
		if plan.entries.size()!=1 or not String(plan.entries[0].key).begins_with(record.type+"/"):return {}
		plan.entries[0].slot="";plan.entries[0].count=1
	return {"id":record.id,"type":record.type,"name":record.name.strip_edges(),"updated":int(record.updated),"plan":plan}

static func save(name: String,type: String,plan: Dictionary,path: String=PATH) -> Dictionary:
	var state := read(path)
	if state.error:return state
	if state.records.size()>=LIMIT:return {"error":"You can save up to 100 creations. Remove one before saving another."}
	var record := _clean({"id":Crypto.new().generate_random_bytes(16).hex_encode(),"type":type,"name":name,"updated":int(Time.get_unix_time_from_system()*1000),"plan":plan})
	if record.is_empty():return {"error":"This creation is invalid and cannot be saved."}
	state.records.push_front(record)
	return {"error":_write(state.records,path),"record":record}

static func remove(id: String,path: String=PATH) -> String:
	var state := read(path)
	if state.error:return state.error
	return _write(state.records.filter(func(record):return record.id!=id),path)

static func _write(records: Array,path: String) -> String:
	var temporary := path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if not file:return "Local storage is unavailable. Copy a link to keep your creation."
	file.store_string(JSON.stringify({"v":1,"records":records}));file.flush()
	var error := file.get_error();file.close()
	if error!=OK or DirAccess.rename_absolute(temporary,path)!=OK:return "Could not save locally. Check free disk space and copy a link as a backup."
	return ""
