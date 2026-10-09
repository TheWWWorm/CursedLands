extends Node
## Original archives/maps, stable client-only placement, clock ownership,
## source rules, avoidance and optional off/on rendered controls.
const Life = preload("res://src/game/fx/ambient_life.gd")
const Habitats = preload("res://src/game/fx/ambient_habitats.gd")
const Model = preload("res://src/game/fx/ambient_models.gd")
const Particles = preload("res://src/game/fx/ambient_particles.gd")
const DrawnGround = preload("res://src/game/fx/ambient_ground.gd")
var checks := 0
var failures := 0
var rows := []
var campaign: CampaignMap
var view: SubViewport
var world: GameWorld
var camera: Camera3D
var render_hour := 12.0
var requested_kind := -1
var requested_species := ""


func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)


func rules() -> void:
	check(Habitats.region_of("gipat2")=="outdoor" and Habitats.region_of("dead_city")=="dead_city","LiA Gipat is not the base Dead City")
	check(Habitats.region_of("unknown")=="unknown" and Habitats.region_of("invented")=="unknown","unrecognized allods admit no regional decoration")
	check(Life.night_at(12)==0 and Life.night_at(0)==1 and Life.night_at(6)==0.5,"night follows game hours with twilight fades")
	var h := {"area":"grass","clear":true,"leafy":false}
	check(Habitats.particles("outdoor","gipat",h,0)==PackedInt32Array([0]),"day grass gets pollen")
	check(Habitats.particles("outdoor","gipat",h,1)==PackedInt32Array([7]),"Gipat night replaces pollen with fireflies")
	check(not 7 in Habitats.particles("outdoor","gipat2",h,1),"LiA Gipat does not inherit unverified base firefly geography")
	h.leafy=true
	check(1 in Habitats.particles("outdoor","gipat",h,0),"actual leafy source admits leaves")
	h.leafy=false
	check(not 1 in Habitats.particles("outdoor","gipat",h,0),"grass alone does not create tree leaves")
	h.area="snow"; h.leafy=true
	check(Habitats.particles("snow","ingos",h,0)==PackedInt32Array([6]),"snow gets glitter without autumn leaves")
	h.area="sand"
	check(Habitats.particles("desert","suslanger",h,0)==PackedInt32Array([5]),"desert sand gets sparse dust")
	h.area="bare"; h.leafy=false
	check(Habitats.particles("cave","cave",h,0)==PackedInt32Array([3]),"cave rock gets dust")
	check(Habitats.particles("dead_city","dead_city",h,0)==PackedInt32Array([2]),"Dead City gets its own motes")
	h.area="lava"
	check(Habitats.particles("cave","cave",h,0)==PackedInt32Array([4]),"actual lava overrides cave dust with embers")
	h.clear=false
	check(Habitats.particles("cave","cave",h,0).is_empty(),"solid scenery excludes particle roots")
	var unit:=GameUnit.new()
	unit.action="walk"; unit.running=false; var walk:=Life.threat_radius(unit)
	unit.running=true; var run:=Life.threat_radius(unit)
	unit.stance=GameUnit.STANCE_CRAWL; var sneak:=Life.threat_radius(unit)
	unit.action="attack"; var combat:=Life.threat_radius(unit)
	check(combat>run and run>walk and walk>sneak,"combat and running disturb a wider area than quiet movement")
	add_child(unit); unit.set_process(false); unit.set_physics_process(false)
	unit.model=EIUnitModel.new(); unit.add_child(unit.model)
	check(Life.shown(unit),"visible creature contributes presentation evidence")
	unit.hidden=true; check(not Life.shown(unit),"hidden creature cannot frighten decorative wildlife"); unit.hidden=false
	unit.fogged=true; check(not Life.shown(unit),"unseen creature cannot reveal itself through wildlife"); unit.fogged=false
	unit.dead=true; check(not Life.shown(unit),"dead creature cannot produce a movement threat")
	unit.free()
	check(not Particles.SHADER.contains("TIME"),"regional particle motion has no wall-clock input")
	check(Particles.SHADER.contains("threats[i]"),"particle shader suppresses visible-unit/combat overlap")


