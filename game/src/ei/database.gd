class_name EIDatabase
extends RefCounted
## Reader for the game databases in res/database.res (*.idb, *.udb, *.sdb, ...).
## Each file is a tree of (id, length) tagged fields; the schema below maps field
## ids to types and column names (from the community format research in EIrepack).
##
## Field type codes: S string, I int, U uint, F float, X bit flags, f float array,
## i int array, B bool, b bool array, H raw bytes, T time, s string list,
## 1/2/3 fixed composite records, 4/5 nested string/int lists. Space = unused id.

const SCHEMA := {
	"items.idb": [
		["materials", "SSSIFFFIFIFfIX", "name,type,code,id,price,weight,mana,slots,durability,skill,damage,resist,unknown,shops"],
		["weapons", "SSISIIIFFFFIFIXB     IHFFFfHHFF", "name,type,type_id,material_type,unknown,texture1,texture2,price,weight,size,mana,slots,durability,components,shops,deconstructable,actions,unknown2,range,min_damage,max_damage,damage,unknown3,unknown4,attack,defence"],
		["armors", "SSISIIIFFFFIFIXB     ffBUHH", "name,type,type_id,material_type,unknown,texture1,texture2,price,weight,size,mana,slots,durability,components,shops,deconstructable,absorption,absorption2,apply_wounds,layer_order,unknown2,unknown3"],
		["quick_items", "SSISIIIFFFFIFIXB     IIFFSbH", "name,type,unknown,material_type,unknown2,texture1,texture2,price,weight,size,mana,slots,durability,components,shops,deconstructable,item_id,graphics_level,damage,unknown3,spell,modifiers,unknown4"],
		["quest_items", "SSISIIIFFFFIFIXB     Is", "name,type,unknown,material_type,unknown2,texture1,texture2,price,weight,size,mana,slots,durability,components,shops,deconstructable,script_id,zones"],
		["loot_items", "SSISIIIFFFFIFIXB     IHI", "name,type,unknown,material_type,unknown2,texture1,texture2,price,weight,size,mana,slots,durability,components,shops,deconstructable,type_id,unknown3,unknown4"],
	],
	"levers.ldb": [
		["levers", "SfIFTSSS", "name,place,unknown,scale,switch_time,material,switch_sound,text"],
	],
	"perks.pdb": [
		["skills", "SSI       s", "name,code,texture_type,base_attributes"],
		["perks", "SSI       SSIIIFFFIIIIBI", "name,code,texture_type,required_perk,skill_type,skill_type_id,unknown,sl,str,dex,int,cost,modifier,multiplier,add,active,exclusive"],
	],
	"spells.sdb": [
		["spell_prototypes", "SSSFIFIFFFFIIIIUSSIIbIXFFFFF", "name,code,subtype,price,type_id,mana,slots,speed,range,area,effect,target,targets,duration,actions,require_trace,buildin_mods,special_mods,texture_type,subtype_id,mods,complex,shops,red,green,blue,light_radius,fadeout"],
		["spell_modifiers", "SSFIFFISX", "name,code,price,type,mana,value,complex,allod,shops"],
		["spell_templates", " SssSX", "prototype,required,optional,power,shops"],
		["armor_spell_templates", " SssSX", "prototype,required,optional,power,shops"],
		["weapon_spell_templates", " SssSX", "prototype,required,optional,power,shops"],
	],
	"units.udb": [
		["hit_locations", "SffUU", "name,resist,resist2,unknown,unknown2"],
		["race_models", "SUFFUUFfFUUf222222            SssFSsfUUfUUIUSBFUUUU",
			"name,type_id,health_regen,mana_regen,language,locomotion,vision_arc,speeds,attack_distance,ai_stay,ai_lie,attack,head,torso,left_arm,right_arm,left_leg,right_leg,mask,textures,textures2,model_shift,sfx_path,steps_path,anim_speeds,idle_sound_p,attack_sound_p,defence,blood_type,cast_type,footprint_type,leg_segment,skin_type,first_step_right,head_height,unknown,unknown2,unknown3,unknown4"],
		["monster_prototypes", "SSIUIFFFSFFFFFFFFFUFFFFFFff33sfssSFFFFFUFUSF",
			"name,base_race,unknown,skin,hair,complexion_x,complexion_y,complexion_z,unknown2,hp,mana,absorption,tuning_actions,tuning_move,attack_range,to_hit,parry,weapon_weight,weapon_type_id,damage_min,damage_max,general_skills,steal_skills,tame_skills,peripheral_skills,senses,detection,loot,rare_loot,items,skills,spells,wears,weapon,info_scale,altitude,random_hit,dialog_cam_distance,dialog_cam_height,real_weapon_type_id,detonation,base_level,second_weapon,experience"],
		["npcs", "SUFFFFbbssssFUB", "name,unknown,experience,str,dex,int,skills,skills2,perks,weapons,quest_items,spells,exp_to_distribute,money,voice"],
	],
	## Ground marks (the original, "prints.db"), one row per ground type
	## in tiledesc.reg order (grass .. highrock; row 8 is unnamed). Each set is
	## [alpha, life ticks, fade ticks]: "normal" when world is 0, else
	## "alt"; footprints' "track" (field 10) is not
	## read by the decal code.
	"prints.db": [
		["blood_prints", " S11", "name,normal,alt"],
		["foot_prints", " S11      1", "name,normal,alt,track"],
		["fire_prints", " S11", "name,normal,alt"],
	],
	"quests.qdb": [
		# Native objectives read field 5 as float (LiA 57aed0, record +0x14).
		# Reading its bits as an int turned the authored 230 into 1130758144.
		["quests", "SFIISFIs", "name,experience,unknown,zone,comment,money,record,unknown2"],
		["briefings", "SFFsSsssssI", "name,unknown,money,give_items,comment,take_items,give_quests,give_quests2,open_zones,unknown2,bonus"],
	],
}

