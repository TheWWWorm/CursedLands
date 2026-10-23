class_name AstralPatches
extends RefCounted
## The official LiA 1.02 behavior is part of the remake. Corrections are
## applied in memory to recognized original data, before remake/mod changes.
const DATA := preload("res://src/ei/astral_patch_data.gd").DATA
const META := &"astral_official_patch"


static func fingerprint(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()


static func _bytes(data: PackedByteArray, patch: Dictionary) -> PackedByteArray:
	if patch.is_empty() or fingerprint(data) != patch.before: return data
	var out := PackedByteArray()
	var cursor := 0
	for edit: Array in patch.edits:
		var at := int(edit[0])
		out.append_array(data.slice(cursor,at))
		out.append_array(Marshalls.base64_to_raw(edit[2]))
		cursor = at+int(edit[1])
	out.append_array(data.slice(cursor))
	if out.size() != int(patch.size) or fingerprint(out) != patch.after:
		push_error("LiA built-in patch failed its output fingerprint")
		return data
	return out


static func database_entry(name: String, data: PackedByteArray) -> PackedByteArray:
	return _bytes(data,DATA.database.get(name.to_lower(),{}))


static func map_file(path: String, data: PackedByteArray) -> PackedByteArray:
	return _bytes(data,DATA.files.get(path.to_lower(),{}))


static func text(key: String, original: String) -> String:
	var patch: Dictionary = DATA.texts.get(key,{})
	if patch.is_empty():return original
	var source := original.sha256_text()
	var result := original
	if source!=patch.canonical:
		if not patch.variants.has(source):return original
		var cursor := 0
		result=""
		for edit: Array in patch.variants[source]:
			result+=original.substr(cursor,int(edit[0])-cursor)+String(edit[2])
			cursor=int(edit[0])+int(edit[1])
		result+=original.substr(cursor)
		if result.sha256_text()!=patch.canonical:
			push_error("LiA built-in text patch failed its output fingerprint: "+key)
			return original
	match key:
		"unit zone3_human_citizen_f":return RemakeText.t("Poor townswoman")+"\n"
		"unit zone3_human_citizen_m":return RemakeText.t("Destitute townsman")+"\n"
		"litem gepard_3":return RemakeText.t("Mature cheetah hide\nA townsman could decorate his home with this hide.")+"\n"
		"quest q10j","quest q11k","quest q13h","quest q18j":
			return RemakeText.t(WikiWorldText.TEXTS[key].en)
	return result


static func snapshot(ast: ScriptParser) -> Dictionary:
	return {"globals":ast.globals,"declares":ast.declares,"scripts":ast.scripts,"world":ast.world}


static func script_fingerprint(ast: ScriptParser) -> String:
	return JSON.stringify(snapshot(ast),"",true,true).sha256_text()


static func apply_script(ast: ScriptParser, zone: String) -> void:
	if not DATA.scripts.has(zone) or ast.has_meta(META): return
	var patch: Dictionary = DATA.scripts[zone]
	var source := script_fingerprint(ast)
	if source != patch.canonical:
		if not patch.variants.has(source): return
		var changed := snapshot(ast).duplicate(true)
		for edit: Array in patch.variants[source].edits:
			var path: Array = edit[1]
			var parent: Variant = changed
			var limit := path.size() if edit[0]=="splice" else path.size()-1
			for i in limit: parent=parent[path[i]]
			match String(edit[0]):
				"set": parent[path.back()]=edit[2].duplicate(true) if edit[2] is Array or edit[2] is Dictionary else edit[2]
				"erase": parent.erase(path.back())
				"splice":
					for i in int(edit[3]):parent.remove_at(int(edit[2]))
					for i in range(edit[4].size()-1,-1,-1):parent.insert(int(edit[2]),edit[4][i].duplicate(true) if edit[4][i] is Array or edit[4][i] is Dictionary else edit[4][i])
		if JSON.stringify(changed,"",true,true).sha256_text() != patch.canonical:
			push_error("LiA built-in script patch failed its output fingerprint: "+zone)
			return
		ast.globals=changed.globals;ast.declares=changed.declares
		ast.scripts=changed.scripts;ast.world=changed.world
	ast.set_meta(META,{"source":source,"zone":zone,"canonical":patch.canonical,"revision":int(DATA.revision)})
