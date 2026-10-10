extends "ground_contact_relief_scene.gd"
## Stamp the real footprint field at an unchanged authored snow/object root.
## This observes the material/light response; it is not a physical walking test.

func run_scene() -> void:
	GameData.options.gfx_soft_ground=1
	Gfx.apply_surface_options()
	await super.run_scene()


func root_anchor(object: Node3D, terrain: EITerrain) -> Vector3:
	var anchor := super.root_anchor(object,terrain)
	if not anchor.is_finite(): return anchor
	var soft := terrain.details.soft_ground
	check(soft!=null,"native footprint owner exists")
	if soft==null: return Vector3.INF
	terrain.details.set_process(false); soft.set_process(false); soft._age=123.0
	var centre := Vector2(anchor.x,-anchor.z)
	var outward := Vector2(VIEW_DIRECTION.x,-VIEW_DIRECTION.z)
	var stamps := []
	for i in 5:
		var p := centre+outward*(0.70-float(i)*0.23)
		var allowed := soft.step_allowed(p)
		check(allowed,"authored snow supports footprint at "+str(p))
		if allowed:
			soft.add_step(p,Vector2(.12,.23),.3)
			stamps.append(str(p))
	check(not soft._queue.is_empty(),"actual footprint jobs queued")
	for i in 16:
		soft._process(0.0); soft._finish_mesh_jobs(true)
		if soft._mesh_jobs.is_empty() and soft._queue.is_empty() and not soft.sectors.values().any(func(row: Dictionary) -> bool: return row.build_pending): break
	check(soft._mesh_jobs.is_empty() and soft._queue.is_empty(),"actual footprint jobs finish")
	check(not soft.sectors.is_empty(),"actual dense replacement geometry installed")
	anchor_witness["footprints"]={"positions":stamps,"clock":soft._age,"installed_sectors":soft.sectors.size(),
		"ground_type":terrain.ground_type(centre.x,centre.y),"controlled_stamps":true}
	return anchor


func light_case(mode: String, view: SubViewport, object: Node3D, owner: GroundContact,
		sun: DirectionalLight3D, point: OmniLight3D, anchor: Vector3) -> void:
	await super.light_case(mode,view,object,owner,sun,point,anchor)
	GameData.options.gfx_ground_contact=1; owner.refresh()
	var on := await capture(view,"tracks-"+mode+"-on")
	var saved := {}
	for mesh in target_meshes(object):
		var material := mesh.material_override as ShaderMaterial
		if saved.has(material): continue
		var source := material.shader
		const MARKER := "result.normal=track_normal;"
		check(source.code.count(MARKER)==1,"one copied-ground track-normal assignment")
		if source.code.count(MARKER)!=1: continue
		var program := Shader.new()
		program.code=source.code.replace(MARKER,"/* diagnostic: copied-ground track normal disabled */")
		check(not program.get_shader_uniform_list().is_empty(),"actual track-normal ablation compiles")
		saved[material]=source; material.shader=program
	var control := await capture(view,"tracks-"+mode+"-normal-disabled")
	var effect := difference(on,control,"band")
	var outside := difference(on,control,"outside_band")
	check(effect.over_two_bytes>8,mode+" native track normals affect lit object band "+str(effect))
	check(outside.changed_pixels==0,mode+" track-normal response stays in contact band")
	for material: ShaderMaterial in saved: material.shader=saved[material]
	var restored := await capture(view,"tracks-"+mode+"-normal-restored")
	check(difference(on,restored).changed_pixels==0,mode+" track-normal restoration is exact")
	rows.append({"light":"tracks-"+mode,"band_normal_response":effect,"outside_band":outside,
		"scope":"Native field stamps and installed terrain; only copied-ground normal ablated, no geometry or colour change."})
	GameData.options.gfx_ground_contact=0; owner.refresh()
