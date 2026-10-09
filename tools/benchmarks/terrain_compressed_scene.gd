extends "terrain_atlas_scene.gd"
## The authored-RGBA control distinguishes expected BC decoding differences
## from array/material/sampler mistakes. Baseline packs show regenerated mips.
var _prepared := false

func stats(texture: TextureLayered) -> Dictionary:
	var result := super.stats(texture)
	if result.is_empty(): return result
	result["format"] = texture.get_format()
	if texture.get_format() in [Image.FORMAT_DXT1,Image.FORMAT_DXT3]:
		var block := 8 if texture.get_format() == Image.FORMAT_DXT1 else 16
		var w := texture.get_width(); var h := texture.get_height(); var bytes := 0
		result.top_bytes = ((w+3)/4)*((h+3)/4)*block*texture.get_layers()
		while true:
			bytes += ((w+3)/4)*((h+3)/4)*block
			if w == 1 and h == 1: break
			w = maxi(1,w>>1); h = maxi(1,h>>1)
		result.mip_bytes = bytes*texture.get_layers()
	return result

func capture(view: SubViewport, camera: Camera3D, center: Vector3, label: String, warm: int) -> void:
	if not _prepared:
		_prepared = true
		var blocks := OS.get_cmdline_user_args().has("--atlas-decoded-blocks")
		if blocks or OS.get_cmdline_user_args().has("--atlas-authored-rgba"):
			for child in view.get_children():
				if not child is EITerrain: continue
				var terrain := child as EITerrain
				var images: Array[Image] = []
				for i in int(terrain.get_meta("textures_count")):
					var pixels := EIMmp.decode_texture(GameData.textures.read("%s%03d.mmp" % [terrain.resource_prefix,i]),
						blocks and RenderingServer.has_os_feature("s3tc"))
					if pixels.is_compressed(): pixels.decompress()
					pixels.convert(Image.FORMAT_RGBA8); images.append(pixels)
				var texture := Texture2DArray.new(); texture.create_from_images(images)
				terrain._atlases = texture; terrain.apply_gfx()
	await super.capture(view,camera,center,label,warm)

func liquid_focus(terrain: EITerrain) -> Vector3:
	# Seek an actually visible liquid surface, not a buried water-grid entry.
	var width := terrain.sectors_x*EITerrain.SECTOR
	var center := terrain.size_ei()*0.5
	var best := Vector3(INF,INF,INF); var distance := INF
	for i in terrain.water_base.size():
		var level := terrain.water_base[i]
		if not is_finite(level): continue
		var x := float(i%width)+0.5; var y := float(i/width)+0.5
		if level < terrain.height_at(x,y)+0.15: continue
		var d := Vector2(x,y).distance_squared_to(center)
		if d < distance: distance = d; best = Vector3(x,level,-y)
	return best
