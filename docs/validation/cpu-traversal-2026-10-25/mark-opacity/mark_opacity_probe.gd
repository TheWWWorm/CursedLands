extends Node
const Candidate=preload("mark_opacity_candidate.gd")
class Spy extends ShaderMaterial:
	var writes:=0
	@warning_ignore("native_method_override")
	func set_shader_parameter(param: StringName, value: Variant) -> void:
		writes+=1
		super.set_shader_parameter(param,value)
func mark()->GroundMarks.Mark:
	var m:=GroundMarks.Mark.new()
	m.foot=true;m.life=10000000;m.fade=100;m.alpha0=.8
	m.decal=Decal.new();m.decal.modulate=Color(1,1,1,GroundMarks._decal_alpha(m.alpha0))
	m.projection=MeshInstance3D.new()
	var mat:=Spy.new();var shader:=Shader.new()
	shader.code="shader_type spatial; uniform float opacity=1.0; void fragment(){ALBEDO=vec3(1.0);ALPHA=opacity;}"
	mat.shader=shader;mat.set_shader_parameter(&"opacity",GroundMarks._decal_alpha(m.alpha0));mat.writes=0
	m.projection.material_override=mat
	return m
func _ready()->void:
	var old:=GroundMarks.new();var candidate:=Candidate.new()
	var a:=mark();var b:=mark()
	for i in 100:old._update(a);candidate._update(b)
	print("MARK_OPACITY_PROBE ",JSON.stringify({"script_writes":a.projection.material_override.writes,"candidate_writes":b.projection.material_override.writes,"same_color":a.decal.modulate==b.decal.modulate,"same_shader_value":a.projection.material_override.get_shader_parameter(&"opacity")==b.projection.material_override.get_shader_parameter(&"opacity"),"raw_alpha":GroundMarks._decal_alpha(.8),"stored_alpha":a.decal.modulate.a}))
	var rows:=[]
	for use_candidate:bool in [false,true,true,false]:
		var collector:GroundMarks=candidate if use_candidate else old
		var current:=b if use_candidate else a
		var start:=Time.get_ticks_usec()
		for i in 100000:collector._update(current)
		rows.append({"candidate":use_candidate,"calls":100000,"usec":Time.get_ticks_usec()-start})
	print("MARK_OPACITY_PROBE_TIMING ",JSON.stringify(rows))
	for m in [a,b]:m.decal.free();m.projection.free()
	old.free();candidate.free();get_tree().quit()
