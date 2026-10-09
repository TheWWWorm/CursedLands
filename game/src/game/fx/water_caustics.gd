extends RefCounted
## Conservative water coverage for terrain receivers. Each valid texel covers
## its entire bilinear footprint, even at maximum authored wave displacement.
## Uses the immutable, axis-aligned authored Water_x_y meshes. A homogeneous
## material ring supplies a lower surface bound and an upper depth-fade bound;
## narrow pools, mixed liquid edges and steep flows may deliberately lose detail.
## SetWaterLevel remains live through the shared level[] uniform. This is a
## shading mask, never a replacement for collision or the exact contact query.
var texture: ImageTexture
var tiles := 0
var bytes := 0
var admitted := 0
static var _pattern: NoiseTexture2D

func _init(terrain: EITerrain) -> void:
	var size := Vector2i(terrain.sectors_x*16,terrain.sectors_y*16)
	var base := PackedFloat32Array(); base.resize(size.x*size.y); base.fill(INF)
	var owner := PackedInt32Array(); owner.resize(base.size()); owner.fill(-1)
	var high := PackedFloat32Array(); high.resize(base.size()); high.fill(-INF)
	var radius := PackedInt32Array(); radius.resize(64)
	var drop := PackedFloat32Array(); drop.resize(64)
	for m in mini(terrain.materials.size(),64):
		var authored: Dictionary = terrain.materials[m]
		var wave := absf(float(authored.get("wave",0.0)))*EIWaterWaves.AMPLITUDE
		var shore := int(authored.get("type",0)) == 4
		var shift := 128.0/252.0+wave if shore else wave*3.0
		# A texel is centred one metre from its tile edge and has a two-metre
		# filter footprint. The enclosing tile ring must exceed that footprint
		# by the maximum horizontal displacement, including land XY offsets.
		radius[m] = maxi(1,ceili((1.001+shift)/2.0))
		drop[m] = 0.0 if shore else wave*0.25
	for node in terrain.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Water_") or node.mesh == null: continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var materials: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		assert(vertices.size()%9 == 0 and vertices.size() == materials.size())
		for first in range(0,vertices.size(),9):
			var tile := Vector2i(roundi(vertices[first].x/2.0),roundi(-vertices[first].z/2.0))
			assert(tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y)
			var index := tile.y*size.x+tile.x
			var cell := tile.y*2*terrain.sectors_x*32+tile.x*2
			var m := int(materials[first].y+0.5)%64
			if m >= terrain.materials.size(): continue
			var valid := not terrain.liquid_ground[cell] in [13,14,255]
			var emission := terrain.material_e(m)
			valid = valid and emission.r+emission.g+emission.b == 0.0
			var height := INF; var ceiling := -INF
			for corner in 9:
				valid = valid and int(materials[first+corner].y+0.5)%64 == m
				height = minf(height,vertices[first+corner].y)
				ceiling = maxf(ceiling,vertices[first+corner].y)
			base[index] = height
			high[index] = ceiling
			owner[index] = m if valid else -1
			tiles += 1
	var data := PackedFloat32Array(); data.resize(size.x*size.y*4)
	for y in size.y:
		for x in size.x:
			var index := y*size.x+x; var m := owner[index]
			if m < 0: continue
			var reach := radius[m]
			if x < reach or y < reach or x+reach >= size.x or y+reach >= size.y: continue
			var valid := true; var height := INF; var ceiling := -INF
			for dy in range(-reach,reach+1):
				for dx in range(-reach,reach+1):
					var other := (y+dy)*size.x+x+dx
					if owner[other] != m: valid = false; break
					height = minf(height,base[other])
					ceiling = maxf(ceiling,high[other])
				if not valid: break
			if not valid: continue
			data[index*4] = height-drop[m]
			data[index*4+1] = m
			data[index*4+2] = ceiling+drop[m]
			data[index*4+3] = 1.0
			admitted += 1
	bytes = data.size()*4
	texture = ImageTexture.create_from_image(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,data.to_byte_array()))

