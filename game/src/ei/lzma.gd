class_name EILzma
extends RefCounted
## LZMA1 / LZMA2 decoder, a port of Igor Pavlov's reference decoder
## LzmaSpec.cpp (LZMA2 framing as in xz's lzma2_decoder). Used to unpack the
## original GOG installer: Inno Setup compresses its header with LZMA1 (5
## property bytes, then the stream) and the file chunks with LZMA2 (one
## dictionary-size byte, then LZMA2 chunks). The whole output stays in memory
## and serves as the dictionary.
##
## GDScript is slow at this, so the hot paths (literals, the range decoder's
## bit) are written out inline instead of calling helpers.

const TOP := 1 << 24
const PROB_INIT := 1024
const END_POS_MODEL := 14
const FULL_DISTANCES := 128
const ALIGN_BITS := 4

var _src: PackedByteArray
var _pos := 0
var _end := 0
var _range := 0xFFFFFFFF
var _code := 0
## Output bytes written so far (read by other threads for progress).
var done := 0
## Set from another thread to stop early (the output is then incomplete).
var abort := false


## Decodes `src[pos..pos+size)` (5 property bytes, then the stream). With
## out_size < 0 the size is unknown: decoding stops at the end marker or when
## the input runs out (Inno's header blocks).
static func decode(src: PackedByteArray, pos: int, size: int, out_size: int) -> PackedByteArray:
	return EILzma.new().run(src, pos, size, out_size)


## LZMA2 stream (after Inno's dictionary-size byte) of known output size.
static func decode2(src: PackedByteArray, pos: int, size: int, out_size: int) -> PackedByteArray:
	return EILzma.new().run2(src, pos, size, out_size)


var _lc := 0
var _lp := 0
var _pb := 0
var _lit := PackedInt32Array()
var _p := PackedInt32Array()
var _state := 0
var _reps := [0, 0, 0, 0]
var _out := PackedByteArray()
var _cap := 0


func _props(d: int) -> void:
	_lc = d % 9
	d /= 9
	_lp = d % 5
	_pb = d / 5


func _reset_state() -> void:
	_lit.resize(0x300 << (_lc + _lp))
	_lit.fill(PROB_INIT)
	_p.resize(1847)
	_p.fill(PROB_INIT)
	_state = 0
	_reps = [0, 0, 0, 0]


## Range decoder init: a zero byte, then four code bytes.
func _init_rc() -> void:
	_range = 0xFFFFFFFF
	_code = 0
	_pos += 1
	for i in 4:
		_code = (_code << 8) | _byte()


func run(src: PackedByteArray, pos: int, size: int, out_size: int) -> PackedByteArray:
	_src = src
	_props(int(src[pos]))
	_pos = pos + 5
	_end = pos + size
	_cap = out_size if out_size >= 0 else maxi(size * 8, 1 << 16)
	_out.resize(_cap)
	_reset_state()
	_init_rc()
	var o := _lzma(0, out_size, out_size < 0)
	done = o
	if out_size < 0:
		_out.resize(o)
	return _out


func run2(src: PackedByteArray, pos: int, size: int, out_size: int) -> PackedByteArray:
	_src = src
	_pos = pos + 1   # Inno's LZMA2 dictionary-size byte
	_end = pos + size
	_cap = out_size
	_out.resize(_cap)
	var o := 0
	while _pos < _end:
		var c := _byte()
		if c == 0:
			break
		if c < 0x80:
			# Stored chunk (1: dictionary reset, 2: none).
			var n := ((_byte() << 8) | _byte()) + 1
			for i in n:
				_out[o + i] = _src[_pos + i]
			_pos += n
			o += n
		else:
			var usize := (((c & 0x1F) << 16) | (_byte() << 8) | _byte()) + 1
			var psize := ((_byte() << 8) | _byte()) + 1
			var mode := (c >> 5) & 3
			if mode >= 2:
				_props(_byte())
			if mode >= 1:
				_reset_state()
			var next := _pos + psize
			_init_rc()
			o = _lzma(o, o + usize, false)
			_pos = next
		done = o
	return _out