func models() -> void:
	var entries:=[]
	for kind: String in Model.SPECS:
		var node:=Model.new(); add_child(node)
		var built:=node.build(kind)
		check(built,"original figure and skin build: "+kind)
		if built:
			var spec:Array=Model.SPECS[kind]
			check(GameData.load_image(spec[1])!=null,"original texture exists: "+spec[1])
			check(node.body_length>=0.15 and node.body_length<=0.24,"fixed small physical length: "+kind)
			var before:=node.figure.scale
			node.pose(1.2,true); node.pose(4.7,false)
			check(node.figure.scale==before and node.mesh_count>0,"animation never rescales the animal: "+kind)
			entries.append({"kind":kind,"body_length":node.body_length,"mesh_parts":node.mesh_count,"clips":Array(node.player.get_animation_list())})
		node.free()
	rows.append({"case":"original-models","models":entries})


func load_world(id: String, scenery: bool) -> bool:
	if is_instance_valid(world): world.free()
	world=GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.zone=campaign.zone(id)
	check(not world.zone.is_empty(),"actual campaign zone "+id)
	if world.zone.is_empty(): return false
	var map: EIMapScene
	if scenery: map=EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false)
	else:
		map=EIMapScene.new(); map.terrain=EITerrain.load_map(world.zone.mpr)
		if map.terrain: map.add_child(map.terrain)
	check(map!=null and map.terrain!=null,"original terrain loads "+id)
	if map==null or map.terrain==null: return false
	world.add_child(map); world.map=map; world.terrain=map.terrain
	map.terrain.set_process(false)
	if map.terrain._water_mat: map.terrain._water_mat.set_shader_parameter("waves",0.0)
	if "--ambient-authored-light" in OS.get_cmdline_user_args():
		var cave:=String(world.zone.get("sky",""))=="cave"
		var lights:=EILights.load_for(String(world.zone.get("allod","")),cave)
		var env:=view.get_node("AmbientEnvironment") as WorldEnvironment
		var sun:=view.get_node("AmbientSun") as DirectionalLight3D
		Gfx.update_original(env.environment,sun,lights,render_hour,cave)
	return true


func census() -> void:
	var astral:=GameData.campaign_id!=CampaignProfile.ORIGINAL
	var ids := ["gz7d1","gz36j","gz9g"] if astral else ["gz1g","gz4g","gz5g","bz7g","gz9g","gz11k","gz18h"]
	for id: String in ids:
		if not load_world(id,false): continue
		var field:=Habitats.new(world.terrain)
		var profiles_ok:=true
		var original_profiles:=world.terrain._tile_tex.get_image()
		for y in original_profiles.get_height():
			for x in original_profiles.get_width():
				var expected:=original_profiles.get_pixel(x,y)
				if DrawnGround.profile(world.terrain,Vector2i(x,y)).distance_to(Vector2(expected.b,expected.a))>0.000001: profiles_ok=false
		check(profiles_ok,"small-animal loose profiles match actual shader texture "+id)
		if id=="gz9g": check(field.region==("outdoor" if astral else "dead_city"),"zone9 uses campaign context")
		var areas:={}; var animals:={}; var particle_kinds:={}; var first:={}
		var water_point:=Vector2.INF
		var size:=Vector2i(world.terrain.size_ei()/32.0)
		var tested:=0; var dry_wet_disagreements:=0
		for y in size.y:
			for x in size.x:
				var key:=Vector2i(x,y); var p:=field.anchor(key); var h:=field.habitat(p,false)
				if h.is_empty(): continue
				tested+=1
				areas[h.area]=int(areas.get(h.area,0))+1
				if h.wet and not water_point.is_finite(): water_point=p
				var kind:=field.species(p,h,field.random(key,3),0.0)
				if not kind.is_empty():
					animals[kind]=int(animals.get(kind,0))+1
					if not first.has(kind): first[kind]=str(p)
				for k in Habitats.particles(field.region,field.biome,h,0.0): particle_kinds[k]=int(particle_kinds.get(k,0))+1
				if not h.wet and world.terrain.water_at(p.x,p.y)>float(h.height)+0.06: dry_wet_disagreements+=1
		check(tested>0,"authored ground samples "+id)
		if field.region=="cave": check(animals.has("rat") or animals.has("spider"),"cave admits small original inhabitants "+id)
		if field.region=="dead_city": check(animals.has("spider") and not animals.has("frog"),"Dead City excludes cute meadow fauna")
		if field.region=="snow": check(particle_kinds.has(6),"original snow atlas categories admit snow motes")
		if field.region=="desert": check(particle_kinds.has(5),"original desert atlas categories admit dust")
		if id=="gz4g": check(animals.has("frog"),"authored swamp bank admits an original small frog")
		if water_point.is_finite() and id in ["gz1g","bz7g","gz7d1"]:
			var before:=field.liquid(water_point); var mat:=int(before.material)
			var original:=float(world.terrain.water_offsets.get(mat,0.0))
			world.terrain.set_water_offset(mat,original+0.75)
			check(field.refresh(),"scripted liquid offsets invalidate regional sources "+id)
			check(absf(float(field.liquid(water_point).height)-float(before.height)-0.75)<0.001,"actual liquid geometry follows scripted height "+id)
			world.terrain.set_water_offset(mat,original); field.refresh()
		check(field._water._sectors.size()<=field._water.CACHE_SECTORS,"liquid query has bounded cache "+id)
		rows.append({"case":"map-census","zone":id,"map":world.terrain.map_name,"allod":world.zone.get("allod",""),"sky":world.zone.get("sky",""),"biome":field.biome,"region":field.region,"area_samples":areas,"species":animals,"particles":particle_kinds,"first":first,"navigation_wet_but_drawn_dry":dry_wet_disagreements})


