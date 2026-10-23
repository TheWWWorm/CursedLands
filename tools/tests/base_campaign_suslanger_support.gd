extends "base_campaign_support.gd"
## Shared interactions for the Suslanger checkpoint programs.
func settle_loaded(names: Array) -> void:
	ticks(8); vm().instances.clear(); start(names)

func approach(id: int) -> void:
	var u: GameUnit = s.world.units.get(id)
	if check(u != null,"authored actor exists for approach: "+str(id)):
		teleport(u.pos+Vector2(0.1,0)); hero().facing = PI
		# Original perception candidates persist for up to eleven ticks.
		# Let the normal scan refresh after this accelerated approach.
		ticks(16)

func approach_object(id: int) -> void:
	var o: Node3D = s.world.objects.get(id)
	if check(o != null,"authored object exists for approach: "+str(id)):
		var p: Vector3 = o.get_meta("ei").position
		teleport(Vector2(p.x+1,p.y)); ticks(5)
