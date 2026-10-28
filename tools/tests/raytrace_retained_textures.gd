extends Node
## Cold unit albedo/material images must use the exact CPU-authored upload,
## without a synchronous GPU readback. Native getters remain the pixel oracle.
const Model=preload("res://src/ei/unit_model.gd")
const Cache=preload("res://src/game/fx/raytrace_source_cache.gd")
const SOURCE_PATH="res://src/game/fx/raytrace_texture_source.gd"
const SOURCE_BUDGET=64*1024*1024
var source_script: Script
var checks:=0
var failures:=0

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func readbacks(cache: RefCounted) -> int:
	for property in cache.get_property_list():
		if property.name=="image_readbacks":return int(cache.get("image_readbacks"))
	# The old implementation reads the texture on every image cache miss.
	return int(cache.get("misses"))

func remember(texture: ImageTexture,image: Image) -> void:
	if source_script:source_script.call("remember",texture,image)

func same(a: Image,b: Image) -> bool:
	return a!=null and b!=null and a.get_size()==b.get_size() and a.get_format()==b.get_format() \
		and a.get_mipmap_count()==b.get_mipmap_count() and a.get_data()==b.get_data()

func normalized(texture: Texture2D,size:=32) -> Image:
	var image:=texture.get_image().duplicate() as Image
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	image.resize(size,size,Image.INTERPOLATE_BILINEAR);image.generate_mipmaps()
	return image

func pattern(size: Vector2i,tint:=0) -> Image:
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			image.set_pixel(x,y,Color(float((x*13+tint)%256)/255.0,float((y*29+tint)%256)/255.0,
				float((x*17+y*11+tint)%256)/255.0,float((x*23+y*31+tint)%256)/255.0))
	image.generate_mipmaps();return image

func probe(texture: Texture2D,label: String) -> void:
	check(texture!=null,label+" authored composition is available")
	if texture==null:return
	var cache:=Cache.new();var image:=cache.image(texture,-1,32)
	check(readbacks(cache)==0,label+" cold PT admission performs no GPU texture readback")
	check(same(image,normalized(texture)),label+" normalized pixels and every mip exactly match native GPU data")
	var retained: Image=source_script.call("image",texture) if source_script else null
	check(retained==null or same(retained,texture.get_image()),label+" any retained upload preserves all original pixels and mips")
	cache.clear()

func edit(texture: ImageTexture,image: Image) -> void:
	texture.update(image)

func _ready() -> void:run.call_deferred()

