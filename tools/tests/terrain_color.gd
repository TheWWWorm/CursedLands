extends Node
var checks:=0
var failures:=0
var images:Array[Image]=[]
var tiles:=PackedInt32Array()
var linear:=false

class BakeJob extends RefCounted:
	var field:RefCounted
	var sector:Vector2i
	var image:Image
	func run()->void:image=field.bake(sector,16)

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)

func texel(image:Image,x:int,y:int)->Color:
	var colour:=image.get_pixel(clampi(x,0,image.get_width()-1),clampi(y,0,image.get_height()-1))
	return colour.srgb_to_linear() if linear else colour

func tile_sample(cell:Vector2i,p:Vector2)->Color:
	var code:=tiles[clampi(cell.y,0,31)*32+clampi(cell.x,0,31)]
	var q:=p-Vector2(.5,.5)
	match (code>>14)&3:
		1:q=Vector2(-q.y,q.x)
		2:q=-q
		3:q=Vector2(q.y,-q.x)
	var local:=(Vector2(.25,.25)+(Vector2(.5,.5)+q)*.5).clamp(Vector2.ZERO,Vector2.ONE)
	local.y=1.0-local.y
	var tile:=code&63
	var uv:=(Vector2(tile%4,3-tile/4)+(local+Vector2(.125,.125))/1.25)/4.0
	var image:=images[(code>>6)&255]
	var point:=uv*Vector2(image.get_size())-Vector2(.5,.5)
	var at:=Vector2i(point.floor());var fraction:=point-Vector2(at)
	return texel(image,at.x,at.y).lerp(texel(image,at.x+1,at.y),fraction.x).lerp(texel(image,at.x,at.y+1).lerp(texel(image,at.x+1,at.y+1),fraction.x),fraction.y)

func ground(point:Vector2)->Color:
	var cell:=Vector2i(point.floor());var p:=point-Vector2(cell)
	var weight:=Vector2(.5*(1.0-smoothstep(0,.12,minf(p.x,1-p.x))),.5*(1.0-smoothstep(0,.12,minf(p.y,1-p.y))))
	var step:=Vector2i(-1 if p.x<.5 else 1,-1 if p.y<.5 else 1)
	var a:=tile_sample(cell,p)
	if weight.x>0:a=a.lerp(tile_sample(cell+Vector2i(step.x,0),p-Vector2(step.x,0)),weight.x)
	if weight.y>0:
		var b:=tile_sample(cell+Vector2i(0,step.y),p-Vector2(0,step.y))
		if weight.x>0:b=b.lerp(tile_sample(cell+step,p-Vector2(step)),weight.x)
		a=a.lerp(b,weight.y)
	return a

func _ready()->void:
	var field:RefCounted=ClassDB.instantiate("TerrainColorField")
	for layer in 2:
		var image:=Image.create(128,128,false,Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:image.set_pixel(x,y,Color(float((x*13+y*7+layer*51)%256)/255.0,float((x*3+y*19)%256)/255.0,float((x+y+layer*87)%256)/255.0))
		image=EITerrain.padded_atlas(image,32,4);image.generate_mipmaps();images.append(image)
	tiles.resize(32*32)
	for i in tiles.size():tiles[i]=(i%16)|((i%2)<<6)|((i%4)<<14)
	check(field.configure(images,tiles,Vector2i(32,32),128,32,4,false),"configure padded atlas snapshots")
	check(field.memory_bytes()==2*160*160*3+32*32*4,"owned RGB bytes, no float expansion")
	var rng:=RandomNumberGenerator.new();rng.seed=178954
	for i in 1500:
		var p:=Vector2(rng.randf_range(-1,33),rng.randf_range(-1,33))
		var expected:=ground(p);var actual:Color=field.sample(p)
		check(Vector3(expected.r,expected.g,expected.b).distance_to(Vector3(actual.r,actual.g,actual.b))<0.0005,"ground colour, rotation and edges "+str(i))
	var tasks:=[];var jobs:Array[BakeJob]=[];var started:=Time.get_ticks_usec()
	for sector in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i.ONE]:
		var job:=BakeJob.new();job.field=field;job.sector=sector;jobs.append(job)
		tasks.append(WorkerThreadPool.add_task(job.run))
	for task in tasks:WorkerThreadPool.wait_for_task_completion(task)
	var elapsed:=Time.get_ticks_usec()-started
	for job in jobs:
		check(job.image!=null and job.image.get_size()==Vector2i(288,288) and job.image.has_mipmaps(),"owned worker image with mipmaps")
		for i in 200:
			var at:=Vector2i(rng.randi_range(0,287),rng.randi_range(0,287))
			var p:=Vector2(job.sector*16-Vector2i.ONE)+(Vector2(at)+Vector2(.5,.5))/16.0
			var expected:=ground(p);var actual:=job.image.get_pixelv(at)
			check(maxf(maxf(absf(actual.r-expected.r),absf(actual.g-expected.g)),absf(actual.b-expected.b))<.0021,"baked texel precision")
	for y in 288:
		check(jobs[0].image.get_pixel(272,y)==jobs[1].image.get_pixel(16,y),"shared sector gutter exact")
	check(field.bake(Vector2i(-1,0),48)==null and field.bake(Vector2i.ZERO,10000)==null,"invalid bounds rejected")
	check(field.bake(Vector2i(2147483647,2147483647),48)==null,"extreme sector rejected before multiplication")
	var bad:RefCounted=ClassDB.instantiate("TerrainColorField")
	check(not bad.configure(images,tiles,Vector2i(0,32),128,32,4,false),"invalid map rejected")
	check(not bad.configure(images,tiles,Vector2i(32,32),2147483646,18,4,false),"extreme atlas layout rejected before multiplication")
	# Vulkan decodes source-color textures before interpolation. The native
	# builder must blend in that same space, then encode its output texture.
	linear=true
	var linear_field:RefCounted=ClassDB.instantiate("TerrainColorField")
	check(linear_field.configure(images,tiles,Vector2i(32,32),128,32,4,true),"linear texture sampling configured")
	for i in 500:
		var p:=Vector2(rng.randf_range(-1,33),rng.randf_range(-1,33))
		var expected:=ground(p);var actual:Color=linear_field.sample(p)
		check(Vector3(expected.r,expected.g,expected.b).distance_to(Vector3(actual.r,actual.g,actual.b))<.0005,"linear ground blend")
	var linear_image:Image=linear_field.bake(Vector2i.ZERO,16)
	check(linear_image!=null and linear_image.has_mipmaps(),"linear bake ready for source-color texture")
	for i in 200:
		var at:=Vector2i(rng.randi_range(0,287),rng.randi_range(0,287))
		var p:=-Vector2.ONE+(Vector2(at)+Vector2(.5,.5))/16.0
		var expected:=ground(p).linear_to_srgb();var actual:=linear_image.get_pixelv(at)
		check(maxf(maxf(absf(actual.r-expected.r),absf(actual.g-expected.g)),absf(actual.b-expected.b))<.0021,"linear blend encoded to output sRGB")
	print("TERRAIN_COLOR checks=",checks," failures=",failures," workers_us=",elapsed)
	get_tree().quit(1 if failures else 0)
