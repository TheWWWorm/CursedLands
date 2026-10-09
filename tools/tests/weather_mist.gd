extends Node
## Actual archive water masks, scene/clock ownership and native fog controls.
const Mist = preload("res://src/game/fx/weather_mist.gd")
const Sources = preload("res://src/game/fx/weather_mist_sources.gd")
var checks:=0
var failures:=0
var rows:=[]
var campaign: CampaignMap
var view: SubViewport
var world: GameWorld
var camera: Camera3D
var environment: Environment
var seconds:=10.0
var hours:=6.0
var focus:=Vector2.ZERO
var requested_type:=0
var actors: Array[EIUnitModel]=[]
var update_costs:=PackedInt64Array()
var source_costs:=PackedInt64Array()
var low_angle:=false
var through_actor: EIUnitModel
var through_source:={}


func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)


func rules() -> void:
	check(Mist.available(true,true,"forward_plus"),"Forward+ with both options permits mist")
	check(not Mist.available(true,true,"mobile") and not Mist.available(true,true,"gl_compatibility"),"unsupported renderers create no mist")
	check(not Mist.available(false,true,"forward_plus") and not Mist.available(true,false,"forward_plus"),"either option disables mist")
	check(Mist.morning(6.0)==1.0 and Mist.morning(12.0)==0.0 and Mist.morning(2.0)==0.0,"reference day-zero morning rises and burns off")
	var mornings:=[]
	for day in 20: mornings.append(Mist.morning(day*24.0+6.0))
	check(mornings.has(0.0) and mornings.has(1.0),"deterministic day chance avoids fog every morning")
	check(Mist.density_weights(12.0,0.0).x==0.0 and Mist.density_weights(12.0,1.0).x>0.0,"rain leaves water mist after clear noon")
	check(Mist.density_weights(12.0,0.0).y>0.0,"verified swamp permits a small persistent component")
	var horizontal:=3.0*Sources.CELL*sqrt(2.0)
	var vertical:=Mist.MAX_VOLUMES*Sources.MAX_HEIGHT
	var depth:=Mist.MAX_DENSITY*sqrt(horizontal*horizontal+vertical*vertical)
	check(depth<=1.000001 and 1.0-exp(-depth)<0.633,"all six boxes obey the conservative long-ray opacity ceiling")
	var bounded:=true
	for i in 480:
		for wet in [0.0,0.1,0.5,1.0]:
			var value:=Mist.density_weights(i*0.5,wet)
			bounded=bounded and value.x>=0 and value.x<=1 and value.y>=0 and value.y<=1
	check(bounded,"all tested weather and daily weights preserve the opacity ceiling")
	var code:=""
	for line: String in Mist.SHADER.split("\n"): code+=line.get_slice("//",0)+"\n"
	check(not code.contains("TIME") and code.contains("EMISSION=vec3(0.0)"),"mist shader has no real-time or emissive light source")
	rows.append({"case":"policy","mornings":mornings,"max_density":Mist.MAX_DENSITY,"max_optical_depth":depth,"opacity_bound":1.0-exp(-depth)})


func load_world(id: String, scenery:=false) -> bool:
	if is_instance_valid(world): world.free()
	world=GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.zone=campaign.zone(id)
	check(not world.zone.is_empty(),"actual zone "+id)
	if world.zone.is_empty(): return false
	var map: EIMapScene
	if scenery: map=EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false)
	else:
		map=EIMapScene.new(); map.terrain=EITerrain.load_map(world.zone.mpr)
		if map.terrain: map.add_child(map.terrain)
	check(map!=null and map.terrain!=null,"actual terrain "+id)
	if map==null or map.terrain==null: return false
	world.add_child(map); world.map=map; world.terrain=map.terrain; world.terrain.set_process(false)
	if world.terrain._water_mat: world.terrain._water_mat.set_shader_parameter("waves",0.0)
	return true


func build(sources: Sources,key: Vector2i) -> Dictionary:
	sources.begin(key)
	while not sources.advance(): pass
	return sources.result()


