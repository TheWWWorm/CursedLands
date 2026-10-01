class_name EIBinkAudio
extends RefCounted
## Bink audio decoder (RDFT variant, the one every Evil Islands movie uses):
## one packet per video frame -> interleaved PCM16.
## Decoder logic follows FFmpeg's libavcodec/binkaudio.c (LGPL-2.1, Peter Ross)
## and the "Bink Audio" page of wiki.multimedia.cx; the inverse real DFT is done
## with a half-size complex FFT.

const CRITICAL_FREQS := [100, 200, 300, 400, 510, 630, 770, 920, 1080, 1270, 1480, 1720, 2000, 2320,
	2700, 3150, 3700, 4400, 5300, 6400, 7700, 9500, 12000, 15500, 24500]
const RLE_LENGTHS := [2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 32, 64]

var rate := 22050
var channels := 1
var supported := true  ## false for the DCT variant (not used by the game)

var _n := 0  # transform size (interleaved samples)
var _ov := 0  # overlap
var _root := 0.0
var _qt := PackedFloat64Array()
var _bands := PackedInt32Array()
var _nb := 0
var _first := true
var _prev := PackedFloat64Array()
var _coef := PackedFloat64Array()
var _out := PackedFloat64Array()
var _quant := PackedFloat64Array()
var _version_b := false
# FFT (size _n / 2)
var _re := PackedFloat64Array()
var _im := PackedFloat64Array()
var _rev := PackedInt32Array()
var _tc := PackedFloat64Array()  # cos(2 pi t / M)
var _ts := PackedFloat64Array()
var _wc := PackedFloat64Array()  # cos(2 pi k / N)
var _ws := PackedFloat64Array()
var _d := PackedByteArray()
var _p := 0


func _init(track: Dictionary, revision := 0x69) -> void:
	rate = int(track.get("rate", 22050))
	channels = int(track.get("channels", 1))
	supported = not track.get("dct", false)
	_version_b = revision == 0x62
	var bits := 9 if rate < 22050 else (10 if rate < 44100 else 11)
	var sr := rate * channels  # RDFT: channels are already interleaved
	if not _version_b and channels == 2:
		bits += 1
	_n = 1 << bits
	_ov = _n / 16
	_root = 2.0 / (sqrt(_n) * 32768.0)
	_qt.resize(96)
	for i in 96:
		_qt[i] = exp(i * 0.15289164787221953823) * _root
	var half := (sr + 1) / 2
	_nb = 1
	while _nb < 25:
		if half <= CRITICAL_FREQS[_nb - 1]:
			break
		_nb += 1
	_bands.resize(_nb + 1)
	_bands[0] = 2
	for i in range(1, _nb):
		_bands[i] = (CRITICAL_FREQS[i - 1] * _n / half) & ~1
	_bands[_nb] = _n
	_quant.resize(26)
	_prev.resize(_ov)
	_coef.resize(_n + 2)
	_out.resize(_n)
	var m := _n / 2
	_re.resize(m)
	_im.resize(m)
	_rev.resize(m)
	var lb := bits - 1
	for i in m:
		var r := 0
		for b in lb:
			if i & (1 << b):
				r |= 1 << (lb - 1 - b)
		_rev[i] = r
	_tc.resize(m)
	_ts.resize(m)
	for t in m:
		_tc[t] = cos(TAU * t / m)
		_ts[t] = sin(TAU * t / m)
	_wc.resize(m)
	_ws.resize(m)
	for k in m:
		_wc[k] = cos(TAU * k / _n)
		_ws[k] = sin(TAU * k / _n)


## Decodes one audio packet (as returned by EIBink.audio_packet) to PCM16.
func decode_packet(pkt: PackedByteArray) -> PackedByteArray:
	var pcm := PackedByteArray()
	if pkt.size() < 4 or not supported:
		return pcm
	var nbits := pkt.size() * 8
	_d = pkt.duplicate()
	_d.resize(pkt.size() + 16)
	_p = 32  # reported decoded size
	while nbits - _p > 0:
		if not _decode_block(nbits, pcm):
			break
		if _p & 31:
			_p += 32 - (_p & 31)
	return pcm


func _bits(n: int) -> int:
	var v := (_d.decode_u32(_p >> 3) >> (_p & 7)) & ((1 << n) - 1)
	_p += n
	return v


func _float() -> float:
	var power := _bits(5)
	var f := float(_bits(23)) * pow(2.0, power - 23)
	return -f if _bits(1) else f


