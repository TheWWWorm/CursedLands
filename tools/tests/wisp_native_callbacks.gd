extends Node
## Compare ported callbacks with actual x86 callback replay, not a second formula.
class RecordedEmitter extends FxEmitter:
	var draws: Array
	var used := 0
	func rnd() -> int:
		var value := int(draws[used]); used += 1
		return value

class BoundsFx extends ParticleFx:
	var radius := 1.6
	func carrier_size(_obj: Object) -> Vector2:
		return Vector2(1.2,radius)

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func _ready() -> void:
	var source: String = get_script().resource_path.get_base_dir().path_join("fixtures/wisp_native_callbacks.json")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var fx := BoundsFx.new()
	for c: Dictionary in fixture.cases:
		var u := GameUnit.new(); u.restore_gait(int(c.gait)); u.dead = bool(c.dead)
		var e := RecordedEmitter.new(); e.fx = fx; e.draws = c.draws
		e.flags = 0x13; e.s = .05; e.d0 = 1
		e.wp = Vector3(c.origin[0],c.origin[1],c.origin[2]); fx.radius = float(c.radius)
		if c.carrier: e.attach(u)
		var p := FxEmitter.new_particle()
		for i in c.steps.size():
			var expected: Dictionary = c.steps[i]
			var result := fx.types.sp_wisp(e,p,0) if i==0 else fx.types.up_wisp(e,p)
			var label := String(c.label)+" step "+str(i)
			check(result==expected["return"],label+" return")
			for field in 8:
				var index: int = [0,1,2,3,8,0x11,0x14,0x16][field]
				check(absf(float(p[index])-float(expected.particle[field])) < 0.000002,label+" field "+str(index))
			check(e.flags==int(expected.flags) and e.d0==int(expected.d0),label+" emission")
			check(e.has_carrier==bool(expected.carrier),label+" attachment")
			check(e.used==int(expected.rng_used),label+" random consumption")
			e.wp += Vector3(10,10,10)
		u.free()
	fx.free()
	print("WISP_NATIVE_CALLBACKS checks=",checks," failures=",failures," cases=",fixture.cases.size())
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