func census() -> void:
	var ids:=["gz4g","gz1g","bz7g","gz11k","gz18h"] if GameData.campaign_id==CampaignProfile.ORIGINAL else ["gz9g","gz7d1"]
	for id: String in ids:
		if not load_world(id): continue
		var source:=Sources.new(world.terrain)
		check(source.field.boxes.is_empty() and source.field.trees.is_empty(),"mist avoids duplicate map-wide scenery index "+id)
		var size:=Vector2i(world.terrain.size_ei()); var kinds:={}; var wet:=0; var nav_only:=0; var chosen:=Vector2.INF
		for y in range(4,size.y-4,8):
			for x in range(4,size.x-4,8):
				var p:=Vector2(x,y); var hit:=source.source(p)
				var ground:=source.field.ground(p)
				if not hit.is_empty():
					kinds[hit.type]=int(kinds.get(hit.type,0))+1; wet+=1
					if not chosen.is_finite() and x>24 and y>24 and x<size.x-24 and y<size.y-24: chosen=p
				elif not ground.is_empty() and world.terrain.water_at(x,y)>float(ground.height)+0.06 and source.field.liquid(p).is_empty(): nav_only+=1
		if source.field.biome=="cave": check(wet==0 and not source.allowed(),"cave liquids never create outdoor mist "+id)
		if source.field.biome=="ingos": check(not kinds.has(6),"Ingos does not inherit open-water evaporation")
		if id in ["gz4g","gz1g","gz9g"]: check(wet>0,"actual outdoor liquid admits mist "+id)
		var source_texels:=0
		if chosen.is_finite():
			var cell:=Vector2i((chosen/Sources.CELL).floor()); var result:=build(source,cell)
			if not result.is_empty():
				source_texels=int(result.count); var correct:=true; var image: Image=result.image
				for y in Sources.GRID:
					for x in Sources.GRID:
						var texel:=image.get_pixel(x,y)
						if texel.a==0.0: continue
						var p:=Vector2(cell)*Sources.CELL+(Vector2(x,y)+Vector2.ONE*0.5)*Sources.STEP
						var hit:=source.source(p)
						correct=correct and not hit.is_empty() and absf(float(hit.get("height",INF))-texel.b)<0.001
				check(correct,"mask stores only verified liquid heights "+id)
			var first:=source.source(chosen); var material:=int(first.material); var before:=float(first.height)
			var old:=float(world.terrain.water_offsets.get(material,0.0))
			world.terrain.set_water_offset(material,old+0.75); source.field.refresh()
			var raised:=source.source(chosen)
			check(not raised.is_empty() and absf(float(raised.height)-before-0.75)<0.001,"scripted offsets move actual source height "+id)
			world.terrain.set_water_offset(material,old); source.field.refresh()
		check(source.field._water._sectors.size()<=16,"liquid geometry query cache is bounded "+id)
		rows.append({"case":"sources","zone":id,"biome":source.field.biome,"verified_samples":wet,"kinds":kinds,"navigation_wet_drawn_dry":nav_only,"mask_texels":source_texels})


func tick(mist: Mist, intensity:=0.0, delta:=0.055) -> void:
	seconds+=delta; hours+=delta/CampaignState.HOUR_SECONDS
	var building:=mist.sources!=null and mist.sources.building; var started:=Time.get_ticks_usec()
	mist.step(world,focus,seconds,hours,intensity,Vector4(0.8,0.6,0.5,0.7))
	update_costs.append(Time.get_ticks_usec()-started)
	if building and mist.sources!=null: source_costs.append(mist.sources.last_build_us)


func settle(mist: Mist) -> void:
	var origin:=Vector2i((focus/Sources.CELL).floor()); var wanted:=[]
	for y in range(origin.y-1,origin.y+2):
		for x in range(origin.x-1,origin.x+2):
			var key:=Vector2i(x,y)
			if focus.distance_to((Vector2(key)+Vector2.ONE*0.5)*Sources.CELL)<Mist.RANGE: wanted.append(key)
	for i in 650:
		tick(mist)
		var ready:=not mist.sources.building
		for key: Vector2i in wanted: ready=ready and mist.cache.has(key)
		if ready: break
	for i in 25: tick(mist)