const SOURCE := """
uniform sampler2D caustic_bed : filter_nearest, repeat_disable;
vec2 bed_value(ivec2 p, float height) {
	ivec2 size = textureSize(caustic_bed,0);
	if (any(lessThan(p,ivec2(0))) || any(greaterThanEqual(p,size))) { return vec2(0.0,-10000.0); }
	vec4 value = texelFetch(caustic_bed,p,0);
	float offset = level[clamp(int(value.y+0.5),0,63)];
	float depth = value.x+offset-height;
	float amount = value.w*smoothstep(0.04,0.25,depth)*exp(-max(value.z+offset-height,0.0)*0.45);
	return vec2(amount,value.w > 0.5 ? depth : -10000.0);
}
vec2 terrain_bed(vec3 position) {
	vec2 grid = vec2(position.x,-position.z)*0.5-0.5;
	ivec2 cell = ivec2(floor(grid));
	vec2 q = fract(grid);
	vec2 a = bed_value(cell,position.y);
	vec2 b = bed_value(cell+ivec2(1,0),position.y);
	vec2 c = bed_value(cell+ivec2(0,1),position.y);
	vec2 d = bed_value(cell+ivec2(1,1),position.y);
	return vec2(mix(mix(a.x,b.x,q.x),mix(c.x,d.x,q.x),q.y),max(max(a.y,b.y),max(c.y,d.y)));
}
"""


## Fractional UV translations keep every component periodic without a clock
## wrap seam. This uses the terrain's scaled, pausable wave clock, never TIME.
static func scroll(seconds: float) -> Vector4:
	return Vector4(fposmod(seconds/61.0,1.0),fposmod(seconds/83.0,1.0),
		fposmod(-seconds/97.0,1.0),fposmod(seconds/53.0,1.0))

static func pattern() -> NoiseTexture2D:
	if _pattern != null: return _pattern
	var noise := FastNoiseLite.new()
	noise.seed = 73621
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.035
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0,0.025,0.13,1.0])
	ramp.colors = PackedColorArray([Color.WHITE,Color.WHITE,Color.BLACK,Color.BLACK])
	_pattern = NoiseTexture2D.new()
	_pattern.width = 256; _pattern.height = 256
	_pattern.seamless = true; _pattern.seamless_blend_skirt = 0.2
	_pattern.generate_mipmaps = true
	_pattern.noise = noise; _pattern.color_ramp = ramp
	return _pattern

const PATTERN := """
uniform sampler2D caustic_pattern : filter_linear_mipmap, repeat_enable;
uniform vec4 caustic_scroll = vec4(0.0);
"""
const APPLY := """
	// Conservative coverage is evaluated at the receiver, so caustics stay
	// on the bed from either side of the water surface. Original underwater
	// attenuation and the existing light/shadow draw still shade this colour.
	float caustic_sun = dot(clamp(ei_sun,vec3(0.0),vec3(1.0)),vec3(0.2126,0.7152,0.0722));
	float caustic_fade = 1.0-smoothstep(35.0,65.0,length(VERTEX));
	if (caustic_sun > 0.001 && dot(ei_sun_dir,ei_sun_dir) > 0.5 && caustic_fade > 0.0) {
		vec2 bed = terrain_bed(wpos);
		vec3 wn = normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
		float amount = bed.x*smoothstep(0.6,0.85,wn.y)*caustic_sun*caustic_fade;
		vec2 p = wpos.xz;
		float a = texture(caustic_pattern,p*0.13+caustic_scroll.xy).r;
		float b = texture(caustic_pattern,vec2(0.8*p.x+0.6*p.y,-0.6*p.x+0.8*p.y)*0.17+caustic_scroll.zw).r;
		c *= 1.0+0.65*min(a+b,1.0)*amount;
	}
"""

static func source(original: String) -> String:
	return original.replace("void vertex() {",SOURCE+PATTERN+"\nvoid vertex() {").replace("\tALBEDO = c;",APPLY+"\tALBEDO = c;")
