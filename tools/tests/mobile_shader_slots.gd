extends Node
## Compile the real composed shaders, including the largest water/fog variant.
## Run on the physical Mobile backend as well as desktop/Compatibility.
func _ready()->void:
	var count:=0
	var sources:=[
		[EITerrain.TERRAIN_SHADER,true],[EITerrain.WATER_SHADER,true],
		[EITerrain.WATER_FX_SHADER,true],[EIFigure.FOLIAGE_SHADER,false],
		[EIFigure.OBJECT_SHADER,false],[EIUnitModel.UNIT_SHADER,false],
		[TerrainDetails.GRASS_SHADER,true]]
	for fog in [false,true]:
		Gfx._vol_fog=fog
		for row:Array in sources:
			var s:=Gfx.make_shader(String(row[0]),true,bool(row[1]))
			var uniforms:=s.get_shader_uniform_list()
			if uniforms.is_empty():
				push_error("Actual composed shader failed, case "+str(count))
				get_tree().quit(1);return
			count+=1
	print("MOBILE_SHADER_SLOTS ",count," actual shader variants compiled")
	Gfx._vol_fog=false
	get_tree().quit()
