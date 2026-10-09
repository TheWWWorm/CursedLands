extends "renderer_world_lifecycle.gd"
## Final P1/P2 composition: the existing real Game/cloud lifetime scene also
## owns compressed raw terrain and a wounded actor, its selection and Paperdoll.
## Prepared health/equipment controls, not a combat or frame-time benchmark.

func installed(label: String) -> void:
	super.installed(label)
	var terrain := host.world.terrain
	check(not terrain._atlas_hd and terrain._atlases is Texture2DArray,
		label+": actual world uses the HD-off raw terrain array")
	check(terrain._atlases.get_format() == Image.FORMAT_DXT1,
		label+": authored base map retains compressed terrain through lifecycle")


func texture_snap(view: SubViewport, label: String) -> Image:
	await frames(20)
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	check(result.save_png("user://texture-integration-"+label+".png")==OK,
		"capture "+label)
	return result


func settle_wounds(doll: Paperdoll) -> void:
	doll._sync_pose()
	check(await until(func(): return UnitWounds._jobs.is_empty(),5.0),
		"actual world and Paperdoll publish wounds through ordinary frame polling")
	doll._sync_pose()


func material_snapshot(model: EIUnitModel) -> Dictionary:
	var result := {}
	for material: Material in UnitWounds._materials(model):
		result[material] = material.albedo_texture
	return result


func shared_wounds(models: Array, label: String) -> void:
	var textures := {}
	var count := 0
	for model: EIUnitModel in models:
		for material: Material in UnitWounds._materials(model):
			count += 1
			check(material is EIUnitModel.LitMaterial or material is EIUnitModel.PreviewMaterial,
				label+": shipped shader material")
			check(material.wound_texture != null,label+": visible damage texture is bound")
			if material.wound_texture: textures[material.wound_texture.get_instance_id()] = true
	check(count > 1 and textures.size()==1,label+": world, selection and preview share one wound upload")
	check(UnitWounds._composites.is_empty() and UnitWounds._bases.is_empty(),
		label+": actual figure paths create no replacement albedo/cache")


func authored_weapon() -> String:
	for weapon: Dictionary in GameData.db.table("weapons"):
		if weapon.get("type","")!="dagger": continue
		for material: Dictionary in GameData.db.table("materials"):
			if weapon.get("material_type") == material.get("type"):
				return String(weapon.name).to_lower()+"."+String(material.name).to_lower()
	return ""


func hold_idle(model: EIUnitModel) -> void:
	model.set_process(false)
	model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.act("idle",1,0.0)
	model.player.seek(0.3,true)
	model.player.speed_scale=0.0
	check(not model.player.assigned_animation.is_empty(),"figure holds an authored idle pose")


func place_on_clear_ground(actor: GameUnit) -> void:
	var habitats := Ambient.Habitats.new(host.world.terrain)
	for radius: float in [0.0,2.0,4.0,8.0]:
		for direction in 16:
			var at := point+Vector2.from_angle(direction*TAU/16.0)*radius
			var land := habitats.habitat(at)
			if land.is_empty() or land.wet or not land.clear: continue
			if absf((land.normal as Vector3).y)<0.94 or not host.world.nav.is_walkable(at): continue
			actor.pos=at; actor.facing=-GameUnit.MODEL_YAW_OFFSET
			actor.resync_drawn()
			check(true,"prepared actor stands on verified clear walkable ground")
			return
	check(false,"prepared actor stands on verified clear walkable ground")