## table name -> Array[Dictionary]
var tables := {}


static func load_from(archive: EIResArchive, quiet := false) -> EIDatabase:
	var db := EIDatabase.new()
	for file: String in SCHEMA:
		var d := archive.read(file)
		if d.is_empty():
			if not quiet:
				push_warning("database.res has no %s" % file)
			continue
		db._parse_file(d, SCHEMA[file])
	return db


func table(name: String) -> Array:
	return tables.get(name, [])


## First row whose `name` column equals `row_name` (case-insensitive).
func find(table_name: String, row_name: String) -> Dictionary:
	var key := row_name.to_lower()
	var idx: Dictionary = tables.get(table_name + "#index", {})
	return idx.get(key, {})


## Appends `other`'s rows of `table_name` whose name this one lacks.
func merge_missing(other: EIDatabase, table_name: String) -> int:
	var rows: Array = tables.get(table_name, [])
	var idx: Dictionary = tables.get(table_name + "#index", {})
	var n := 0
	for row: Dictionary in other.table(table_name):
		var nm := String(row.get("name", "")).to_lower()
		if nm and not idx.has(nm):
			rows.append(row)
			idx[nm] = row
			n += 1
	tables[table_name] = rows
	tables[table_name + "#index"] = idx
	return n


# ---------------------------------------------------------------- parsing

var _d: PackedByteArray
var _p := 0


func _id_len() -> Vector2i:
	var id := _d[_p]
	var n := _d[_p + 1]
	if n & 1:
		n = _d.decode_u32(_p + 1) - 1
		_p += 5
	else:
		_p += 2
	return Vector2i(id, n / 2)


func _parse_file(d: PackedByteArray, sections: Array) -> void:
	_d = d
	_p = 0
	var root := _id_len()
	var root_end := mini(_p + root.y, d.size())
	for sec: Array in sections:
		# The German GOG spells.sdb ends after spell_modifiers (its root length
		# covers two sections, 10 stray bytes follow): no template tables.
		if _p + 2 > root_end:
			break
		var h := _id_len()
		var end := _p + h.y
		var rows: Array[Dictionary] = []
		var index := {}
		var cols: PackedStringArray = String(sec[2]).split(",")
		while _p < end:
			var vals := _read_record(sec[1])
			var row := {}
			var spec: String = sec[1]
			var col := 0
			for fid in spec.length():
				if spec[fid] == " ":
					continue
				if vals.has(fid) and col < cols.size():
					row[cols[col]] = vals[fid]
				col += 1
			rows.append(row)
			var nm := String(row.get("name", "")).to_lower()
			if nm and not index.has(nm):
				index[nm] = row
		_p = end
		tables[sec[0]] = rows
		tables[sec[0] + "#index"] = index


func _str(n: int) -> String:
	var s := _d.slice(_p, _p + n)
	_p += n
	return EIText.ansi(s)


## Returns field id -> value.
func _read_record(spec: String) -> Dictionary:
	var out := {}
	var h := _id_len()
	var end := _p + h.y
	while _p < end:
		var f := _id_len()
		var start := _p
		var t := spec[f.x] if f.x < spec.length() else "H"
		match t:
			"S": out[f.x] = (_str(f.y))
			"I": out[f.x] = (_d.decode_s32(_p))
			"U", "T": out[f.x] = (_d.decode_u32(_p))
			"F": out[f.x] = (_d.decode_float(_p))
			"B": out[f.x] = (_d[_p] != 0)
			"f": out[f.x] = (_d.slice(_p, _p + f.y).to_float32_array())
			"i": out[f.x] = (_d.slice(_p, _p + f.y).to_int32_array())
			"b": out[f.x] = (_d.slice(_p, _p + f.y))
			"X": out[f.x] = (_d.decode_u32(_p))
			"s":
				var list := PackedStringArray()
				while _p < start + f.y:
					var s := _id_len()
					list.append(_str(s.y))
				out[f.x] = (list)
			"1", "2", "3":
				var sub_spec: String = {"1": "FII", "2": "SUFF", "3": "FFFF"}[t]
				var sub := []
				for c in sub_spec:
					if _p >= start + f.y:
						break
					var s := _id_len()
					match c:
						"S": sub.append(_str(s.y))
						"F": sub.append(_d.decode_float(_p))
						"I": sub.append(_d.decode_s32(_p))
						"U": sub.append(_d.decode_u32(_p))
					_p += 0 if c == "S" else s.y
				out[f.x] = (sub)
			_:
				out[f.x] = (_d.slice(_p, _p + f.y))
		_p = start + f.y
	_p = end
	return out