func frame() -> void:
	for i in 4: await get_tree().process_frame


func snap(label: String) -> Image:
	await frame(); await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image(); image.save_png("user://ambient-"+label+".png")
	return image


func changed(a: Image,b: Image) -> int:
	var result:=0; var x:=a.get_data(); var y:=b.get_data()
	for i in x.size():
		if abs(int(x[i])-int(y[i]))>2: result+=1
	return result


func clear_camera(field: Habitats, p: Vector2, height: float) -> Vector3:
	var focus:=Vector3(p.x,height+0.9,-p.y)
	for angle in [0.0,PI*0.5,PI,PI*1.5]:
		var offset:=Vector2(2.7,5.0).rotated(angle)
		var eye:=focus+Vector3(offset.x,3.5,offset.y)
		var clear:=true
		for i in range(1,21):
			var point:=focus.lerp(eye,i/20.0); var xy:=Vector2(point.x,-point.z)
			var land:=field.ground(xy); var water:=field.liquid(xy)
			if land.is_empty() or float(land.height)>point.y-0.25 or (not water.is_empty() and float(water.height)>point.y-0.25): clear=false; break
			if not field.clear_at(xy,point.y-0.2): clear=false; break
		if clear: return eye
	return Vector3.INF


func authored_floor(p: Vector2,height: float) -> bool:
	# Keep visual evidence in the authored play area, away from the high
	# flat cave rim. These MOB spawn records are only a fixture selector.
	if world.map.unit_records.is_empty(): return true
	for record: Dictionary in world.map.unit_records:
		var point: Vector3=record.position
		if p.distance_to(Vector2(point.x,point.y))>45.0: continue
		if absf(world.terrain.height_at(point.x,point.y)+point.z-height)<4.0: return true
	return false


func capture_candidates(field: Habitats) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if requested_kind==1:
		# Leaves belong to the authored trees' small footprint. A 32 m
		# animal admission grid is too sparse to choose this visual case.
		var trees:={}
		for bucket: PackedVector2Array in field.trees.values():
			for point: Vector2 in bucket: trees[point]=true
		for point: Vector2 in trees:
			for i in 8: points.append(point+Vector2.from_angle(i*TAU/8.0)*4.0)
	else:
		var size:=Vector2i(world.terrain.size_ei()/32.0)
		for y in size.y:
			for x in size.x: points.append(field.anchor(Vector2i(x,y)))
	return points


