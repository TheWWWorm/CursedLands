extends RefCounted
## Release large CPU snapshots a few records at a time. Shared caches are not
## placed here; only containers owned by the retired scene/device may be drained.
var parts: Array = []
var _keys: Array = []

func step(budget_us := 1000,max_items := 256) -> bool:
	var started:=Time.get_ticks_usec();var count:=0
	while not parts.is_empty():
		var part: Variant=parts.back()
		if part is Array and not part.is_empty():part.pop_back()
		elif part is Dictionary and not part.is_empty():
			if _keys.is_empty():_keys=part.keys()
			part.erase(_keys.pop_back())
		else:
			parts.pop_back();_keys.clear()
		# A packed buffer or last RefCounted owner can be the large object.
		# Release the temporary before measuring the step's actual work.
		part=null;count+=1
		if (max_items>0 and count>=max_items) or (budget_us>0 and Time.get_ticks_usec()-started>=budget_us):break
	return parts.is_empty()

func finish() -> void:
	step(0,0)