func rendered_composition() -> void:
	if DisplayServer.get_name()=="headless": return
	await super.rendered_composition()
	var party := host.party_units(0)
	check(not party.is_empty(),"actual Game has its original hero")
	if party.is_empty(): return
	var actor: GameUnit = party[0]
	var original_position := actor.pos
	var original_facing := actor.facing
	# PartyFaces/UnitPanel redraw health from the prepared part changes. Keep
	# their pixels out of the world comparison so only the body proves wounds.
	host.game.hud.hide()
	var marks := host.game.marks
	marks.set_process(false)
	marks._lighten(actor.model,false)
	actor.set_equipment(PackedStringArray(),PackedStringArray())
	actor.set_process(false); actor.set_physics_process(false)
	hold_idle(actor.model)
	place_on_clear_ground(actor)
	for part: UnitBodyPart in actor.parts: part.cur=part.max
	UnitWounds.update(actor)
	var camera := host.game.rig.camera
	lens.clear()
	camera.global_position=actor.global_position+Vector3(2.8,2.4,4.5)
	camera.look_at(actor.global_position+Vector3(0,0.9,0))
	var doll := Paperdoll.new()
	doll.follow_pose=true
	add_child(doll)
	doll.show_unit(actor)
	await frames(12)
	doll.set_process(false); doll._model.set_process(false)
	doll._vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	await settle_wounds(doll)
	var world_bases := material_snapshot(actor.model)
	var doll_bases := material_snapshot(doll._model)
	var healthy := await texture_snap(host.get_viewport(),"world-healthy")
	var healthy_doll := await texture_snap(doll._vp,"paperdoll-healthy")
	var held := difference(healthy,await texture_snap(host.get_viewport(),"world-held"))
	check(held.channels_over_2==0,"held actual-world texture control is stable within 2/255")
	for part: UnitBodyPart in actor.parts: part.cur=part.max*0.5
	UnitWounds.update(actor)
	await settle_wounds(doll)
	shared_wounds([actor.model,doll._model],"damaged")
	for material in world_bases:
		check(material.albedo_texture==world_bases[material],"actual world keeps its unwounded base identity")
	for material in doll_bases:
		check(material.albedo_texture==doll_bases[material],"actual Paperdoll keeps its unwounded base identity")
	var wounded := await texture_snap(host.get_viewport(),"world-wounded")
	var wounded_doll := await texture_snap(doll._vp,"paperdoll-wounded")
	var world_delta := difference(healthy,wounded)
	var doll_delta := difference(healthy_doll,wounded_doll)
	check(world_delta.channels_over_2>32,"wounds visibly affect the composed world figure")
	check(doll_delta.channels_over_2>32,"wounds visibly affect the actual Paperdoll")
	marks._lighten(actor.model,true)
	var highlighted := 0
	var valid_copies := true
	var valid_textures := true
	for mesh: MeshInstance3D in actor.model.find_children("*","MeshInstance3D",true,false):
		if not mesh.has_meta("unlit"): continue
		var base: Material = mesh.get_meta("unlit")
		var bright := mesh.material_override as EIUnitModel.LitMaterial
		if bright == null: continue
		highlighted += 1
		valid_copies = valid_copies and bright!=base and marks._bright.get(base)==bright
		valid_textures = valid_textures and bright.albedo_texture==base.albedo_texture and bright.wound_texture==base.wound_texture
	check(highlighted>0,"actual world figure has active selection replacements")
	check(valid_copies,"every selected part uses its active bright material copy")
	check(valid_textures,"every active selection copy retains both base and wound texture identity")
	shared_wounds([actor.model,doll._model],"selected")
	await texture_snap(host.get_viewport(),"world-selected")
	marks._lighten(actor.model,false)
	for part: UnitBodyPart in actor.parts: part.cur=part.max
	UnitWounds.update(actor)
	await settle_wounds(doll)
	check(difference(healthy,await texture_snap(host.get_viewport(),"world-healed")).channels_over_2==0,
		"healing restores the composed world within 2/255")
	check(difference(healthy_doll,await texture_snap(doll._vp,"paperdoll-healed")).channels_over_2==0,
		"healing restores the actual Paperdoll within 2/255")
	# Exercise the actual equipment replacement, not an in-place test texture.
	for part: UnitBodyPart in actor.parts: part.cur=part.max*0.5
	UnitWounds.update(actor)
	var old_model := weakref(actor.model)
	var old_preview := weakref(doll._model)
	var preview_view := doll._vp
	var weapon := authored_weapon()
	check(not weapon.is_empty(),"original database supplies a valid dagger/material pair")
	actor.set_equipment(PackedStringArray(),PackedStringArray([weapon]))
	hold_idle(actor.model)
	UnitWounds.update(actor)
	doll.show_unit(actor)
	for i in 3: doll._process(0.1)
	doll.set_process(false); doll._model.set_process(false)
	await settle_wounds(doll)
	await frames(8)
	check(old_model.get_ref()==null,"actual redress retires the previous world figure")
	check(old_preview.get_ref()==null and doll._vp==preview_view and doll._pairs_src==actor.model,
		"Paperdoll retires the old figure and follows the replacement in its retained viewport")
	check(doll._framed>=3 and not is_instance_valid(doll._old_pivot) and doll._pivot.visible,
		"redressed Paperdoll has completed its normal framed swap")
	shared_wounds([actor.model,doll._model],"redressed")
	await texture_snap(doll._vp,"paperdoll-redressed")
	rows.append({"case":"actual-texture-owners","world_delta":world_delta,
		"paperdoll_delta":doll_delta,"held":held,"highlighted_parts":highlighted,
		"raw_format":host.world.terrain._atlases.get_format(),
		"scope":"Prepared real GameUnit, equipment replacement and Paperdoll; no combat or performance claim."})
	doll.free()
	UnitWounds.shutdown()
	# Ambient placement intentionally avoids visible actors. Restore the hero
	# and camera before the superclass tests effect re-admission on this patch.
	actor.pos=original_position; actor.facing=original_facing
	actor.resync_drawn()
	configure_view()
	await frames(8)
