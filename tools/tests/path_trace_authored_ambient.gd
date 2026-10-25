extends "res://tools/tests/path_trace_contacts.gd"
## Authored interior irradiance is a diffuse minimum, never outdoor sky or
## an extra light added to an already lit surface. Inspect raw transport.
var ambient := Vector3(0.07,0.07,0.10)

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	for i in 3:bytes.encode_float((167+4*i)*4,ambient[i])
	return bytes

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native interior-lighting device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.8
	size=Vector2i(256,144);spp=1;bounces=2
	check(await contact_fixture(0.005,Transform3D.IDENTITY,"sky",false),"build enclosed receiver with a black roof")
	sky_energy=0.0
	var interior:=await capture("authored-interior")
	check(absf(interior.mean[0]-ambient.x)<0.001 and absf(interior.mean[2]-ambient.z)<0.001,"unlit cave retains its authored coloured diffuse floor")
	ambient=Vector3.ZERO
	var physical:=await capture("no-authored-interior")
	check(physical.peak<0.0001,"interior minimum is absent when the level supplies none")
	check(await contact_fixture(0.0),"build sunlit receiver")
	ambient=Vector3(0.07,0.07,0.10)
	var sunlit:=await capture("sunlit-with-interior-minimum")
	check(absf(sunlit.mean[0]-1.0)<0.005,"authored minimum does not add brightness above stronger traced sunlight")
	ambient=Vector3.ZERO
	var outdoor:=await capture("sunlit-without-interior-minimum")
	check(absf(outdoor.mean[0]-sunlit.mean[0])<0.001,"outdoor transport is unchanged")
	FileAccess.open(out.path_join("authored-ambient.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":report},"\t"))
	finish()
