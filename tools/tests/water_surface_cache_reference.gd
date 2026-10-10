extends "res://src/game/fx/water_surface.gd"
## Frozen 3d7c79d query, before mean-triangle caching.
## Sector indexing and per-frame vertex evaluation are unchanged and inherited.

func sample(point: Vector2) -> Dictionary:
	if not is_instance_valid(terrain) or not point.is_finite(): return {}
	var local := terrain.to_local(Vector3(point.x,terrain.global_position.y,point.y))
	# A deformed edge can cross a sector boundary. Authored water currently
	# uses axis-aligned map transforms; the triangle test itself is in world.
	# Tight candidate bounds avoid loading nine full sectors for a query well
	# inside one sector. Type-4 vertices can inherit up to 128/252 m land XY.
	var reach := _margin+128.0/252.0
	var first := Vector2i(floori((local.x-reach)/32.0),floori((-local.z-reach)/32.0))
	var last := Vector2i(floori((local.x+reach)/32.0),floori((-local.z+reach)/32.0))
	var best := {}
	for sy in range(maxi(0,first.y),mini(terrain.sectors_y,last.y+1)):
		for sx in range(maxi(0,first.x),mini(terrain.sectors_x,last.x+1)):
			var key := Vector2i(sx,sy)
			var record := _sector(key)
			if record.is_empty(): continue
			var node := (record.node as WeakRef).get_ref() as MeshInstance3D
			if node == null or node.mesh == null or node.mesh != (record.mesh as WeakRef).get_ref():
				_sectors.erase(key); continue
			var xf := node.global_transform
			var p := node.to_local(Vector3(point.x,node.global_position.y,point.y))
			var bucket := Vector2i(floori(p.x/BUCKET),floori(-p.z/BUCKET))
			for at: int in record.buckets.get(bucket,PackedInt32Array()):
				var ia: int = record.indices[at]; var ib: int = record.indices[at+1]; var ic: int = record.indices[at+2]
				var a := _vertex(record,ia,xf); var b := _vertex(record,ib,xf); var c := _vertex(record,ic,xf)
				var ab := Vector2(b.x-a.x,b.z-a.z); var ac := Vector2(c.x-a.x,c.z-a.z)
				var ap := point-Vector2(a.x,a.z)
				var det := ab.cross(ac)
				if absf(det) < 1e-8: continue
				var v := ap.cross(ac)/det; var w := ab.cross(ap)/det
				if v < -0.000001 or w < -0.000001 or v+w > 1.000001: continue
				var height := a.y+v*(b.y-a.y)+w*(c.y-a.y)
				if not best.is_empty() and height <= float(best.height): continue
				var ma := clampi(int(record.uv2[ia].y+0.5)%64,0,63)
				var mb := clampi(int(record.uv2[ib].y+0.5)%64,0,63)
				var mc := clampi(int(record.uv2[ic].y+0.5)%64,0,63)
				var lava := false
				for m: int in [ma,mb,mc]:
					lava = lava or (m < terrain._lava.size() and terrain._lava[m] > 0.0)
				best = {"height":height,"lava":lava,"material":ma,
					"slope":Vector2(((b.y-a.y)*ac.y-(c.y-a.y)*ab.y)/det,
						(ab.x*(c.y-a.y)-ac.x*(b.y-a.y))/det)}
	return best
