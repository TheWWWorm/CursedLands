class_name EIBink
extends RefCounted
## Native Bink 1 (.bik) movie reader for the original cutscenes: container
## (header, audio track headers, frame index with keyframe bit), video
## decoding for the Bink 1 revisions after 'b' (the game has 'f' and 'i'; all
## block types, bundles, Huffman trees, DCT / residue, Y/U/V planes; alpha
## planes are decoded and dropped) and access to the audio packets (decoded by
## EIBinkAudio). Speed: ~20-50 ms per 640x272 frame, see EIBinkCache.
##
## Decoder logic follows FFmpeg's libavformat/bink.c, libavcodec/bink.c and
## libavcodec/binkdsp.c (LGPL-2.1, Konstantin Shishkov, Peter Ross); the tables
## at the end come from libavcodec/binkdata.h. See also wiki.multimedia.cx
## "Bink Video" / "Bink Container".
##
## A decoded frame is kept as three planes (BT.601, limited range): Y
## (width x height) and U, V (half size). yuv_image() packs them into one L8
## image (Y on top, U | V side by side below) for the YUV -> RGB shader of the
## movie player; rgb_image() converts on the CPU (slow, for tools).

const FLAG_ALPHA := 0x00100000
const AUD_16BITS := 0x4000
const AUD_STEREO := 0x2000
const AUD_USEDCT := 0x1000

# bundle ids (FFmpeg enum Sources)
const B_TYPES := 0
const B_SUB := 1
const B_COLORS := 2
const B_PATTERN := 3
const B_XOFF := 4
const B_YOFF := 5
const B_INTRA_DC := 6
const B_INTER_DC := 7
const B_RUN := 8
const NB_SRC := 9
const BUNDLE_CAP := 16384 + 128
const RLE_LENS := [4, 8, 12, 32]
const PLANES_ALL := 7
const PLANES_Y := 1
const PLANES_UV := 6

var width := 0
var height := 0
var frame_count := 0
var fps_num := 25
var fps_den := 1
var revision := 0  ## ASCII code of the 4th signature byte ('f', 'i', ...)
var video_flags := 0
## One Dictionary per audio track: {rate, flags, channels, stereo, dct, id}.
var audio_tracks: Array[Dictionary] = []
var error := ""  ## last decode problem (the frame is still produced)
var _fatal := false
var chroma_offset := 0  ## 'i' frames: chroma offset stored in the frame
var chroma_start := 0  ## where the chroma planes really started (checks)

var _f: DataReadCursor
var _offsets := PackedInt64Array()  # frame_count + 1 entries
var _keys := PackedByteArray()

# video state
var _cur: Array[PackedByteArray] = []  # Y, U, V, A
var _prev: Array[PackedByteArray] = []
var _stride := PackedInt32Array([0, 0, 0, 0])
var _has_alpha := false
var _swap := false
var _d := PackedByteArray()  # current packet (padded)
var _p := 0  # bit position in _d
var _bd: Array[PackedInt32Array] = []  # bundle data
var _dec := PackedInt32Array()  # decode position per bundle (-1 = ended)
var _ptr := PackedInt32Array()  # read position per bundle
var _len := PackedInt32Array()  # bit length of the count field per bundle
var _trees := PackedInt32Array()  # 32 trees x 128 entries: (symbol << 4) | code length
var _col_last := 0
var _coord := PackedInt32Array()  # per stride: pattern -> pixel offsets (16 x 64)
var _coord_stride := -1
var _ucoord := PackedInt32Array()  # patterns in an 8-wide block
var _blk := PackedInt32Array()  # dct / residue block
var _tmp := PackedInt32Array()
var _ublock := PackedInt32Array()
var _cl := PackedInt32Array()
var _ml := PackedInt32Array()
var _cidx := PackedInt32Array()
var _ccount := 0
var _nz := PackedInt32Array()

static var _vlc := PackedInt32Array()  # 16 trees x 128: (leaf << 4) | len
static var _scan := PackedInt32Array()
static var _iq := PackedInt32Array()
static var _xq := PackedInt32Array()
static var _fill := PackedInt64Array()  # byte -> 8 copies
static var _expand := PackedInt64Array()  # 8-bit mask -> 0xFF bytes


## Opens a .bik file; false (with `error` set) when it is not Bink 1.
func open(path: String) -> bool:
	_f = DataReadCursor.open(path)
	if _f == null:
		error = "cannot open " + path
		return false
	var sig := _f.get_32()
	if sig & 0xFFFFFF != 0x4B4942:
		error = "not a Bink 1 file"
		return false
	revision = sig >> 24
	if revision < 0x64:  # 'b' uses the older binkb coding, not needed here
		error = "Bink revision %c not supported" % revision
		return false
	var file_size := _f.get_32() + 8
	frame_count = _f.get_32()
	_f.get_32()  # largest frame
	_f.get_32()
	width = _f.get_32()
	height = _f.get_32()
	fps_num = _f.get_32()
	fps_den = maxi(_f.get_32(), 1)
	video_flags = _f.get_32()
	var na := _f.get_32()
	if frame_count <= 0 or width <= 0 or height <= 0 or width > 7680 or height > 4800 or na > 256:
		error = "bad Bink header"
		return false
	if revision == 0x6B:  # 'k'
		_f.get_32()
	_f.seek(_f.get_position() + 4 * na)  # max decoded sizes
	audio_tracks.clear()
	for i in na:
		var rate := _f.get_16()
		var fl := _f.get_16()
		audio_tracks.append({"rate": rate, "flags": fl, "stereo": fl & AUD_STEREO != 0,
			"channels": 2 if fl & AUD_STEREO else 1, "dct": fl & AUD_USEDCT != 0})
	for i in na:
		audio_tracks[i]["id"] = _f.get_32()
	_offsets.resize(frame_count + 1)
	_keys.resize(frame_count)
	var next := _f.get_32()
	for i in frame_count:
		_keys[i] = 1 if i == 0 else (next & 1)
		_offsets[i] = next & ~1
		next = file_size if i == frame_count - 1 else _f.get_32()
	_offsets[frame_count] = next & ~1
	_init_video()
	return true


func fps() -> float:
	return float(fps_num) / float(fps_den)


## Packet size of frame i in bytes.
func frame_size(i: int) -> int:
	return _offsets[i + 1] - _offsets[i]


func is_keyframe(i: int) -> bool:
	return _keys[i] != 0


## Raw packet of frame i (audio packets of every track, then video).
func frame_data(i: int) -> PackedByteArray:
	_f.seek(_offsets[i])
	return _f.get_buffer(_offsets[i + 1] - _offsets[i])


## Audio packet of `track` inside a frame packet (empty when none).
func audio_packet(data: PackedByteArray, track := 0) -> PackedByteArray:
	var pos := 0
	for t in audio_tracks.size():
		if pos + 4 > data.size():
			break
		var n := data.decode_u32(pos)
		if t == track:
			return data.slice(pos + 4, pos + 4 + n) if n >= 4 else PackedByteArray()
		pos += 4 + n
	return PackedByteArray()


## True when the luma and chroma planes can be decoded independently (on two
## threads, see decode_frame's `planes`): from revision 'i' on, each frame starts
## with the byte offset of its first chroma plane.
func can_split() -> bool:
	return revision >= 0x69 and not _has_alpha


## Decodes the video part of frame packet `data` into the current planes.
## Frames must be decoded in order (inter frames use the previous picture).
## `planes`: PLANES_ALL, or (when can_split()) PLANES_Y / PLANES_UV to decode
## only those planes of every frame; another instance decodes the rest.
func decode_frame(data: PackedByteArray, planes := PLANES_ALL) -> bool:
	var pos := 0
	for t in audio_tracks.size():
		if pos + 4 > data.size():
			break
		pos += 4 + data.decode_u32(pos)
	error = ""
	_fatal = false
	var tmp := _prev
	_prev = _cur
	_cur = tmp
	_d = data.slice(pos)
	var nbits := _d.size() * 8
	_d.resize(_d.size() + 16)
	_p = 0
	if _has_alpha:
		if revision >= 0x69:
			_p += 32
		_decode_plane(3, false)
	var first := 0
	if revision >= 0x69:  # 'i': byte offset of the first chroma plane
		chroma_offset = _d.decode_u32(_p >> 3)
		_p += 32
	if planes == PLANES_UV:
		if chroma_offset <= 4 or chroma_offset * 8 >= nbits:
			return error.is_empty()
		_p = chroma_offset * 8
		first = 1
	for plane in range(first, 1 if planes == PLANES_Y else 3):
		if plane == 1:
			chroma_start = _p >> 3
		var idx := plane if plane == 0 or not _swap else plane ^ 3
		_decode_plane(idx, plane > 0)
		if _p >= nbits:
			break
	return error.is_empty()