func choose(source: Sources) -> Dictionary:
	var size:=Vector2i(world.terrain.size_ei()/Sources.CELL)
	var cells:=[]
	for y in range(1,size.y-1):
		for x in range(1,size.x-1): cells.append(Vector2i(x,y))
	cells.sort_custom(func(a,b): return Vector2(a).distance_squared_to(Vector2(size)*0.5)<Vector2(b).distance_squared_to(Vector2(size)*0.5))
	for key: Vector2i in cells:
		var result:=build(source,key)
		if result.is_empty() or int(result.count)<12: continue
		var sum:=Vector2.ZERO; var count:=0; var image: Image=result.image
		for py in Sources.GRID:
			for px in Sources.GRID:
				var texel:=image.get_pixel(px,py)
				if (requested_type==0 and texel.a>0.5) or (requested_type==6 and texel.r>0.5) or (requested_type==14 and texel.g>0.5):
					sum+=Vector2(px,py)+Vector2.ONE*0.5; count+=1
		if count>=12: return {"point":Vector2(key)*Sources.CELL+sum/count*Sources.STEP,"height":result.high,"key":key,"source_type":requested_type}
	return {}


func frame(count:=8) -> void:
	for i in count: await get_tree().process_frame


func snap(name_: String) -> Image:
	await frame(32); await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image(); image.save_png("user://mist-"+name_+".png"); return image


func comparison(a: Image,b: Image) -> Dictionary:
	var changed:=0; var peak:=0; var sum:=0; var x:=a.get_data(); var y:=b.get_data()
	for i in x.size():
		var d:=abs(int(x[i])-int(y[i])); peak=maxi(peak,d); sum+=d
		if d>2: changed+=1
	return {"channels":changed,"peak":peak,"mean":float(sum)/x.size(),"exact":x==y}


func offset_lifetime(mist: Mist) -> void:
	var chosen:=Vector2.INF; var key:=Vector2i.ZERO; var height:=0.0
	for k: Vector2i in mist.cache:
		var source: Dictionary=mist.cache[k]
		if source.is_empty(): continue
		var image: Image=source.image
		for y in Sources.GRID:
			for x in Sources.GRID:
				var texel:=image.get_pixel(x,y)
				if texel.a>0.5:
					chosen=Vector2(k)*Sources.CELL+(Vector2(x,y)+Vector2.ONE*0.5)*Sources.STEP
					key=k; height=texel.b; break
			if chosen.is_finite(): break
		if chosen.is_finite(): break
	check(chosen.is_finite(),"live offset regression has an actual cached source")
	if not chosen.is_finite(): return
	var hit:=mist.sources.source(chosen); var material:=int(hit.material)
	var old:=float(world.terrain.water_offsets.get(material,0.0))
	var nodes:=[]
	for row: Dictionary in mist.volumes.values(): nodes.append(row.node)
	world.terrain.set_water_offset(material,old+0.75)
	var old_drift:=mist.drift
	mist.step(world,focus,seconds,hours,0.0,Vector4.ZERO)
	check(mist.volumes.is_empty() and mist.cache.is_empty() and mist.drift==old_drift,"held-clock flood immediately invalidates stale masks without moving wisps")
	for i in 12: tick(mist)
	var hidden:=true
	for node in nodes: hidden=hidden and (not is_instance_valid(node) or not node.visible)
	check(hidden,"scripted liquid changes hide stale FogVolumes before rebuilding")
	settle(mist)
	var source: Dictionary=mist.cache.get(key,{})
	var raised: Color=(source.image as Image).get_pixelv(Vector2i((chosen-Vector2(key)*Sources.CELL)/Sources.STEP)) if not source.is_empty() else Color()
	check(raised.a>0.5 and absf(raised.b-height-0.75)<0.001,"rebuilt native source mask follows scripted liquid height")
	world.terrain.set_water_offset(material,old)
	for i in 12: tick(mist)
	settle(mist)


func visible_position(field: Sources,target: Vector3) -> bool:
	var screen:=camera.unproject_position(target)
	if camera.is_position_behind(target) or screen.x<40 or screen.y<40 or screen.x>view.size.x-40 or screen.y>view.size.y-40: return false
	for i in range(1,120):
		var probe:=camera.position.lerp(target,i/120.0)
		var land:=field.field.ground(Vector2(probe.x,-probe.z),true)
		if not land.is_empty() and float(land.height)>probe.y-0.03: return false
	return true


