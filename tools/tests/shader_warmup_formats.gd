extends Node
## Large meshes need a layout-equivalent representative, not an uploaded copy
## of every source vertex. Cover compression, index and custom/bone channels.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	for primitive in [Mesh.PRIMITIVE_POINTS, Mesh.PRIMITIVE_LINES, Mesh.PRIMITIVE_LINE_STRIP, Mesh.PRIMITIVE_TRIANGLES, Mesh.PRIMITIVE_TRIANGLE_STRIP]:
		for indexed in [false,true]:
			for compressed in [false,true]:
				ShaderWarmup._formats.clear()
				var count := 12000
				var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
				var vertices := PackedVector3Array(); vertices.resize(count); vertices.fill(Vector3.ONE)
				var normals := PackedVector3Array(); normals.resize(count); normals.fill(Vector3.UP)
				var tangents := PackedFloat32Array(); tangents.resize(count*4); tangents.fill(1.0)
				var colours := PackedColorArray(); colours.resize(count); colours.fill(Color.WHITE)
				var uv := PackedVector2Array(); uv.resize(count); uv.fill(Vector2.ONE)
				var custom := PackedFloat32Array(); custom.resize(count*2); custom.fill(0.25)
				var bones := PackedInt32Array(); bones.resize(count*4)
				var weights := PackedFloat32Array(); weights.resize(count*4); weights.fill(0.25)
				arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TANGENT]=tangents
				arrays[Mesh.ARRAY_COLOR]=colours; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_CUSTOM0]=custom
				arrays[Mesh.ARRAY_BONES]=bones; arrays[Mesh.ARRAY_WEIGHTS]=weights
				if indexed:
					var indices := PackedInt32Array()
					for i in count: indices.append(i)
					arrays[Mesh.ARRAY_INDEX]=indices
				var flags := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
				if compressed: flags |= Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
				var source := ArrayMesh.new(); source.add_surface_from_arrays(primitive,arrays,[],{},flags)
				var original := source.surface_get_arrays(0)
				var warmed := ShaderWarmup._zero_format(source) as ArrayMesh
				var label := "%d indexed=%s compressed=%s" % [primitive,indexed,compressed]
				check(warmed != null,"representative exists "+label)
				if warmed == null: continue
				var result := warmed.surface_get_arrays(0)
				check(result[Mesh.ARRAY_VERTEX].size() <= 3,"bounded representative vertex count "+label)
				check(warmed.surface_get_format(0) == source.surface_get_format(0) and warmed.surface_get_primitive_type(0) == primitive,"exact source vertex format and primitive "+label)
				check(result[Mesh.ARRAY_VERTEX].count(Vector3.ZERO) == result[Mesh.ARRAY_VERTEX].size(),"representative has zero area "+label)
				check(source.surface_get_arrays(0) == original,"preparation leaves source data untouched "+label)
				check(ShaderWarmup._zero_format(source) == warmed,"matching layouts reuse one representative "+label)
	ShaderWarmup._formats.clear()
	print("SHADER_WARMUP_FORMATS ",checks," checks ",failures," failures")
	get_tree().quit(int(failures > 0))
