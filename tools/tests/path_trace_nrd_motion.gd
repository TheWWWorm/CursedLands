extends "res://tools/tests/path_trace_motion.gd"
func _init() -> void:custom_history=false
func native_sequence() -> void:
	size=Vector2i(160,90);camera.size=8;camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var value:=Color()
	for i in 20:value=await native_frame({"instances":[{"index":motion_index,"transform":Transform3D.IDENTITY,"mask":7}]} if i==0 else {},i>0)
	check(device.nrd_active and value.a>8,"NRD accumulates the stationary rigid surface")
	var moved:=Transform3D(Basis(Vector3.UP,0.15),Vector3(0.2,0,0.1))
	value=await native_frame({"instances":[{"index":motion_index,"transform":moved,"mask":7}]})
	check(device.nrd_active and value.a>1 and is_finite(value.r),"NRD world motion retains valid rigid-surface history")
	await native_frame({"instances":[{"index":motion_index,"transform":moved,"mask":0}]})
	value=await native_frame({"instances":[{"index":motion_index,"transform":moved,"mask":7}]})
	check(value.a<=1.01,"NRD rejects newly visible instance history")
	for i in 8:await native_frame()
	value=await native_frame({"poses":[{"geometry":0,"data":mesh_data.to_byte_array()}]})
	check(value.a<=1.01,"NRD confidence rejects untracked deformation")
	for i in 8:await native_frame()
	size=Vector2i(127,71);value=await native_frame()
	check(device.nrd_active and value.a<=1.01,"NRD odd-sized resize restarts motion history")