func snow_surface(life: Life, rendered: bool) -> void:
	if life.residents.is_empty() or life.field.region!="snow": return
	var row: Dictionary=life.residents.values()[0]
	var t:=world.terrain
	var was: bool=t._land_mat.get_shader_parameter("soft_ground")
	t._land_mat.set_shader_parameter("soft_ground",false)
	life._resurface()
	var base:=float(row.node.position.y)
	check(absf(base-float(life.field.ground(row.p).height))<0.00001,"soft-ground off returns animals to original triangles")
	t._land_mat.set_shader_parameter("soft_ground",true)
	life._resurface()
	var loose:=float(row.node.position.y)
	check(loose>base+0.05,"small snow animal stands on the raised visible loose layer")
	var pose: Transform3D=row.node.figure.transform
	check(world.terrain.details!=null and world.terrain.details.soft_ground!=null,"actual loose-ground controller is available")
	var soft:=t.details.soft_ground
	soft.set_process(false)
	var unchanged:=t.heights.duplicate()
	soft.add_step(row.p,Vector2(0.30,0.40),0.0)
	soft._process(0.0); soft._finish_mesh_jobs(true)
	check(soft.field!=null and not soft.field._slots.is_empty(),"actual footprint mesh and field are installed")
	life._resurface()
	var tracked:=float(row.node.position.y)
	check(tracked<loose-0.04,"animal follows live footprint compaction")
	check(row.node.figure.transform==pose,"surface option or footprint changes never advance the pose")
	if rendered:
		life.root.hide(); var off:=await snap("snow-track-off")
		life.root.show(); life.particles.hide(); var animal:=await snap("snow-track-animal")
		check(changed(off,animal)>10,"small snow animals remain visible inside actual footprints")
		life.particles.show()
	soft.clear(); life._resurface()
	check(absf(float(row.node.position.y)-loose)<0.00001,"clearing footprints restores the loose-layer placement")
	check(t.heights==unchanged,"visible animal placement does not mutate original ground heights")
	rows.append({"case":"snow-surface","original":base,"loose":loose,"compacted":tracked,"restored":row.node.position.y})
	t._land_mat.set_shader_parameter("soft_ground",was); life._resurface()


