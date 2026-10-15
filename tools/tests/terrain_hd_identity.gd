extends Node
const Cliffs=preload("res://src/game/fx/terrain_cliff.gd")
const Transitions=preload("res://src/game/fx/terrain_transition.gd")
func _ready()->void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"gfx_terrain":2,"gfx_terrain_cliffs":1,"gfx_hd_textures":0},true)
	var rows:=[];var baseline:={};var failures:=0;var checks:=0
	for hd in [false,true]:
		if hd:
			var error:=ModStore.create_profile("HD terrain identity probe",false,["community.hd-lands-textures@1.5.0"])
			if not error.is_empty():printerr("FAIL ",error);get_tree().quit(1);return
			if not GameData.open(GameData.root).is_empty():get_tree().quit(1);return
		for map:String in ["zone1","zone2"]:
			var t:=EITerrain.load_map(map);add_child(t);t.set_process(false)
			var cliffs:=Cliffs.new(t);var transitions:=Transitions.new(t)
			var row:={"hd":hd,"map":map,"texture_width":GameData.load_image(t.resource_prefix+"000").get_width(),"cliffs":cliffs.admitted,"transitions":transitions.admitted}
			if not hd:baseline[map]={"cliffs":cliffs.eligible,"transitions":transitions.rows,"cliff_count":cliffs.admitted,"transition_count":transitions.admitted}
			else:
				for ok:bool in [cliffs.admitted>0,transitions.admitted>0,cliffs.eligible==baseline[map].cliffs,transitions.rows==baseline[map].transitions,row.texture_width>512,GameData.load_original_image(t.resource_prefix+"000").get_width()==512,t._atlases.get_width()==2048]:
					checks+=1
					if not ok:failures+=1;printerr("FAIL terrain atlas identity ",map)
			rows.append(row);print("HD_TERRAIN ",JSON.stringify(row));t.free()
	FileAccess.open("user://hd-terrain-identity.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"  "))
	TexUpscale.shutdown();print("HD_TERRAIN_IDENTITY ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
