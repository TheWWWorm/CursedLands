extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func has_trident(model: Node) -> bool:
	for mesh: Node in model.find_children("*", "MeshInstance3D",true,false):
		if "trident" in String(mesh.get_path()): return true
	return false
func _ready() -> void:
	var mob := EIMob.load_bytes(GameData.read_file("maps/bz4g.mob"))
	var record := {}
	for o: Dictionary in mob.objects:
		if o.get("template","")=="unmoli": record=o; break
	check(not record.is_empty(),"original camp lizard record found")
	var model := EIUnitModel.create(record)
	add_child(model)
	check(has_trident(model),"original lizard carries its natural trident")
	var omitted := record.duplicate(true)
	omitted.parts=PackedStringArray(["hp","bd","nc","hd","lh1","lh2","lh3","rh1","rh2","rh3","ll1","ll2","ll3","rl1","rl2","rl3","tl1","tl2"])
	var bare := EIUnitModel.create(omitted); add_child(bare); bare.position.x=2.0
	check(not has_trident(bare),"explicit authored part omission still hides the trident")
	var camera:=Camera3D.new(); add_child(camera); camera.current=true
	camera.position=Vector3(5,3.2,6); camera.look_at(Vector3(0.8,1.0,0))
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-40,-35,0); add_child(light)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0.14,0.16,0.18)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=0.7
	add_child(environment)
	for i in 12: await get_tree().process_frame
	if DisplayServer.get_name()!="headless":
		check(get_viewport().get_texture().get_image().save_png("user://lizard-trident.png")==OK,"original-model trident render captured")
		print("LIZARD_IMAGE ",ProjectSettings.globalize_path("user://lizard-trident.png"))
	model.queue_free(); bare.queue_free(); camera.queue_free(); light.queue_free(); environment.queue_free()
	for i in 8: await get_tree().process_frame
	print("LIZARD_TRIDENT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