func lifetime(id: String, rendered: bool) -> void:
	if not load_world(id,true): return
	var life:=Life.new(); view.add_child(life); life.set_process(false)
	life.wildlife=requested_kind<0; life.regional=true
	var field:=Habitats.new(world.terrain); var centre:=Vector2.ZERO; var chosen:=false; var eye:=Vector3.INF
	for p: Vector2 in capture_candidates(field):
		var h:=field.habitat(p)
		if h.is_empty() or not h.clear or (h.wet and requested_kind!=4) or (not h.wet and absf((h.normal as Vector3).y)<0.96): continue
		if not authored_floor(p,float(h.height)): continue
		if not requested_species.is_empty() and field.species(p,h,0,Life.night_at(render_hour))!=requested_species: continue
		if requested_kind>=0:
			if not requested_kind in Habitats.particles(field.region,field.biome,h,Life.night_at(render_hour)): continue
		elif field.region in ["cave","dead_city","snow"] and field.species(p,h,0,0).is_empty(): continue
		elif field.region=="outdoor" and h.area not in ["grass","bare","dry"]: continue
		eye=clear_camera(field,p,float(h.height))
		if not eye.is_finite(): continue
		centre=p; chosen=true; break
	check(chosen,"authored resident location survives scenery "+id)
	if not chosen: life.free(); return
	var registry:=world.units.duplicate(); var water:=world.terrain.water.duplicate(); var positions:=world.terrain.heights.duplicate()
	life.step(world,centre,10.0,render_hour)
	check(life.residents.size()<=Life.MAX_GROUND and life.flock.size()<=Life.MAX_BIRDS,"bounded local animal population")
	if field.region!="desert" and render_hour==12.0 and requested_kind<0:
		check(life.residents.size()+life.flock.size()>0,"real habitat admits visible decorative models")
	check(life.particles.records.size()>0 and life.particles.records.size()<=Particles.MAX_PARTICLES,"bounded regional particles from actual map")
	var scales:=[]; var transforms:=[]
	for row: Dictionary in life.residents.values()+life.flock:
		scales.append(row.node.figure.scale); transforms.append(row.node.transform)
	var records:=life.particles.records.duplicate(true)
	life.step(world,centre+Vector2(0.2,0.1),10.0,0.0)
	var after:=[]
	for row: Dictionary in life.residents.values()+life.flock: after.append(row.node.transform)
	check(transforms==after and life.particles.records==records,"held terrain time holds particles, poses and admissions")
	life.step(world,centre+Vector2(0.2,0.1),10.1,render_hour)
	var next_scales:=[]
	for row: Dictionary in life.residents.values()+life.flock: next_scales.append(row.node.figure.scale)
	check(scales==next_scales,"camera motion does not change animal physical size")
	var common:=0; var stable:=true
	life.particles.rebuild(field,centre+Vector2(8.0,0.0))
	for a: Dictionary in records:
		for b: Dictionary in life.particles.records:
			if a.key==b.key: common+=1; stable=stable and a==b
	check(common>0 and stable,"particle cells retain exact positions/seeds across camera boundary")
	life.particles.rebuild(field,centre,true)
	check(life.particles.records==records,"returning camera restores the same particle field")
	var key:=Vector2i.ZERO
	for i in 200: life._cooldown(Vector2i(i,1))
	check(life.cooldowns.size()==Life.MAX_COOLDOWNS,"long camera travel bounds cooldown storage")
	life.cooldowns.clear()
	check(world.units==registry and world.terrain.water==water and world.terrain.heights==positions,"decoration leaves unit registry, navigation water and terrain unchanged")
	var draw_rows:=[]
	for row: Dictionary in life.residents.values()+life.flock: draw_rows.append({"kind":row.kind,"point":str(row.node.position),"parts":row.node.mesh_count})
	if not requested_species.is_empty():
		var admitted:=false
		for row: Dictionary in life.residents.values(): admitted=admitted or row.kind==requested_species
		check(admitted,"requested species is admitted at its authored habitat")
	var kinds:={}
	for row: Dictionary in life.particles.records: kinds[row.kind]=int(kinds.get(row.kind,0))+1
	if requested_kind>=0: check(kinds.has(requested_kind),"requested original habitat has its own particle roots")
	rows.append({"case":"lifetime","zone":id,"point":str(centre),"residents":draw_rows,"particles":life.particles.records.size(),"particle_kinds":kinds,"hour":render_hour,"authored_light":"--ambient-authored-light" in OS.get_cmdline_user_args(),"step_us":life.last_update_us,"root_nodes":life.root.find_children("*","Node",true,false).size(),"leafy_source_buckets":field.trees.size(),"solid_source_buckets":field.boxes.size()})
	if rendered:
		var h:=field.habitat(centre); var focus:=Vector3(centre.x,float(h.height)+0.9,-centre.y)
		camera.global_position=eye; camera.look_at(focus); camera.current=true
		if requested_kind>=0:
			for i in life.particles.records.size():
				var row: Dictionary=life.particles.records[i]
				if row.kind!=requested_kind: life.particles.multimesh.set_instance_custom_data(i,Color(row.seed,row.kind,0,0))
		life.root.hide(); var off:=await snap("off")
		for row: Dictionary in life.residents.values()+life.flock:
			row.node.visible=requested_species.is_empty() or row.kind==requested_species
		life.root.show(); life.particles.hide(); var animals:=await snap("animals")
		var animal_delta:=changed(off,animals)
		if life.residents.size()+life.flock.size()>0: check(animal_delta>10,"original animal figures are independently visible")
		for row: Dictionary in life.residents.values()+life.flock: row.node.hide()
		life.particles.show(); var motes:=await snap("particles")
		var mote_delta:=changed(off,motes)
		check(mote_delta>5,"regional particles are independently visible"+(" (kind %d)"%requested_kind if requested_kind>=0 else ""))
		for row: Dictionary in life.residents.values()+life.flock:
			row.node.visible=requested_species.is_empty() or row.kind==requested_species
		life.root.show(); var on:=await snap("on")
		var delta:=changed(off,on); check(delta>10,"ambient geometry is visible against an unchanged original map")
		var held:=await snap("held")
		var paused_delta:=changed(on,held)
		check(paused_delta==0,"rendered decoration freezes at the held terrain clock")
		for i in 40: life.step(world,centre,10.2+i*0.05,render_hour)
		var moving:=await snap("advanced")
		var advanced_delta:=changed(held,moving)
		check(advanced_delta>10,"advancing game time moves original figures and regional particles")
		rows.append({"case":"render","zone":id,"on_off_bytes":delta,"animals_bytes":animal_delta,"particles_bytes":mote_delta,"requested_kind":requested_kind,"paused_bytes":paused_delta,"held_exact_pixels":on.get_data()==held.get_data(),"advanced_bytes":advanced_delta,"renderer":RenderingServer.get_current_rendering_method()})
	await snow_surface(life,rendered)
	if not life.residents.is_empty() or not life.flock.is_empty():
		var subject: Dictionary = life.residents.values()[0] if not life.residents.is_empty() else life.flock[0]
		var before: Vector2=subject.p
		var height:=float(field.ground(before).height)
		life.threats=PackedVector4Array([Vector4(before.x-1,height+20.0,before.y,9.0)])
		check(life.threat_at(before,0,height)==Vector2.ZERO,"distant upper floors do not frighten ground residents")
		life.threats=PackedVector4Array([Vector4(before.x-1,height,before.y,9.0)])
		check(life.threat_at(before).x>0.9,"visible combat threat chooses an away direction")
		life._move(subject,0.10)
		check((subject.flee as Vector2).x>0.9 and (subject.p as Vector2).x>before.x,"resident actually flees the visible threat")
		life.threats.clear(); check(life.threat_at(before)==Vector2.ZERO,"no unseen unit contributes a phantom threat")
	var old_root:=life.root.get_instance_id()
	life.step(world,centre,life.clock+4.0,12.0)
	check(life.root.get_instance_id()!=old_root,"large clock gap replaces stale residents without a catch-up trail")
	var reset_clock:=life.clock
	if not life.flock.is_empty():
		for i in 32: life.step(world,centre,reset_clock+0.1*(i+1),0.0)
		check(life.flock.is_empty(),"day birds depart at night and do not respawn")
	old_root=life.root.get_instance_id()
	life.step(world,centre,1.0,12.0)
	check(life.root.get_instance_id()!=old_root and life.clock==1.0,"clock rewind starts a fresh local population")
	process_mode=Node.PROCESS_MODE_ALWAYS; get_tree().paused=true
	check(not life.can_process(),"Game's always-processing parent does not bypass ambient pause")
	await frame(); get_tree().paused=false; process_mode=Node.PROCESS_MODE_INHERIT
	old_root=life.root.get_instance_id()
	if load_world(id,false):
		life.step(world,centre,1.0,12.0)
		check(life.root.get_instance_id()!=old_root and life.field.terrain==world.terrain,"world reload discards old sources even at the same held clock")
	life.clear(); await frame()
	check(life.root==null and life.field==null and life.residents.is_empty() and life.particles==null,"disable/world exit releases local population and particle resources")
	life.free()