func create_actors(field: Sources, height: float) -> void:
	actors.clear()
	var direction:=(Vector2(camera.position.x,-camera.position.z)-focus).normalized()
	for side: float in [-1.0,0.0,1.0]:
		var found:=false
		for angle: float in [0.0,-0.4,0.4,-0.8,0.8,-1.2,1.2]:
			for distance in range(4,41):
				var p:=focus+direction.rotated(angle)*distance+direction.orthogonal()*side*1.5
				var hit:=field.field.ground(p,true)
				if hit.is_empty() or absf(float(hit.height)-height)>8.0 or absf((hit.normal as Vector3).y)<0.90: continue
				var liquid:=field.field.liquid(p)
				if not liquid.is_empty() and float(liquid.height)-float(hit.height)>0.6: continue
				var point:=Vector3(p.x,float(hit.height),-p.y)
				if not visible_position(field,point+Vector3.UP*0.9): continue
				var actor:=EIUnitModel.create({"prototype":"Human Hero"})
				if actor==null: continue
				world.terrain.add_child(actor); actor.position=point
				actor.act("idle",1,0.0); actor.set_process(false)
				if actor.player: actor.player.advance(0.0); actor.player.speed_scale=0.0
				actor.process_mode=Node.PROCESS_MODE_DISABLED
				actors.append(actor); found=true; break
			if found: break
	check(not actors.is_empty(),"real original human figures provide shore readability controls")


func party_contrast(off: Image,on: Image,bg_off: Image,bg_on: Image) -> Dictionary:
	var a:=off.get_data(); var b:=on.get_data(); var c:=bg_off.get_data(); var d:=bg_on.get_data()
	var old:=0.0; var now:=0.0; var pixels:=0
	for i in range(0,a.size(),4):
		var strongest:=0
		for k in 3: strongest=maxi(strongest,abs(int(a[i+k])-int(c[i+k])))
		if strongest<8: continue
		pixels+=1
		for k in 3:
			old+=abs(int(a[i+k])-int(c[i+k])); now+=abs(int(b[i+k])-int(d[i+k]))
	return {"pixels":pixels,"contrast_retained":now/maxf(old,1.0)}


func ray_depth(mist: Mist,target: Vector3) -> float:
	# Fixture selector only: sampled native-quantized source support along
	# the actor ray. Independent rendered contrast below is the acceptance.
	var value:=0.0; var distance:=camera.position.distance_to(target)/120.0
	for i in range(1,121):
		var p:=camera.position.lerp(target,i/120.0); var xy:=Vector2(p.x,-p.z)
		var key:=Vector2i((xy/Sources.CELL).floor())
		if not mist.volumes.has(key): continue
		var source: Dictionary=mist.cache[key]; var image: Image=source.image
		var q:=Vector2i((xy-Vector2(key)*Sources.CELL)/Sources.STEP)
		if q.x<0 or q.y<0 or q.x>=Sources.GRID or q.y>=Sources.GRID: continue
		var pixel:=image.get_pixelv(q)
		if pixel.a<0.5: continue
		var height:=p.y-pixel.b
		var layer:=smoothstep(0.0,0.3,height)*(1.0-smoothstep(3.0,4.0,height))*exp(-maxf(height,0.0)*0.3)
		var wisp:=0.55+0.35*sin((xy+mist.drift).dot(Vector2(0.12,0.08)))+0.10*cos((xy+mist.drift).dot(Vector2(-0.07,0.10)))
		var density:=Mist.MAX_DENSITY*(pixel.r*mist.weights.x+pixel.g*mist.weights.y)*layer*wisp
		if density>0.001: value+=floorf(density*1024.0)/1024.0*distance
	return value


func create_through_actor(mist: Mist,height: float) -> void:
	through_actor=null; through_source={}
	var away:=(focus-Vector2(camera.position.x,-camera.position.z)).normalized()
	for angle: float in [0.0,-0.2,0.2,-0.4,0.4,-0.7,0.7]:
		for distance in range(4,41):
			var p:=focus+away.rotated(angle)*distance
			var ground:=mist.sources.field.ground(p,true)
			if ground.is_empty() or absf((ground.normal as Vector3).y)<0.75: continue
			var base:=float(ground.height)
			var water:=mist.sources.field.liquid(p)
			if not water.is_empty() and float(water.height)-base>0.6: continue
			if base<height-0.6 or base>height+3.0: continue
			var point:=Vector3(p.x,base,-p.y); var target:=point+Vector3.UP*0.9
			if not visible_position(mist.sources,target): continue
			var depth:=ray_depth(mist,target)
			if depth<0.006: continue
			var actor:=EIUnitModel.create({"prototype":"Human Hero"})
			if actor==null: continue
			world.terrain.add_child(actor); actor.position=point; actor.act("idle",1,0.0)
			if actor.player: actor.player.advance(0.0); actor.player.speed_scale=0.0
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			through_actor=actor; actors.append(actor)
			through_source={"position":str(point),"sampled_optical_depth":depth,"liquid_depth":float(water.height)-base if not water.is_empty() else 0.0}
			break
		if through_actor: break
	check(through_actor!=null,"low-angle actor ray crosses verified mist on a far bank or shallow water")


