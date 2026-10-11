extends Node
const Reflection = preload("res://src/game/fx/water_reflection.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	# For any camera angle, points on the mirror plane must project to the
	# same height/depth, with only the deliberate horizontal reversal.
	for angles: Vector3 in [Vector3(-0.04,0,0),Vector3(-0.6,0.7,0),Vector3(-1.3,-1.2,0.25)]:
		for level in [-3.0,4.176689,22.0]:
			var source := Transform3D(Basis.from_euler(angles),Vector3(12,level+5,-30))
			var reflected := Reflection.reflected_transform(source,level)
			var point := Vector3(15,level,-44)
			var a := source.affine_inverse()*point
			var b := reflected.affine_inverse()*point
			check(b.is_equal_approx(Vector3(-a.x,a.y,a.z)),"water-plane projection aligns for angle %s, level %s"%[angles,level])
			check(is_equal_approx(reflected.basis.determinant(),1.0),"reflected camera retains a right-handed orthonormal basis")
			var object := Vector3(16,level+8,-48)
			var mirrored_object := Vector3(object.x,2*level-object.y,object.z)
			a = source.affine_inverse()*mirrored_object
			b = reflected.affine_inverse()*object
			check(b.is_equal_approx(Vector3(-a.x,a.y,a.z)),"geometry reflection matches a virtual mirrored object")
	check(Reflection.target_size(Vector2(1280,720))==Vector2i(640,360),"ordinary views use half resolution")
	check(Reflection.target_size(Vector2(5120,2880))==Vector2i(1024,576),"large displays obey the reflection pixel budget")
	check(Reflection.target_size(Vector2(720,1280))==Vector2i(360,640),"portrait views keep their aspect ratio")
	check((0xFFFFF & Reflection.CAMERA_MARKER)==0,"ordinary cameras cannot trigger reflected-view clipping")
	check((Reflection.WATER_LAYER & Reflection.CAMERA_MARKER)==0,"water geometry and reflected camera marker are distinct")
	TexUpscale.shutdown()
	print("WATER_REFLECTION_GEOMETRY checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