func run() -> void:
	if ResourceLoader.exists(SOURCE_PATH):source_script=load(SOURCE_PATH)
	var native:=DisplayServer.get_name()!="headless"
	# Dummy texture_2d_update is empty and texture_replace discards its input.
	# Headless covers their Resource notifications; rendered runs additionally
	# require the exact changed GPU pixels, which Dummy cannot represent.
	print("RT_RETAINED_TEXTURE_EDIT_MODE ","native update and replacement" if native else "headless setter invalidation; Dummy pixels immutable")
	for row: Array in [["unanwiba","bat00",Vector3(.08,.92,0)],["unorma","skin_00",Vector3(.08,.92,0)],
		["unorma","ax_01.sl.0",Vector3(.19,.84,0)]]:
		var layers: Array[String]=[row[1]];var profiles: Array[Vector3]=[row[2]]
		probe(Model._compose(row[0],layers),row[0]+" "+row[1]+" albedo")
		probe(Model._compose_surface(row[0],layers,profiles),row[0]+" "+row[1]+" surface")
	var original:=pattern(Vector2i(16,8))
	# The independent upload copy also models GPU ownership in Dummy storage.
	var texture:=ImageTexture.create_from_image(original.duplicate() as Image);remember(texture,original)
	var cache:=Cache.new();var initial:=cache.image(texture,-1,32)
	check(readbacks(cache)==0 and same(initial,normalized(texture)),"synthetic alpha/color pattern retains exact cold normalized data")
	original.fill(Color.GREEN);original.generate_mipmaps();cache.clear()
	var isolated:=cache.image(texture,-1,32)
	check(same(isolated,initial) and same(isolated,normalized(texture)),"mutating the source Image cannot replace pixels that were uploaded earlier")
	var replacement:=pattern(Vector2i(16,8),97);var before:=readbacks(cache)
	edit(texture,replacement)
	var updated:=cache.image(texture,-1,32)
	check(readbacks(cache)==before+1 and not texture.has_meta(&"ei_cpu_raytrace_image") and same(updated,normalized(texture)),
		"same-size native texture update invalidates retained and normalized images")
	check(not native or (same(texture.get_image(),replacement) and not same(updated,initial)),"native updated GPU pixels and mips actually change (requires rendered backend)")
	remember(texture,texture.get_image());cache.clear();cache.image(texture,-1,32)
	var resized:=pattern(Vector2i(8,16),43);before=readbacks(cache);texture.set_image(resized)
	var current:=cache.image(texture,-1,32)
	check(readbacks(cache)==before+1 and not texture.has_meta(&"ei_cpu_raytrace_image") and same(current,normalized(texture)),
		"set_image replacement invalidates size, content and retained ownership")
	check(same(initial,isolated),"live texture edits leave previously packed snapshots immutable")
	var original_current:=texture.get_image().duplicate() as Image
	remember(texture,original_current)
	var clone:=texture.duplicate() as ImageTexture;var clone_cache:=Cache.new()
	var copied:=clone_cache.image(clone,-1,32)
	check(readbacks(clone_cache)==1 and same(copied,normalized(clone)),"cloned metadata cannot claim another texture's CPU upload")
	var clone_pixels:=pattern(clone.get_size(),131);edit(clone,clone_pixels)
	copied=clone_cache.image(clone,-1,32)
	check(readbacks(clone_cache)==2 and same(copied,normalized(clone)) and same(texture.get_image(),original_current)
		and (not native or same(clone.get_image(),clone_pixels)),
		"clone updates stay current and do not invalidate the original texture")
	var disabled:=Cache.new();disabled._enabled=false
	var first:=disabled.image(texture,-1,32);var second:=disabled.image(texture,-1,32)
	check(readbacks(disabled)==2 and same(first,second) and same(first,normalized(texture)),"disabled source cache still forces actual texture reads")
	var generic:=ImageTexture.create_from_image(pattern(Vector2i(4,4),19));var ordinary:=Cache.new()
	check(same(ordinary.image(generic,-1,32),normalized(generic)) and readbacks(ordinary)==1,"generic textures keep the current native getter")
	var hd:=TexUpscale.texture_2d(pattern(Vector2i(8,8),37),true);var hd_cache:=Cache.new()
	check(same(hd_cache.image(hd,-1,32),normalized(hd)) and readbacks(hd_cache)==1 and not hd.has_meta(&"ei_cpu_raytrace_image"),
		"GPU-upscaled HD output retains its existing exact-pixel fallback")
	var life_pixels:=pattern(Vector2i(4,4));var life:=ImageTexture.create_from_image(life_pixels)
	remember(life,life_pixels);var life_cache:=Cache.new();life_cache.image(life,-1,16)
	var id:=life.get_instance_id();var owner: WeakRef = weakref(life);life=null
	check(owner.get_ref()==null,"retained image and cache watches do not keep the texture owner alive")
	if source_script:source_script.call("memory_stats")
	life_cache._erase(id)
	check(life_cache._bytes==0 and life_cache._entries.is_empty(),"expired texture releases normalized cache accounting")
	budget_controls()
	cache.clear();clone_cache.clear();disabled.clear();ordinary.clear();hd_cache.clear()
	if source_script:source_script.call("clear")
	print("RT_RETAINED_TEXTURES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func budget_controls() -> void:
	var labels:=["retained image storage obeys its explicit64MiB packed-byte budget",
		"budget pressure evicts the oldest retained texture without changing GPU pixels",
		"the newest retained texture avoids readback after budget pressure",
		"budget eviction and repeated clear remove all retention watches and accounting"]
	if not source_script:
		for label: String in labels:check(true,label+" (unfixed path retains no images)")
		return
	source_script.call("clear")
	var pixels:=Image.create(512,512,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.4,.7,.6));pixels.generate_mipmaps()
	var bytes:=pixels.get_data().size();var count:=int(SOURCE_BUDGET/bytes)+1
	var textures: Array[ImageTexture]=[]
	for i in count:
		var texture:=ImageTexture.create_from_image(pixels);remember(texture,pixels);textures.append(texture)
	var stats: Dictionary=source_script.call("memory_stats")
	check(stats.max_bytes==SOURCE_BUDGET and stats.packed_bytes<=SOURCE_BUDGET and stats.textures==count-1,labels[0])
	var evicted:=Cache.new();var old:=evicted.image(textures[0],-1,16)
	check(readbacks(evicted)==1 and not textures[0].has_meta(&"ei_cpu_raytrace_image") and same(old,normalized(textures[0],16)),labels[1])
	var latest:=Cache.new();var recent:=latest.image(textures[-1],-1,16)
	check(readbacks(latest)==0 and same(recent,normalized(textures[-1],16)),labels[2])
	source_script.call("clear");source_script.call("clear");stats=source_script.call("memory_stats")
	check(stats.textures==0 and stats.packed_bytes==0 and textures.all(func(t: ImageTexture):return not t.has_meta(&"ei_cpu_raytrace_image")),labels[3])
	print("RT_RETAINED_TEXTURE_MEMORY ",{"limit":SOURCE_BUDGET,"source_bytes":bytes,"attempted_textures":count,"retained_before_clear":count-1})
	evicted.clear();latest.clear();textures.clear()