func shore_spread(field: Sources,off: Image,on: Image) -> Dictionary:
	var tested:=0; var peak:=0; var channels:=0
	for y in range(-16,17,4):
		for x in range(-16,17,4):
			var p:=focus+Vector2(x,y); var hit:=field.field.ground(p)
			if hit.is_empty() or not field.source(p).is_empty(): continue
			var point:=Vector3(p.x,float(hit.height)+0.10,-p.y)
			if camera.is_position_behind(point): continue
			var screen:=Vector2i(camera.unproject_position(point))
			if screen.x<3 or screen.y<3 or screen.x>=view.size.x-3 or screen.y>=view.size.y-3: continue
			var intersects:=false; var obscured:=false
			for i in range(1,81):
				var sample:=camera.position.lerp(point,i/80.0); var xy:=Vector2(sample.x,-sample.z)
				var source:=field.source(xy); var land:=field.field.ground(xy)
				if not land.is_empty() and float(land.height)>sample.y: obscured=true; break
				if not source.is_empty() and sample.y>float(source.height) and sample.y<float(source.height)+Sources.LAYER_HEIGHT: intersects=true; break
			if intersects or obscured: continue
			tested+=1
			for dy in range(-1,2):
				for dx in range(-1,2):
					var a:=off.get_pixel(screen.x+dx,screen.y+dy); var b:=on.get_pixel(screen.x+dx,screen.y+dy)
					for k in 3:
						var delta:=roundi(absf(a[k]-b[k])*255.0); peak=maxi(peak,delta)
						if delta>2: channels+=1
	return {"sampled_dry_rays":tested,"peak_channel_delta":peak,"changed_channels":channels}


func render_controls(mist: Mist,label: String,id: String) -> void:
	mist.root.hide(); var off:=await snap(label+"-off")
	var through_off: Image
	if is_instance_valid(through_actor):
		through_actor.hide(); through_off=await snap(label+"-without-through-off"); through_actor.show()
	for actor in actors: actor.hide()
	var bg_off:=await snap(label+"-background-off")
	for actor in actors: actor.show()
	mist.root.show(); var on:=await snap(label+"-on")
	var held:=await snap(label+"-held")
	var through_on: Image
	if is_instance_valid(through_actor):
		through_actor.hide(); through_on=await snap(label+"-without-through-on"); through_actor.show()
	for actor in actors: actor.hide()
	var bg_on:=await snap(label+"-background-on")
	for actor in actors: actor.show()
	var delta:=comparison(off,on); var frozen:=comparison(on,held)
	check(int(delta.channels)>100,label+" verified liquid mist independently changes rendered pixels")
	check(int(delta.peak)<100 and float(delta.mean)<10.0,label+" local mist preserves scene readability")
	check(int(frozen.channels)==0,label+" held clock settles to the same native fog image")
	var party:=party_contrast(off,on,bg_off,bg_on)
	check(int(party.pixels)>30 and float(party.contrast_retained)>0.74,label+" original human silhouettes retain contrast")
	var through:={}
	if is_instance_valid(through_actor):
		through=party_contrast(off,on,through_off,through_on)
		check(int(through.pixels)>10 and float(through.contrast_retained)>0.74 and float(through.contrast_retained)<0.999,label+" through-mist figure is affected but retains readable contrast")
	var shore:=shore_spread(mist.sources,off,on)
	check(int(shore.sampled_dry_rays)>0 and int(shore.peak_channel_delta)<8,label+" dry-shore rays have no large native-froxel spill")
	var masks:=[]; var empty_image:=Image.create(Sources.GRID,Sources.GRID,false,Image.FORMAT_RGBAF)
	var empty_texture:=ImageTexture.create_from_image(empty_image)
	for row: Dictionary in mist.volumes.values():
		masks.append([row.material,row.material.get_shader_parameter("source_mask")])
		row.material.set_shader_parameter("source_mask",empty_texture)
	var no_source:=await snap(label+"-empty-source"); var zero:=comparison(off,no_source)
	check(int(zero.channels)==0,label+" empty masks add no fog while volumes remain")
	for entry: Array in masks: entry[0].set_shader_parameter("source_mask",entry[1])
	# Hold hour/weather to isolate slow wind from morning burn-off/wetness.
	# Observe both endpoints: a single phase pair can be almost equal when
	# broad wisps pass through a trough in a narrow, darker regional source.
	var motion:={"channels":0,"peak":0,"mean":0.0,"exact":true}; var wind_observations:=[]
	for interval in 2:
		for i in 600:
			seconds+=0.1; mist.step(world,focus,seconds,hours,0.0,Vector4(0.8,0.6,0.5,0.7))
		var moved:=await snap(label+"-advanced-"+str((interval+1)*60)); var sample:=comparison(held,moved)
		wind_observations.append({"terrain_seconds":(interval+1)*60,"comparison":sample})
		if int(sample.channels)>int(motion.channels) or (int(sample.channels)==int(motion.channels) and int(sample.peak)>int(motion.peak)): motion=sample
	check(int(motion.channels)>20,label+" advancing game clock changes native wisps")
	mist.root.hide(); var restored:=await snap(label+"-restored"); var empty:=comparison(off,restored)
	check(int(empty.channels)==0,label+" removing local mist restores unchanged environment")
	rows.append({"case":"render","phase":label,"zone":id,"source_type":requested_type,"point":str(focus),"hour":hours,"weights":str(mist.weights),"wetness":mist.wetness,"rain":mist.rain,"drift":str(mist.drift),"volumes":mist.volumes.size(),"on":delta,"held":frozen,"party":party,"through_actor":through,"through_source":through_source,"shore":shore,"empty_source":zero,"advanced":motion,"wind_observations":wind_observations,"restored":empty})


