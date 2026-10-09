extends Node3D
## Small original figures, without a GameUnit, collision or registration.
## Shared figure/animation caches remain shared. Only five residents at most
## own skeleton nodes; decorative meshes never cast shadow maps.
const SPECS := {
	"rat":["unanwira","rat00",0.23], "snowmouse":["unanwira","rat00",0.16],
	"spider":["unmosp","spider00",0.19], "frog":["unmoto","toad00",0.16],
	"bird":["unmobi","bird00",0.22],
}
var player: AnimationPlayer
var figure: Node3D
var kind := ""
var body_length := 0.0
var mesh_count := 0
static var _tints := {}


func build(species: String) -> bool:
	if not SPECS.has(species): return false
	kind = species
	var spec: Array = SPECS[kind]
	figure = EIFigure.instantiate(spec[0],spec[1],Vector3.ZERO,PackedStringArray(),false,true)
	if figure==null: return false
	add_child(figure)
	var paths := {}; var bounds := AABB(); var first := true
	for node: Node3D in figure.find_children("*","Node3D",true,false):
		if not node is MeshInstance3D:
			paths[String(node.name)] = figure.get_path_to(node)
			continue
		var mesh := node as MeshInstance3D
		if mesh.mesh==null: continue
		# Original invisible helpers are not part of a tiny animal's size.
		if String(mesh.get_parent().name).to_lower() in ["box","box01"]: mesh.hide(); continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind in ["snowmouse","frog"] and mesh.material_override is ShaderMaterial:
			var original := mesh.material_override as ShaderMaterial
			var key := "%s:%d"%[kind,original.get_instance_id()]
			if not _tints.has(key):
				var material := original.duplicate() as ShaderMaterial
				var colour := "mix(t.rgb,vec3(0.76,0.76,0.71),0.80)" if kind=="snowmouse" else "t.rgb*vec3(0.70,0.93,0.48)"
				material.shader=Gfx.make_shader(EIFigure.OBJECT_SHADER.replace("ALBEDO = t.rgb;","ALBEDO = "+colour+";"))
				_tints[key]=material
			mesh.material_override=_tints[key]
		mesh_count += 1
		var xf := Transform3D.IDENTITY
		var part := node
		while part!=figure:
			xf = part.transform*xf; part = part.get_parent() as Node3D
		var box := xf*mesh.get_aabb()
		bounds = box if first else bounds.merge(box); first = false
	if first: return false
	body_length = maxf(bounds.size.x,bounds.size.z)
	if body_length<0.001: return false
	var factor := float(spec[2])/body_length
	figure.scale = Vector3.ONE*factor
	figure.position.y = -bounds.position.y*factor
	body_length = float(spec[2])
	var model := EIFigure.get_model(spec[0])
	var root_part: String = model.links[0][0] if not model.links.is_empty() else ""
	player = AnimationPlayer.new(); figure.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("ei",EIAnim.library(spec[0],paths,root_part))
	player.speed_scale = 0.0
	pose(0.0,false)
	return true


func pose(seconds: float, moving: bool, running := false) -> void:
	if player==null: return
	var clip := "cflight" if kind=="bird" else ("crun" if running else ("cwalk" if moving else "cidle"))
	if not player.has_animation("ei/"+clip): clip = "cwalk" if moving else "cidle"
	if not player.has_animation("ei/"+clip): return
	if player.current_animation!="ei/"+clip: player.play("ei/"+clip)
	var duration := player.get_animation("ei/"+clip).length
	player.seek(fposmod(seconds,maxf(duration,0.001)),true)