## Decodes into _out from `o` up to `o_end` (or, with `unknown`, until the end
## marker / the input runs out). Returns the new output position.
func _lzma(o: int, o_end: int, unknown: bool) -> int:
	var lc := _lc
	var lp := _lp
	var pb := _pb
	var lit := _lit
	var p := _p
	var out := _out
	var cap := _cap
	var out_size := o_end
	const IS_MATCH := 0            # 12 states << 4 pos states
	const IS_REP := 192
	const IS_REP_G0 := 204
	const IS_REP_G1 := 216
	const IS_REP_G2 := 228
	const IS_REP0_LONG := 240      # 192
	const POS_SLOT := 432          # 4 x 64
	const POS_DEC := 688           # 1 + 128 - 14 = 115
	const ALIGN := 803             # 16
	const LEN := 819               # length decoder (514)
	const REP_LEN := 1333          # rep length decoder (514)

	var pb_mask := (1 << pb) - 1
	var lp_mask := (1 << lp) - 1
	var state := _state
	var rep0: int = _reps[0]
	var rep1: int = _reps[1]
	var rep2: int = _reps[2]
	var rep3: int = _reps[3]
	var rng := _range
	var code := _code
	var s := _src
	var sp := _pos
	var send := _end
	while unknown or o < out_size:
		if unknown and sp > send + 4:
			break
		var pos_state := o & pb_mask
		# ---- is_match bit (inline)
		var pi := IS_MATCH + (state << 4) + pos_state
		var prob := p[pi]
		var bound := (rng >> 11) * prob
		if code < bound:
			rng = bound
			p[pi] = prob + ((2048 - prob) >> 5)
			if rng < TOP:
				rng <<= 8
				code = (code << 8) | (s[sp] if sp < send else 0)
				sp += 1
			# ---- literal
			if o >= cap:
				cap *= 2
				out.resize(cap)
			var prev := int(out[o - 1]) if o > 0 else 0
			var base := 0x300 * (((o & lp_mask) << lc) + (prev >> (8 - lc)))
			var sym := 1
			if state >= 7:
				var mb := int(out[o - rep0 - 1])
				while sym < 0x100:
					var mbit := (mb >> 7) & 1
					mb <<= 1
					var li := base + ((1 + mbit) << 8) + sym
					prob = lit[li]
					bound = (rng >> 11) * prob
					var bit := 0
					if code < bound:
						rng = bound
						lit[li] = prob + ((2048 - prob) >> 5)
					else:
						rng -= bound
						code -= bound
						lit[li] = prob - (prob >> 5)
						bit = 1
					if rng < TOP:
						rng <<= 8
						code = (code << 8) | (s[sp] if sp < send else 0)
						sp += 1
					sym = (sym << 1) | bit
					if mbit != bit:
						break
			while sym < 0x100:
				var li := base + sym
				prob = lit[li]
				bound = (rng >> 11) * prob
				if code < bound:
					rng = bound
					lit[li] = prob + ((2048 - prob) >> 5)
					sym <<= 1
				else:
					rng -= bound
					code -= bound
					lit[li] = prob - (prob >> 5)
					sym = (sym << 1) | 1
				if rng < TOP:
					rng <<= 8
					code = (code << 8) | (s[sp] if sp < send else 0)
					sp += 1
			out[o] = sym - 0x100
			o += 1
			state = 0 if state < 4 else (state - 3 if state < 10 else state - 6)
			if (o & 0xFFFF) == 0:
				done = o
				if abort:
					break
			continue
		rng -= bound
		code -= bound
		p[pi] = prob - (prob >> 5)
		if rng < TOP:
			rng <<= 8
			code = (code << 8) | (s[sp] if sp < send else 0)
			sp += 1

		# ---- matches and reps (helpers; much rarer than literal bits)
		_range = rng
		_code = code
		_pos = sp
		var length := 0
		if _bit(p, IS_REP + state) != 0:
			if o == 0:
				push_error("LZMA: rep before any output")
				break
			if _bit(p, IS_REP_G0 + state) == 0:
				if _bit(p, IS_REP0_LONG + (state << 4) + pos_state) == 0:
					state = 9 if state < 7 else 11
					if o >= cap:
						cap *= 2
						out.resize(cap)
					out[o] = out[o - rep0 - 1]
					o += 1
					rng = _range
					code = _code
					sp = _pos
					continue
			else:
				var dist := 0
				if _bit(p, IS_REP_G1 + state) == 0:
					dist = rep1
				else:
					if _bit(p, IS_REP_G2 + state) == 0:
						dist = rep2
					else:
						dist = rep3
						rep3 = rep2
					rep2 = rep1
				rep1 = rep0
				rep0 = dist
			length = _len(p, REP_LEN, pos_state)
			state = 8 if state < 7 else 11
		else:
			rep3 = rep2
			rep2 = rep1
			rep1 = rep0
			length = _len(p, LEN, pos_state)
			state = 7 if state < 7 else 10
			# distance
			var slot := _tree(p, POS_SLOT + (mini(length, 3) << 6), 6)
			if slot < 4:
				rep0 = slot
			else:
				var nd := (slot >> 1) - 1
				var dist := (2 | (slot & 1)) << nd
				if slot < END_POS_MODEL:
					dist += _rtree(p, POS_DEC + dist - slot, nd)
				else:
					dist += _direct(nd - ALIGN_BITS) << ALIGN_BITS
					dist += _rtree(p, ALIGN, ALIGN_BITS)
				rep0 = dist
				if rep0 == 0xFFFFFFFF:   # end marker
					break
		rng = _range
		code = _code
		sp = _pos
		length += 2
		if rep0 >= o:
			push_error("LZMA: distance beyond output")
			break
		var need := o + length
		if unknown:
			while need > cap:
				cap *= 2
				out.resize(cap)
		else:
			need = mini(need, out_size)
		var from := o - rep0 - 1
		if rep0 + 1 >= length and need <= cap:
			# Non-overlapping copy in one native call.
			var n := need - o
			var chunk := out.slice(from, from + n)
			for i in n:
				out[o + i] = chunk[i]
			o = need
		else:
			while o < need:
				out[o] = out[from]
				o += 1
				from += 1
		done = o
	_state = state
	_reps = [rep0, rep1, rep2, rep3]
	_range = rng
	_code = code
	_pos = sp
	_out = out
	_cap = cap
	return o