## The last decoded frame as an L8 image: Y (width x height) on top, then U and
## V (width/2 x height/2 each, rounded up) side by side. `chroma` is the
## instance that decoded the chroma planes (PLANES_UV), if not this one.
func yuv_image(chroma: EIBink = null) -> Image:
	var cw := (width + 1) >> 1
	var ch := (height + 1) >> 1
	var out := PackedByteArray()
	out.resize(width * (height + ch))
	var y := _cur[0]
	var s := _stride[0]
	var o := 0
	for r in height:
		_copy_into(out, o, y.slice(r * s, r * s + width))
		o += width
	var cb := chroma if chroma else self
	var u := cb._cur[1]
	var v := cb._cur[2]
	var cs := _stride[1]
	for r in ch:
		_copy_into(out, o, u.slice(r * cs, r * cs + cw))
		_copy_into(out, o + cw, v.slice(r * cs, r * cs + cw))
		o += width
	return Image.create_from_data(width, height + ch, false, Image.FORMAT_L8, out)


static func _copy_into(dst: PackedByteArray, at: int, src: PackedByteArray) -> void:
	var n := src.size()
	var i := 0
	while i + 8 <= n:
		dst.encode_s64(at + i, src.decode_s64(i))
		i += 8
	while i < n:
		dst[at + i] = src[i]
		i += 1


## Converts a yuv_image() of a `h` pixel high frame to RGB8 on the CPU
## (BT.601 limited range; slow, for tools).
static func yuv_to_rgb(img: Image, h: int) -> Image:
	var w := img.get_width()
	var cw := (w + 1) >> 1
	var src := img.get_data()
	var out := PackedByteArray()
	out.resize(w * h * 3)
	var o := 0
	for y in h:
		var yr := y * w
		var cr := (h + (y >> 1)) * w
		for x in w:
			var yy := (src[yr + x] - 16) * 1192
			var uu := src[cr + (x >> 1)] - 128
			var vv := src[cr + cw + (x >> 1)] - 128
			out[o] = clampi((yy + 1634 * vv + 512) >> 10, 0, 255)
			out[o + 1] = clampi((yy - 401 * uu - 832 * vv + 512) >> 10, 0, 255)
			out[o + 2] = clampi((yy + 2066 * uu + 512) >> 10, 0, 255)
			o += 3
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, out)


func rgb_image() -> Image:
	return yuv_to_rgb(yuv_image(), height)


# --- setup -----------------------------------------------------------------

## Builds the shared tables (call once on the main thread before decoding on
## several threads; open() does it too).
static func init_tables() -> void:
	if not _vlc.is_empty():
		return
	var vlc := PackedInt32Array()
	vlc.resize(16 * 128)
	for n in 16:
		for s in 16:
			var l: int = TREE_LENS[n * 16 + s]
			var c: int = TREE_BITS[n * 16 + s]
			var h := 0
			while (c | (h << l)) < 128:
				vlc[n * 128 + (c | (h << l))] = (s << 4) | l
				h += 1
	_scan = PackedInt32Array(SCAN)
	_iq = PackedInt32Array(INTRA_QUANT)
	_xq = PackedInt32Array(INTER_QUANT)
	var fill := PackedInt64Array()
	var expand := PackedInt64Array()
	fill.resize(256)
	expand.resize(256)
	for v in 256:
		var f := 0
		var e := 0
		for k in 8:
			f |= v << (8 * k)
			if v & (1 << k):
				e |= 0xFF << (8 * k)
		fill[v] = f
		expand[v] = e
	_fill = fill
	_expand = expand
	_vlc = vlc


func _init_video() -> void:
	init_tables()
	_has_alpha = video_flags & FLAG_ALPHA != 0
	_swap = revision >= 0x68  # 'h'
	# planes rounded up to whole 16x16 blocks (scaled blocks may cover the
	# last odd block row), like FFmpeg's padded frame buffers
	var bw := (((width + 7) >> 3) + 1) & ~1
	var bh := (((height + 7) >> 3) + 1) & ~1
	var cbw := (((width + 15) >> 4) + 1) & ~1
	var cbh := (((height + 15) >> 4) + 1) & ~1
	_stride = PackedInt32Array([bw * 8, cbw * 8, cbw * 8, bw * 8])
	var sizes := [bw * bh * 64, cbw * cbh * 64, cbw * cbh * 64, bw * bh * 64 if _has_alpha else 0]
	_cur.clear()
	_prev.clear()
	for i in 4:
		for arr in [_cur, _prev]:
			var b := PackedByteArray()
			b.resize(sizes[i] + 16)
			if i == 1 or i == 2:
				b.fill(128)
			arr.append(b)
	_bd.clear()
	for i in NB_SRC:
		var b := PackedInt32Array()
		b.resize(BUNDLE_CAP)
		_bd.append(b)
	_dec.resize(NB_SRC)
	_ptr.resize(NB_SRC)
	_len.resize(NB_SRC)
	_trees.resize(32 * 128)
	_blk.resize(64)
	_tmp.resize(64)
	_ublock.resize(64)
	_cl.resize(128)
	_ml.resize(128)
	_cidx.resize(64)
	_nz.resize(64)
	_ucoord.resize(16 * 64)
	for i in 16 * 64:
		_ucoord[i] = PATTERNS[i]


func _set_coord(stride: int) -> void:
	if _coord_stride == stride:
		return
	_coord_stride = stride
	_coord.resize(16 * 64)
	for i in 16 * 64:
		var c: int = PATTERNS[i]
		_coord[i] = (c & 7) + (c >> 3) * stride


# --- bit reading -------------------------------------------------------------

func _bits(n: int) -> int:
	var v := (_d.decode_u32(_p >> 3) >> (_p & 7)) & ((1 << n) - 1)
	_p += n
	return v


func _bit() -> int:
	var v := (_d[_p >> 3] >> (_p & 7)) & 1
	_p += 1
	return v


## Reads a Huffman tree description into slot `slot` of _trees.
func _read_tree(slot: int) -> void:
	var vlc := _bits(4)
	var syms := PackedInt32Array()
	syms.resize(16)
	if vlc == 0:
		for i in 16:
			syms[i] = i
	elif _bit():
		var used := PackedByteArray()
		used.resize(16)
		var l := _bits(3)
		for i in l + 1:
			syms[i] = _bits(4)
			used[syms[i]] = 1
		var i := 0
		while i < 16 and l < 15:
			if not used[i]:
				l += 1
				syms[l] = i
			i += 1
	else:
		var l := _bits(2)
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		a.resize(16)
		b.resize(16)
		for i in 16:
			a[i] = i
		for i in l + 1:
			var size := 1 << i
			var t := 0
			while t < 16:
				# merge a[t..t+size) and a[t+size..t+2size) into b[t..]
				var s1 := t
				var s2 := t + size
				var n1 := size
				var n2 := size
				var o := t
				while n1 > 0 and n2 > 0:
					if _bit() == 0:
						b[o] = a[s1]
						s1 += 1
						n1 -= 1
					else:
						b[o] = a[s2]
						s2 += 1
						n2 -= 1
					o += 1
				while n1 > 0:
					b[o] = a[s1]
					o += 1
					s1 += 1
					n1 -= 1
				while n2 > 0:
					b[o] = a[s2]
					o += 1
					s2 += 1
					n2 -= 1
				t += size << 1
			var sw := a
			a = b
			b = sw
		syms = a
	var base := slot * 128
	var vb := vlc * 128
	for c in 128:
		var e := _vlc[vb + c]
		_trees[base + c] = (syms[e >> 4] << 4) | (e & 15)