func lifecycle(id: String,rendered: bool) -> void:
	if not load_world(id,true): return
	var field:=Sources.new(world.terrain); var candidate:=choose(field)
	check(not candidate.is_empty(),"actual broad liquid patch survives conservative mask "+id)
	if candidate.is_empty(): return
	focus=candidate.point
	var mist:=Mist.new(); view.add_child(mist); mist.set_process(false); mist.enabled=true
	seconds=10.0; hours=6.0
	var nav:=world.terrain.heights.duplicate(); var water:=world.terrain.water.duplicate(); var units:=world.units.duplicate()
	var density:=environment.volumetric_fog_density; var length_:=environment.volumetric_fog_length
	mist.step(world,focus,seconds,hours,0.0,Vector4(0.8,0.6,0.5,0.7)); settle(mist)
	check(not mist.volumes.is_empty() and mist.volumes.size()<=Mist.MAX_VOLUMES,"bounded native local FogVolumes are admitted")
	check(mist.cache.size()<=Mist.CACHE_CELLS,"positive and empty source masks have bounded cache")
	var sizes_ok:=true
	for row: Dictionary in mist.volumes.values():
		var node: FogVolume=row.node
		sizes_ok=sizes_ok and node.size.x==Sources.CELL and node.size.z==Sources.CELL and node.size.y<=Sources.MAX_HEIGHT
	check(sizes_ok,"all boxes obey the continuous opacity bound")
	check(environment.volumetric_fog_density==density and environment.volumetric_fog_length==length_,"global volumetric density and range remain unchanged")
	check(nav==world.terrain.heights and water==world.terrain.water and units==world.units,"mist changes no navigation, liquid data or gameplay registry")
	var before:=mist.drift; var old_wet:=mist.wetness; var old_rain:=mist.rain; var old_keys:=mist.cache.keys(); var old_weights:=mist.weights
	mist.step(world,focus+Vector2(50,0),seconds,12.0,1.0,Vector4(-1,0,1,1))
	check(mist.drift==before and mist.wetness==old_wet and mist.rain==old_rain and mist.cache.keys()==old_keys and mist.weights==old_weights,"held clock freezes wind, weather, placement and uniforms")
	offset_lifetime(mist)
	for i in 180: tick(mist,1.0)
	check(mist.wetness>0.70 and mist.rain>0.70,"rain ramps mist using game hours")
	var soaked:=mist.wetness
	for i in 260: tick(mist,0.0)
	check(mist.rain<0.001 and mist.wetness>0.1 and mist.wetness<soaked,"wetness lingers and decays after rain")
	mist.drift=Vector2.ONE*(Mist.DRIFT_PERIOD-0.001)
	var unwrapped:=mist.drift+Vector2(0.8,0.6)*0.055*0.19
	tick(mist)
	check(mist.drift.x>=0 and mist.drift.x<Mist.DRIFT_PERIOD and mist.drift.y>=0 and mist.drift.y<Mist.DRIFT_PERIOD,"wind drift wraps into its bounded phase interval")
	check(absf(sin(unwrapped.dot(Vector2(0.12,0.08)))-sin(mist.drift.dot(Vector2(0.12,0.08))))<0.0001 \
		and absf(cos(unwrapped.dot(Vector2(-0.07,0.10)))-cos(mist.drift.dot(Vector2(-0.07,0.10))))<0.0001,"phase wrapping preserves both native shader wisps")
	if rendered and RenderingServer.get_current_rendering_method()=="forward_plus":
		var aim:=Vector3(focus.x,float(candidate.height)+0.8,-focus.y)
		var best:=Vector3.INF
		for angle: float in ([0.0] if low_angle else [0.0,PI*0.25,-PI*0.25,PI*0.5,-PI*0.5,PI*0.75,-PI*0.75,PI]):
			var flat:=Vector2(16,22).rotated(angle)
			var position_:=aim+Vector3(flat.x,3.5 if low_angle else 12.0,flat.y)
			# Keep the actual source visible above authored banks/cliffs. Try
			# another azimuth before lifting a normal camera over a tall ridge.
			for i in range(0,120):
				var t:=i/120.0; var probe:=position_.lerp(aim,t)
				var land:=mist.sources.field.ground(Vector2(probe.x,-probe.z),true)
				if not land.is_empty(): position_.y=maxf(position_.y,(float(land.height)+0.8-aim.y*t)/(1.0-t))
			if position_.y<best.y: best=position_
			if best.y<=aim.y+(3.5 if low_angle else 12.0): break
		camera.position=best
		camera.look_at(aim)
		rows.append({"case":"view","low_angle":low_angle,"camera":str(camera.position),"target":str(aim),"pitch_degrees":rad_to_deg(atan2(camera.position.y-aim.y,Vector2(16,22).length()))})
		create_actors(mist.sources,float(candidate.height))
		if low_angle: create_through_actor(mist,float(candidate.height))
		await render_controls(mist,"dawn",id)
		mist.clear(); seconds=10.0; hours=11.0
		mist.step(world,focus,seconds,hours,0.0,Vector4(0.8,0.6,0.5,0.7)); settle(mist)
		while hours<11.70: tick(mist,1.0)
		while hours<12.0: tick(mist,0.0)
		check(Mist.morning(hours)==0.0 and mist.rain<0.001 and mist.wetness>0.25,"post-rain view has genuine lingering wetness at clear noon")
		await render_controls(mist,"after-rain",id)
	var old_root:=mist.root.get_instance_id()
	mist.step(world,focus,seconds+4.0,hours+4.0,0.0,Vector4.ZERO)
	check(mist.root.get_instance_id()!=old_root and mist.wetness==0.0 and mist.drift==Vector2.ZERO,"clock gaps discard old weather and do not drag stale mist")
	old_root=mist.root.get_instance_id()
	mist.step(world,focus,1.0,1.0,0.0,Vector4.ZERO)
	check(mist.root.get_instance_id()!=old_root and mist.hours==1.0,"rewinds start a fresh local source lifetime")
	old_root=mist.root.get_instance_id()
	var old_world:=world.get_instance_id()
	world.map.free()
	var replacement:=EIMapScene.new(); replacement.terrain=EITerrain.load_map(world.zone.mpr)
	replacement.add_child(replacement.terrain); world.add_child(replacement); world.map=replacement; world.terrain=replacement.terrain
	world.terrain.set_process(false)
	mist.step(world,focus,1.0,1.0,0.0,Vector4.ZERO)
	check(world.get_instance_id()==old_world and mist.root.get_instance_id()!=old_root and mist.sources.field.terrain==world.terrain,"same GameWorld replaces terrain even at a held clock")
	process_mode=Node.PROCESS_MODE_ALWAYS; get_tree().paused=true
	check(not mist.can_process(),"parent always-processing mode cannot bypass mist pause")
	await frame(2); get_tree().paused=false; process_mode=Node.PROCESS_MODE_INHERIT
	old_root=mist.root.get_instance_id()
	if load_world(id):
		mist.step(world,focus,1.0,1.0,0.0,Vector4.ZERO)
		check(mist.root.get_instance_id()!=old_root and mist.sources.field.terrain==world.terrain,"world reload replaces sources even at the same held clock")
	GameData.options.gfx_volumetric=0; mist.refresh()
	check(mist.root==null and mist.sources==null and mist.volumes.is_empty() and mist.cache.is_empty(),"disabling required volumetrics releases local mist resources")
	rows.append({"case":"lifecycle","zone":id,"chosen":str(candidate),"cleared_clock":not is_finite(mist.clock),"update_cost_us":costs(update_costs),"source_slice_us":costs(source_costs),"cost_note":"Descriptive CPU wall-time samples from this fixture only; no frame-time, hardware or performance acceptance."})
	mist.free()