func _byte() -> int:
	var b := int(_src[_pos]) if _pos < _end else 0
	_pos += 1
	return b


func _bit(p: PackedInt32Array, i: int) -> int:
	var prob := p[i]
	var bound := (_range >> 11) * prob
	var bit := 0
	if _code < bound:
		_range = bound
		p[i] = prob + ((2048 - prob) >> 5)
	else:
		_range -= bound
		_code -= bound
		p[i] = prob - (prob >> 5)
		bit = 1
	if _range < TOP:
		_range <<= 8
		_code = (_code << 8) | _byte()
	return bit


func _tree(p: PackedInt32Array, base: int, bits: int) -> int:
	var m := 1
	for i in bits:
		m = (m << 1) + _bit(p, base + m)
	return m - (1 << bits)


func _rtree(p: PackedInt32Array, base: int, bits: int) -> int:
	var m := 1
	var sym := 0
	for i in bits:
		var b := _bit(p, base + m)
		m = (m << 1) + b
		sym |= b << i
	return sym


func _direct(bits: int) -> int:
	var res := 0
	for i in bits:
		_range >>= 1
		var b := 0
		if _code >= _range:
			_code -= _range
			b = 1
		res = (res << 1) | b
		if _range < TOP:
			_range <<= 8
			_code = (_code << 8) | _byte()
	return res


## Length decoder at `base`: choice, choice2, low[16 pos states][8],
## mid[16][8], high[256].
func _len(p: PackedInt32Array, base: int, pos_state: int) -> int:
	if _bit(p, base) == 0:
		return _tree(p, base + 2 + (pos_state << 3), 3)
	if _bit(p, base + 1) == 0:
		return 8 + _tree(p, base + 2 + 128 + (pos_state << 3), 3)
	return 16 + _tree(p, base + 2 + 256, 8)