func _huff(slot: int) -> int:
	var e := _trees[slot * 128 + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
	_p += e & 15
	return e >> 4


# --- bundles -----------------------------------------------------------------

func _log2(v: int) -> int:
	var n := 0
	while v > 1:
		v >>= 1
		n += 1
	return n


func _init_lengths(w: int, bw: int) -> void:
	w = (w + 7) & ~7
	_len[B_TYPES] = _log2((w >> 3) + 511) + 1
	_len[B_SUB] = _log2((w >> 4) + 511) + 1
	_len[B_COLORS] = _log2(bw * 64 + 511) + 1
	_len[B_INTRA_DC] = _log2((w >> 3) + 511) + 1
	_len[B_INTER_DC] = _len[B_INTRA_DC]
	_len[B_XOFF] = _len[B_INTRA_DC]
	_len[B_YOFF] = _len[B_INTRA_DC]
	_len[B_PATTERN] = _log2((bw << 3) + 511) + 1
	_len[B_RUN] = _log2(bw * 48 + 511) + 1


func _read_bundle(b: int) -> void:
	if b == B_COLORS:
		for i in 16:
			_read_tree(16 + i)
		_col_last = 0
	if b != B_INTRA_DC and b != B_INTER_DC:
		_read_tree(b)
	_dec[b] = 0
	_ptr[b] = 0


## CHECK_READ_VAL: number of values to decode now (0 = keep buffered data).
## The buffer restarts at 0 whenever everything decoded so far was consumed.
func _count(b: int) -> int:
	var dec := _dec[b]
	if dec < 0 or dec > _ptr[b]:
		return 0
	_dec[b] = 0
	_ptr[b] = 0
	var t := _bits(_len[b])
	if t == 0:
		_dec[b] = -1
	elif t > BUNDLE_CAP - 64:
		error = "bundle overflow"
		_fatal = true
		_dec[b] = -1
		return 0
	return t


func _read_block_types(b: int) -> void:
	var t := _count(b)
	if t == 0:
		return
	if revision == 0x6B:
		t ^= 0xBB
		if t == 0:
			_dec[b] = -1
			return
	var arr := _bd[b]
	var dec := 0
	if _bit():
		var v := _bits(4)
		for i in t:
			arr[i] = v
		dec = t
	else:
		var last := 0
		var slot := b * 128
		while dec < t:
			var e := _trees[slot + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
			_p += e & 15
			var v := e >> 4
			if v < 12:
				last = v
				arr[dec] = v
				dec += 1
			else:
				var run: int = RLE_LENS[v - 12]
				if t - dec < run:
					error = "block type run"
					run = t - dec
				for k in run:
					arr[dec + k] = last
				dec += run
	_dec[b] = dec


func _read_values(b: int, signed: bool) -> void:
	# runs (unsigned 4-bit) and motion values (signed)
	var t := _count(b)
	if t == 0:
		return
	var arr := _bd[b]
	if _bit():
		var v := _bits(4)
		if signed and v and _bit():
			v = -v
		for i in t:
			arr[i] = v
	else:
		var slot := b * 128
		for i in t:
			var e := _trees[slot + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
			_p += e & 15
			var v := e >> 4
			if signed and v:
				if (_d[_p >> 3] >> (_p & 7)) & 1:
					v = -v
				_p += 1
			arr[i] = v
	_dec[b] = t


func _read_patterns(b: int) -> void:
	var t := _count(b)
	if t == 0:
		return
	var arr := _bd[b]
	var slot := b * 128
	for i in t:
		var e := _trees[slot + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
		_p += e & 15
		var e2 := _trees[slot + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
		_p += e2 & 15
		arr[i] = (e >> 4) | ((e2 >> 4) << 4)
	_dec[b] = t


func _read_colors(b: int) -> void:
	var t := _count(b)
	if t == 0:
		return
	var arr := _bd[b]
	var old := revision < 0x69
	var slot := b * 128
	if _bit():
		_col_last = _huff(16 + _col_last)
		var v := (_col_last << 4) | _huff(b)
		if old:
			v = (0x80 - (v & 0x7F)) if v & 0x80 else (v + 0x80)
			v &= 0xFF
		for i in t:
			arr[i] = v
	else:
		var last := _col_last
		for i in t:
			var e := _trees[(16 + last) * 128 + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
			_p += e & 15
			last = e >> 4
			var e2 := _trees[slot + ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 127)]
			_p += e2 & 15
			var v := (last << 4) | (e2 >> 4)
			if old:
				v = ((0x80 - (v & 0x7F)) if v & 0x80 else (v + 0x80)) & 0xFF
			arr[i] = v
		_col_last = last
	_dec[b] = t


func _read_dcs(b: int, has_sign: int) -> void:
	var l := _count(b)
	if l == 0:
		return
	var arr := _bd[b]
	var v := _bits(11 - has_sign)
	if v and has_sign and _bit():
		v = -v
	arr[0] = v
	var o := 1
	l -= 1
	var i := 0
	while i < l:
		var l2 := mini(l - i, 8)
		var bsize := _bits(4)
		if bsize:
			var mask := (1 << bsize) - 1
			for j in l2:
				var v2 := (_d.decode_u32(_p >> 3) >> (_p & 7)) & mask
				_p += bsize
				if v2:
					if (_d[_p >> 3] >> (_p & 7)) & 1:
						v2 = -v2
					_p += 1
				v += v2
				arr[o] = v
				o += 1
		else:
			for j in l2:
				arr[o] = v
				o += 1
		i += 8
	_dec[b] = o


func _read_row_bundles() -> void:
	_read_block_types(B_TYPES)
	_read_block_types(B_SUB)
	_read_colors(B_COLORS)
	_read_patterns(B_PATTERN)
	_read_values(B_XOFF, true)
	_read_values(B_YOFF, true)
	_read_dcs(B_INTRA_DC, 0)
	_read_dcs(B_INTER_DC, 1)
	_read_values(B_RUN, false)


# --- DCT / residue ---------------------------------------------------------

## read_dct_coeffs + unquantize_dct_coeffs: fills _blk (natural order, DC
## already in _blk[0]) with the dequantised coefficients and _ccount.
func _read_dct(quant: PackedInt32Array) -> void:
	var cl := _cl
	var ml := _ml
	var blk := _blk
	var cidx := _cidx
	var d := _d
	var p := _p
	var ls := 64
	var le := 64
	cl[64] = 4
	ml[64] = 0
	cl[65] = 24
	ml[65] = 0
	cl[66] = 44
	ml[66] = 0
	cl[67] = 1
	ml[67] = 3
	cl[68] = 2
	ml[68] = 3
	cl[69] = 3
	ml[69] = 3
	le = 70
	var cc := 0
	var bits := ((d.decode_u32(p >> 3) >> (p & 7)) & 15) - 1
	p += 4
	while bits >= 0:
		var lp := ls
		while lp < le:
			var mode := ml[lp]
			var ccoef := cl[lp]
			if (mode | ccoef) == 0:
				lp += 1
				continue
			var bit := (d[p >> 3] >> (p & 7)) & 1
			p += 1
			if bit == 0:
				lp += 1
				continue
			if mode == 0 or mode == 2:
				if mode == 0:
					cl[lp] = ccoef + 4
					ml[lp] = 1
				else:
					cl[lp] = 0
					ml[lp] = 0
					lp += 1
				for i in 4:
					var f := (d[p >> 3] >> (p & 7)) & 1
					p += 1
					if f:
						ls -= 1
						cl[ls] = ccoef
						ml[ls] = 3
					else:
						var t: int
						if bits == 0:
							t = 1 - (((d[p >> 3] >> (p & 7)) & 1) << 1)
							p += 1
						else:
							t = ((d.decode_u32(p >> 3) >> (p & 7)) & ((1 << bits) - 1)) | (1 << bits)
							p += bits
							if (d[p >> 3] >> (p & 7)) & 1:
								t = -t
							p += 1
						blk[_scan[ccoef]] = t
						cidx[cc] = ccoef
						cc += 1
					ccoef += 1
			elif mode == 1:
				ml[lp] = 2
				for i in 3:
					ccoef += 4
					cl[le] = ccoef
					ml[le] = 2
					le += 1
			else:  # mode 3
				var t: int
				if bits == 0:
					t = 1 - (((d[p >> 3] >> (p & 7)) & 1) << 1)
					p += 1
				else:
					t = ((d.decode_u32(p >> 3) >> (p & 7)) & ((1 << bits) - 1)) | (1 << bits)
					p += bits
					if (d[p >> 3] >> (p & 7)) & 1:
						t = -t
					p += 1
				blk[_scan[ccoef]] = t
				cidx[cc] = ccoef
				cc += 1
				cl[lp] = 0
				ml[lp] = 0
				lp += 1
		bits -= 1
	var base := ((d.decode_u32(p >> 3) >> (p & 7)) & 15) * 64
	p += 4
	_p = p
	_ccount = cc
	# (int)(coef * quant) >> 11 with C's 32-bit wrap-around
	var v := blk[0] * quant[base]
	if v > 0x7FFFFFFF or v < -0x80000000:
		v = ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
	blk[0] = v >> 11
	for i in cc:
		var idx := cidx[i]
		var pos := _scan[idx]
		v = blk[pos] * quant[base + idx]
		if v > 0x7FFFFFFF or v < -0x80000000:
			v = ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
		blk[pos] = v >> 11


## read_residue: fills _blk (must be zeroed) with at most `masks` coefficients.
func _read_residue(masks: int) -> void:
	var cl := _cl
	var ml := _ml
	var blk := _blk
	var nz := _nz
	var d := _d
	var p := _p
	var ls := 64
	cl[64] = 4
	ml[64] = 0
	cl[65] = 24
	ml[65] = 0
	cl[66] = 44
	ml[66] = 0
	cl[67] = 0
	ml[67] = 2
	var le := 68
	var nzc := 0
	var mask := 1 << ((d.decode_u32(p >> 3) >> (p & 7)) & 7)
	p += 3
	while mask:
		for i in nzc:
			var bit := (d[p >> 3] >> (p & 7)) & 1
			p += 1
			if not bit:
				continue
			var pos := nz[i]
			if blk[pos] < 0:
				blk[pos] -= mask
			else:
				blk[pos] += mask
			masks -= 1
			if masks < 0:
				_p = p
				return
		var lp := ls
		while lp < le:
			var mode := ml[lp]
			var ccoef := cl[lp]
			if (mode | ccoef) == 0:
				lp += 1
				continue
			var bit := (d[p >> 3] >> (p & 7)) & 1
			p += 1
			if bit == 0:
				lp += 1
				continue
			if mode == 0 or mode == 2:
				if mode == 0:
					cl[lp] = ccoef + 4
					ml[lp] = 1
				else:
					cl[lp] = 0
					ml[lp] = 0
					lp += 1
				for i in 4:
					var f := (d[p >> 3] >> (p & 7)) & 1
					p += 1
					if f:
						ls -= 1
						cl[ls] = ccoef
						ml[ls] = 3
					else:
						var pos := _scan[ccoef]
						nz[nzc] = pos
						nzc += 1
						blk[pos] = -mask if (d[p >> 3] >> (p & 7)) & 1 else mask
						p += 1
						masks -= 1
						if masks < 0:
							_p = p
							return
					ccoef += 1
			elif mode == 1:
				ml[lp] = 2
				for i in 3:
					ccoef += 4
					cl[le] = ccoef
					ml[le] = 2
					le += 1
			else:
				var pos := _scan[ccoef]
				nz[nzc] = pos
				nzc += 1
				blk[pos] = -mask if (d[p >> 3] >> (p & 7)) & 1 else mask
				p += 1
				cl[lp] = 0
				ml[lp] = 0
				lp += 1
				masks -= 1
				if masks < 0:
					_p = p
					return
		mask >>= 1
	_p = p


## Bink IDCT of _blk; writes (add = false) or adds (add = true) the 8x8 result
## into dst at off with the given stride (bytes wrap like FFmpeg's uint8_t).
func _idct(dst: PackedByteArray, off: int, stride: int, add: bool) -> void:
	var blk := _blk
	if _ccount == 0:
		var dc := (blk[0] + 0x7F) >> 8
		if add:
			for r in 8:
				var o := off + r * stride
				for c in 8:
					dst[o + c] = dst[o + c] + dc
		else:
			var f := _fill[dc & 0xFF]
			for r in 8:
				dst.encode_s64(off + r * stride, f)
		return
	var tmp := _tmp
	for i in 8:
		var s0 := blk[i]
		var s1 := blk[8 + i]
		var s2 := blk[16 + i]
		var s3 := blk[24 + i]
		var s4 := blk[32 + i]
		var s5 := blk[40 + i]
		var s6 := blk[48 + i]
		var s7 := blk[56 + i]
		if (s1 | s2 | s3 | s4 | s5 | s6 | s7) == 0:
			tmp[i] = s0
			tmp[8 + i] = s0
			tmp[16 + i] = s0
			tmp[24 + i] = s0
			tmp[32 + i] = s0
			tmp[40 + i] = s0
			tmp[48 + i] = s0
			tmp[56 + i] = s0
			continue
		var a0 := s0 + s4
		var a1 := s0 - s4
		var a2 := s2 + s6
		var a3 := (2896 * (s2 - s6)) >> 11
		var a4 := s5 + s3
		var a5 := s5 - s3
		var a6 := s1 + s7
		var a7 := s1 - s7
		var b0 := a4 + a6
		var b1 := (3784 * (a5 + a7)) >> 11
		var b2 := ((-5352 * a5) >> 11) - b0 + b1
		var b3 := ((2896 * (a6 - a4)) >> 11) - b2
		var b4 := ((2217 * a7) >> 11) + b3 - b1
		tmp[i] = a0 + a2 + b0
		tmp[8 + i] = a1 + a3 - a2 + b2
		tmp[16 + i] = a1 - a3 + a2 + b3
		tmp[24 + i] = a0 - a2 - b4
		tmp[32 + i] = a0 - a2 + b4
		tmp[40 + i] = a1 - a3 + a2 - b3
		tmp[48 + i] = a1 + a3 - a2 - b2
		tmp[56 + i] = a0 + a2 - b0
	for i in 8:
		var k := i * 8
		var s0 := tmp[k]
		var s1 := tmp[k + 1]
		var s2 := tmp[k + 2]
		var s3 := tmp[k + 3]
		var s4 := tmp[k + 4]
		var s5 := tmp[k + 5]
		var s6 := tmp[k + 6]
		var s7 := tmp[k + 7]
		var o := off + i * stride
		if (s1 | s2 | s3 | s4 | s5 | s6 | s7) == 0:
			var dc := (s0 + 0x7F) >> 8
			if add:
				for c in 8:
					dst[o + c] = dst[o + c] + dc
			else:
				dst.encode_s64(o, _fill[dc & 0xFF])
			continue
		var a0 := s0 + s4
		var a1 := s0 - s4
		var a2 := s2 + s6
		var a3 := (2896 * (s2 - s6)) >> 11
		var a4 := s5 + s3
		var a5 := s5 - s3
		var a6 := s1 + s7
		var a7 := s1 - s7
		var b0 := a4 + a6
		var b1 := (3784 * (a5 + a7)) >> 11
		var b2 := ((-5352 * a5) >> 11) - b0 + b1
		var b3 := ((2896 * (a6 - a4)) >> 11) - b2
		var b4 := ((2217 * a7) >> 11) + b3 - b1
		if add:
			dst[o] = dst[o] + ((a0 + a2 + b0 + 0x7F) >> 8)
			dst[o + 1] = dst[o + 1] + ((a1 + a3 - a2 + b2 + 0x7F) >> 8)
			dst[o + 2] = dst[o + 2] + ((a1 - a3 + a2 + b3 + 0x7F) >> 8)
			dst[o + 3] = dst[o + 3] + ((a0 - a2 - b4 + 0x7F) >> 8)
			dst[o + 4] = dst[o + 4] + ((a0 - a2 + b4 + 0x7F) >> 8)
			dst[o + 5] = dst[o + 5] + ((a1 - a3 + a2 - b3 + 0x7F) >> 8)
			dst[o + 6] = dst[o + 6] + ((a1 + a3 - a2 - b2 + 0x7F) >> 8)
			dst[o + 7] = dst[o + 7] + ((a0 + a2 - b0 + 0x7F) >> 8)
		else:
			dst[o] = (a0 + a2 + b0 + 0x7F) >> 8
			dst[o + 1] = (a1 + a3 - a2 + b2 + 0x7F) >> 8
			dst[o + 2] = (a1 - a3 + a2 + b3 + 0x7F) >> 8
			dst[o + 3] = (a0 - a2 - b4 + 0x7F) >> 8
			dst[o + 4] = (a0 - a2 + b4 + 0x7F) >> 8
			dst[o + 5] = (a1 - a3 + a2 - b3 + 0x7F) >> 8
			dst[o + 6] = (a1 + a3 - a2 - b2 + 0x7F) >> 8
			dst[o + 7] = (a0 + a2 - b0 + 0x7F) >> 8


# --- plane ---------------------------------------------------------------------

func _decode_plane(idx: int, chroma: bool) -> void:
	var bw := ((width + 15) >> 4) if chroma else ((width + 7) >> 3)
	var bh := ((height + 15) >> 4) if chroma else ((height + 7) >> 3)
	var pw := width >> 1 if chroma else width
	var ph := height >> 1 if chroma else height
	var stride := _stride[idx]
	var dst := _cur[idx]
	var prev := _prev[idx]
	if revision == 0x6B and _bit():
		var fill := _bits(8)
		for r in ph:
			for c in pw:
				dst[r * stride + c] = fill
		_align32()
		return
	_init_lengths(maxi(pw, 8), bw)
	for i in NB_SRC:
		_read_bundle(i)
	_set_coord(stride)
	var coord := _coord
	var ucoord := _ucoord
	var ublock := _ublock
	var blk := _blk
	var fills := _fill
	var expand := _expand
	var ref_end := (bw - 1 + stride * (bh - 1)) * 8
	var types := _bd[B_TYPES]
	var subs := _bd[B_SUB]
	var cols := _bd[B_COLORS]
	var pats := _bd[B_PATTERN]
	var xo := _bd[B_XOFF]
	var yo := _bd[B_YOFF]
	var idc := _bd[B_INTRA_DC]
	var xdc := _bd[B_INTER_DC]
	var runs := _bd[B_RUN]
	var ptr := _ptr
	for by in bh:
		_read_row_bundles()
		if _fatal:
			break
		var pt := ptr[B_TYPES]
		var ps := ptr[B_SUB]
		var pc := ptr[B_COLORS]
		var pp := ptr[B_PATTERN]
		var px := ptr[B_XOFF]
		var py := ptr[B_YOFF]
		var pi := ptr[B_INTRA_DC]
		var pe := ptr[B_INTER_DC]
		var pr := ptr[B_RUN]
		var row := by * 8 * stride
		var bx := 0
		while bx < bw:
			var off := row + bx * 8
			var blkt := types[pt]
			pt += 1
			if blkt == 1 and ((by & 1) or (bx & 1)):
				bx += 2
				continue
			match blkt:
				0:  # skip
					for r in 8:
						var o := off + r * stride
						dst.encode_s64(o, prev.decode_s64(o))
				1:  # scaled 16x16
					var sub := subs[ps]
					ps += 1
					if sub == 3:  # run
						var sb := ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 15) * 64
						_p += 4
						var i := 0
						while true:
							var run := runs[pr] + 1
							pr += 1
							if i + run > 64:
								error = "run out of bounds"
								run = 64 - i
							if (_d[_p >> 3] >> (_p & 7)) & 1:
								_p += 1
								var v := cols[pc]
								pc += 1
								for j in run:
									ublock[ucoord[sb + i + j]] = v
							else:
								_p += 1
								for j in run:
									ublock[ucoord[sb + i + j]] = cols[pc]
									pc += 1
							i += run
							if i >= 63:
								break
						if i == 63:
							ublock[ucoord[sb + 63]] = cols[pc]
							pc += 1
					elif sub == 5:  # intra
						blk.fill(0)
						blk[0] = idc[pi]
						pi += 1
						_read_dct(_iq)
						_idct_ublock()
					elif sub == 6:  # fill
						var f := fills[cols[pc] & 0xFF]
						pc += 1
						for r in 16:
							dst.encode_s64(off + r * stride, f)
							dst.encode_s64(off + r * stride + 8, f)
					elif sub == 8:  # pattern
						var c0 := cols[pc]
						var c1 := cols[pc + 1]
						pc += 2
						for r in 8:
							var v := pats[pp]
							pp += 1
							for c in 8:
								ublock[r * 8 + c] = c1 if v & 1 else c0
								v >>= 1
					elif sub == 9:  # raw
						for k in 64:
							ublock[k] = cols[pc + k]
						pc += 64
					else:
						error = "bad 16x16 block type %d" % sub
						_fatal = true
					if sub != 6:
						for r in 8:
							var o := off + r * 2 * stride
							var k := r * 8
							for c in 8:
								var v := ublock[k + c]
								dst[o + 2 * c] = v
								dst[o + 2 * c + 1] = v
							var w := dst.decode_s64(o)
							var w2 := dst.decode_s64(o + 8)
							dst.encode_s64(o + stride, w)
							dst.encode_s64(o + stride + 8, w2)
					bx += 1
				2, 4, 7:  # motion, residue, inter
					var ref := off + xo[px] + yo[py] * stride
					px += 1
					py += 1
					if ref < 0 or ref > ref_end:
						error = "copy out of bounds"
					else:
						for r in 8:
							dst.encode_s64(off + r * stride, prev.decode_s64(ref + r * stride))
					if blkt == 4:
						blk.fill(0)
						var masks := (_d.decode_u32(_p >> 3) >> (_p & 7)) & 127
						_p += 7
						_read_residue(masks)
						for r in 8:
							var o := off + r * stride
							var k := r * 8
							for c in 8:
								dst[o + c] = dst[o + c] + blk[k + c]
					elif blkt == 7:
						blk.fill(0)
						blk[0] = xdc[pe]
						pe += 1
						_read_dct(_xq)
						_idct(dst, off, stride, true)
				3:  # run
					var sb := ((_d.decode_u32(_p >> 3) >> (_p & 7)) & 15) * 64
					_p += 4
					var i := 0
					while true:
						var run := runs[pr] + 1
						pr += 1
						if i + run > 64:
							error = "run out of bounds"
							run = 64 - i
						if (_d[_p >> 3] >> (_p & 7)) & 1:
							_p += 1
							var v := cols[pc]
							pc += 1
							for j in run:
								dst[off + coord[sb + i + j]] = v
						else:
							_p += 1
							for j in run:
								dst[off + coord[sb + i + j]] = cols[pc]
								pc += 1
						i += run
						if i >= 63:
							break
					if i == 63:
						dst[off + coord[sb + 63]] = cols[pc]
						pc += 1
				5:  # intra
					blk.fill(0)
					blk[0] = idc[pi]
					pi += 1
					_read_dct(_iq)
					_idct(dst, off, stride, false)
				6:  # fill
					var f := fills[cols[pc] & 0xFF]
					pc += 1
					for r in 8:
						dst.encode_s64(off + r * stride, f)
				8:  # pattern
					var f0 := fills[cols[pc] & 0xFF]
					var f1 := fills[cols[pc + 1] & 0xFF]
					pc += 2
					for r in 8:
						var m := expand[pats[pp] & 0xFF]
						pp += 1
						dst.encode_s64(off + r * stride, (f0 & ~m) | (f1 & m))
				9:  # raw
					for r in 8:
						var o := off + r * stride
						var k := pc + r * 8
						for c in 8:
							dst[o + c] = cols[k + c]
					pc += 64
				_:
					error = "bad block type %d" % blkt
					_fatal = true
			if _fatal:
				break
			bx += 1
		ptr[B_TYPES] = pt
		ptr[B_SUB] = ps
		ptr[B_COLORS] = pc
		ptr[B_PATTERN] = pp
		ptr[B_XOFF] = px
		ptr[B_YOFF] = py
		ptr[B_INTRA_DC] = pi
		ptr[B_INTER_DC] = pe
		ptr[B_RUN] = pr
		if _fatal:
			break
	_align32()


func _idct_ublock() -> void:
	# idct_put into the 8x8 ublock (as int values, wrapped to bytes)
	var tmpb := PackedByteArray()
	tmpb.resize(64)
	_idct(tmpb, 0, 8, false)
	for k in 64:
		_ublock[k] = tmpb[k]


func _align32() -> void:
	if _p & 31:
		_p += 32 - (_p & 31)


# --- tables (libavcodec/binkdata.h) -------------------------------------------

const SCAN := [
	0, 1, 8, 9, 2, 3, 10, 11, 4, 5, 12, 13, 6, 7, 14, 15,
	20, 21, 28, 29, 22, 23, 30, 31, 16, 17, 24, 25, 32, 33, 40, 41,
	34, 35, 42, 43, 48, 49, 56, 57, 50, 51, 58, 59, 18, 19, 26, 27,
	36, 37, 44, 45, 38, 39, 46, 47, 52, 53, 60, 61, 54, 55, 62, 63,
]

const TREE_BITS := [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
	0, 1, 3, 5, 7, 9, 11, 13, 15, 19, 21, 23, 25, 27, 29, 31,
	0, 2, 1, 9, 5, 21, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31,
	0, 2, 6, 1, 9, 5, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31,
	0, 4, 2, 6, 1, 9, 5, 13, 3, 19, 11, 27, 7, 23, 15, 31,
	0, 4, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 23, 15, 31,
	0, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 27, 7, 23, 15, 31,
	0, 1, 5, 3, 19, 11, 27, 59, 7, 39, 23, 55, 15, 47, 31, 63,
	0, 1, 3, 19, 11, 43, 27, 59, 7, 39, 23, 55, 15, 47, 31, 63,
	0, 1, 5, 13, 3, 19, 11, 27, 7, 39, 23, 55, 15, 47, 31, 63,
	0, 2, 1, 5, 13, 3, 19, 11, 27, 7, 23, 55, 15, 47, 31, 63,
	0, 1, 9, 5, 13, 3, 19, 11, 27, 7, 23, 55, 15, 47, 31, 63,
	0, 2, 1, 3, 19, 11, 27, 59, 7, 39, 23, 55, 15, 47, 31, 63,
	0, 1, 5, 3, 7, 39, 23, 55, 15, 79, 47, 111, 31, 95, 63, 127,
	0, 1, 5, 3, 7, 23, 55, 119, 15, 79, 47, 111, 31, 95, 63, 127,
	0, 2, 1, 5, 3, 7, 39, 23, 55, 15, 47, 111, 31, 95, 63, 127,
]

const TREE_LENS := [
	4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
	1, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
	2, 2, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
	2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5,
	3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5,
	2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5,
	1, 3, 3, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	1, 2, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	1, 3, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6,
	2, 2, 3, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6,
	1, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6,
	2, 2, 2, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
	1, 3, 3, 3, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7,
	1, 3, 3, 3, 5, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
	2, 2, 3, 3, 3, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7,
]

const PATTERNS := [
	0, 8, 16, 24, 32, 40, 48, 56, 57, 49, 41, 33, 25, 17, 9, 1,
	2, 10, 18, 26, 34, 42, 50, 58, 59, 51, 43, 35, 27, 19, 11, 3,
	4, 12, 20, 28, 36, 44, 52, 60, 61, 53, 45, 37, 29, 21, 13, 5,
	6, 14, 22, 30, 38, 46, 54, 62, 63, 55, 47, 39, 31, 23, 15, 7,
	59, 58, 57, 56, 48, 49, 50, 51, 43, 42, 41, 40, 32, 33, 34, 35,
	27, 26, 25, 24, 16, 17, 18, 19, 11, 10, 9, 8, 0, 1, 2, 3,
	4, 5, 6, 7, 15, 14, 13, 12, 20, 21, 22, 23, 31, 30, 29, 28,
	36, 37, 38, 39, 47, 46, 45, 44, 52, 53, 54, 55, 63, 62, 61, 60,
	25, 17, 18, 26, 27, 19, 11, 3, 2, 10, 9, 1, 0, 8, 16, 24,
	32, 40, 48, 56, 57, 49, 41, 42, 50, 58, 59, 51, 43, 35, 34, 33,
	29, 21, 22, 30, 31, 23, 15, 7, 6, 14, 13, 5, 4, 12, 20, 28,
	36, 44, 52, 60, 61, 53, 45, 46, 54, 62, 63, 55, 47, 39, 38, 37,
	3, 11, 2, 10, 1, 9, 0, 8, 16, 24, 17, 25, 18, 26, 19, 27,
	35, 43, 34, 42, 33, 41, 32, 40, 48, 56, 49, 57, 50, 58, 51, 59,
	60, 52, 61, 53, 62, 54, 63, 55, 47, 39, 46, 38, 45, 37, 44, 36,
	28, 20, 29, 21, 30, 22, 31, 23, 15, 7, 14, 6, 13, 5, 12, 4,
	24, 25, 16, 17, 8, 9, 0, 1, 2, 3, 10, 11, 18, 19, 26, 27,
	28, 29, 20, 21, 12, 13, 4, 5, 6, 7, 14, 15, 22, 23, 30, 31,
	39, 38, 47, 46, 55, 54, 63, 62, 61, 60, 53, 52, 45, 44, 37, 36,
	35, 34, 43, 42, 51, 50, 59, 58, 57, 56, 49, 48, 41, 40, 33, 32,
	0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19, 24, 25, 26, 27,
	32, 33, 34, 35, 40, 41, 42, 43, 48, 49, 50, 51, 56, 57, 58, 59,
	4, 5, 6, 7, 12, 13, 14, 15, 20, 21, 22, 23, 28, 29, 30, 31,
	36, 37, 38, 39, 44, 45, 46, 47, 52, 53, 54, 55, 60, 61, 62, 63,
	6, 7, 15, 14, 13, 5, 12, 4, 3, 11, 2, 10, 9, 1, 0, 8,
	16, 24, 17, 25, 18, 26, 19, 27, 20, 28, 21, 29, 22, 30, 23, 31,
	39, 47, 38, 46, 37, 45, 36, 44, 35, 43, 34, 42, 33, 41, 32, 40,
	49, 48, 56, 57, 58, 50, 59, 51, 60, 52, 61, 53, 54, 55, 63, 62,
	0, 1, 2, 3, 4, 5, 6, 7, 15, 14, 13, 12, 11, 10, 9, 8,
	16, 17, 18, 19, 20, 21, 22, 23, 31, 30, 29, 28, 27, 26, 25, 24,
	32, 33, 34, 35, 36, 37, 38, 39, 47, 46, 45, 44, 43, 42, 41, 40,
	48, 49, 50, 51, 52, 53, 54, 55, 63, 62, 61, 60, 59, 58, 57, 56,
	0, 8, 9, 1, 2, 3, 11, 10, 18, 19, 27, 26, 25, 17, 16, 24,
	32, 40, 41, 33, 34, 35, 43, 42, 50, 49, 48, 56, 57, 58, 59, 51,
	52, 60, 61, 62, 63, 55, 54, 53, 45, 44, 36, 37, 38, 46, 47, 39,
	31, 23, 22, 30, 29, 28, 20, 21, 13, 12, 4, 5, 6, 14, 15, 7,
	24, 25, 16, 17, 8, 9, 0, 1, 2, 3, 10, 11, 18, 19, 26, 27,
	28, 29, 20, 21, 12, 13, 4, 5, 6, 7, 14, 15, 22, 23, 30, 31,
	38, 39, 46, 47, 54, 55, 62, 63, 60, 61, 52, 53, 44, 45, 36, 37,
	34, 35, 42, 43, 50, 51, 58, 59, 56, 57, 48, 49, 40, 41, 32, 33,
	0, 8, 1, 9, 2, 10, 3, 11, 19, 27, 18, 26, 17, 25, 16, 24,
	32, 40, 33, 41, 34, 42, 35, 43, 51, 59, 50, 58, 49, 57, 48, 56,
	60, 52, 61, 53, 62, 54, 63, 55, 47, 39, 46, 38, 45, 37, 44, 36,
	31, 23, 30, 22, 29, 21, 28, 20, 12, 4, 13, 5, 14, 6, 15, 7,
	0, 8, 16, 24, 25, 26, 27, 19, 11, 3, 2, 1, 9, 17, 18, 10,
	4, 12, 20, 28, 29, 30, 31, 23, 15, 7, 6, 5, 13, 21, 22, 14,
	36, 44, 52, 60, 61, 62, 63, 55, 47, 39, 38, 37, 45, 53, 54, 46,
	32, 40, 48, 56, 57, 58, 59, 51, 43, 35, 34, 33, 41, 49, 50, 42,
	0, 8, 9, 1, 2, 3, 11, 10, 19, 27, 26, 18, 17, 16, 24, 25,
	33, 32, 40, 41, 42, 34, 35, 43, 51, 59, 58, 50, 49, 57, 56, 48,
	52, 60, 61, 53, 54, 62, 63, 55, 47, 39, 38, 46, 45, 44, 36, 37,
	29, 28, 20, 21, 22, 30, 31, 23, 14, 15, 7, 6, 5, 13, 12, 4,
	24, 16, 8, 0, 1, 2, 3, 11, 19, 27, 26, 25, 17, 10, 9, 18,
	28, 20, 12, 4, 5, 6, 7, 15, 23, 31, 30, 29, 21, 14, 13, 22,
	60, 52, 44, 36, 37, 38, 39, 47, 55, 63, 62, 61, 53, 46, 45, 54,
	56, 48, 40, 32, 33, 34, 35, 43, 51, 59, 58, 57, 49, 42, 41, 50,
	0, 8, 9, 1, 2, 10, 18, 17, 16, 24, 25, 26, 27, 19, 11, 3,
	7, 6, 14, 15, 23, 22, 21, 13, 5, 4, 12, 20, 28, 29, 30, 31,
	63, 62, 54, 55, 47, 46, 45, 53, 61, 60, 52, 44, 36, 37, 38, 39,
	56, 48, 49, 57, 58, 50, 42, 41, 40, 32, 33, 34, 35, 43, 51, 59,
	0, 1, 8, 9, 16, 17, 24, 25, 32, 33, 40, 41, 48, 49, 56, 57,
	58, 59, 50, 51, 42, 43, 34, 35, 26, 27, 18, 19, 10, 11, 2, 3,
	4, 5, 12, 13, 20, 21, 28, 29, 36, 37, 44, 45, 52, 53, 60, 61,
	62, 63, 54, 55, 46, 47, 38, 39, 30, 31, 22, 23, 14, 15, 6, 7,
]

const INTRA_QUANT := [
	65536, 90901, 124989, 173365, 85627, 91511, 192998, 160332,
	65536, 61146, 147714, 98203, 48768, 24862, 67644, 42322,
	139144, 121939, 163757, 128663, 83993, 42819, 88625, 38536,
	144495, 200421, 130042, 180374, 118784, 164758, 102983, 129450,
	144495, 130042, 121939, 143800, 77586, 122988, 51984, 72104,
	115852, 104264, 85638, 74415, 181800, 163616, 169909, 147250,
	151552, 109419, 119074, 88499, 75369, 36163, 60959, 30189,
	84236, 66184, 63285, 61265, 57585, 29357, 42200, 25879,
	87381, 121201, 166652, 231153, 114169, 122015, 257331, 213777,
	87381, 81528, 196952, 130938, 65024, 33149, 90191, 56429,
	185525, 162585, 218343, 171551, 111991, 57092, 118166, 51382,
	192661, 267228, 173390, 240499, 158379, 219678, 137310, 172600,
	192661, 173390, 162585, 191733, 103448, 163984, 69312, 96138,
	154470, 139019, 114185, 99220, 242400, 218154, 226545, 196334,
	202069, 145892, 158765, 117998, 100492, 48217, 81278, 40252,
	112315, 88245, 84380, 81687, 76780, 39142, 56267, 34505,
	109227, 151502, 208315, 288941, 142712, 152519, 321663, 267221,
	109227, 101910, 246190, 163672, 81280, 41436, 112739, 70536,
	231906, 203231, 272929, 214439, 139988, 71365, 147708, 64227,
	240826, 334035, 216737, 300623, 197973, 274597, 171638, 215749,
	240826, 216737, 203231, 239667, 129310, 204980, 86640, 120173,
	193087, 173774, 142731, 124025, 303000, 272693, 283181, 245417,
	252587, 182365, 198456, 147498, 125615, 60271, 101598, 50314,
	140393, 110306, 105474, 102109, 95975, 48928, 70334, 43131,
	131072, 181802, 249978, 346729, 171254, 183023, 385996, 320665,
	131072, 122292, 295428, 196406, 97537, 49724, 135287, 84643,
	278287, 243878, 327514, 257326, 167986, 85638, 177249, 77073,
	288991, 400842, 260085, 360748, 237568, 329516, 205965, 258899,
	288991, 260085, 243878, 287600, 155172, 245976, 103968, 144207,
	231705, 208529, 171277, 148830, 363600, 327231, 339817, 294501,
	303104, 218838, 238147, 176997, 150738, 72325, 121918, 60377,
	168472, 132368, 126569, 122530, 115170, 58713, 84400, 51757,
	174763, 242403, 333304, 462306, 228338, 244030, 514661, 427553,
	174763, 163056, 393905, 261875, 130049, 66298, 180383, 112858,
	371050, 325170, 436686, 343102, 223981, 114185, 236333, 102763,
	385321, 534456, 346780, 480997, 316757, 439355, 274620, 345199,
	385321, 346780, 325170, 383467, 206896, 327969, 138624, 192276,
	308940, 278038, 228369, 198440, 484800, 436309, 453090, 392667,
	404139, 291784, 317530, 235996, 200984, 96434, 162557, 80503,
	224630, 176490, 168759, 163374, 153560, 78284, 112534, 69009,
	229376, 318154, 437461, 606776, 299694, 320290, 675493, 561164,
	229376, 214011, 517000, 343711, 170689, 87016, 236752, 148126,
	487003, 426786, 573150, 450321, 293975, 149867, 310187, 134877,
	505734, 701473, 455149, 631309, 415744, 576654, 360439, 453074,
	505734, 455149, 426786, 503300, 271551, 430459, 181944, 252363,
	405483, 364925, 299735, 260452, 636300, 572655, 594680, 515376,
	530432, 382967, 416758, 309745, 263792, 126569, 213356, 105660,
	294826, 231644, 221496, 214428, 201548, 102748, 147701, 90575,
	262144, 363604, 499956, 693459, 342508, 366045, 771992, 641330,
	262144, 244584, 590857, 392813, 195073, 99447, 270574, 169287,
	556575, 487756, 655029, 514653, 335972, 171277, 354499, 154145,
	577982, 801684, 520170, 721496, 475136, 659033, 411930, 517799,
	577982, 520170, 487756, 575200, 310344, 491953, 207935, 288415,
	463410, 417058, 342554, 297660, 727200, 654463, 679635, 589001,
	606208, 437676, 476295, 353994, 301477, 144651, 243835, 120755,
	336944, 264736, 253139, 245061, 230341, 117427, 168801, 103514,
	327680, 454505, 624945, 866823, 428135, 457557, 964990, 801662,
	327680, 305730, 738571, 491016, 243841, 124309, 338218, 211609,
	695719, 609695, 818786, 643316, 419965, 214096, 443124, 192682,
	722477, 1002104, 650212, 901870, 593920, 823791, 514913, 647248,
	722477, 650212, 609695, 719000, 387929, 614941, 259919, 360518,
	579262, 521322, 428192, 372075, 909000, 818079, 849543, 736251,
	757760, 547095, 595368, 442493, 376846, 180813, 304794, 150943,
	421180, 330919, 316423, 306326, 287926, 146783, 211001, 129393,
	393216, 545406, 749934, 1040188, 513761, 549068, 1157987, 961995,
	393216, 366876, 886285, 589219, 292610, 149171, 405861, 253930,
	834862, 731633, 982543, 771979, 503958, 256915, 531748, 231218,
	866972, 1202525, 780255, 1082244, 712704, 988549, 617896, 776698,
	866972, 780255, 731633, 862800, 465515, 737929, 311903, 432622,
	695114, 625586, 513831, 446490, 1090800, 981694, 1019452, 883502,
	909312, 656514, 714442, 530991, 452215, 216976, 365753, 181132,
	505417, 397103, 379708, 367591, 345511, 176140, 253201, 155271,
	524288, 727208, 999912, 1386917, 685015, 732091, 1543983, 1282660,
	524288, 489167, 1181714, 785625, 390146, 198895, 541148, 338574,
	1113150, 975511, 1310057, 1029305, 671944, 342554, 708998, 308290,
	1155963, 1603367, 1040340, 1442992, 950272, 1318065, 823861, 1035597,
	1155963, 1040340, 975511, 1150400, 620687, 983906, 415871, 576829,
	926819, 834115, 685108, 595319, 1454400, 1308926, 1359269, 1178002,
	1212416, 875352, 952589, 707988, 602953, 289301, 487671, 241509,
	673889, 529471, 506278, 490121, 460681, 234853, 337602, 207028,
	786432, 1090813, 1499867, 2080376, 1027523, 1098136, 2315975, 1923990,
	786432, 733751, 1772570, 1178438, 585219, 298342, 811722, 507861,
	1669725, 1463267, 1965086, 1543958, 1007916, 513831, 1063497, 462436,
	1733945, 2405051, 1560509, 2164489, 1425408, 1977098, 1235791, 1553396,
	1733945, 1560509, 1463267, 1725600, 931031, 1475859, 623806, 865244,
	1390229, 1251173, 1027662, 892979, 2181601, 1963389, 2038904, 1767003,
	1818624, 1313028, 1428884, 1061982, 904430, 433952, 731506, 362264,
	1010833, 794206, 759416, 735182, 691022, 352280, 506402, 310542,
	1114112, 1545318, 2124812, 2947199, 1455658, 1555693, 3280964, 2725652,
	1114112, 1039481, 2511141, 1669454, 829061, 422651, 1149940, 719469,
	2365444, 2072961, 2783872, 2187274, 1427881, 727927, 1506620, 655117,
	2456422, 3407155, 2210722, 3066359, 2019328, 2800889, 1750704, 2200644,
	2456422, 2210722, 2072961, 2444600, 1318960, 2090800, 883726, 1225763,
	1969490, 1772495, 1455854, 1265054, 3090601, 2781467, 2888447, 2503254,
	2576384, 1860123, 2024252, 1504475, 1281275, 614766, 1036300, 513207,
	1432014, 1125126, 1075840, 1041508, 978948, 499063, 717403, 439935,
	1441792, 1999823, 2749757, 3814022, 1883792, 2013250, 4245954, 3527315,
	1441792, 1345210, 3249712, 2160470, 1072902, 546961, 1488158, 931078,
	3061162, 2682656, 3602657, 2830590, 1847845, 942023, 1949744, 847799,
	3178899, 4409260, 2860934, 3968229, 2613248, 3624679, 2265618, 2847892,
	3178899, 2860934, 2682656, 3163600, 1706889, 2705741, 1143645, 1586281,
	2548752, 2293817, 1884047, 1637129, 3999601, 3599546, 3737990, 3239506,
	3334144, 2407219, 2619620, 1946967, 1658121, 795579, 1341094, 664150,
	1853194, 1456045, 1392263, 1347834, 1266873, 645846, 928404, 569328,
	1835008, 2545229, 3499690, 4854210, 2397554, 2562318, 5403941, 4489310,
	1835008, 1712086, 4135998, 2749689, 1365511, 696132, 1894019, 1185008,
	3896025, 3414289, 4585200, 3602569, 2351803, 1198939, 2481492, 1079017,
	4045872, 5611785, 3641188, 5050473, 3325952, 4613228, 2883513, 3624590,
	4045872, 3641188, 3414289, 4026400, 2172405, 3443670, 1455548, 2018903,
	3243867, 2919403, 2397878, 2083618, 5090401, 4581240, 4757442, 4123007,
	4243456, 3063733, 3334062, 2477958, 2110336, 1012555, 1706847, 845282,
	2358611, 1853148, 1771972, 1715425, 1612384, 821986, 1181605, 724599,
	2228224, 3090636, 4249624, 5894398, 2911315, 3111386, 6561929, 5451305,
	2228224, 2078961, 5022283, 3338908, 1658121, 845303, 2299880, 1438939,
	4730887, 4145923, 5567743, 4374548, 2855761, 1455854, 3013241, 1310234,
	4912844, 6814311, 4421443, 6132718, 4038656, 5601777, 3501409, 4401288,
	4912844, 4421443, 4145923, 4889200, 2637920, 4181600, 1767451, 2451525,
	3938981, 3544989, 2911709, 2530108, 6181202, 5562935, 5776894, 5006509,
	5152768, 3720247, 4048504, 3008949, 2562551, 1229531, 2072600, 1026414,
	2864027, 2250252, 2151680, 2083016, 1957895, 998126, 1434807, 879870,
	2883584, 3999646, 5499513, 7628044, 3767584, 4026499, 8491907, 7054629,
	2883584, 2690421, 6499425, 4320940, 2145804, 1093921, 2976315, 1862156,
	6122324, 5365312, 7205314, 5661179, 3695691, 1884047, 3899488, 1695597,
	6357798, 8818519, 5721867, 7936458, 5226496, 7249358, 4531235, 5695784,
	6357798, 5721867, 5365312, 6327200, 3413779, 5411482, 2287290, 3172562,
	5097505, 4587633, 3768094, 3274257, 7999202, 7199092, 7475980, 6479011,
	6668288, 4814437, 5239241, 3893934, 3316242, 1591158, 2682189, 1328300,
	3706388, 2912090, 2784527, 2695668, 2533747, 1291693, 1856808, 1138655,
]

const INTER_QUANT := [
	65536, 96582, 107945, 149724, 90979, 86695, 148460, 133610,
	73728, 57928, 113626, 89276, 42118, 21472, 61494, 32917,
	112385, 92505, 110777, 87037, 63719, 32484, 59952, 30563,
	112385, 155883, 105961, 146971, 94208, 130670, 77237, 107131,
	123089, 110777, 100915, 94605, 55418, 83017, 31642, 43889,
	78200, 70378, 44296, 39865, 146839, 132151, 138444, 124596,
	98304, 77237, 83673, 65742, 53202, 28252, 45284, 23085,
	59852, 47025, 33903, 27525, 33591, 17125, 18960, 10289,
	87381, 128776, 143927, 199632, 121305, 115593, 197947, 178147,
	98304, 77237, 151502, 119034, 56157, 28629, 81992, 43889,
	149847, 123340, 147703, 116049, 84958, 43311, 79936, 40751,
	149847, 207844, 141281, 195962, 125611, 174227, 102983, 142841,
	164118, 147703, 134553, 126140, 73891, 110689, 42190, 58519,
	104267, 93838, 59061, 53154, 195785, 176202, 184592, 166129,
	131072, 102983, 111564, 87656, 70936, 37669, 60378, 30781,
	79803, 62701, 45203, 36700, 44788, 22833, 25279, 13719,
	109227, 160971, 179908, 249540, 151631, 144492, 247433, 222684,
	122880, 96546, 189377, 148793, 70197, 35786, 102490, 54861,
	187309, 154176, 184628, 145061, 106198, 54139, 99920, 50939,
	187309, 259805, 176601, 244952, 157013, 217784, 128728, 178551,
	205148, 184628, 168192, 157675, 92364, 138362, 52737, 73149,
	130334, 117297, 73826, 66442, 244731, 220252, 230740, 207661,
	163840, 128728, 139456, 109570, 88670, 47087, 75473, 38476,
	99753, 78376, 56504, 45875, 55986, 28541, 31599, 17148,
	131072, 193165, 215890, 299448, 181957, 173390, 296920, 267221,
	147456, 115855, 227253, 178551, 84236, 42943, 122988, 65834,
	224771, 185011, 221554, 174074, 127438, 64967, 119904, 61127,
	224771, 311766, 211921, 293943, 188416, 261341, 154474, 214261,
	246177, 221554, 201830, 189211, 110837, 166034, 63285, 87778,
	156401, 140757, 88592, 79730, 293677, 264302, 276888, 249193,
	196608, 154474, 167347, 131483, 106403, 56504, 90567, 46171,
	119704, 94051, 67805, 55050, 67183, 34249, 37919, 20578,
	174763, 257553, 287853, 399264, 242610, 231187, 395893, 356294,
	196608, 154474, 303003, 238068, 112315, 57258, 163984, 87778,
	299694, 246681, 295405, 232098, 169917, 86623, 159872, 81502,
	299694, 415688, 282561, 391924, 251221, 348454, 205965, 285682,
	328237, 295405, 269107, 252281, 147783, 221379, 84380, 117038,
	208534, 187676, 118122, 106307, 391569, 352403, 369184, 332257,
	262144, 205965, 223129, 175311, 141871, 75339, 120757, 61561,
	159605, 125401, 90407, 73400, 89577, 45666, 50559, 27437,
	229376, 338038, 377807, 524034, 318425, 303432, 519610, 467636,
	258048, 202747, 397692, 312465, 147413, 75151, 215229, 115209,
	393349, 323769, 387719, 304629, 223016, 113692, 209832, 106971,
	393349, 545590, 370862, 514400, 329728, 457346, 270329, 374958,
	430810, 387719, 353202, 331118, 193965, 290560, 110748, 153612,
	273701, 246325, 155035, 139528, 513935, 462529, 484554, 436087,
	344064, 270329, 292857, 230096, 186206, 98882, 158493, 80799,
	209482, 164589, 118659, 96337, 117570, 59937, 66358, 36012,
	262144, 386329, 431780, 598896, 363914, 346780, 593840, 534442,
	294912, 231711, 454505, 357102, 168472, 85886, 245976, 131668,
	449541, 370021, 443108, 348147, 254875, 129934, 239808, 122253,
	449541, 623532, 423842, 587886, 376832, 522681, 308948, 428523,
	492355, 443108, 403660, 378421, 221674, 332068, 126569, 175557,
	312801, 281514, 177183, 159461, 587354, 528605, 553776, 498385,
	393216, 308948, 334693, 262967, 212807, 113008, 181135, 92342,
	239408, 188102, 135610, 110100, 134365, 68499, 75838, 41156,
	327680, 482912, 539725, 748620, 454893, 433475, 742300, 668052,
	368640, 289639, 568132, 446378, 210590, 107358, 307471, 164584,
	561927, 462527, 553884, 435184, 318594, 162418, 299760, 152816,
	561927, 779415, 529803, 734857, 471040, 653351, 386185, 535654,
	615443, 553884, 504575, 473026, 277092, 415085, 158212, 219446,
	391002, 351892, 221479, 199326, 734193, 660756, 692220, 622982,
	491520, 386185, 418367, 328709, 266009, 141260, 226419, 115427,
	299260, 235127, 169513, 137625, 167957, 85624, 94798, 51445,
	393216, 579494, 647670, 898344, 545872, 520170, 890760, 801662,
	442368, 347566, 681758, 535654, 252708, 128830, 368965, 197501,
	674312, 555032, 664661, 522221, 382313, 194901, 359712, 183380,
	674312, 935298, 635763, 881829, 565248, 784022, 463422, 642784,
	738532, 664661, 605490, 567632, 332511, 498102, 189854, 263335,
	469202, 422271, 265775, 239191, 881031, 792907, 830664, 747578,
	589824, 463422, 502040, 394450, 319210, 169513, 271702, 138513,
	359112, 282152, 203415, 165150, 201548, 102748, 113757, 61734,
	524288, 772659, 863560, 1197792, 727829, 693560, 1187679, 1068883,
	589824, 463422, 909010, 714205, 336944, 171773, 491953, 263335,
	899083, 740043, 886215, 696295, 509750, 259869, 479616, 244506,
	899083, 1247063, 847684, 1175772, 753664, 1045362, 617896, 857046,
	984710, 886215, 807320, 756842, 443348, 664136, 253139, 351114,
	625603, 563028, 354366, 318921, 1174708, 1057209, 1107553, 996771,
	786432, 617896, 669387, 525934, 425614, 226017, 362270, 184683,
	478816, 376203, 271220, 220200, 268731, 136998, 151676, 82312,
	786432, 1158988, 1295340, 1796688, 1091743, 1040340, 1781519, 1603325,
	884736, 695133, 1363516, 1071307, 505417, 257659, 737929, 395003,
	1348624, 1110064, 1329323, 1044442, 764626, 389803, 719424, 366759,
	1348624, 1870595, 1271526, 1763657, 1130496, 1568043, 926844, 1285569,
	1477064, 1329323, 1210979, 1135263, 665022, 996205, 379708, 526670,
	938404, 844542, 531549, 478382, 1762062, 1585814, 1661329, 1495156,
	1179648, 926844, 1004080, 788901, 638421, 339025, 543404, 277025,
	718224, 564305, 406830, 330299, 403096, 205497, 227514, 123469,
	1114112, 1641900, 1835065, 2545308, 1546636, 1473814, 2523819, 2271377,
	1253376, 984771, 1931647, 1517686, 716007, 365017, 1045400, 559587,
	1910551, 1572591, 1883207, 1479626, 1083220, 552221, 1019184, 519576,
	1910551, 2650010, 1801329, 2498515, 1601536, 2221394, 1313028, 1821223,
	2092508, 1883207, 1715554, 1608290, 942114, 1411290, 537920, 746116,
	1329406, 1196434, 753028, 677707, 2496255, 2246570, 2353549, 2118138,
	1671168, 1313028, 1422447, 1117610, 904430, 480286, 769823, 392452,
	1017483, 799432, 576343, 467924, 571053, 291120, 322312, 174914,
	1441792, 2124812, 2374790, 3293928, 2001529, 1907289, 3266118, 2939429,
	1622016, 1274410, 2499779, 1964064, 926597, 472375, 1352871, 724172,
	2472477, 2035118, 2437092, 1914811, 1401814, 714638, 1318945, 672392,
	2472477, 3429424, 2331131, 3233372, 2072576, 2874746, 1699213, 2356876,
	2707951, 2437092, 2220129, 2081316, 1219207, 1826375, 696132, 965562,
	1720408, 1548326, 974507, 877033, 3230447, 2907326, 3045770, 2741120,
	2162688, 1699213, 1840814, 1446318, 1170438, 621546, 996241, 507879,
	1316743, 1034558, 745855, 605549, 739009, 376744, 417109, 226359,
	1835008, 2704306, 3022460, 4192272, 2547401, 2427459, 4156878, 3741091,
	2064384, 1621976, 3181537, 2499717, 1179305, 601205, 1721835, 921673,
	3146789, 2590150, 3101753, 2437032, 1784127, 909540, 1678657, 855772,
	3146789, 4364722, 2966894, 4115200, 2637824, 3658767, 2162635, 2999661,
	3446483, 3101753, 2825619, 2648948, 1551718, 2324478, 885986, 1228898,
	2189610, 1970597, 1240282, 1116224, 4111478, 3700232, 3876434, 3488698,
	2752512, 2162635, 2342854, 1840769, 1489649, 791059, 1267944, 646392,
	1675855, 1316711, 949270, 770698, 940557, 479492, 530866, 288093,
	2228224, 3283800, 3670130, 5090616, 3093272, 2947629, 5047638, 4542754,
	2506752, 1969542, 3863294, 3035371, 1432014, 730034, 2090800, 1119175,
	3821101, 3145183, 3766414, 2959253, 2166440, 1104441, 2038369, 1039151,
	3821101, 5300019, 3602657, 4997029, 3203072, 4442789, 2626057, 3642445,
	4185015, 3766414, 3431108, 3216579, 1884228, 2822580, 1075840, 1492233,
	2658812, 2392868, 1506056, 1355415, 4992509, 4493140, 4707099, 4236277,
	3342336, 2626057, 2844895, 2235219, 1808859, 960571, 1539646, 784905,
	2034967, 1598863, 1152686, 935848, 1142106, 582240, 644623, 349828,
	2883584, 4249624, 4749580, 6587856, 4003058, 3814578, 6532237, 5878858,
	3244032, 2548820, 4999558, 3928127, 1853194, 944750, 2705741, 1448344,
	4944954, 4070236, 4874183, 3829621, 2803628, 1429277, 2637889, 1344784,
	4944954, 6858849, 4662262, 6466744, 4145152, 5749491, 3398426, 4713753,
	5415902, 4874183, 4440258, 4162632, 2438413, 3652750, 1392263, 1931125,
	3440816, 3096652, 1949014, 1754066, 6460894, 5814651, 6091539, 5482241,
	4325376, 3398426, 3681628, 2892637, 2340877, 1243092, 1992483, 1015759,
	2633486, 2069117, 1491711, 1211097, 1478019, 753488, 834218, 452718,
]
