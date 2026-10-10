extends "res://src/game/fx/water_surface.gd"
## Frozen eager phase initialization and vertex query from 3f6fa6d.

func _init(t: EITerrain) -> void:
	_phase = WaveState.phase_grid()
	super(t)

func _vertex(record: Dictionary, index: int, transform: Transform3D) -> Vector3:
	if int(record.frame) != _frame:
		record.ready.fill(0); record.frame = _frame
	if record.ready[index] != 0: return record.posed[index]
	var encoded := int(record.uv2[index].y+0.5)
	var material := clampi(encoded%64,0,63)
	var p: Vector3 = record.vertices[index]
	p.y += float(terrain.water_offsets.get(material,0.0))
	var world := transform*p
	if _waves and material < terrain.materials.size():
		var authored: Dictionary = terrain.materials[material]
		var ei := Vector3(world.x,-world.z,world.y)
		var cell := Vector2i(posmod(floori(ei.x+0.5),32),posmod(floori(ei.y+0.5),32))
		var moved := terrain._waves.vertex(ei,cell,int(authored.get("type",0)),
			float(authored.get("wave",0.0)),_phase[cell.y*33+cell.x],encoded >= 64)
		# The shader evaluates phase in world coordinates but adds displacement
		# in local coordinates, before MODEL_MATRIX. Preserve that order.
		var delta := moved-ei
		world = transform*(p+Vector3(delta.x,delta.z,-delta.y))
	record.posed[index] = world; record.ready[index] = 1
	return world