func _decode_block(nbits: int, pcm: PackedByteArray) -> bool:
	var n := _n
	var coef := _coef
	var quant := _quant
	if _version_b:
		if nbits - _p < 64:
			return false
		var b := PackedByteArray()
		b.resize(4)
		b.encode_u32(0, _bits(16) | (_bits(16) << 16))
		coef[0] = b.decode_float(0) * _root
		b.encode_u32(0, _bits(16) | (_bits(16) << 16))
		coef[1] = b.decode_float(0) * _root
	else:
		if nbits - _p < 58:
			return false
		coef[0] = _float() * _root
		coef[1] = _float() * _root
	if nbits - _p < _nb * 8:
		return false
	for i in _nb:
		quant[i] = _qt[mini(_bits(8), 95)]
	var bands := _bands
	var d := _d
	var p := _p
	var k := 0
	var q := quant[0]
	var i := 2
	while i < n:
		var j: int
		if _version_b:
			j = i + 16
		else:
			if (d[p >> 3] >> (p & 7)) & 1:
				p += 1
				j = i + RLE_LENGTHS[(d.decode_u32(p >> 3) >> (p & 7)) & 15] * 8
				p += 4
			else:
				p += 1
				j = i + 8
		if j > n:
			j = n
		var width := (d.decode_u32(p >> 3) >> (p & 7)) & 15
		p += 4
		if width == 0:
			while i < j:
				coef[i] = 0.0
				i += 1
			while bands[k] < i:
				q = quant[k]
				k += 1
		else:
			var mask := (1 << width) - 1
			while i < j:
				if bands[k] == i:
					q = quant[k]
					k += 1
				var c := (d.decode_u32(p >> 3) >> (p & 7)) & mask
				p += width
				if c:
					if (d[p >> 3] >> (p & 7)) & 1:
						coef[i] = -q * c
					else:
						coef[i] = q * c
					p += 1
				else:
					coef[i] = 0.0
				i += 1
		if p > nbits + 64:
			_p = p
			return false
	_p = p
	_inverse_rdft()
	var out := _out
	var ov := _ov
	if not _first:
		for t in ov:
			out[t] = (_prev[t] * (ov - t) + out[t] * t) / ov
	for t in ov:
		_prev[t] = out[n - ov + t]
	_first = false
	var cnt := n - ov
	var base := pcm.size()
	pcm.resize(base + cnt * 2)
	for t in cnt:
		pcm.encode_s16(base + t * 2, clampi(roundi(out[t] * 32768.0), -32768, 32767))
	return true


## x[t] = c0/2 + (-1)^t cN/2 + sum_k (R_k cos(2 pi k t / N) + I_k sin(2 pi k t / N))
## (FFmpeg's inverse RDFT with scale 0.5 after negating the odd coefficients).
func _inverse_rdft() -> void:
	var n := _n
	var m := n >> 1
	var c := _coef
	var re := _re
	var im := _im
	var rev := _rev
	var wc := _wc
	var ws := _ws
	# pre-processing into a half-size complex spectrum, stored bit-reversed
	for k in m:
		var ar: float
		var ai: float
		var br: float
		var bi: float
		if k == 0:
			ar = c[0]
			ai = 0.0
			br = c[1]
			bi = 0.0
		else:
			ar = c[2 * k]
			ai = -c[2 * k + 1]
			br = c[2 * (m - k)]
			bi = c[2 * (m - k) + 1]  # conj(Z[m-k]) = R + iI
		var er := ar + br
		var ei := ai + bi
		var dr := ar - br
		var di := ai - bi
		var orr := dr * wc[k] - di * ws[k]
		var oi := dr * ws[k] + di * wc[k]
		var r := rev[k]
		re[r] = er - oi
		im[r] = ei + orr
	# iterative radix-2 inverse FFT
	var tc := _tc
	var ts := _ts
	var size := 2
	while size <= m:
		var h := size >> 1
		var step := m / size
		for j in h:
			var wr := tc[j * step]
			var wi := ts[j * step]
			var s := j
			while s < m:
				var s2 := s + h
				var xr := re[s2] * wr - im[s2] * wi
				var xi := re[s2] * wi + im[s2] * wr
				var ur := re[s]
				var ui := im[s]
				re[s] = ur + xr
				im[s] = ui + xi
				re[s2] = ur - xr
				im[s2] = ui - xi
				s += size
		size <<= 1
	var out := _out
	for t in m:
		out[2 * t] = 0.5 * re[t]
		out[2 * t + 1] = 0.5 * im[t]