func costs(values: PackedInt64Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted:=values.duplicate(); sorted.sort()
	return {"count":sorted.size(),"median":sorted[sorted.size()/2],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max":sorted[-1]}


func unsupported(id: String) -> void:
	if not load_world(id,true): return
	var source:=Sources.new(world.terrain); var candidate:=choose(source)
	check(not candidate.is_empty(),"unsupported-renderer control uses actual liquid scene")
	if candidate.is_empty(): return
	var point: Vector2=candidate.point; var aim:=Vector3(point.x,float(candidate.height),-point.y)
	camera.position=aim+Vector3(16,12,22); camera.look_at(aim)
	GameData.options.gfx_weather_mist=0
	var mist:=Mist.new(); view.add_child(mist); mist.set_process(false)
	var off:=await snap("off")
	GameData.options.gfx_weather_mist=1; mist.refresh()
	mist.step(world,point,10.0,6.0,1.0,Vector4(1,0,1,1))
	check(not mist.enabled and mist.root==null,"unsupported renderer rejects native volume allocation")
	var on:=await snap("on"); var delta:=comparison(off,on)
	check(int(delta.channels)==0,"unsupported option is an unchanged rendered scene")
	rows.append({"case":"unsupported","renderer":RenderingServer.get_current_rendering_method(),"comparison":delta})
	mist.free()


func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_wind":0,"gfx_ambient_wildlife":0,"gfx_ambient_particles":0,
		"gfx_grass":0,"gfx_biome_cover":0,"gfx_water":0,"gfx_water_waves":0,"gfx_taa":0,"gfx_ssao":0,"gfx_volumetric":1,"gfx_weather_mist":1},true)
	campaign=CampaignMap.load_from(GameData.texts)
	view=SubViewport.new(); view.size=Vector2i(1280,900); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	camera=Camera3D.new(); view.add_child(camera)
	var env:=WorldEnvironment.new(); environment=Environment.new(); env.environment=environment
	Gfx.setup_original_env(environment); Gfx.setup_volumetric(environment); Gfx.apply_env(environment)
	environment.volumetric_fog_density=0.0005; environment.background_mode=Environment.BG_COLOR; environment.background_color=Color(0.13,0.18,0.23); view.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.6,0.6,0.6),Color(0.75,0.75,0.75)); Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var id:="gz4g" if GameData.campaign_id==CampaignProfile.ORIGINAL else "gz9g"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mist-zone="): id=arg.trim_prefix("--mist-zone=")
		if arg.begins_with("--mist-type="): requested_type=int(arg.trim_prefix("--mist-type="))
		if arg=="--mist-low-angle": low_angle=true
	rules()
	if not "--mist-render-only" in OS.get_cmdline_user_args(): census()
	if DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()!="forward_plus": await unsupported(id)
	else: await lifecycle(id,DisplayServer.get_name()!="headless")
	var file:=FileAccess.open("user://mist-receipt.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"campaign":GameData.campaign_id,"checks":checks,"failures":failures,"rows":rows},"\t")); file.close()
	print("WEATHER_MIST ",GameData.campaign_id," ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