func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_wind":0,"gfx_ambient_wildlife":0,"gfx_ambient_particles":0,
		"gfx_grass":0,"gfx_biome_cover":0,"gfx_water":0,"gfx_water_waves":0,"gfx_taa":0,"gfx_ssao":0,"gfx_volumetric":0},true)
	campaign=CampaignMap.load_from(GameData.texts)
	view=SubViewport.new(); view.size=Vector2i(1280,900); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	camera=Camera3D.new(); view.add_child(camera)
	var env:=WorldEnvironment.new(); env.name="AmbientEnvironment"; env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.13,0.18,0.23); view.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.name="AmbientSun"; sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.6,0.6,0.6),Color(0.75,0.75,0.75)); Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var id := "gz1g" if GameData.campaign_id==CampaignProfile.ORIGINAL else "gz9g"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ambient-zone="): id=arg.trim_prefix("--ambient-zone=")
		if arg.begins_with("--ambient-hour="): render_hour=float(arg.trim_prefix("--ambient-hour="))
		if arg.begins_with("--ambient-kind="): requested_kind=int(arg.trim_prefix("--ambient-kind="))
		if arg.begins_with("--ambient-species="): requested_species=arg.trim_prefix("--ambient-species=")
	rules(); models()
	if not "--ambient-render-only" in OS.get_cmdline_user_args(): census()
	await lifetime(id,DisplayServer.get_name()!="headless")
	var file:=FileAccess.open("user://ambient-receipt.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"campaign":GameData.campaign_id,"checks":checks,"failures":failures,"rows":rows},"\t")); file.close()
	print("AMBIENT_LIFE ",GameData.campaign_id," ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
