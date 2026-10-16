extends Node
## Diagnostic only: measures shared script work with the same release runtime
## and a dummy renderer. This is not a GPU or end-to-end FPS measurement.
var rows := []

func measure(label: String, callback: Callable) -> void:
	for i in 1000: callback.call()
	var batches := []
	for batch in 9:
		var start := Time.get_ticks_usec()
		for i in 5000: callback.call()
		batches.append(float(Time.get_ticks_usec()-start)/5000.0)
	var sorted := batches.duplicate(); sorted.sort()
	rows.append({"case":label,"microseconds_per_call":batches,"median_us":sorted[sorted.size()/2]})

func _ready() -> void:
	GameData.options.merge({"gfx_soft_particles":0,"gfx_lit_particles":0,"gfx_bloom":0,"gfx_firelight":0},true)
	Gfx.ensure_globals()
	var fx := ParticleFx.new()
	fx._material("firesmoke",false,false,true)
	fx._material("firesmoke",true,true,false,true)
	fx._material("firesmoke",false,false,false,false,true,true)
	fx._material("firesmoke",true,true)
	measure("four_particle_materials_unchanged",fx._apply_material_options)
	var lights: Array[OmniLight3D] = []
	for i in 6:
		var light := OmniLight3D.new(); add_child(light)
		light.position=Vector3(i*2,0,0);light.omni_range=10;light.omni_attenuation=0
		light.add_to_group(Gfx.POINT_LIGHT_GROUP);lights.append(light)
	measure("six_original_point_lights_unchanged",func():Gfx.update_pass_lights(get_tree(),Vector3.ZERO))
	FileAccess.open("user://shared-cpu-probe.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"renderer":RenderingServer.get_current_rendering_method(),"scope":"CPU microbenchmark with dummy renderer; excludes native rendering and GPU work"},"\t"))
	for row in rows: print("SHARED_CPU ",JSON.stringify(row))
	fx.free();TexUpscale.shutdown();UnitWounds.shutdown();get_tree().quit()
