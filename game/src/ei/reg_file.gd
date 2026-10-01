class_name EIRegFile
extends RefCounted
## Nival .reg files (binary sections of typed keys), e.g. res/music.reg.
## Returns {section: {key: int | float | String | Array}}.


static func parse(d: PackedByteArray) -> Dictionary:
	var out := {}
	if d.size() < 6 or d.decode_u32(0) != 0x45AB3EFB:
		return out
	var n := d.decode_u16(4)
	for i in n:
		var off := d.decode_u32(6 + i * 6 + 2)
		var kc := d.decode_u16(off)
		var nl := d.decode_u16(off + 2)
		var name := EIText.ansi(d.slice(off + 4, off + 4 + nl))
		var keys := {}
		var p := off + 4 + nl
		for k in kc:
			var q := off + d.decode_u32(p + k * 6 + 2)
			var t := d[q]
			var kl := d.decode_u16(q + 1)
			var kn := EIText.ansi(d.slice(q + 3, q + 3 + kl))
			q += 3 + kl
			if t & 0x80:
				var cnt := d.decode_u16(q)
				q += 2
				var arr := []
				for j in cnt:
					var r := _one(d, t & 0x7f, q)
					arr.append(r[0])
					q = r[1]
				keys[kn] = arr
			else:
				keys[kn] = _one(d, t, q)[0]
		out[name] = keys
	return out


static func _one(d: PackedByteArray, t: int, q: int) -> Array:
	match t:
		0: return [d.decode_s32(q), q + 4]
		1: return [d.decode_float(q), q + 4]
		2:
			var l := d.decode_u16(q)
			return [EIText.ansi(d.slice(q + 2, q + 2 + l)), q + 2 + l]
	return [null, q]
