extends Node
## Camera policy and attribute ownership, independent of content/art.
class BareGame extends Game:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _unhandled_input(_event: InputEvent) -> void: pass

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func aim(cam: Camera3D, degrees: float, distance := 20.0) -> Vector3:
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-deg_to_rad(degrees),0,0)),Vector3(0,20,0))
	return cam.global_position - cam.global_basis.z * distance

func _ready() -> void:
	check(CameraDepthOfField.pitch_factor(25)==1.0 and CameraDepthOfField.pitch_factor(50)==0.0,"R1 exact low/tactical endpoints")
	check(is_equal_approx(CameraDepthOfField.pitch_factor(37.5),0.5),"R1 midpoint")
	var monotonic := true
	for i in range(-10,89): monotonic = monotonic and CameraDepthOfField.pitch_factor(i) >= CameraDepthOfField.pitch_factor(i+1)
	check(monotonic,"pitch ramp stays bounded and monotonic across camera range")
	check(not CameraDepthOfField.lens(50,20,1080).active and not CameraDepthOfField.lens(80,20,1080).active,"tactical views disable lens")
	check(CameraDepthOfField.lens(25,20,1080).active and is_equal_approx(CameraDepthOfField.lens(25,20,1080).begin,40.0),"far blur starts behind focus margin")
	check(CameraDepthOfField.supported("forward_plus")==OS.has_feature("ei_far_dof_guard") and CameraDepthOfField.supported("mobile")==OS.has_feature("ei_far_dof_guard") and not CameraDepthOfField.supported("gl_compatibility"),"backend policy requires native sharp-edge guard")
	check(GameData.option("gfx_depth_of_field")==0,"effect default is off")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true;add_child(viewport)
	var game := BareGame.new(); viewport.add_child(game)
	var rig := CameraRig.new(); game.add_child(rig); rig.set_process(false)
	if rig._depth_of_field: rig._depth_of_field.set_process(false)
	check((rig._depth_of_field!=null)==CameraDepthOfField.supported(),"unsupported runtime/backend creates no persistent effect node")
	var worker:=BareGame.new();worker.simulation_only=true;viewport.add_child(worker)
	var worker_rig:=CameraRig.new();worker.add_child(worker_rig);worker_rig.set_process(false)
	check(worker_rig._depth_of_field==null,"simulation worker allocates no effect helper")
	worker.free()
	var camera := rig.camera
	var target := aim(camera,25)
	var original := CameraAttributesPractical.new(); original.exposure_multiplier=0.75
	camera.attributes=original
	var fx := CameraDepthOfField.new(); add_child(fx); fx.set_process(false)
	fx.update(camera,target,0.1,false)
	check(camera.attributes==original and fx._attributes==null,"off keeps exact original attribute resource")
	fx.update(camera,target,0.1,true)
	if not CameraDepthOfField.supported():
		check(camera.attributes==original and fx._attributes==null,"unsupported backend allocates no blur resource")
	else:
		check(camera.attributes!=original and camera.attributes.exposure_multiplier==0.75 and not original.dof_blur_far_enabled,"enabled lens clones prior exposure without modifying owner")
		check(camera.attributes.dof_blur_far_enabled and not camera.attributes.dof_blur_near_enabled,"only far field blurs")
		var first: float=fx._focus
		fx.update(camera,aim(camera,25,40),0.1,true)
		check(fx._focus>first and fx._focus<40.0,"zoom/target changes focus smoothly")
		for i in 30: fx.update(camera,aim(camera,25,40),0.1,true)
		check(absf(fx._focus-40.0)<0.01,"focus settles without oscillation")
		fx.update(camera,aim(camera,50),0.1,true)
		check(camera.attributes==original and fx._attributes==null and fx._focus==0.0,"tactical view restores owner and drops focus history")
		fx.update(camera,aim(camera,25,12),0.1,true)
		check(is_equal_approx(fx._focus,12.0),"reactivating starts at current target")
		fx.update(camera,target,0.1,false)
		check(camera.attributes==original and fx._attributes==null,"disable restores exact attributes")
		camera.attributes=null
		camera.get_world_3d().camera_attributes=original
		fx.update(camera,aim(camera,25),0.1,true)
		check(camera.attributes.exposure_multiplier==0.75,"inherited world exposure is preserved")
		fx.clear(); check(camera.attributes==null,"clear restores world-attribute inheritance")
		camera.get_world_3d().camera_attributes=null
		camera.attributes=original; fx.update(camera,aim(camera,25),0.1,true)
		var replacement:=CameraAttributesPractical.new(); replacement.exposure_multiplier=0.9
		camera.attributes=replacement
		fx.update(camera,target,0.1,true); fx.update(camera,target,0.1,true)
		check(camera.attributes==replacement,"another attribute owner is not overwritten on following frames")
		fx.update(camera,target,0.1,false); fx.update(camera,target,0.1,true)
		check(camera.attributes!=replacement and is_equal_approx(camera.attributes.exposure_multiplier,0.9),"explicit re-enable adopts current owner settings")
		var other:=Camera3D.new(); viewport.add_child(other)
		fx.update(other,aim(other,25),0.1,true)
		check(camera.attributes==replacement and other.attributes!=null,"camera switch releases old camera before acquiring new")
		fx.clear();check(other.attributes==null,"new camera clears independently")
		other.free()
		var physical:=CameraAttributesPhysical.new();camera.attributes=physical
		fx.update(camera,aim(camera,25),0.1,true)
		check(camera.attributes==physical and fx._attributes==null,"physical camera policy is not replaced")
	rig.held=false;rig.position=Vector3(2,3,4)
	check(rig.presentation_focus()==rig.global_position,"ordinary focus uses orbit pivot")
	rig.hold_view(Vector3(0,10,20),Vector3(1,2,3))
	check(rig.presentation_focus()==Vector3(1,2,3),"dialogue focus uses actual held target")
	rig.release();check(rig.presentation_focus()==rig.global_position,"dialogue close releases target")
	fx.free();viewport.free()
	print("CAMERA_DEPTH_OF_FIELD %d checks %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
