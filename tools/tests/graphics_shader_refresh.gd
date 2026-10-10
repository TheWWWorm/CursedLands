extends Node
## Actual Shader.changed signals distinguish retained programs from recompiles;
## camera-fade copies must keep identity and follow only real source changes.
var checks:=0
var failures:=0
var changed:={"land":0,"water":0,"fade":0}
var rows:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_water":1,"gfx_materials":1,"auto_graphics":0,"vsync":0,"confine_mouse":0},true)
	Gfx.ensure_globals();Gfx.apply_surface_options()
	var land:=Gfx.make_shader(EITerrain.TERRAIN_SHADER,true,true)
	var water:=Gfx.make_shader(EITerrain.WATER_FX_SHADER,true,true)
	var fade:=CameraFade.dither_shader(land)
	var original:=[land.code,water.code,fade.code]
	var ids:=[land.get_rid(),water.get_rid(),fade.get_rid()]
	land.changed.connect(func():changed.land+=1)
	water.changed.connect(func():changed.water+=1)
	fade.changed.connect(func():changed.fade+=1)
	var plan:=[
		[{"gfx_clouds":3},[0,0,0],"sky only"],
		[{"gfx_cloud_shadows":1},[1,1,1],"enable shadows"],
		[{"gfx_cloud_reflections":1},[0,1,0],"add reflections"],
		[{"gfx_cloud_reflections":0},[0,1,0],"remove reflections"],
		[{"gfx_cloud_shadows":0},[1,1,1],"remove shadows"],
		[{"gfx_clouds":1},[0,0,0],"change sky quality"],
		[{"gfx_clouds":0},[0,0,0],"disable sky"]]
	for entry:Array in plan:
		changed={"land":0,"water":0,"fade":0}
		GameData.options.merge(entry[0],true)
		var started:=Time.get_ticks_usec();Gfx.apply_surface_options();var elapsed:=Time.get_ticks_usec()-started
		check([changed.land,changed.water,changed.fade]==entry[1],"recompile only affected live programs: "+entry[2])
		check([land.get_rid(),water.get_rid(),fade.get_rid()]==ids,"shader identities survive: "+entry[2])
		check(CameraFade.dither_shader(land)==fade and fade.code==CameraFade._dither_code(land.code),"existing camera fade tracks live source: "+entry[2])
		rows.append({"case":entry[2],"changes":changed.duplicate(),"apply_us":elapsed})
	check([land.code,water.code,fade.code]==original,"final native programs restore exactly")
	# Batch exercise many visible-material variants without rendering. Report
	# source-generation/parse work only, never present this as GPU/FPS gain.
	var retained:Array[Shader]=[]
	for i in 16:
		var sh:=Gfx.make_shader(EITerrain.TERRAIN_SHADER+"\n// refresh variant "+str(i),true,true)
		retained.append(sh);sh.get_rid()
	var samples:=[];var state:=true
	for i in 24:
		GameData.options.gfx_clouds=3 if state else 1;state=not state
		var start:=Time.get_ticks_usec();Gfx.apply_surface_options();samples.append((Time.get_ticks_usec()-start)/1000.0)
	samples.sort();rows.append({"case":"unchanged-live-variants","count":retained.size()+2,"samples":samples,"median_ms":samples[12]})
	retained.clear();Gfx.clear_clouds();CameraFade._derived.clear();CameraFade._shaders.clear();TexUpscale.shutdown()
	FileAccess.open("user://graphics-shader-refresh.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	print("GRAPHICS_SHADER_REFRESH checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
